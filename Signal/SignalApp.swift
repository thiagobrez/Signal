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
    /// top-center edge and a checkmark-in-a-circle centered below it. Rendered
    /// as a template image so it adapts to light/dark menu bars.
    static let signalMenuBar: NSImage = {
        let size = NSSize(width: 20, height: 13)
        let strokeWidth: CGFloat = 1.4
        let inset: CGFloat = strokeWidth / 2 + 0.5
        let displayCornerRadius: CGFloat = 2.6

        let notchWidth: CGFloat = 7
        let notchDepth: CGFloat = 2.4
        let notchCornerRadius: CGFloat = 1

        let circleRadius: CGFloat = 3
        let innerLineWidth: CGFloat = 1.1

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

            // Checkmark in a circle, centered in the screen below the notch.
            let center = CGPoint(x: frame.midX, y: (bottom + frame.maxY) / 2)
            ctx.setLineWidth(innerLineWidth)
            ctx.addEllipse(in: CGRect(
                x: center.x - circleRadius,
                y: center.y - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            ))
            ctx.strokePath()

            let check = CGMutablePath()
            check.move(to: CGPoint(x: center.x - 1.6, y: center.y))
            check.addLine(to: CGPoint(x: center.x - 0.55, y: center.y + 1.05))
            check.addLine(to: CGPoint(x: center.x + 1.7, y: center.y - 1.3))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(check)
            ctx.strokePath()
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
