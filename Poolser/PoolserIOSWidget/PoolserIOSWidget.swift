import SwiftUI
import WidgetKit
import PoolserKit

private struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: PortfolioSnapshot?
}

private struct PortfolioProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: SelectWalletIntent, in context: Context) async -> PortfolioEntry {
        PortfolioEntry(
            date: .now,
            snapshot: PortfolioSnapshotStore.load(walletID: configuration.wallet?.id) ?? (context.isPreview ? .preview : nil)
        )
    }

    func timeline(for configuration: SelectWalletIntent, in context: Context) async -> Timeline<PortfolioEntry> {
        let now = Date()
        return Timeline(
            entries: [PortfolioEntry(date: now, snapshot: PortfolioSnapshotStore.load(walletID: configuration.wallet?.id))],
            policy: .after(now.addingTimeInterval(15 * 60))
        )
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
        AppIntentConfiguration(kind: "PortfolioIOS", intent: SelectWalletIntent.self, provider: PortfolioProvider()) { entry in
            PortfolioEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Value, fees and range status of your Uniswap positions, for all wallets or one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
