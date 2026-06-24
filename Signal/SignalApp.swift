import SwiftUI

@main
struct SignalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Signal", systemImage: "circle.dotted") {
            MenuBarContent()
        }

        Settings {
            PreferencesView()
        }
    }
}

private struct MenuBarContent: View {
    var body: some View {
        Button("Show / Hide Signal") {
            SignalServices.shared.controller.toggle()
        }

        Divider()

        SettingsLink {
            Text("Preferences…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Signal") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
