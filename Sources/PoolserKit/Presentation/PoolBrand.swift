import SwiftUI

public enum PoolTypography {
    public static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("AvenirNext-DemiBold", size: size, relativeTo: style)
    }

    public static func amount(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        heading(size, relativeTo: style).monospacedDigit()
    }
}

/// The brand accent is separate from the fee pool: its shape never implies a financial value.
public struct PoolBrandRibbon: View {
    private let animated: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(animated: Bool = true) { self.animated = animated }

    public var body: some View {
        let palette = GraphitePalette.current(scheme)
        ZStack(alignment: .topTrailing) {
            RibbonShape()
                .fill(LinearGradient(colors: [palette.brandStart.opacity(0.12), palette.brandStart, palette.brandEnd],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(RibbonShape().stroke(palette.brandStart.opacity(0.24), lineWidth: 0.5))
                .scaleEffect(x: 1, y: reduceMotion || appeared || !animated ? 1 : 0.2, anchor: .topTrailing)
            PoolEyes()
                .scaleEffect(1.35)
                .padding(.trailing, 22)
                .padding(.top, 16)
                .opacity(appeared || !animated ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.22), value: appeared)
        }
        .frame(height: 36)
        .opacity(appeared || !animated ? 1 : 0)
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.55), value: appeared)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.22, y: 0))
        p.addCurve(to: CGPoint(x: r.width * 0.70, y: r.height * 0.4),
                   control1: CGPoint(x: r.width * 0.44, y: -r.height * 0.05),
                   control2: CGPoint(x: r.width * 0.46, y: r.height * 0.7))
        p.addCurve(to: CGPoint(x: r.width, y: r.height),
                   control1: CGPoint(x: r.width * 0.91, y: -r.height * 0.1),
                   control2: CGPoint(x: r.width * 0.98, y: r.height * 0.6))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.closeSubpath()
        return p
    }
}

public struct PoolBrandMark: View {
    public init() {}
    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(GraphitePalette.current(scheme).brand)
            .overlay { PoolEyes() }
            .frame(width: 28, height: 26)
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}
