import SwiftUI

/// Year mode: twelve mini-months; days with at least one occurrence render
/// green. Clicking a month drills down to Month mode.
struct ScheduleYearView: View {
    let model: ScheduleOverviewModel

    private let calendar = Calendar.current
    private static let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
    private static let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        // One pass over the tasks for the whole grid.
        let taskDays = model.taskDaysInYear()

        VStack(spacing: 0) {
            LazyVGrid(columns: Self.monthColumns, alignment: .leading, spacing: 12) {
                ForEach(model.yearMonths, id: \.self) { month in
                    miniMonth(month, taskDays: taskDays)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func miniMonth(_ month: Date, taskDays: Set<Date>) -> some View {
        let isCurrent = calendar.isDate(month, equalTo: Date(), toGranularity: .month)

        return Button {
            model.drillDown(toMonth: month)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(monthName(month))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCurrent ? .green : .white.opacity(0.7))

                // Always six week-rows (42 slots) so every mini-month is the
                // same height and months don't shift as you page between years.
                LazyVGrid(columns: Self.dayColumns, spacing: 1) {
                    ForEach(Array(monthSlots(of: month).enumerated()), id: \.offset) { _, slot in
                        if let day = slot {
                            Text(dayNumber(day))
                                .font(.system(size: 7, weight: taskDays.contains(day) ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(taskDays.contains(day) ? .green : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(" ")
                                .font(.system(size: 7))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A fixed 42-slot (6×7) Monday-first grid for the month: leading nil pads
    /// before day 1, the days, then trailing nil pads to 42.
    private func monthSlots(of month: Date) -> [Date?] {
        let blanks = (calendar.component(.weekday, from: month) + 5) % 7
        guard let range = calendar.range(of: .day, in: .month, for: month) else {
            return Array(repeating: nil, count: 42)
        }
        var slots: [Date?] = Array(repeating: nil, count: blanks)
        slots += range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        slots += Array(repeating: nil, count: max(0, 42 - slots.count))
        return slots
    }

    private func monthName(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: month)
    }

    private func dayNumber(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
}
