import Foundation
import Darwin

/// Used only on the enhancement coordinator's worker task, never on the main thread.
final class CodexSessionIndex {
    let home: URL
    private var paths: [String: URL] = [:]
    private var scannedAt = Date.distantPast
    private var fullScannedAt = Date.distantPast
    private static let maximumCachedPaths = 128
    private static let recentScanInterval: TimeInterval = 5
    private static let fullScanInterval: TimeInterval = 60
    private static let metadataReadLimit = 512 * 1024

    init(environment: [String: String]) {
        home = URL(fileURLWithPath: environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
                   ?? "\(environment["HOME"] ?? NSHomeDirectory())/.codex").standardizedFileURL.resolvingSymlinksInPath()
    }

    func file(for id: String, now: Date = Date()) -> URL? {
        guard CodexLiveMetrics.validThreadID(id) else { return nil }
        if let path = paths[id], FileManager.default.fileExists(atPath: path.path) { return path }
        guard now.timeIntervalSince(scannedAt) > Self.recentScanInterval else { return nil }
        scannedAt = now
        let roots = ["sessions", "archived_sessions"].map { home.appendingPathComponent($0) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        // New local chats are cheap to find, including after midnight. Older missing IDs
        // get a bounded full-directory retry, rather than rescanning all history every tick.
        var recent = roots
        for zone in [TimeZone.current, TimeZone(secondsFromGMT: 0)!] {
            formatter.timeZone = zone
            for day in [now, now.addingTimeInterval(-86400)] {
                recent.append(roots[0].appendingPathComponent(formatter.string(from: day)))
            }
        }
        for directory in recent {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for file in files where file.lastPathComponent.contains(id) {
                if let found = verified(file, id: id, roots: roots) { return found }
            }
        }
        guard now.timeIntervalSince(fullScannedAt) > Self.fullScanInterval else { return nil }
        fullScannedAt = now
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let file as URL in enumerator {
                if Task.isCancelled { return nil }
                guard file.lastPathComponent.contains(id) else { continue }
                if let found = verified(file, id: id, roots: roots) { return found }
            }
        }
        return nil
    }

    private func verified(_ file: URL, id: String, roots: [URL]) -> URL? {
        guard file.pathExtension == "jsonl",
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              roots.contains(where: { file.resolvingSymlinksInPath().path.hasPrefix($0.path + "/") }),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.metadataReadLimit)) ?? Data()
        guard let end = data.firstIndex(of: 10),
              let object = try? JSONSerialization.jsonObject(with: data[..<end]) as? [String: Any],
              object["type"] as? String == "session_meta",
              let meta = object["payload"] as? [String: Any],
              (meta["id"] as? String ?? meta["session_id"] as? String) == id else { return nil }
        if paths.count >= Self.maximumCachedPaths { paths.removeAll() }
        paths[id] = file
        return file
    }
}

/// One reader per worker subscription. Calls are synchronous and must stay on that worker.
/// Each read opens and closes its own handle so replaced or rotated files are rechecked.
final class CodexLiveUsageReader {
    private let url: URL
    private let threadID: String
    private var identity: UInt64?
    private var offset: UInt64 = 0
    private var buffer = Data()
    private var skippingLine = false
    private var metrics: CodexLiveMetrics
    private(set) var bytesRead = 0
    private static let maxLine = 512 * 1024
    private static let maxTail: UInt64 = 8 * 1024 * 1024

    init(url: URL, threadID: String) {
        self.url = url; self.threadID = threadID
        metrics = CodexLiveMetrics(threadID: threadID)
    }

    func read() throws -> CodexLiveSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(handle.fileDescriptor, &metadata) == 0 else { throw CodexEnhancementError.unavailable }
        let nextIdentity = UInt64(metadata.st_ino)
        let size = try handle.seekToEnd()
        if identity != nextIdentity || size < offset {
            try handle.seek(toOffset: 0)
            let header = try handle.read(upToCount: Self.maxLine) ?? Data()
            if let end = header.firstIndex(of: 10),
               let object = try? JSONSerialization.jsonObject(with: header[..<end]) as? [String: Any],
               object["type"] as? String == "session_meta", let meta = object["payload"] as? [String: Any],
               (meta["id"] as? String ?? meta["session_id"] as? String) != threadID {
                throw CodexEnhancementError.unavailable
            }
            identity = nextIdentity; metrics = CodexLiveMetrics(threadID: threadID)
            buffer.removeAll(); skippingLine = false
            offset = size > Self.maxTail ? size - Self.maxTail : 0
            skippingLine = offset > 0
        }
        try handle.seek(toOffset: offset)
        // Bound each tick even if a tool is appending a very large transcript.
        let data = try handle.read(upToCount: Int(min(size - offset, Self.maxTail))) ?? Data()
        bytesRead += data.count; offset += UInt64(data.count)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 10) ?? data.endIndex
            let length = data.distance(from: start, to: end)
            if !skippingLine {
                if buffer.count + length <= Self.maxLine { buffer.append(data[start..<end]) }
                else { buffer.removeAll(); skippingLine = true }
            }
            if end < data.endIndex {
                if !skippingLine { metrics.consume(buffer) }
                buffer.removeAll(keepingCapacity: true); skippingLine = false
                start = data.index(after: end)
            } else { break }
        }
        return metrics.snapshot
    }
}
