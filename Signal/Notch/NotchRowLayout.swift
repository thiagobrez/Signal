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
    /// Extra vertical space wedged in *above* a row, keyed by its index. The
    /// list uses it for the block that separates the two sections — the "Add a
    /// task" footer and the `SCHEDULED` header — which sits between the last
    /// regular row and the first scheduled one without being a row itself.
    let extras: [Int: CGFloat]

    init(heights: [CGFloat], spacing: CGFloat, extras: [Int: CGFloat] = [:]) {
        self.heights = heights
        self.spacing = spacing
        self.extras = extras
    }

    /// Every row plus the gaps between them and any extra blocks wedged in
    /// between; zero when there are no rows (an empty list has no gaps to
    /// account for either).
    var contentHeight: CGFloat {
        guard !heights.isEmpty else { return 0 }
        return heights.reduce(0, +)
            + CGFloat(heights.count - 1) * spacing
            + extras.values.reduce(0, +)
    }

    /// The row's top edge, measured from the top of the list.
    func top(of index: Int) -> CGFloat {
        let rows = heights.prefix(max(0, index)).reduce(0) { $0 + $1 + spacing }
        let blocks = extras.reduce(0) { $1.key <= index ? $0 + $1.value : $0 }
        return rows + blocks
    }

    /// How far the next row's top sits below this row's top.
    ///
    /// Deliberately blind to `extras`: it's the drag's unit of travel, and a
    /// drag never crosses a section gap — the view clamps a swap that would at
    /// the boundary, exactly as it does at either end of the list.
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
