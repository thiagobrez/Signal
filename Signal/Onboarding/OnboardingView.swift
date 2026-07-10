import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts

/// First-launch onboarding: a small paged tour that welcomes the user and
/// explains the ideas behind Signal — where it lives (the notch), the hotkey,
/// the three tasks (the signal), planning tasks ahead in plain words, the stats,
/// when it shows up, and the Preferences. Hosted in a plain `NSWindow` by
/// `OnboardingWindowController`; `onFinish` is called when the user reaches the
/// end (or taps Skip).
struct OnboardingView: View {
    /// Called when onboarding is completed or skipped. The window controller
    /// uses this to persist the "seen" flag and close the window.
    let onFinish: () -> Void

    @State private var page = 0
    /// Drives the direction of the slide transition between pages.
    @State private var forward = true

    private let pageCount = 8
    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                pageContent
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.green)
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0: WelcomePage()
        case 1: NotchPage()
        case 2: HotkeyPage()
        case 3: TasksPage()
        case 4: PlanAheadPage()
        case 5: StatsPage()
        case 6: SchedulePage()
        default: PreferencesPage()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(height: 40)
    }

    private var bottomBar: some View {
        ZStack {
            // Page dots: centered in the window, independent of the button
            // widths — so "Next" growing to "Get Started" doesn't shift them.
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .animation(.snappy(duration: 0.3), value: page)

            HStack {
                Button("Back") { go(to: page - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(page > 0 ? 1 : 0)
                    .disabled(page == 0)

                Spacer()

                Button(isLastPage ? "Get Started" : "Next") {
                    if isLastPage { onFinish() } else { go(to: page + 1) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Navigation

    private func go(to target: Int) {
        guard target >= 0, target < pageCount else { return }
        forward = target > page
        withAnimation(.snappy(duration: 0.3)) {
            page = target
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

// MARK: - Shared page scaffold

/// Common vertical layout for a page: a hero area (icon/illustration) that
/// springs in on appear, a title, and free-form content below.
private struct PageScaffold<Hero: View, Content: View>: View {
    let title: String
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            hero
                .frame(minHeight: 120)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            content
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.snappy(duration: 0.4)) { appeared = true }
        }
    }
}

/// A body paragraph styled consistently across pages.
private struct PageText: View {
    let text: String
    var secondary = false
    init(_ text: String, secondary: Bool = false) {
        self.text = text
        self.secondary = secondary
    }
    var body: some View {
        Text(text)
            .font(.system(size: secondary ? 12 : 14))
            .foregroundStyle(secondary ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A circular tinted glyph used as the hero on text-only pages.
private struct GlyphHero: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(.green)
            .frame(width: 88, height: 88)
            .background(Color.green.opacity(0.12), in: Circle())
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        PageScaffold(title: appName) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 124, height: 124)
        } content: {
            SignalQuote()
                .frame(maxWidth: 360)
        }
    }

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Signal"
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage()
    }
}

private struct NotchPage: View {
    var body: some View {
        PageScaffold(title: "Signal lives in your notch") {
            NotchLoopAnimation()
        } content: {
            PageText("It slides down from the top of your screen.\nYour day's tasks, always a glance away.")
        }
    }
}

/// A looping, zoomed-out mock of the top of a macOS desktop: the menu bar and
/// notch sit idle, then the Signal panel drops open with a few sketch tasks,
/// holds, and closes — over and over.
private struct NotchLoopAnimation: View {
    @State private var open = false

    private let screenW: CGFloat = 300
    private let screenH: CGFloat = 150
    private let closedW: CGFloat = 64
    private let closedH: CGFloat = 13
    private let openW: CGFloat = 152
    private let openH: CGFloat = 98

    var body: some View {
        ZStack(alignment: .top) {
            // Wallpaper.
            LinearGradient(
                colors: [Color(red: 0.17, green: 0.13, blue: 0.30), Color(red: 0.33, green: 0.21, blue: 0.44)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Menu bar.
            VStack(spacing: 0) {
                menuBar
                Spacer(minLength: 0)
            }

            // The notch, which expands into the Signal panel.
            panel
        }
        .frame(width: screenW, height: screenH)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .task { await runLoop() }
    }

    private var menuBar: some View {
        HStack(spacing: 6) {
            Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5)
            Capsule().fill(.white.opacity(0.45)).frame(width: 16, height: 4)
            Capsule().fill(.white.opacity(0.30)).frame(width: 12, height: 4)
            Spacer()
            Capsule().fill(.white.opacity(0.30)).frame(width: 9, height: 4)
            Capsule().fill(.white.opacity(0.30)).frame(width: 11, height: 4)
        }
        .padding(.horizontal, 9)
        .frame(height: 15)
        .background(.black.opacity(0.22))
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if open {
                sketchTasks
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .transition(.opacity)
            }
        }
        .frame(width: open ? openW : closedW, height: open ? openH : closedH)
        .background(.black)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: open ? 16 : 6,
                bottomTrailingRadius: open ? 16 : 6,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 10, y: 5)
    }

    private var sketchTasks: some View {
        VStack(alignment: .leading, spacing: 9) {
            sketchRow(done: true, width: 92)
            sketchRow(done: false, width: 112)
            sketchRow(done: false, width: 74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sketchRow(done: Bool, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(done ? Color.green : Color.clear)
                .overlay(Circle().strokeBorder(done ? Color.green : Color.white.opacity(0.35), lineWidth: 1.5))
                .frame(width: 11, height: 11)
            Capsule()
                .fill(.white.opacity(done ? 0.25 : 0.55))
                .frame(width: width, height: 5)
        }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            open = false
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { open = true }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) { open = false }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

private struct HotkeyPage: View {
    var body: some View {
        PageScaffold(title: "Summon it from anywhere") {
            HotkeyKeysView()
        } content: {
            VStack(spacing: 16) {
                PageText("Press your hotkey to bring it up — and put it away — from any app.")

                KeyboardShortcuts.Recorder("Toggle Signal", name: .toggleSignal)
                    .fixedSize()

                PageText("You can change this anytime.", secondary: true)
            }
        }
    }
}

/// The hero for the hotkey page: keycaps showing the current shortcut. Only
/// while the recorder below is focused (i.e. the user is actively recording) do
/// the caps track the modifiers being held live; otherwise they show the saved
/// shortcut and ignore keystrokes elsewhere.
private struct HotkeyKeysView: View {
    @State private var saved: [String] = []
    @State private var live: [String] = []
    @State private var recording = false

    // Lightweight poll: cheap (reads first responder + current modifier flags)
    // and only runs while this page is on screen.
    private let ticker = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var display: [String] { recording ? live : saved }

    var body: some View {
        HStack(spacing: 10) {
            if display.isEmpty {
                KeyCap(text: recording ? "…" : "·")
            } else {
                ForEach(Array(display.enumerated()), id: \.offset) { _, symbol in
                    KeyCap(text: symbol)
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: display)
        .animation(.snappy(duration: 0.15), value: recording)
        .onAppear { saved = Self.savedSymbols() }
        .onReceive(ticker) { _ in tick() }
    }

    private func tick() {
        if Self.isRecorderFocused() {
            recording = true
            live = Self.symbols(modifiers: NSEvent.modifierFlags, keyChar: nil)
        } else {
            recording = false
            saved = Self.savedSymbols()
        }
    }

    /// Whether the KeyboardShortcuts recorder currently holds keyboard focus. A
    /// focused text control edits through the window's field editor, whose
    /// delegate is the control itself (the recorder).
    private static func isRecorderFocused() -> Bool {
        guard
            let window = NSApp.keyWindow,
            let responder = window.firstResponder
        else { return false }

        if let editor = responder as? NSTextView {
            return editor.delegate.map(isRecorder) ?? false
        }
        return isRecorder(responder)
    }

    private static func isRecorder(_ object: AnyObject) -> Bool {
        String(describing: type(of: object)).contains("Recorder")
    }

    /// Modifier symbols in canonical display order, plus the key.
    private static func symbols(modifiers: NSEvent.ModifierFlags, keyChar: String?) -> [String] {
        var out: [String] = []
        if modifiers.contains(.control) { out.append("⌃") }
        if modifiers.contains(.option) { out.append("⌥") }
        if modifiers.contains(.shift) { out.append("⇧") }
        if modifiers.contains(.command) { out.append("⌘") }
        if let keyChar, !keyChar.isEmpty, keyChar != "\u{1b}" {
            out.append(keyChar.uppercased())
        }
        return out
    }

    private static func savedSymbols() -> [String] {
        guard
            let shortcut = KeyboardShortcuts.getShortcut(for: .toggleSignal),
            let keyChar = shortcut.description.last
        else { return [] }
        return symbols(modifiers: shortcut.modifiers, keyChar: String(keyChar))
    }
}

private struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .frame(minWidth: 46, minHeight: 46)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }
}

private struct TasksPage: View {
    var body: some View {
        PageScaffold(title: "Three tasks. That's the Signal.") {
            TasksChecklistAnimation()
        } content: {
            VStack(spacing: 12) {
                PageText("Each day, pick the three things that actually matter.\nGet them done, and you've moved the needle.")
                PageText("Don't worry, you can add extra tasks, but we encourage you not to.\nCut the noise.", secondary: true)
            }
        }
    }
}

/// A looping checklist: the three tasks tick off one by one — checkmark pop plus
/// a strikethrough that draws across — then reset and repeat.
private struct TasksChecklistAnimation: View {
    @State private var doneCount = 0

    private let tasks = ["Ship the onboarding", "Reply to that email", "Plan tomorrow"]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { index, text in
                row(text: text, done: index < doneCount)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .task { await runLoop() }
    }

    private func row(text: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            checkbox(done: done)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize()
                .overlay(alignment: .leading) {
                    // Strikethrough that draws in from the left.
                    Rectangle()
                        .fill(.secondary)
                        .frame(height: 1.2)
                        .scaleEffect(x: done ? 1 : 0, anchor: .leading)
                }
            Spacer(minLength: 0)
        }
    }

    private func checkbox(done: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                .opacity(done ? 0 : 1)
                .scaleEffect(done ? 0.5 : 1)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
                .opacity(done ? 1 : 0)
                .scaleEffect(done ? 1 : 0.4)
        }
        .frame(width: 16, height: 16)
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            doneCount = 0
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.35)) { doneCount = 1 }
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.35)) { doneCount = 2 }
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.35)) { doneCount = 3 }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { doneCount = 0 }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

private struct PlanAheadPage: View {
    var body: some View {
        PageScaffold(title: "Plan ahead, in plain words") {
            ScheduleTypingAnimation()
        } content: {
            VStack(spacing: 12) {
                PageText("Add a day to any task as you type — “tomorrow”, “monday”, “in 2 weeks”.\nIt shows up on its own when it's due.")
                PageText("Make it recurring with “every day” or “every Monday”.", secondary: true)
            }
        }
    }
}

/// A looping demo of natural-language scheduling: a task types itself out, the
/// trailing date word lights up green with the ↵ confirm hint, then Enter files
/// it away as “Scheduled for tomorrow” — before clearing and starting over.
private struct ScheduleTypingAnimation: View {
    @State private var typed = ""
    @State private var highlighting = false
    @State private var confirmed = false
    @State private var caretOn = true

    private let base = "Do the dishes"
    private let phrase = "tomorrow"
    private var fullText: String { "\(base) \(phrase)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            activeRow
            placeholderRow
        }
        .padding(15)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .task { await runLoop() }
    }

    private var activeRow: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(.white.opacity(confirmed ? 0.2 : 0.35), lineWidth: 1.5)
                .frame(width: 17, height: 17)

            ZStack(alignment: .leading) {
                if confirmed {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Scheduled for tomorrow")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.green)
                    .transition(.opacity)
                } else if highlighting {
                    HStack(spacing: 5) {
                        Text(base)
                            .foregroundStyle(.white)
                        Text(phrase)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Color.green.opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .font(.system(size: 14, weight: .medium))
                } else {
                    HStack(spacing: 1) {
                        Text(typed)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2, height: 17)
                            .opacity(caretOn ? 1 : 0.15)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "return")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .opacity(highlighting && !confirmed ? 1 : 0)
        }
    }

    private var placeholderRow: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                .frame(width: 17, height: 17)
            Text("Prep for the week…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func runLoop() async {
        // The caret pulses independently for the life of the view.
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            caretOn = false
        }
        while !Task.isCancelled {
            typed = ""
            highlighting = false
            confirmed = false
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }

            // Type the task out, character by character.
            for index in fullText.indices {
                typed = String(fullText[...index])
                try? await Task.sleep(for: .seconds(0.055))
                guard !Task.isCancelled else { return }
            }

            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.3)) { highlighting = true }

            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.35)) { confirmed = true }

            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                confirmed = false
                highlighting = false
                typed = ""
            }
            try? await Task.sleep(for: .seconds(0.7))
        }
    }
}

private struct StatsPage: View {
    var body: some View {
        PageScaffold(title: "See your progress") {
            StatsLoopAnimation()
        } content: {
            VStack(spacing: 14) {
                PageText("Look back on every day — your completion rate, and the days you finished in full.")
                PageText("Open Task Stats anytime with its own hotkey.", secondary: true)
            }
        }
    }
}

/// A looping mock of the Task Stats window: the completion ring sweeps up to a
/// percentage while the weekday bars rise, holds, then resets and repeats.
private struct StatsLoopAnimation: View {
    @State private var filled = false

    /// Relative bar heights (0–1), tallest on the right — echoes the app's
    /// "best day of the week" chart.
    private let bars: [CGFloat] = [0.45, 0.3, 0.38, 0.68, 0.42, 0.72, 1.0]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                sidebar
                Divider().opacity(0.4)
                content
            }
        }
        .frame(width: 320, height: 188)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .task { await runLoop() }
    }

    private var titleBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { _ in
                Circle().fill(Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                Capsule().fill(Color.primary.opacity(0.4)).frame(width: 40, height: 5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.green.opacity(0.15))
            )

            dayRow(width: 46, done: true)
            dayRow(width: 38, done: true)
            dayRow(width: 52, done: false)
            dayRow(width: 34, done: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 104)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
    }

    private func dayRow(width: CGFloat, done: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: width, height: 5)
            Spacer(minLength: 0)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            } else {
                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 11, height: 5)
            }
        }
        .padding(.horizontal, 4)
    }

    private var content: some View {
        VStack(spacing: 8) {
            donutCard
            barsCard
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var donutCard: some View {
        HStack(spacing: 12) {
            DonutRing(progress: filled ? 0.70 : 0)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 7) {
                statLine(value: 54, label: 40)
                statLine(value: 46, label: 34)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func statLine(value: CGFloat, label: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.primary.opacity(0.45)).frame(width: value, height: 6)
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: label, height: 4)
        }
    }

    private var barsCard: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(bars.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.blue.opacity(0.85))
                    .frame(width: 9, height: max(3, (filled ? bars[index] : 0.06) * 34))
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.05),
                        value: filled
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            filled = false
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.85)) { filled = true }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { filled = false }
            try? await Task.sleep(for: .seconds(0.7))
        }
    }
}

/// A donut whose sweep and centered percentage stay in lock-step: because the
/// view is `Animatable`, its `progress` is interpolated frame-by-frame, so the
/// number counts up as the ring fills.
private struct DonutRing: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let clamped = max(0, min(1, progress))
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

private struct SchedulePage: View {
    var body: some View {
        PageScaffold(title: "Show up on schedule") {
            GlyphHero(systemName: "calendar.badge.clock")
        } content: {
            VStack(spacing: 16) {
                // Sized to its widest row (not stretched to full width) so the
                // block centers as a unit directly under the title.
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "sunrise",
                        title: "Opens at the start of your day",
                        detail: "Launch at login, or at a time you choose."
                    )
                    featureRow(
                        icon: "clock.arrow.circlepath",
                        title: "Quick glances through the day",
                        detail: "Brief, gentle check-ins to keep your Signal in view."
                    )
                }
                .fixedSize()

                PageText("Fine-tune it all in Preferences.", secondary: true)
            }
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

private struct PreferencesPage: View {
    var body: some View {
        PageScaffold(title: "Make it yours") {
            GlyphHero(systemName: "slider.horizontal.3")
        } content: {
            VStack(spacing: 16) {
                PageText("Customize sounds, your hotkey, and when Signal shows up.")

                SettingsLink {
                    Text("Open Preferences…")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
