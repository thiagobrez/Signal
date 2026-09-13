import CoreGraphics

/// The vertical geometry of the task list: where each row sits, how tall the
/// stack is, and how far a dragged row has to travel before it swaps with the
/// neighbour it's passing.
///
/// Rows used to be a fixed height, so all of this was a single multiplication.
/// Now that long tasks wrap onto extra lines every row can be a different
/// height, and the arithmetic has to walk the measured heights instead. It's
/// pulled out of the view — pure numbers, no SwiftUI — so the thresholds the
/// drag depends on can be pinned by unit tests.
struct NotchRowLayout {
    /// Each row's measured height, in list order.
    let heights: [CGFloat]
    /// The gap between two consecutive rows.
    let spacing: CGFloat

    /// Every row plus the gaps between them; zero when there are no rows (an
    /// empty list has no gaps to account for either).
    var contentHeight: CGFloat {
        guard !heights.isEmpty else { return 0 }
        return heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing
    }

    /// The row's top edge, measured from the top of the list.
    func top(of index: Int) -> CGFloat {
        heights.prefix(max(0, index)).reduce(0) { $0 + $1 + spacing }
    }

    /// How far the next row's top sits below this row's top.
    func stride(of index: Int) -> CGFloat {
        guard heights.indices.contains(index) else { return spacing }
        return heights[index] + spacing
    }

    /// Whether the row sits fully inside the viewport. The slack absorbs the
    /// fractional offsets SwiftUI's scrolling rests at.
    func isVisible(
        _ index: Int,
        scrollOrigin: CGFloat,
        viewportHeight: CGFloat,
        slack: CGFloat = 1
    ) -> Bool {
        guard heights.indices.contains(index) else { return false }
        let top = top(of: index)
        let bottom = top + heights[index]
        return top >= scrollOrigin - slack && bottom <= scrollOrigin + viewportHeight + slack
    }

    /// The swap a drag has earned, if any: once the row has travelled more than
    /// half the neighbour it's passing, the two change places. The distance is
    /// the neighbour's own stride — with rows of different heights, passing a
    /// wrapped row takes further than passing a single-line one.
    func swapStep(from index: Int, offset: CGFloat) -> (to: Int, distance: CGFloat)? {
        guard offset != 0 else { return nil }
        let to = offset > 0 ? index + 1 : index - 1
        guard heights.indices.contains(to) else { return nil }
        let distance = heights[to] + spacing
        guard abs(offset) > distance / 2 else { return nil }
        return (to, distance)
    }

    /// How far past its slot a row at either end of the list may be dragged
    /// before it's held back — half its own stride, so it hangs level with
    /// where the neighbour that isn't there would have been.
    func boundaryLimit(at index: Int) -> CGFloat {
        stride(of: index) / 2
    }
}
