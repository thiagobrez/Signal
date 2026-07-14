import SwiftUI
import SwiftData

/// The big notch surface opened by long-pressing the toggle hotkey: every
/// pending schedule laid out as a calendar, in Week, Month, or Year mode with
/// iOS-Calendar-style drill-down (year → month → week).
struct ScheduleOverviewView: View {
    let controller: NotchController
    @State private var model: ScheduleOverviewModel

    /// Fixed height for the mode body so the card doesn't jump when switching
    /// between Week, Month, and Year.
    private static let bodyHeight: CGFloat = 340

    init(repository: ScheduleRepository, controller: NotchController) {
        self.controller = controller
        _model = State(initialValue: ScheduleOverviewModel(repository: repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Group {
                switch model.mode {
                case .week: ScheduleWeekView(model: model)
                case .month: ScheduleMonthView(model: model)
                case .year: ScheduleYearView(model: model)
                }
            }
            .frame(height: Self.bodyHeight)
        }
        .padding(16)
        .frame(width: 660)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy(duration: 0.2), value: model.mode)
        .onKeyPress(.escape) {
            controller.hideOverview()
            return .handled
        }
        .onChange(of: controller.overviewPresentationRequest) { _, _ in model.reset() }
        .onAppear { model.reset() }
        // The panel is key while the overview is up, so plain-key shortcuts
        // reach these hidden buttons without any focused control.
        .background {
            Group {
                Button("") { controller.hideOverview() }
                    .keyboardShortcut(.cancelAction)
                Button("") { model.zoomOut() }
                    .keyboardShortcut(.upArrow, modifiers: [])
            }
            .buttonStyle(.plain)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("SCHEDULED")
                .font(.system(size: 10, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            Button(action: model.goPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Text(model.periodTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 170)

            Button(action: model.goNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button(action: model.goToToday) {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
            .keyboardShortcut("t", modifiers: [])

            Spacer()

            modeSwitcher
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.6))
    }

    /// A dark capsule segmented control — the system `.segmented` picker
    /// renders poorly on the black card.
    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleOverviewModel.ViewMode.allCases, id: \.self) { mode in
                Button {
                    model.mode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.mode == mode ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            if model.mode == mode {
                                Capsule().fill(.white.opacity(0.15))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}
