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
    private let compact: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(animated: Bool = true, compact: Bool = false) {
        self.animated = animated
        self.compact = compact
    }

    public var body: some View {
        let palette = GraphitePalette.current(scheme)
        let surface = compact ? palette.popover : palette.card
        let height: CGFloat = compact ? 36 : 54
        let eyesWidth: CGFloat = compact ? 34 : 52
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                CrestShape(front: false)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.35, green: 0.80, blue: 0.42), location: 0.3),
                            .init(color: Color(red: 0.19, green: 0.72, blue: 0.65), location: 0.66),
                            .init(color: Color(red: 0.18, green: 0.51, blue: 0.94), location: 1)
                        ],
                        startPoint: .trailing, endPoint: .leading
                    ))
                // A low highlight rounds the crest without turning the whole card glossy.
                CrestShape(front: false)
                    .fill(LinearGradient(colors: [.white.opacity(0.3), .clear, .clear],
                                         startPoint: .top, endPoint: .bottom))
                PoolEyes(width: eyesWidth)
                    .padding(.top, height * 0.29)
                    .padding(.leading, compact ? 16 : 22)
                    .opacity(appeared || !animated ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.22), value: appeared)
                CrestShape(front: true)
                    .fill(surface)
                CrestEdge()
                    .stroke(palette.brandEnd.opacity(scheme == .dark ? 0.2 : 0.12), lineWidth: 3)
                    .blur(radius: 2)
                CrestEdge()
                    .stroke(LinearGradient(colors: [surface, .white.opacity(0.75), palette.brandEnd.opacity(0.35)],
                                           startPoint: .leading, endPoint: .trailing), lineWidth: 0.8)
            }
            .frame(width: geometry.size.width, height: height)
            .scaleEffect(x: 1, y: reduceMotion || appeared || !animated ? 1 : 0.2, anchor: .topLeading)
        }
        .frame(height: height)
        .opacity(appeared || !animated ? 1 : 0)
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.55), value: appeared)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CrestShape: Shape {
    let front: Bool

    func path(in r: CGRect) -> Path {
        var p = CrestEdge.curve(in: r, front: front)
        if front {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        }
        p.closeSubpath()
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: r.width, ty: 0))
    }
}

private struct CrestEdge: Shape {
    func path(in r: CGRect) -> Path {
        Self.curve(in: r, front: true)
            .applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: r.width, ty: 0))
    }

    static func curve(in r: CGRect, front: Bool) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: r.width * 0.25, y: 0))
        p.addCurve(to: CGPoint(x: r.width * 0.61, y: r.height * (front ? 0.82 : 0.56)),
                   control1: CGPoint(x: r.width * 0.43, y: 0),
                   control2: CGPoint(x: r.width * 0.46, y: r.height * (front ? 0.89 : 0.63)))
        p.addCurve(to: CGPoint(x: r.width, y: r.height * (front ? 0.78 : 1)),
                   control1: CGPoint(x: r.width * 0.86, y: r.height * (front ? 0.37 : 0.25)),
                   control2: CGPoint(x: r.width * 0.89, y: r.height * (front ? 0.90 : 0.88)))
        return p
    }
}

/// Samples the unmodified app icon; the crop and masks retain its actual pupils and reflections.
public struct PoolEyes: View {
    private let width: CGFloat

    public init(width: CGFloat = 18) { self.width = width }

    public var body: some View {
        let scale = width / 700
        GeometryReader { _ in
            if let artwork = PoolCharacterArtwork.image {
                Image(platformImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 1024 * scale, height: 1024 * scale)
                    .position(x: (512 - 160) * scale, y: (512 - 306) * scale)
            }
        }
        .frame(width: width, height: 416 * scale)
        .mask {
            HStack(spacing: 40 * scale) {
                Ellipse()
                Ellipse()
            }
        }
        .accessibilityHidden(true)
    }
}

enum PoolCharacterArtwork {
    static let image: PlatformImage? = {
        guard let url = Bundle.module.url(forResource: "PoolserCharacter", withExtension: "png") else { return nil }
        #if canImport(AppKit)
        return PlatformImage(contentsOf: url)
        #else
        return PlatformImage(contentsOfFile: url.path)
        #endif
    }()
}

public struct PoolBrandMark: View {
    public init() {}

    public var body: some View {
        Group {
            if let artwork = PoolCharacterArtwork.image {
                Image(platformImage: artwork)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: 34, height: 34)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
