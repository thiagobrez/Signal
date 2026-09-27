import Foundation
import SwiftData

/// A single thing shown on a day in the overview: either an upcoming schedule
/// or one of that day's actual to-dos.
enum OverviewEntry: Identifiable {
    case scheduled(ScheduledTask)
    case todo(TodoItem)

    var id: PersistentIdentifier {
        switch self {
        case .scheduled(let task): return task.persistentModelID
        case .todo(let item): return item.persistentModelID
        }
    }

    var text: String {
        switch self {
        case .scheduled(let task): return task.text
        case .todo(let item): return item.text
        }
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One editable row of the week, in the order the keyboard walks them. Rows are
/// grouped so Tab on the last row of a group can spill into a fresh row on the
/// same day, exactly as it does at the bottom of the panel's list.
struct OverviewFocusRow: Identifiable {
    /// Which run of rows this one belongs to.
    enum Group: Equatable {
        /// The EVERY DAY section, which belongs to no single day.
        case daily
        /// Today's own tasks, and below them the ones its schedule delivered.
        case todayRegular
        case todayScheduled
        case future(Date)
    }

    let entry: OverviewEntry
    /// The day the row is drawn on; nil in the EVERY DAY section.
    let day: Date?
    let group: Group

    var id: PersistentIdentifier { entry.id }

    /// The day a Tab off the end of this group adds to — nil for the groups
    /// that have no add button of their own.
    var addDay: Date? {
        switch group {
        case .daily, .todayScheduled: return nil
        case .todayRegular: return day
        case .future(let day): return day
        }
    }
}
