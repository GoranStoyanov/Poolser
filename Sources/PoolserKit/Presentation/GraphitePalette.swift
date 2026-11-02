import SwiftUI

/// Shared Poolser colours. Jade denotes earnings, amber attention, and blue today.
/// See docs/BRAND.md for the visual and interaction reference.
public struct GraphitePalette {
    public struct StatusColors {
        /// Text, marker and dot colour.
        public let tint: Color
        /// Pill background.
        public let background: Color
        /// Range band fill.
        public let bandFill: Color
        /// Range band outline and inactive mini bars.
        public let bandEdge: Color
    }

    public let popover: Color
    public let card: Color
    public let cardLine: Color
    public let hairline: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let fees: Color
    public let bar: Color
    public let barToday: Color
    public let onBarToday: Color
    public let track: Color
    public let control: Color
    public let strong: Color
    public let onStrong: Color
    public let onStatus: Color
    public let brandStart: Color
    public let brandEnd: Color
    /// Opacity of the front and back water layers in the fee pool.
    public let waterFront: Double
    public let waterBack: Double
    /// Muted hues that tell saved wallets apart on the All Wallets page. They stay clear of the
    /// status colours, so a wallet never reads as in range or out of range.
    let walletColors: [Color]

    public let inRange: StatusColors
    public let nearEdge: StatusColors
    public let outOfRange: StatusColors
    public let fullRange: StatusColors
    public let unknown: StatusColors

    public func status(_ status: RangeStatus) -> StatusColors {
        switch status {
        case .inRange:    return inRange
        case .nearMin, .nearMax: return nearEdge
        case .outOfRange: return outOfRange
        case .fullRange:  return fullRange
        case .unknown:    return unknown
        }
    }

    /// The colour of the saved wallet at `index` in the wallet list; repeats after eight.
    public func walletColor(_ index: Int) -> Color {
        walletColors[((index % walletColors.count) + walletColors.count) % walletColors.count]
    }

    public var brand: LinearGradient {
        LinearGradient(colors: [brandStart, brandEnd], startPoint: .leading, endPoint: .trailing)
    }

    public static func current(_ scheme: ColorScheme) -> GraphitePalette {
        scheme == .dark ? .dark : .light
    }

    public static let light = GraphitePalette(
        popover: Color(hex: 0xF5F7F3),
        card: Color(hex: 0xFFFFFF),
        cardLine: Color(hex: 0xDCE7E5),
        hairline: Color(hex: 0xEAF1EF),
        primaryText: Color(hex: 0x153D47),
        secondaryText: Color(hex: 0x536D76),
        fees: Color(hex: 0x187C67),
        bar: Color(hex: 0x80C5B5),
        barToday: Color(hex: 0x3979B7),
        onBarToday: Color(hex: 0xFFFFFF),
        track: Color(hex: 0xE1ECE9),
        control: Color(hex: 0xEAF1EF),
        strong: Color(hex: 0x153D47),
        onStrong: Color(hex: 0xFFFFFF),
        onStatus: Color(hex: 0xFFFFFF),
        brandStart: Color(hex: 0x278D78),
        brandEnd: Color(hex: 0x3979B7),
        waterFront: 0.14,
        waterBack: 0.08,
        walletColors: [0x4A6FA5, 0x7A6AA8, 0xA8657F, 0x4F8F98, 0x8A6F5A, 0x5C6B84, 0x93609A, 0x3F7E7A].map(Color.init(hex:)),
        inRange: StatusColors(tint: Color(hex: 0x187C67), background: Color(hex: 0xE5F3ED),
                              bandFill: Color(hex: 0xB8E1D4), bandEdge: Color(hex: 0x278D78)),
        nearEdge: StatusColors(tint: Color(hex: 0x955800), background: Color(hex: 0xFBF2DC),
                               bandFill: Color(hex: 0xF6F1E4), bandEdge: Color(hex: 0xD2B25E)),
        outOfRange: StatusColors(tint: Color(hex: 0xA45417), background: Color(hex: 0xFCF0E4),
                                 bandFill: Color(hex: 0xFCF0E4), bandEdge: Color(hex: 0xD9945D)),
        fullRange: StatusColors(tint: Color(hex: 0x454B57), background: Color(hex: 0xEDEEF1),
                                bandFill: Color(hex: 0xEDEEF1), bandEdge: Color(hex: 0xADB2BC)),
        unknown: StatusColors(tint: Color(hex: 0x536D76), background: Color(hex: 0xEAF1EF),
                              bandFill: Color(hex: 0xEAF1EF), bandEdge: Color(hex: 0xC8C8CE))
    )

    public static let dark = GraphitePalette(
        popover: Color(hex: 0x10262D),
        card: Color(hex: 0x18343C),
        cardLine: Color(hex: 0x2E4D53),
        hairline: Color(hex: 0x27454B),
        primaryText: Color(hex: 0xEAF4F2),
        secondaryText: Color(hex: 0xA4BEC3),
        fees: Color(hex: 0x68D4B5),
        bar: Color(hex: 0x347A6D),
        barToday: Color(hex: 0x629FE0),
        onBarToday: Color(hex: 0x153D47),
        track: Color(hex: 0x24444A),
        control: Color(hex: 0x24444A),
        strong: Color(hex: 0xEAF4F2),
        onStrong: Color(hex: 0x153D47),
        onStatus: Color(hex: 0x153D47),
        brandStart: Color(hex: 0x42B69C),
        brandEnd: Color(hex: 0x629FE0),
        waterFront: 0.30,
        waterBack: 0.16,
        walletColors: [0x7C9DD0, 0xA898D4, 0xD490AA, 0x7DBCC4, 0xB89C86, 0x8E9BB3, 0xBF8EC6, 0x6FAEA9].map(Color.init(hex:)),
        inRange: StatusColors(tint: Color(hex: 0x68D4B5), background: Color(hex: 0x16302A),
                              bandFill: Color(hex: 0x245C50), bandEdge: Color(hex: 0x42B69C)),
        nearEdge: StatusColors(tint: Color(hex: 0xF5C451), background: Color(hex: 0x372E17),
                               bandFill: Color(hex: 0x332B17), bandEdge: Color(hex: 0x8A6D2A)),
        outOfRange: StatusColors(tint: Color(hex: 0xF2B174), background: Color(hex: 0x3A2417),
                                 bandFill: Color(hex: 0x382317), bandEdge: Color(hex: 0x9A5530)),
        fullRange: StatusColors(tint: Color(hex: 0xC4C8D0), background: Color(hex: 0x2A2D33),
                                bandFill: Color(hex: 0x2A2D33), bandEdge: Color(hex: 0x5A5F69)),
        unknown: StatusColors(tint: Color(hex: 0xA4BEC3), background: Color(hex: 0x24444A),
                              bandFill: Color(hex: 0x24444A), bandEdge: Color(hex: 0x45454B))
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
