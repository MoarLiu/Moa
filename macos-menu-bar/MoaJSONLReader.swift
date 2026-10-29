import Foundation

/// Searches each input chunk once and retains only a bounded prefix of a line.
enum MoaJSONLReader {
    static let maximumLineBytes = 8 * 1024 * 1024

    static func scan(fileURL: URL, maximumLineBytes: Int = maximumLineBytes,
                     onLine: (Data, Bool) -> Void) throws {
        precondition(maximumLineBytes > 0 && maximumLineBytes < Int.max)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var buffer = Data()
        var truncated = false
        func emitLine(terminated: Bool) {
            if terminated, !truncated, buffer.last == 13 { buffer.removeLast() }
            if buffer.count > maximumLineBytes {
                buffer.removeLast(buffer.count - maximumLineBytes)
                truncated = true
            }
            onLine(buffer, truncated)
            buffer.removeAll(keepingCapacity: true)
            truncated = false
        }
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 10)
                let end = newline ?? chunk.endIndex
                // One extra byte distinguishes an exact-limit CRLF line from oversized content.
                let count = min(end - start, maximumLineBytes + 1 - buffer.count)
                buffer.append(contentsOf: chunk[start..<(start + count)])
                truncated = truncated || count < end - start
                guard let newline else { break }
                emitLine(terminated: true)
                start = newline + 1
            }
        }
        if !buffer.isEmpty || truncated { emitLine(terminated: false) }
    }
}
