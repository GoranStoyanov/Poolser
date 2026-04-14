import SwiftUI

struct LogsView: View {
    @ObservedObject private var store = LogStore.shared
    var onDismiss: (() -> Void)? = nil

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Logs")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    let lines = store.entries.map { e in
                        let lvl = switch e.level {
                            case .info: "INFO"; case .request: "REQ "
                            case .response: "RESP"; case .error: "ERR "
                        }
                        return "[\(Self.timeFmt.string(from: e.timestamp))] [\(lvl)] \(e.message)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy all logs")
                Button {
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear logs")
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            HStack(spacing: 12) {
                ForEach(legendItems, id: \.label) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.color).frame(width: 6, height: 6)
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private let legendItems: [(label: String, color: Color)] = [
        ("info",     Color.secondary),
        ("request",  .blue),
        ("response", .green),
        ("error",    .orange),
    ]

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            Text("No logs yet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.entries.reversed()) { entry in
                        LogRow(entry: entry)
                        Divider().opacity(0.15)
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .padding(.top, 3)
            Text(Self.timeFmt.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var dotColor: Color {
        switch entry.level {
        case .info:     return Color.secondary
        case .request:  return .blue
        case .response: return .green
        case .error:    return .orange
        }
    }
}
