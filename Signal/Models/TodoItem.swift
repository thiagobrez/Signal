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
    /// Whether the task arrived from the schedule rather than being typed into
    /// today. Scheduled tasks live in their own section at the bottom of the
    /// panel, after every regular row, so a recurring task never claims one of
    /// the three Signal slots. The flag survives carry-over into the next day.
    var isScheduled: Bool = false
    var day: DayLog?

    init(
        text: String = "",
        isCompleted: Bool = false,
        order: Int,
        completedAt: Date? = nil,
        isScheduled: Bool = false
    ) {
        self.text = text
        self.isCompleted = isCompleted
        self.order = order
        self.completedAt = completedAt
        self.isScheduled = isScheduled
    }
}
