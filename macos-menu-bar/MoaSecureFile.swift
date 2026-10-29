import Darwin
import Foundation

enum MoaSecureFile {
    #if MOA_TESTING || MOA_TEST_SUPPORT
    static var testingAfterOpeningDirectory: (() throws -> Void)?
    #endif
    /// Only Moa-owned directories should have their existing permissions tightened.
    /// User-selected directory links are resolved before opening a fixed directory handle.
    static func ensurePrivateDirectory(_ url: URL) throws {
        let directory = url.resolvingSymlinksInPath().standardizedFileURL
        let fd = try openDirectory(directory)
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0 else { throw posixError(at: url) }
        guard fchmod(fd, attributes.st_mode & mode_t(0o700)) == 0 else { throw posixError(at: url) }
    }

    /// Preserve existing parent permissions, including shared client and export directories.
    /// Relative operations cannot be redirected by replacing the opened parent directory link.
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let directoryFD = try openDirectory(directory)
        defer { Darwin.close(directoryFD) }
        #if MOA_TESTING || MOA_TEST_SUPPORT
        try testingAfterOpeningDirectory?()
        #endif
        let name = url.lastPathComponent
        var attributes = stat()
        if fstatat(directoryFD, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 {
            if attributes.st_mode & S_IFMT == S_IFLNK {
                throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                    NSFilePathErrorKey: url.path,
                    NSLocalizedDescriptionKey: MoaL10n.format("Cannot replace a symbolic link: %@", url.path)
                ])
            }
        } else if errno != ENOENT {
            throw posixError(at: url)
        }
        let temporaryName = ".moa-private-\(UUID().uuidString)"
        let fd = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw posixError(at: url) }
        defer { Darwin.close(fd); unlinkat(directoryFD, temporaryName, 0) }
        guard fchmod(fd, mode_t(0o600)) == 0 else { throw posixError(at: url) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError(at: url) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw posixError(at: url) }
        guard renameat(directoryFD, temporaryName, directoryFD, name) == 0 else { throw posixError(at: url) }
    }

    private static func openDirectory(_ url: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posixError(at: url) }
        return fd
    }

    private static func posixError(at url: URL) -> NSError {
        let code = Int(errno)
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: code)
        return NSError(domain: NSPOSIXErrorDomain, code: code, userInfo: [
            NSFilePathErrorKey: url.path,
            NSUnderlyingErrorKey: underlying,
            NSLocalizedDescriptionKey: MoaL10n.format("Could not access %@. %@", url.path, underlying.localizedDescription)
        ])
    }
}
