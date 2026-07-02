import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsStore.Key.carryOverIncomplete) private var carryOver = true
    @AppStorage(SettingsStore.Key.openOnLaunch) private var openOnLaunch = true
    @AppStorage(SettingsStore.Key.dailyPromptEnabled) private var dailyPromptEnabled = true
    @AppStorage(SettingsStore.Key.dailyPromptHour) private var dailyPromptHour = 9
    @AppStorage(SettingsStore.Key.dailyPromptMinute) private var dailyPromptMinute = 0
    @AppStorage(SettingsStore.Key.glancesEnabled) private var glancesEnabled = true
    @AppStorage(SettingsStore.Key.glanceCount) private var glanceCount = 3
    @AppStorage(SettingsStore.Key.glanceWindowStartHour) private var glanceStart = 10
    @AppStorage(SettingsStore.Key.glanceWindowEndHour) private var glanceEnd = 18
    @AppStorage(SettingsStore.Key.completionSound) private var completionSound = "pop"
    @AppStorage(SettingsStore.Key.celebrationSound) private var celebrationSound = "meadow"
    @AppStorage(SettingsStore.Key.openSound) private var openSound = "sys:Blow"

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                Toggle("Carry unfinished tasks over to the next day", isOn: $carryOver)
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Signal", name: .toggleSignal)
            }

            Section("Daily prompt") {
                Toggle("Open Signal when it launches", isOn: $openOnLaunch)
                Toggle("Open Signal every day at a set time", isOn: $dailyPromptEnabled)
                DatePicker("Time", selection: dailyPromptTime, displayedComponents: .hourAndMinute)
                    .disabled(!dailyPromptEnabled)
            }

            Section("Sound") {
                soundPicker("On open", selection: $openSound)
                soundPicker("On completion", selection: $completionSound)
                soundPicker("On all done", selection: $celebrationSound, includesCelebration: true)
            }

            Section("Quick reminders") {
                Toggle("Show quick glances during the day", isOn: $glancesEnabled)
                Stepper("Times per day: \(glanceCount)", value: $glanceCount, in: 0...12)
                    .disabled(!glancesEnabled)
                Picker("From", selection: $glanceStart) { hourOptions }
                    .disabled(!glancesEnabled)
                Picker("Until", selection: $glanceEnd) { hourOptions }
                    .disabled(!glancesEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private func soundPicker(
        _ label: String,
        selection: Binding<String>,
        includesCelebration: Bool = false
    ) -> some View {
        var customNames = SoundPlayer.bundledSoundNames
        if includesCelebration { customNames.append(SoundPlayer.celebrationOnlyID) }
        customNames.sort()

        return HStack {
            Picker(label, selection: selection) {
                Text("None").tag(SoundPlayer.noneID)
                Section("Custom") {
                    ForEach(customNames, id: \.self) { name in
                        Text(name.capitalized).tag(name)
                    }
                }
                Section("System") {
                    ForEach(SoundPlayer.systemSoundNames, id: \.self) { name in
                        Text(name).tag("sys:\(name)")
                    }
                }
            }
            Button {
                SoundPlayer.play(selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview")
            .disabled(selection.wrappedValue == SoundPlayer.noneID)
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24) { hour in
            Text(String(format: "%02d:00", hour)).tag(hour)
        }
    }

    private var dailyPromptTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: dailyPromptHour, minute: dailyPromptMinute, second: 0, of: Date()
            ) ?? Date()
        } set: { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyPromptHour = comps.hour ?? 9
            dailyPromptMinute = comps.minute ?? 0
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Reflect the real state if the change failed.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
