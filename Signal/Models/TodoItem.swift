import Foundation
import SwiftData

/// A single to-do. A `DayLog` holds at least three, and more once the user adds
/// them; `order` is its slot position within the day.
@Model
final class TodoItem {
    var text: String
    var isCompleted: Bool
    var order: Int
    var completedAt: Date?
    /// Whether the task was delivered by a recurring schedule ("every day",
    /// "every monday"). Routines live in their own `ROUTINES` section at the
    /// bottom of the panel, after every regular row, so they never claim one
    /// of the three Signal slots. The flag survives carry-over into the next
    /// day. A task delivered by a one-time schedule is an ordinary row.
    var isRoutine: Bool = false
    /// Legacy: builds before the Routines section set this on *anything* the
    /// schedule delivered. Nothing writes `true` any more — it now only marks a
    /// row that hasn't been reclassified yet, see
    /// `SignalStore.upgradeLegacyScheduledItems`.
    var isScheduled: Bool = false
    var day: DayLog?

    init(
        text: String = "",
        isCompleted: Bool = false,
        order: Int,
        completedAt: Date? = nil,
        isRoutine: Bool = false
    ) {
        self.text = text
        self.isCompleted = isCompleted
        self.order = order
        self.completedAt = completedAt
        self.isRoutine = isRoutine
    }
}
