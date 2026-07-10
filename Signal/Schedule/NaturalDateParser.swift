import Foundation

/// How a scheduled task repeats. Lives here rather than in the SwiftData model
/// so the parser and its tests stay free of any persistence dependency.
enum Recurrence: Equatable {
    case daily
    /// `weekday` uses Calendar's numbering: 1 (Sunday) – 7 (Saturday).
    case weekly(weekday: Int)

    /// Start of day of the first occurrence strictly after `date` — a rule
    /// created on a Monday for Mondays first fires the *next* Monday.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            let day = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: 1, to: day) ?? date
        case .weekly(let weekday):
            let next = calendar.nextDate(
                after: date,
                matching: DateComponents(weekday: weekday),
                matchingPolicy: .nextTime
            ) ?? date
            return calendar.startOfDay(for: next)
        }
    }
}

/// The result of finding a trailing date phrase in task text:
/// "Do the dishes tomorrow" → clean text "Do the dishes", due tomorrow.
struct ScheduleParse: Equatable {
    /// UTF-16 range of the phrase in the original text, ready for
    /// NSTextStorage/NSAttributedString highlighting.
    let matchedRange: NSRange
    /// The task text with the phrase stripped and whitespace trimmed.
    let cleanText: String
    /// Start of day the task should (first) appear.
    let dueDate: Date
    /// nil for a one-time task.
    let recurrence: Recurrence?
    /// Short label for the post-Enter confirmation beat,
    /// e.g. "Scheduled for tomorrow" or "Every Monday".
    let confirmationLabel: String
}

/// Parses a natural-language date/recurrence phrase off the END of task text.
/// English keywords, case-insensitive. The phrase must be the last thing in the
/// string so a task merely *mentioning* "monday" mid-sentence isn't hijacked,
/// and trailing punctuation defeats the parse on purpose — "Plan tomorrow."
/// stays a literal task.
enum NaturalDateParser {
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> ScheduleParse? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let full = NSRange(location: 0, length: ns.length)

        for rule in rules {
            guard let match = rule.regex.firstMatch(in: text, range: full),
                  let (dueDate, recurrence, label) = rule.resolve(match, ns, now, calendar)
            else { continue }

            let phraseRange = match.range(at: 1)
            let cleanText = ns.substring(to: phraseRange.location)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // A phrase with no task in front of it ("tomorrow" alone) is just
            // a task named tomorrow, not a scheduling request.
            guard !cleanText.isEmpty else { return nil }

            return ScheduleParse(
                matchedRange: phraseRange,
                cleanText: cleanText,
                dueDate: dueDate,
                recurrence: recurrence,
                confirmationLabel: label
            )
        }
        return nil
    }

    // MARK: - Grammar

    /// A grammar rule: the phrase regex plus how a match resolves. Resolvers
    /// return nil to reject a syntactic match ("in 0 days"), letting later
    /// rules have a go.
    private struct Rule {
        let regex: NSRegularExpression
        let resolve: (NSTextCheckingResult, NSString, Date, Calendar) -> (Date, Recurrence?, String)?
    }

    /// Full names only — "mon"/"tue" collide with too many ordinary words.
    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let weekdayPattern = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"

    /// Ordered — first match wins, so "every monday" is claimed before the
    /// bare-weekday rule could match just "monday".
    private static let rules: [Rule] = {
        // Anchor every phrase to the end of the text, preceded by start or
        // whitespace so it can't match inside a word ("Doomsday").
        func rule(
            _ body: String,
            _ resolve: @escaping (NSTextCheckingResult, NSString, Date, Calendar) -> (Date, Recurrence?, String)?
        ) -> Rule {
            let pattern = "(?:^|\\s)(\(body))\\s*$"
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return Rule(regex: regex, resolve: resolve)
        }

        return [
            // "every monday" — weekly, first firing strictly next week.
            rule("every\\s+(\(weekdayPattern))") { match, ns, now, calendar in
                let name = ns.substring(with: match.range(at: 2)).lowercased()
                guard let weekday = weekdayNumbers[name] else { return nil }
                let recurrence = Recurrence.weekly(weekday: weekday)
                let due = recurrence.nextOccurrence(after: now, calendar: calendar)
                return (due, recurrence, "Every \(name.capitalized)")
            },
            // "every day" / "everyday" — daily, starting tomorrow.
            rule("every\\s?day") { _, _, now, calendar in
                let recurrence = Recurrence.daily
                let due = recurrence.nextOccurrence(after: now, calendar: calendar)
                return (due, recurrence, "Every day")
            },
            // "every week" — weekly on today's weekday, starting next week.
            rule("every\\s+week") { _, _, now, calendar in
                let recurrence = Recurrence.weekly(weekday: calendar.component(.weekday, from: now))
                let due = recurrence.nextOccurrence(after: now, calendar: calendar)
                return (due, recurrence, "Every week")
            },
            // "in 3 days" / "in 2 weeks" — liberal about pluralization.
            rule("in\\s+(\\d{1,3})\\s+(days?|weeks?)") { match, ns, now, calendar in
                guard let count = Int(ns.substring(with: match.range(at: 2))) else { return nil }
                let unit = ns.substring(with: match.range(at: 3)).lowercased()
                let days = unit.hasPrefix("week") ? count * 7 : count
                guard days >= 1, days <= 730,
                      let due = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
                else { return nil }
                return (due, nil, oneTimeLabel(for: due, now: now, calendar: calendar))
            },
            // "tomorrow"
            rule("tomorrow") { _, _, now, calendar in
                guard let due = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
                return (due, nil, "Scheduled for tomorrow")
            },
            // "friday" — the next strictly future one, so today's own weekday
            // means next week.
            rule("(\(weekdayPattern))") { match, ns, now, calendar in
                let name = ns.substring(with: match.range(at: 2)).lowercased()
                guard let weekday = weekdayNumbers[name] else { return nil }
                let due = Recurrence.weekly(weekday: weekday).nextOccurrence(after: now, calendar: calendar)
                return (due, nil, oneTimeLabel(for: due, now: now, calendar: calendar))
            },
        ]
    }()

    // MARK: - Labels

    /// Matches the notch header's date style ("EEE, MMM d").
    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static func oneTimeLabel(for due: Date, now: Date, calendar: Calendar) -> String {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if due == tomorrow { return "Scheduled for tomorrow" }
        return "Scheduled for \(labelFormatter.string(from: due))"
    }
}
