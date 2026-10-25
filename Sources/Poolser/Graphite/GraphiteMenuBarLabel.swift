import SwiftUI

/// Status item content: position value, unclaimed fees and a dot while a position needs
/// attention.
///
/// `MenuBarExtra` labels draw only `Text` and `Image`, so the live app has to render this view
/// to an image (`ImageRenderer`) rather than use it as the label directly.
struct GraphiteMenuBarLabel: View {
    let totalValueUSD: Double
    let unclaimedFeesUSD: Double
    var needsAttention = false

    var body: some View {
        HStack(spacing: 6) {
            Text(PositionPresentation.compactUSD(totalValueUSD))
            Rectangle()
                .fill(.primary.opacity(0.3))
                .frame(width: 1, height: 11)
            Text(formatUSD(unclaimedFeesUSD))
            if needsAttention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("A position needs attention")
            }
        }
        .font(.body.weight(.semibold).monospacedDigit())
        .fixedSize()
    }
}
