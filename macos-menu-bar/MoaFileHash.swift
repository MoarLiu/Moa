import CryptoKit
import Foundation

enum MoaFileHash {
    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let hasMore = try autoreleasepool { () throws -> Bool in
                guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { return false }
                hash.update(data: data)
                return true
            }
            if !hasMore { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
