import Foundation
import Combine

enum LogLevel { case info, request, response, error }

struct LogEntry: Identifiable {
    let id        = UUID()
    let timestamp = Date()
    let level:    LogLevel
    let message:  String
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()
    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    func log(_ message: String, level: LogLevel = .info) {
        entries.append(LogEntry(level: level, message: message))
        if entries.count > 500 { entries.removeFirst() }
    }

    func clear() { entries.removeAll() }
}
