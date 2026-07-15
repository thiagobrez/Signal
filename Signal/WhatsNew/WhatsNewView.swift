import SwiftUI

/// The "What's New" release notes: a single scrollable page listing, per
/// release, the new features (minor/major changes) and fixes (patch changes)
/// parsed from the bundled CHANGELOG.md. Hosted in a plain `NSWindow` by
/// `WhatsNewWindowController`; `onFinish` is called when the user continues.
struct WhatsNewView: View {
    let releases: [ChangelogRelease]
    /// Called when the user taps Continue. The window controller uses this to
    /// persist the "seen" version and close the window.
    let onFinish: () -> Void

    /// The opt-out checkbox writes the same key `SignalServices` gates the
    /// post-update auto-show on. The manual menu item ignores it.
    @AppStorage(SettingsStore.Key.showWhatsNewAfterUpdates)
    private var showAfterUpdates = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 22)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(releases, id: \.version) { release in
                        releaseSection(release)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.green)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            Text("What's New in Signal")
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage()
    }

    private var bottomBar: some View {
        HStack {
            Toggle("Show release notes after updates", isOn: $showAfterUpdates)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Continue") { onFinish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Releases

    @ViewBuilder
    private func releaseSection(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version \(release.version)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if !release.features.isEmpty {
                group(title: "New Features", icon: "star.fill", items: release.features)
            }
            if !release.fixes.isEmpty {
                group(title: "Fixes", icon: "wrench.and.screwdriver.fill", items: release.fixes)
            }
        }
    }

    private func group(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                        Text(item)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
