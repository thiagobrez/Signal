import SwiftData
import SwiftUI

/// Root of the Task Stats window: the pinned Overview entry plus a
/// month-grouped day list on the left, charts or a single day's tasks on the
/// right.
struct StatsView: View {
    /// Relays taps from the titlebar accessory's sidebar-toggle button.
    let windowState: StatsWindowState

    /// Live query so the window can stay open while tasks are toggled in the
    /// notch — both run on the same `mainContext`, so edits flow straight in.
    @Query(sort: \DayLog.date, order: .reverse) private var days: [DayLog]

    @State private var selection: SidebarSelection? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// `nil` = all. Months use `Calendar` numbering (1...12).
    @State private var monthFilter: Int?
    @State private var yearFilter: Int?

    private let calendar = Calendar.current

    enum SidebarSelection: Hashable {
        case overview
        /// Keyed by the day's (unique) date rather than its model identifier,
        /// so selection survives query refreshes.
        case day(Date)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                // The default toggle lives in the sidebar's toolbar and
                // shifts with it; the fixed one in the titlebar accessory
                // replaces it (see StatsTitlebarAccessory).
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detail
        }
        // Animate the toggle here (not in the accessory's separate hosting
        // view) so the transaction reaches the split view and the detail pane
        // reflows in step with the sidebar rather than snapping at the end.
        .onChange(of: windowState.toggleCount) {
            withAnimation(.easeInOut(duration: 0.28)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Static breathing room between the filter bar and the Overview
            // row. A `contentMargins(.top:)` here instead is a scroll-content
            // inset that SwiftUI recomputes every frame as the column relayouts
            // during the collapse animation, which nudges the first row.
            Color.clear.frame(height: 8)

            List(selection: $selection) {
                Label("Overview", systemImage: "chart.bar.xaxis")
                    .tag(SidebarSelection.overview)

                ForEach(StatsCalculator.monthSections(days: visibleDays, calendar: calendar)) { section in
                    Section(section.label) {
                        ForEach(section.days, id: \.date) { day in
                            dayRow(day)
                                .tag(SidebarSelection.day(day.date))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Picker("Month", selection: $monthFilter) {
                Text("All Months").tag(Int?.none)
                ForEach(Array(1...12), id: \.self) { month in
                    Text(calendar.monthSymbols[month - 1]).tag(Int?.some(month))
                }
            }
            Picker("Year", selection: $yearFilter) {
                Text("All Years").tag(Int?.none)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func dayRow(_ day: DayLog) -> some View {
        let tasks = StatsCalculator.nonEmptyItems(of: day)
        let completed = tasks.filter(\.isCompleted).count

        return HStack {
            Text(dayLabel(for: day.date))
            Spacer()
            if !tasks.isEmpty, completed == tasks.count {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(completed)/\(tasks.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview, nil:
            // Pre-filtered days, so Overview doubles as per-month stats when
            // a filter is active.
            OverviewView(days: visibleDays)
        case .day(let date):
            // Looked up in the unfiltered list so an already-open day keeps
            // rendering even when a filter hides it from the sidebar.
            if let day = days.first(where: { $0.date == date }) {
                DayDetailView(day: day, isToday: calendar.isDateInToday(date))
            } else {
                ContentUnavailableView("No day selected", systemImage: "calendar")
            }
        }
    }

    // MARK: - Data

    /// Days that show in the sidebar and feed the Overview: anything with at
    /// least one real task, plus today (even while still empty), narrowed by
    /// the month/year filter.
    private var visibleDays: [DayLog] {
        days.filter { day in
            if let yearFilter, calendar.component(.year, from: day.date) != yearFilter {
                return false
            }
            if let monthFilter, calendar.component(.month, from: day.date) != monthFilter {
                return false
            }
            return calendar.isDateInToday(day.date) || !StatsCalculator.nonEmptyItems(of: day).isEmpty
        }
    }

    /// Distinct years present in the history, newest first (input is
    /// date-descending).
    private var availableYears: [Int] {
        var seen = Set<Int>()
        return days.compactMap { day in
            let year = calendar.component(.year, from: day.date)
            return seen.insert(year).inserted ? year : nil
        }
    }

    private func dayLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if !calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }
}
