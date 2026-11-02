import SwiftUI

// MARK: - Fee history chart

public struct FeeHistoryChart: View {
    let values: [Double]
    @Binding var days: Int

    public init(values: [Double], days: Binding<Int>) {
        self.values = values
        self._days = days
    }

    @Environment(\.colorScheme) private var colorScheme

    /// A short history still gets a week of slots, empty before its first day, so the chart
    /// shows from the first day of recording instead of appearing a day later.
    private var periods: [Int] {
        [7, 14, 30].filter { $0 == 7 || $0 <= values.count }
    }

    private var slots: Int {
        periods.contains(days) ? days : periods.last ?? 7
    }

    @State private var hovered: Int?
    @State private var showingContext = false

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        let shown = Array(values.suffix(slots))
        let empty = slots - shown.count
        let peak = shown.max() ?? 0
        let total = shown.reduce(0, +)
        VStack(spacing: 6) {
            HStack {
                if shown.count > 1 {
                    Button { showingContext.toggle() } label: {
                        Text("\(shown.count)D fees  \(formatUSD(total))")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.primaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Average \(formatUSD(total / Double(shown.count)))/day over \(shown.count) days")
                    .accessibilityHint("Show average daily fees")
                    .popover(isPresented: $showingContext) {
                        Text("\(shown.count) days · \(formatUSD(total)) total\nAverage \(formatUSD(total / Double(shown.count)))/day")
                            .font(.callout.monospacedDigit())
                            .padding(16)
                    }
                }
                Spacer()
                badge(shown: shown, palette: palette)
            }
            HStack(alignment: .bottom, spacing: slots > 20 ? 2 : 4) {
                ForEach(0..<slots, id: \.self) { slot in
                    let index = slot - empty
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    Button {
                        if index >= 0 { hovered = hovered == index ? nil : index }
                    } label: {
                        Group {
                            if index < 0 {
                                shape.fill(palette.track).frame(height: 3)
                            } else {
                                shape
                                    .fill(index == shown.count - 1 ? palette.barToday : hovered == index ? palette.fees : palette.bar)
                                    .frame(height: barHeight(shown[index], peak: peak))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index >= 0 ? "\(startDate(daysBack: shown.count - 1 - index).formatted(date: .abbreviated, time: .omitted)), \(formatUSD(shown[index]))" : "No history")
                    .disabled(index < 0)
                    .onHover { inside in
                        if inside, index >= 0 {
                            hovered = index
                        } else if hovered == index {
                            hovered = nil
                        }
                    }
                }
            }
            .frame(height: 62, alignment: .bottom)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Fees per day, last \(shown.count) days")
            .accessibilityValue("Today \(formatUSD(shown.last ?? 0)), total \(formatUSD(total))")
            HStack {
                if values.count < 2 {
                    Text("History starts today")
                } else {
                    Text(startDate(daysBack: slots - 1), format: .dateTime.month(.abbreviated).day())
                }
                Spacer()
                if periods.count > 1 {
                    Picker("Period", selection: $days) {
                        ForEach(periods, id: \.self) { Text("\($0)D").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()
                    Spacer()
                }
                Text("Today")
            }
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
        }
        .onChange(of: slots) { hovered = nil }
    }

    /// Today's fees, or the hovered day's with its date.
    private func badge(shown: [Double], palette: GraphitePalette) -> some View {
        let index = hovered.flatMap { shown.indices.contains($0) ? $0 : nil } ?? shown.count - 1
        let isToday = index == shown.count - 1
        let value = formatUSD(shown.indices.contains(index) ? shown[index] : 0)
        let date = startDate(daysBack: shown.count - 1 - index).formatted(.dateTime.month(.abbreviated).day())
        return Text(isToday ? "Today \(value)" : "\(date) · \(value)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(isToday ? palette.onBarToday : palette.primaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                if isToday { shape.fill(palette.barToday) } else { shape.fill(palette.bar) }
            }
    }

    /// A day that earned anything stays taller than the 3pt empty-slot track, so a small day
    /// next to a large one still reads as data.
    private func barHeight(_ value: Double, peak: Double) -> CGFloat {
        guard value > 0, peak > 0 else { return 2 }
        return max(6, 48 * value / peak)
    }

    private func startDate(daysBack: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
    }
}
