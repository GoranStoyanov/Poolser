import SwiftUI
import WidgetKit
import PoolserKit

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioSnapshot?
}

/// Reads the snapshot the app writes after each refresh; the app reloads the timeline when the
/// picture changes, so entries only need to keep the "Updated … ago" line current.
struct PortfolioProvider: TimelineProvider {
    private static let step: TimeInterval = 15 * 60
    private static let entryCount = 8

    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        // The widget gallery shows sample data until the app has written a snapshot.
        let snapshot = PortfolioSnapshotStore.load() ?? (context.isPreview ? .preview : nil)
        completion(PortfolioEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let snapshot = PortfolioSnapshotStore.load()
        let now = Date()
        let entries = (0..<Self.entryCount).map {
            PortfolioEntry(date: now.addingTimeInterval(Double($0) * Self.step), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
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
    }
}

@main
struct PoolserWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Portfolio", provider: PortfolioProvider()) { entry in
            PortfolioEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Value, unclaimed fees and range status of your Uniswap positions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    PoolserWidget()
} timeline: {
    PortfolioEntry(date: .now, snapshot: .preview)
    PortfolioEntry(date: .now, snapshot: nil)
}
