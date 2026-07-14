import SwiftUI

/// Month mode: a Monday-first grid of the anchor month with occurrence dots.
/// Clicking a day drills down to its week.
struct ScheduleMonthView: View {
    let model: ScheduleOverviewModel

    private let calendar = Calendar.current
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(model.monthCells, id: \.self) { day in
                    cell(day)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func cell(_ day: Date) -> some View {
        let inMonth = model.isInAnchorMonth(day)
        let isToday = calendar.isDateInToday(day)
        let count = model.taskCount(on: day)

        return Button {
            model.drillDown(to: day)
        } label: {
            VStack(spacing: 3) {
                Text(dayNumber(day))
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .black : .white)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(.green)
                        }
                    }

                HStack(spacing: 2) {
                    ForEach(0 ..< min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                    }
                    if count > 3 {
                        Text("+")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(inMonth ? 1 : 0.25)
    }

    private func dayNumber(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
}
