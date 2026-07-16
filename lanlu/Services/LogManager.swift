import Foundation
import OSLog

extension Notification.Name {
    static let diagnosticsLogDidChange = Notification.Name("diagnosticsLogDidChange")
}

final class LogManager: @unchecked Sendable {
    static let shared = LogManager()
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "lanlu",
        category: "Diagnostics"
    )
    private let maximumEntryCount = 2_000
    private var entries: [(Date, String)] = []

    func log(_ message: String) {
        let entry = (Date(), message)
        lock.lock()
        entries.append(entry)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        lock.unlock()

        logger.log("\(message, privacy: .public)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .diagnosticsLogDidChange, object: nil)
        }
    }

    var allEntries: [(Date, String)] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    var logText: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return allEntries
            .map { "[\(df.string(from: $0.0))] \($0.1)" }
            .joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .diagnosticsLogDidChange, object: nil)
        }
    }
}
