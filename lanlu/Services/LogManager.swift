import Foundation
import OSLog

class LogManager {
    static let shared = LogManager()
    private var entries: [(Date, String)] = []

    func log(_ message: String) {
        let entry = (Date(), message)
        entries.append(entry)
        os_log(.default, "%{public}@", message)
    }

    var allEntries: [(Date, String)] { entries }

    var logText: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.map { "[\(df.string(from: $0.0))] \($0.1)" }.joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }
}
