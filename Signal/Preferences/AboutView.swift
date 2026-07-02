import AppKit
import SwiftUI

/// The "About" tab in Preferences: the app's identity (icon, name, version), a
/// small "built by" credit mirroring the website footer, and buttons out to the
/// source repository and the open-source acknowledgements (the latter opens in
/// a sheet rather than living inline here).
struct AboutView: View {
    @State private var showingAcknowledgements = false

    private static let repoURL = URL(string: "https://github.com/thiagobrez/Signal")!
    private static let authorGitHubURL = URL(string: "https://github.com/thiagobrez")!
    private static let authorXURL = URL(string: "https://x.com/thiagobrez")!
    private static let avatarURL = URL(string: "https://github.com/thiagobrez.png?size=128")!

    var body: some View {
        VStack(spacing: 20) {
            appIdentity
            buttons
            SignalQuote()
                .frame(maxWidth: 360)
            Divider().frame(width: 200)
            builtBy
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(width: 440)
        .sheet(isPresented: $showingAcknowledgements) {
            AcknowledgementsView()
        }
    }

    // MARK: - App identity

    private var appIdentity: some View {
        VStack(spacing: 10) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            Text(Self.appName)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(Self.versionString)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Built by

    private var builtBy: some View {
        HStack(spacing: 12) {
            AsyncImage(url: Self.avatarURL) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text("Built by Thiago Brezinski")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 12) {
                    Link("GitHub", destination: Self.authorGitHubURL)
                    Text("·").foregroundStyle(.tertiary)
                    Link("X", destination: Self.authorXURL)
                }
                .font(.system(size: 12))
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 12) {
            Link(destination: Self.repoURL) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.bordered)

            Button {
                showingAcknowledgements = true
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Bundle values

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Signal"
    }

    private static var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage()
    }

    /// e.g. "Version 1.0.1 (1)" — marketing version plus the build number.
    private static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}
