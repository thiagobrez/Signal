//
//  NotchlessView.swift
//  DynamicNotchKit
//
//  Created by Kai Azim on 2024-04-06.
//

import SwiftUI

struct NotchlessView<Expanded, CompactLeading, CompactTrailing>: View where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>
    @State private var windowHeight: CGFloat = 0
    // [Signal patch] Interior inset around the content. Upstream is 15, which shows a
    // ring of popover material around the hosted card; zeroed so the card's own
    // background reaches the floating window's edges.
    private let safeAreaInset: CGFloat = 0
    // [Signal patch] Outer gap between the floating panel and its window. Upstream is 20.
    private let outerPadding: CGFloat = 0

    init(dynamicNotch: DynamicNotch<Expanded, CompactLeading, CompactTrailing>) {
        self.dynamicNotch = dynamicNotch
    }

    private var cornerRadius: CGFloat {
        if case let .floating(cornerRadius) = dynamicNotch.style {
            cornerRadius
        } else {
            20
        }
    }

    var body: some View {
        notchContent()
            .background {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .padding(outerPadding)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newHeight in
                // This makes sure that the floating window FULLY slides off before disappearing
                windowHeight = newHeight
            }
            .offset(y: dynamicNotch.state == .expanded ? dynamicNotch.notchSize.height : -windowHeight)
            .onHover(perform: dynamicNotch.updateHoverState)
    }

    private func notchContent() -> some View {
        VStack(spacing: 0) {
            dynamicNotch.expandedContent
                .transition(.blur(intensity: 10).combined(with: .opacity))
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: safeAreaInset) }
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
                .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: safeAreaInset) }
        }
        .fixedSize()
    }
}
