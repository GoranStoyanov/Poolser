import Foundation
import Combine

public enum LogLevel: CaseIterable, Hashable { case info, request, response, error }

public struct LogEntry: Identifiable {
    public let id        = UUID()
    public let timestamp = Date()
    public let level:    LogLevel
    public let message:  String
}

@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()
    @Published public private(set) var entries: [LogEntry] = []

    private init() {}

    public func log(_ message: String, level: LogLevel = .info) {
        entries.append(LogEntry(level: level, message: message))
        if entries.count > 500 { entries.removeFirst() }
    }

    public func clear() { entries.removeAll() }
}
