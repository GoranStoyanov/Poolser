import SwiftUI

/// Measures the actual price text so tiny token prices can sit near either edge without clipping.
struct RangePriceLabelLayout: Layout {
    let gauge: RangeGaugeLayout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let size = label.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        let size = label.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let center = gauge.labelCenter(labelWidth: size.width, containerWidth: bounds.width)
        label.place(at: CGPoint(x: bounds.minX + center, y: bounds.minY), anchor: .top,
                    proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}

struct PositionRangeTrack: View {
    let gauge: RangeGaugeLayout
    let colors: GraphitePalette.StatusColors
    let palette: GraphitePalette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track).frame(height: 3)
                Capsule().fill(colors.bandFill)
                    .frame(width: max((gauge.bandEnd - gauge.bandStart) * width, 4), height: 10)
                    .offset(x: gauge.bandStart * width)
                ForEach([gauge.bandStart, gauge.bandEnd], id: \.self) { bound in
                    Rectangle().fill(colors.tint.opacity(0.65)).frame(width: 1, height: 14)
                        .offset(x: min(bound * width, max(width - 1, 0)))
                }
                Capsule().fill(palette.barToday).frame(width: 3, height: 22)
                    .offset(x: min(max(gauge.marker * width - 1.5, 0), max(width - 3, 0)))
            }
            .frame(height: 22)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}
