import SwiftUI

/// Week mode: a dedicated "Every day" section for daily tasks, then one
/// vertical row per day, Monday through Sunday.
struct ScheduleWeekView: View {
    let model: ScheduleOverviewModel

    private let calendar = Calendar.current

    var body: some View {
        if model.weekIsEmpty {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !model.dailyTasks.isEmpty {
                        everydaySection
                        Divider().overlay(.white.opacity(0.1))
                    }

                    ForEach(model.weekDays, id: \.self) { day in
                        dayRow(day)
                    }
                }
            }
        }
    }

    private var everydaySection: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text("EVERY DAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.green.opacity(0.8))
            }
            .frame(width: 64, alignment: .leading)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.dailyTasks, id: \.persistentModelID) { task in
                    ScheduledTaskRow(task: task, model: model)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.green.opacity(0.06))
        )
        .padding(.bottom, 4)
    }

    private func dayRow(_ day: Date) -> some View {
        let entries = model.entries(on: day)
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: Date()) && !isToday
        let isHighlighted = model.highlightedDay == day

        return HStack(alignment: .top, spacing: 12) {
            // Single compact line to keep the week rows dense (days with many
            // tasks grow taller and the week scrolls).
            // The weekday label is fixed-width so the day numbers line up in a
            // column regardless of "WED" being wider than "TUE".
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(weekdayLabel(day))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .frame(width: 30, alignment: .leading)
                Text(dayNumber(day))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isToday ? .green : .white.opacity(isPast ? 0.25 : 0.5))
            .frame(width: 64, alignment: .leading)
            .padding(.top, 3)

            if entries.isEmpty {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .scheduled(let task):
                            ScheduledTaskRow(task: task, model: model)
                        case .todo(let item):
                            DayTaskRow(item: item)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.25))
            Text("Nothing scheduled this week")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("Type a task ending in \u{201C}tomorrow\u{201D} or \u{201C}every monday\u{201D} in the Signal panel")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: day).uppercased()
    }

    private func dayNumber(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: day)
    }
}
