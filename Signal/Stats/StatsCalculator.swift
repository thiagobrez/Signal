import Foundation

/// Pure aggregation logic for the Task Stats window. Operates on `DayLog`s but
/// never touches UI, so the math stays testable and out of view bodies.
///
/// Throughout, only items with non-empty (trimmed) text count as tasks — days
/// keep empty placeholder slots (see `SignalStore.createDayLog`) that would
/// otherwise skew every rate.
enum StatsCalculator {
    struct OverviewStats {
        var completedTasks = 0
        var totalTasks = 0
        var fullDays = 0
        var trackedDays = 0

        var completionRate: Double {
            totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0
        }
    }

    struct WeekdayRow: Identifiable {
        /// `Calendar` weekday unit: 1 = Sunday … 7 = Saturday.
        let weekday: Int
        let label: String
        var tasksCompleted = 0
        var fullDaysCompleted = 0

        var id: Int { weekday }
    }

    struct MonthSection: Identifiable {
        let year: Int
        let month: Int
        let label: String
        var days: [DayLog]

        var id: String { "\(year)-\(month)" }
    }

    static func nonEmptyItems(of day: DayLog) -> [TodoItem] {
        day.orderedItems.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Aggregates for the Overview panel. Today is skipped — it's still in
    /// progress, and counting it would deflate the rate every morning.
    static func overview(
        days: [DayLog],
        calendar: Calendar = .current
    ) -> (stats: OverviewStats, weekdays: [WeekdayRow]) {
        var stats = OverviewStats()

        // All 7 weekdays, zeros included, starting at the locale's first
        // weekday, so the chart axis is stable regardless of the data.
        var rows = (0 ..< 7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return WeekdayRow(weekday: weekday, label: calendar.shortWeekdaySymbols[weekday - 1])
        }
        let rowIndexByWeekday = Dictionary(
            uniqueKeysWithValues: rows.enumerated().map { ($0.element.weekday, $0.offset) }
        )

        for day in days {
            guard !calendar.isDateInToday(day.date) else { continue }
            let tasks = nonEmptyItems(of: day)
            guard !tasks.isEmpty else { continue }

            let completed = tasks.filter(\.isCompleted).count
            stats.trackedDays += 1
            stats.totalTasks += tasks.count
            stats.completedTasks += completed

            guard let index = rowIndexByWeekday[calendar.component(.weekday, from: day.date)] else {
                continue
            }
            rows[index].tasksCompleted += completed
            if completed == tasks.count {
                stats.fullDays += 1
                rows[index].fullDaysCompleted += 1
            }
        }

        return (stats, rows)
    }

    /// Sidebar sections: days bucketed per calendar month. The input arrives
    /// date-descending (newest first) and that order is preserved, so the
    /// newest month is the first section.
    static func monthSections(days: [DayLog], calendar: Calendar = .current) -> [MonthSection] {
        var sections: [MonthSection] = []
        for day in days {
            let components = calendar.dateComponents([.year, .month], from: day.date)
            guard let year = components.year, let month = components.month else { continue }

            if let last = sections.indices.last, sections[last].year == year, sections[last].month == month {
                sections[last].days.append(day)
            } else {
                sections.append(MonthSection(
                    year: year,
                    month: month,
                    label: day.date.formatted(.dateTime.month(.wide).year()),
                    days: [day]
                ))
            }
        }
        return sections
    }
}
