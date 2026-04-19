import SwiftUI

struct LogsView: View {
    @ObservedObject private var store = LogStore.shared
    @State private var hiddenLevels: Set<LogLevel> = []
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
                    let lines = filteredEntries.map { e in
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
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Button {
                        toggle(level)
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(color(for: level)).frame(width: 6, height: 6)
                            Text(label(for: level))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .opacity(hiddenLevels.contains(level) ? 0.35 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .help(hiddenLevels.contains(level) ? "Show \(label(for: level)) logs" : "Hide \(label(for: level)) logs")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private var filteredEntries: [LogEntry] {
        store.entries.filter { !hiddenLevels.contains($0.level) }
    }

    private func toggle(_ level: LogLevel) {
        if hiddenLevels.contains(level) { hiddenLevels.remove(level) }
        else { hiddenLevels.insert(level) }
    }

    private func label(for level: LogLevel) -> String {
        switch level {
        case .info: return "info"
        case .request: return "request"
        case .response: return "response"
        case .error: return "error"
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return Color.secondary
        case .request: return .blue
        case .response: return .green
        case .error: return .orange
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            Text("No logs yet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        } else if filteredEntries.isEmpty {
            Text("No logs for selected legend filters")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries.reversed()) { entry in
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

    @State private var copied = false

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
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.message, forType: .string)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeInOut(duration: 0.2)) { copied = false }
            }
        }
        .help("Click to copy")
        .overlay(alignment: .center) {
            if copied {
                Text("Copied")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
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
