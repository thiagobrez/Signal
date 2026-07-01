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
    var day: DayLog?

    init(text: String = "", isCompleted: Bool = false, order: Int, completedAt: Date? = nil) {
        self.text = text
        self.isCompleted = isCompleted
        self.order = order
        self.completedAt = completedAt
    }
}
