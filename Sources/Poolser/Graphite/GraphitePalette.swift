import SwiftUI
import PoolserKit

/// Colours for the Graphite popover. Near-monochrome on purpose: green is reserved for fees and
/// in-range, amber and orange for ranges that need attention, so colour always carries meaning.
/// The one exception is the logo's green-to-blue gradient, kept for the fee pool and today's bar.
///
/// Plain SwiftUI colours picked by `ColorScheme` rather than dynamic `NSColor`s, so the palette
/// follows `.preferredColorScheme` in previews and image renders and has no AppKit dependency.
struct GraphitePalette {
    struct StatusColors {
        /// Text, marker and dot colour.
        let tint: Color
        /// Pill background.
        let background: Color
        /// Range band fill.
        let bandFill: Color
        /// Range band outline and inactive mini bars.
        let bandEdge: Color
    }

    let popover: Color
    let card: Color
    let cardLine: Color
    let hairline: Color
    let primaryText: Color
    let secondaryText: Color
    let fees: Color
    let bar: Color
    let barToday: Color
    let onBarToday: Color
    let track: Color
    let control: Color
    let strong: Color
    let onStrong: Color
    let onStatus: Color
    let brandStart: Color
    let brandEnd: Color
    /// Opacity of the front and back water layers in the fee pool.
    let waterFront: Double
    let waterBack: Double

    let inRange: StatusColors
    let nearEdge: StatusColors
    let outOfRange: StatusColors
    let fullRange: StatusColors
    let unknown: StatusColors

    func status(_ status: RangeStatus) -> StatusColors {
        switch status {
        case .inRange:    return inRange
        case .nearMin, .nearMax: return nearEdge
        case .outOfRange: return outOfRange
        case .fullRange:  return fullRange
        case .unknown:    return unknown
        }
    }

    var brand: LinearGradient {
        LinearGradient(colors: [brandStart, brandEnd], startPoint: .leading, endPoint: .trailing)
    }

    static func current(_ scheme: ColorScheme) -> GraphitePalette {
        scheme == .dark ? .dark : .light
    }

    static let light = GraphitePalette(
        popover: Color(hex: 0xFAFAFA),
        card: Color(hex: 0xFFFFFF),
        cardLine: Color(hex: 0xE6E6EA),
        hairline: Color(hex: 0xF0F0F2),
        primaryText: Color(hex: 0x111113),
        secondaryText: Color(hex: 0x62626C),
        fees: Color(hex: 0x0B7A55),
        bar: Color(hex: 0xDADBE0),
        barToday: Color(hex: 0x111113),
        onBarToday: Color(hex: 0xFFFFFF),
        track: Color(hex: 0xEDEDF0),
        control: Color(hex: 0xF0F0F2),
        strong: Color(hex: 0x111113),
        onStrong: Color(hex: 0xFFFFFF),
        onStatus: Color(hex: 0xFFFFFF),
        brandStart: Color(hex: 0x4DBF6A),
        brandEnd: Color(hex: 0x3B86EC),
        waterFront: 0.24,
        waterBack: 0.13,
        inRange: StatusColors(tint: Color(hex: 0x0B7A55), background: Color(hex: 0xE8F4EF),
                              bandFill: Color(hex: 0xF0F1F3), bandEdge: Color(hex: 0xA9ADB5)),
        nearEdge: StatusColors(tint: Color(hex: 0x955800), background: Color(hex: 0xFBF2DC),
                               bandFill: Color(hex: 0xF6F1E4), bandEdge: Color(hex: 0xD2B25E)),
        outOfRange: StatusColors(tint: Color(hex: 0xC2410C), background: Color(hex: 0xFDEEE6),
                                 bandFill: Color(hex: 0xFDEEE6), bandEdge: Color(hex: 0xEFA27C)),
        fullRange: StatusColors(tint: Color(hex: 0x454B57), background: Color(hex: 0xEDEEF1),
                                bandFill: Color(hex: 0xEDEEF1), bandEdge: Color(hex: 0xADB2BC)),
        unknown: StatusColors(tint: Color(hex: 0x62626C), background: Color(hex: 0xF0F0F2),
                              bandFill: Color(hex: 0xF0F0F2), bandEdge: Color(hex: 0xC8C8CE))
    )

    static let dark = GraphitePalette(
        popover: Color(hex: 0x161618),
        card: Color(hex: 0x1F1F22),
        cardLine: Color(hex: 0x2E2E33),
        hairline: Color(hex: 0x29292D),
        primaryText: Color(hex: 0xF4F4F5),
        secondaryText: Color(hex: 0xA1A1AA),
        fees: Color(hex: 0x4ADE9A),
        bar: Color(hex: 0x3A3A40),
        barToday: Color(hex: 0xF4F4F5),
        onBarToday: Color(hex: 0x111113),
        track: Color(hex: 0x2A2A2F),
        control: Color(hex: 0x2A2A2F),
        strong: Color(hex: 0xF4F4F5),
        onStrong: Color(hex: 0x111113),
        onStatus: Color(hex: 0x111113),
        brandStart: Color(hex: 0x5FD27C),
        brandEnd: Color(hex: 0x5A9EF5),
        waterFront: 0.30,
        waterBack: 0.16,
        inRange: StatusColors(tint: Color(hex: 0x4ADE9A), background: Color(hex: 0x16302A),
                              bandFill: Color(hex: 0x26272B), bandEdge: Color(hex: 0x5A5C63)),
        nearEdge: StatusColors(tint: Color(hex: 0xF5C451), background: Color(hex: 0x372E17),
                               bandFill: Color(hex: 0x332B17), bandEdge: Color(hex: 0x8A6D2A)),
        outOfRange: StatusColors(tint: Color(hex: 0xFF9B5C), background: Color(hex: 0x3A2417),
                                 bandFill: Color(hex: 0x382317), bandEdge: Color(hex: 0x9A5530)),
        fullRange: StatusColors(tint: Color(hex: 0xC4C8D0), background: Color(hex: 0x2A2D33),
                                bandFill: Color(hex: 0x2A2D33), bandEdge: Color(hex: 0x5A5F69)),
        unknown: StatusColors(tint: Color(hex: 0xA1A1AA), background: Color(hex: 0x2A2A2F),
                              bandFill: Color(hex: 0x2A2A2F), bandEdge: Color(hex: 0x45454B))
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
