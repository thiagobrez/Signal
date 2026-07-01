import Foundation
import SwiftData

/// One record per calendar day. The full set of `DayLog`s is the history we keep
/// for future insights — prior days are never mutated.
@Model
final class DayLog {
    /// Start of the day (midnight, local). Unique so there is at most one log per day.
    @Attribute(.unique) var date: Date

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.day)
    var items: [TodoItem]

    init(date: Date) {
        self.date = date
        self.items = []
    }

    /// Items in slot order (0-based, contiguous).
    var orderedItems: [TodoItem] {
        items.sorted { $0.order < $1.order }
    }
}
