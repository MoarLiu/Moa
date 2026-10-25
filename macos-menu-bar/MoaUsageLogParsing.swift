import Foundation

enum CodexUsageDateParser {
    private static let lock = NSLock()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: text) ?? plain.date(from: text)
    }
}

extension Data {
    func containsASCII(_ text: String) -> Bool {
        range(of: Data(text.utf8)) != nil
    }
}
