import Charts
import SwiftUI

/// The "Overview" detail panel: overall completion-rate donut plus the
/// weekday bar chart. `days` arrives pre-filtered by the sidebar's month/year
/// filter, so the charts double as per-month stats.
struct OverviewView: View {
    let days: [DayLog]

    var body: some View {
        let (stats, weekdays) = StatsCalculator.overview(days: days)

        if stats.trackedDays == 0 {
            ContentUnavailableView(
                "No history yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Stats cover finished days — come back after your first one.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    completionSection(stats)
                    weekdaySection(weekdays)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Completion rate

    private func completionSection(_ stats: StatsCalculator.OverviewStats) -> some View {
        GroupBox("Task completion") {
            HStack(spacing: 24) {
                donut(rate: stats.completionRate)
                    .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 12) {
                    statLine(
                        value: "\(stats.completedTasks) of \(stats.totalTasks)",
                        label: "tasks completed"
                    )
                    statLine(
                        value: "\(stats.fullDays) of \(stats.trackedDays)",
                        label: "days fully completed"
                    )
                }

                Spacer()
            }
            .padding(8)
        }
    }

    private func donut(rate: Double) -> some View {
        Chart {
            SectorMark(angle: .value("Completed", rate), innerRadius: .ratio(0.72), angularInset: 1)
                .foregroundStyle(.green)
            SectorMark(angle: .value("Remaining", 1 - rate), innerRadius: .ratio(0.72), angularInset: 1)
                .foregroundStyle(Color.secondary.opacity(0.2))
        }
        .chartLegend(.hidden)
        .overlay {
            Text(rate.formatted(.percent.precision(.fractionLength(0))))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func statLine(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Weekday chart

    private func weekdaySection(_ rows: [StatsCalculator.WeekdayRow]) -> some View {
        GroupBox("By day of the week") {
            Chart(rows) { row in
                BarMark(
                    x: .value("Weekday", row.label),
                    y: .value("Count", row.tasksCompleted)
                )
                .foregroundStyle(by: .value("Metric", "Tasks completed"))
                .position(by: .value("Metric", "Tasks completed"))

                BarMark(
                    x: .value("Weekday", row.label),
                    y: .value("Count", row.fullDaysCompleted)
                )
                .foregroundStyle(by: .value("Metric", "Full days completed"))
                .position(by: .value("Metric", "Full days completed"))
            }
            // Charts sorts string categories alphabetically — pin locale order.
            .chartXScale(domain: rows.map(\.label))
            .chartForegroundStyleScale([
                "Tasks completed": Color.accentColor,
                "Full days completed": Color.green,
            ])
            .frame(height: 220)
            .padding(8)
        }
    }
}
