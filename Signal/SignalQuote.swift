import SwiftUI

/// The Steve Jobs "signal vs. noise" quote, framed with stylish oversized
/// quotation marks. Shared by Preferences and the onboarding welcome page so
/// the two stay identical.
struct SignalQuote: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Every day, there's three things you gotta get done.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)

            Text("That’s called the signal.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)

            Text("Everything that stops you from getting it done is the noise.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)

            Text("— Steve Jobs")
                .font(.custom("Apple Chancery", size: 12))
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            quoteMark("“")
                .rotationEffect(.degrees(-12))
                .offset(x: 4, y: -2)
        }
        .overlay(alignment: .bottomTrailing) {
            quoteMark("”")
                .rotationEffect(.degrees(12))
                .offset(x: -4, y: -6)
        }
    }

    private func quoteMark(_ glyph: String) -> some View {
        Text(glyph)
            .font(.custom("Apple Chancery", size: 44))
            .foregroundStyle(.secondary.opacity(0.25))
    }
}
