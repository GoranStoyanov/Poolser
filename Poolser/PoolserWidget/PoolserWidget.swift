import SwiftUI
import WidgetKit
import PoolserKit

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioSnapshot?
}

/// Reads the snapshot the app writes for the chosen wallet after each refresh; the app reloads
/// the timeline when the picture changes, so entries only need to keep the "Updated … ago"
/// line current.
struct PortfolioProvider: AppIntentTimelineProvider {
    private static let step: TimeInterval = 15 * 60
    private static let entryCount = 8

    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), snapshot: .preview)
    }

    func snapshot(for configuration: SelectWalletIntent, in context: Context) async -> PortfolioEntry {
        // The widget gallery shows sample data until the app has written a snapshot.
        let snapshot = PortfolioSnapshotStore.load(walletID: configuration.wallet?.id) ?? (context.isPreview ? .preview : nil)
        return PortfolioEntry(date: Date(), snapshot: snapshot)
    }

    func timeline(for configuration: SelectWalletIntent, in context: Context) async -> Timeline<PortfolioEntry> {
        let snapshot = PortfolioSnapshotStore.load(walletID: configuration.wallet?.id)
        let now = Date()
        let entries = (0..<Self.entryCount).map {
            PortfolioEntry(date: now.addingTimeInterval(Double($0) * Self.step), snapshot: snapshot)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct PortfolioEntryView: View {
    let entry: PortfolioEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PortfolioWidgetView(
            snapshot: entry.snapshot,
            size: family == .systemSmall ? .small : .medium,
            date: entry.date
        )
        .containerBackground(GraphitePalette.current(colorScheme).popover, for: .widget)
        // Without a URL a click only activates the app, and a menu bar app has no window to show.
        .widgetURL(URL(string: "poolser://open"))
    }
}

@main
struct PoolserWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Portfolio", intent: SelectWalletIntent.self, provider: PortfolioProvider()) { entry in
            PortfolioEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Value, unclaimed fees and range status of your Uniswap positions, for all wallets or one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    PoolserWidget()
} timeline: {
    PortfolioEntry(date: .now, snapshot: .preview)
    PortfolioEntry(date: .now, snapshot: nil)
}
