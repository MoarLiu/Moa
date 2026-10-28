import Darwin
import Foundation

enum MoaSecureFile {
    /// Remove access for other users without granting the owner new permissions.
    static func ensurePrivateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o700
        try fm.setAttributes([.posixPermissions: mode & 0o700], ofItemAtPath: url.path)
    }

    /// The temporary file is private from creation, including on first save.
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try ensurePrivateDirectory(directory)
        if (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let temporary = directory.appendingPathComponent(".moa-private-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw posixError() }
        defer { Darwin.close(fd); try? fm.removeItem(at: temporary) }
        guard fchmod(fd, mode_t(0o600)) == 0 else { throw posixError() }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw posixError() }
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
