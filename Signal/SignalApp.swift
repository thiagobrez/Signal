import SwiftUI

@main
struct SignalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(nsImage: .signalMenuBar)
        }

        Settings {
            PreferencesView()
        }
    }
}

extension NSImage {
    /// Minimal display-with-notch glyph used for the menu bar item. A stroked
    /// rounded rectangle (the screen) with a shallow notch hanging from the
    /// top-center edge. Rendered as a template image so it adapts to
    /// light/dark menu bars.
    static let signalMenuBar: NSImage = {
        let size = NSSize(width: 20, height: 13)
        let strokeWidth: CGFloat = 1.4
        let inset: CGFloat = strokeWidth / 2 + 0.5
        let displayCornerRadius: CGFloat = 2.6

        let notchWidth: CGFloat = 7
        let notchDepth: CGFloat = 2.4
        let notchCornerRadius: CGFloat = 1

        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.set()

            let frame = rect.insetBy(dx: inset, dy: inset)

            // Screen outline.
            ctx.addPath(CGPath(
                roundedRect: frame,
                cornerWidth: displayCornerRadius,
                cornerHeight: displayCornerRadius,
                transform: nil
            ))
            ctx.setLineWidth(strokeWidth)
            ctx.strokePath()

            // Notch: a shallow rounded tab hanging from the top-center edge.
            let cx = frame.midX
            let left = cx - notchWidth / 2
            let right = cx + notchWidth / 2
            let top = frame.minY
            let bottom = top + notchDepth

            let notch = CGMutablePath()
            notch.move(to: CGPoint(x: left, y: top))
            notch.addLine(to: CGPoint(x: left, y: bottom - notchCornerRadius))
            notch.addQuadCurve(
                to: CGPoint(x: left + notchCornerRadius, y: bottom),
                control: CGPoint(x: left, y: bottom)
            )
            notch.addLine(to: CGPoint(x: right - notchCornerRadius, y: bottom))
            notch.addQuadCurve(
                to: CGPoint(x: right, y: bottom - notchCornerRadius),
                control: CGPoint(x: right, y: bottom)
            )
            notch.addLine(to: CGPoint(x: right, y: top))
            notch.closeSubpath()

            ctx.addPath(notch)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
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
