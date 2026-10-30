import SwiftUI
import WidgetKit
import PoolserKit

private struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioSnapshot?
}

private struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        completion(PortfolioEntry(
            date: .now,
            snapshot: PortfolioSnapshotStore.load() ?? (context.isPreview ? .preview : nil)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let now = Date()
        completion(Timeline(
            entries: [PortfolioEntry(date: now, snapshot: PortfolioSnapshotStore.load())],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }
}

private struct PortfolioEntryView: View {
    let entry: PortfolioEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 0) {
                    Text(entry.snapshot.map { "\(max(0, $0.positionCount - $0.attentionCount))/\($0.positionCount)" } ?? "–")
                        .font(.headline.monospacedDigit())
                    Text("in range")
                        .font(.system(size: 9, weight: .medium))
                }
                .containerBackground(.clear, for: .widget)
            } else {
                PortfolioWidgetView(
                    snapshot: entry.snapshot,
                    size: family == .systemSmall ? .small : .medium,
                    date: entry.date
                )
                .containerBackground(GraphitePalette.current(colorScheme).popover, for: .widget)
            }
        }
    }
}

@main
struct PoolserIOSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioIOS", provider: PortfolioProvider()) { entry in
            PortfolioEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Value, fees and range status of your Uniswap positions.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
