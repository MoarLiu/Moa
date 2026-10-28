import CryptoKit
import Darwin
import Foundation

enum MoaDataRoot {
    private static let iCloudStorageStateFileName = "icloud-data-root-enabled"
    private static let legacyICloudSyncStateFileName = "icloud-sync-enabled"
    private static let legacyMoaLiteDirectoryName = ".moa-lite"
    private static let legacyMoaLiteSupportDirectoryName = "Moa-Lite"
    private static let legacyMoaLiteICloudDirectoryName = "Moa-Lite"
    private static let legacyMigrationCompleteName = "moa-lite-migration-complete"
    private static let legacyMigrationPendingName = "moa-lite-migration-pending"

    /// 数据根切换（导入数据包 / 切 iCloud / 移回本机）后广播，让能安全 reload 的 store 重新从当前数据根读取。
    static let didChangeNotification = Notification.Name("MoaDataRootDidChange")

    /// 数据根切换“之前”广播：让有延迟落盘的 store 先把待写内容刷到旧数据根。
    /// 须在主线程同步 post（在真正搬移数据之前），观察者同步 flush。
    static let willChangeNotification = Notification.Name("MoaDataRootWillChange")

    static func homeDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
    }

    static func localURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        homeDirectory(environment: environment)
            .appendingPathComponent(".moa", isDirectory: true)
            .standardizedFileURL
    }

    static func supportDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        homeDirectory(environment: environment)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Moa", isDirectory: true)
            .standardizedFileURL
    }

    static func iCloudStorageStateURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        supportDirectory(environment: environment).appendingPathComponent(iCloudStorageStateFileName)
    }

    static func legacyICloudSyncStateURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        supportDirectory(environment: environment).appendingPathComponent(legacyICloudSyncStateFileName)
    }

    static func iCloudDriveRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        homeDirectory(environment: environment)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .standardizedFileURL
    }

    static func iCloudURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        iCloudDriveRoot(environment: environment)
            .appendingPathComponent("Moa", isDirectory: true)
            .standardizedFileURL
    }

    static func legacyNestedICloudURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        iCloudURL(environment: environment)
            .appendingPathComponent(".moa", isDirectory: true)
            .standardizedFileURL
    }

    static func currentURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        isICloudStorageEnabled(environment: environment)
            ? iCloudURL(environment: environment)
            : localURL(environment: environment)
    }

    static func isICloudStorageEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: iCloudStorageStateURL(environment: environment).path)
            || fileManager.fileExists(atPath: legacyICloudSyncStateURL(environment: environment).path) {
            return true
        }
        return legacyICloudSymlinkDestination(environment: environment) != nil
    }

    static func legacyICloudSymlinkDestination(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        let local = localURL(environment: environment)
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: local.path) else {
            return nil
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: local.deletingLastPathComponent())
            .standardizedFileURL
        let supportedDestinations = [
            iCloudURL(environment: environment).standardizedFileURL.path,
            legacyNestedICloudURL(environment: environment).standardizedFileURL.path
        ]
        return supportedDestinations.contains(resolved.path) ? resolved : nil
    }

    static func recoveryURLs(forFileNamed fileName: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let roots = [
            currentURL(environment: environment),
            iCloudURL(environment: environment),
            legacyNestedICloudURL(environment: environment),
            localURL(environment: environment)
        ]
        var seen = Set<String>()
        return roots.compactMap { root in
            let url = root.appendingPathComponent(fileName).standardizedFileURL
            guard seen.insert(url.path).inserted else {
                return nil
            }
            return url
        }
    }

    @discardableResult
    static func migrateLegacyMoaLiteRootsIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let support = supportDirectory(environment: environment)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let lockPath = support.appendingPathComponent("moa-lite-migration.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { flock(descriptor, LOCK_UN) }
        return try migrateLegacyMoaLiteRootsLocked(environment: environment, fileManager: fileManager)
    }

    private static func migrateLegacyMoaLiteRootsLocked(environment: [String: String], fileManager: FileManager) throws -> Bool {
        var migrated = false
        let oldSupport = legacyMoaLiteSupportDirectory(environment: environment)
        let newSupport = supportDirectory(environment: environment)
        let oldLocal = legacyMoaLiteLocalURL(environment: environment)
        let newLocal = localURL(environment: environment)
        let oldICloud = legacyMoaLiteICloudURL(environment: environment)
        let newICloud = iCloudURL(environment: environment)
        let oldLocalSymlinkDestination = symlinkDestination(of: oldLocal, fileManager: fileManager)
        let oldICloudEnabled = oldMoaLiteICloudStateExists(environment: environment, fileManager: fileManager)
            || oldLocalSymlinkDestination != nil
        let complete = newSupport.appendingPathComponent(legacyMigrationCompleteName)
        let pending = newSupport.appendingPathComponent(legacyMigrationPendingName)
        guard !fileManager.fileExists(atPath: complete.path) else { return false }

        let hasLegacy = fileManager.fileExists(atPath: oldSupport.path)
            || fileManager.fileExists(atPath: oldLocal.path)
            || symlinkDestination(of: oldLocal, fileManager: fileManager) != nil
            || fileManager.fileExists(atPath: oldICloud.path)
        guard hasLegacy else { return false }

        try fileManager.createDirectory(at: newSupport, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: pending.path),
           fileManager.fileExists(atPath: newLocal.path),
           !isICloudStorageEnabled(environment: environment) {
            // The app can create local data after an earlier migration failure.
            try Data().write(to: complete, options: .atomic)
            try fileManager.removeItem(at: pending)
            return false
        }
        if !fileManager.fileExists(atPath: pending.path) {
            // Existing Moa roots are authoritative, including a prior decision to disable iCloud.
            if fileManager.fileExists(atPath: newLocal.path) || isICloudStorageEnabled(environment: environment) {
                try Data().write(to: complete, options: .atomic)
                return false
            }
            if oldICloudEnabled, fileManager.fileExists(atPath: newICloud.path) {
                try Data().write(to: iCloudStorageStateURL(environment: environment), options: .atomic)
                try Data().write(to: complete, options: .atomic)
                return true
            }
            try Data().write(to: pending, options: .atomic)
        }
        if fileManager.fileExists(atPath: oldSupport.path) {
            migrated = try copyMissingContents(from: oldSupport, to: newSupport, fileManager: fileManager) {
                $0 == iCloudStorageStateFileName || $0 == legacyICloudSyncStateFileName
            } || migrated
        }
        let oldNestedICloud = oldICloud.appendingPathComponent(legacyMoaLiteDirectoryName, isDirectory: true)
        if oldICloudEnabled {
            if !fileManager.fileExists(atPath: newICloud.path) {
                let source = firstExistingDirectory(
                    [oldICloud, oldNestedICloud, oldLocalSymlinkDestination, oldLocal],
                    fileManager: fileManager
                )
                guard let source else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try fileManager.createDirectory(at: newICloud.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staged = newICloud.deletingLastPathComponent().appendingPathComponent(".moa-migration-\(UUID().uuidString)")
                defer { try? fileManager.removeItem(at: staged) }
                try fileManager.copyItem(at: source, to: staged)
                try fileManager.moveItem(at: staged, to: newICloud)
                migrated = true
            }

            let copiedOldNested = newICloud.appendingPathComponent(legacyMoaLiteDirectoryName, isDirectory: true)
            if fileManager.fileExists(atPath: copiedOldNested.path) {
                let outerItems = try fileManager.contentsOfDirectory(atPath: newICloud.path)
                    .filter { ![legacyMoaLiteDirectoryName, ".DS_Store", ".localized"].contains($0) }
                if outerItems.isEmpty {
                    migrated = try copyMissingContents(from: copiedOldNested, to: newICloud, fileManager: fileManager) || migrated
                }
            }
            if fileManager.fileExists(atPath: newLocal.path), !isICloudStorageEnabled(environment: environment) {
                try Data().write(to: complete, options: .atomic)
                try fileManager.removeItem(at: pending)
                return migrated
            }
            try Data().write(to: iCloudStorageStateURL(environment: environment), options: .atomic)
            migrated = true
        } else if oldLocalSymlinkDestination == nil {
            migrated = try copyDirectoryIfDestinationMissing(from: oldLocal, to: newLocal, fileManager: fileManager) || migrated
        }
        try Data().write(to: complete, options: .atomic)
        try fileManager.removeItem(at: pending)
        return migrated
    }

    private static func legacyMoaLiteLocalURL(environment: [String: String]) -> URL {
        homeDirectory(environment: environment)
            .appendingPathComponent(legacyMoaLiteDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private static func legacyMoaLiteSupportDirectory(environment: [String: String]) -> URL {
        homeDirectory(environment: environment)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(legacyMoaLiteSupportDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private static func legacyMoaLiteICloudURL(environment: [String: String]) -> URL {
        iCloudDriveRoot(environment: environment)
            .appendingPathComponent(legacyMoaLiteICloudDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private static func oldMoaLiteICloudStateExists(environment: [String: String], fileManager: FileManager) -> Bool {
        let support = legacyMoaLiteSupportDirectory(environment: environment)
        return fileManager.fileExists(atPath: support.appendingPathComponent(iCloudStorageStateFileName).path)
            || fileManager.fileExists(atPath: support.appendingPathComponent(legacyICloudSyncStateFileName).path)
    }

    private static func copyDirectoryIfDestinationMissing(from source: URL, to destination: URL, fileManager: FileManager) throws -> Bool {
        guard firstExistingDirectory([source], fileManager: fileManager) != nil,
              !fileManager.fileExists(atPath: destination.path)
        else {
            return false
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".moa-migration-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: source, to: staged)
        try fileManager.moveItem(at: staged, to: destination)
        return true
    }

    private static func firstExistingDirectory(_ candidates: [URL?], fileManager: FileManager) -> URL? {
        for candidate in candidates {
            guard let candidate else {
                continue
            }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func symlinkDestination(of url: URL, fileManager: FileManager) -> URL? {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        return URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
            .standardizedFileURL
    }

    @discardableResult
    static func copyMissingContents(
        from source: URL,
        to destination: URL,
        fileManager: FileManager,
        shouldSkipRelativePath: (String) -> Bool = { _ in false }
    ) throws -> Bool {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return false
        }
        var copied = false
        for case let url as URL in enumerator {
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(sourcePath + "/") else { continue }
            let relativePath = String(filePath.dropFirst(sourcePath.count + 1))
            let sourceIsDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if shouldSkipRelativePath(relativePath) {
                if sourceIsDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            let target = destination.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: target.path) {
                if sourceIsDirectory {
                    let targetValues = try? target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if targetValues?.isDirectory != true || targetValues?.isSymbolicLink == true {
                        enumerator.skipDescendants()
                    }
                }
                continue
            }
            if sourceIsDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: target)
            }
            copied = true
        }
        return copied
    }
}

struct MoaDataPackageManifest: Codable {
    struct FileEntry: Codable {
        enum Kind: String, Codable, Equatable {
            case file
            case symbolicLink
        }

        var path: String
        var size: Int64
        var sha256: String?
        var kind: Kind? = nil
        var symbolicLinkDestination: String? = nil

        var resolvedKind: Kind { kind ?? .file }
    }

    var schemaVersion: Int
    var exportedAt: String
    var appVersion: String
    var appBuild: String
    var dataRootName: String
    var files: [FileEntry]
}

enum MoaDataPackageError: LocalizedError {
    case moaHomeMissing(URL)
    case invalidPackage
    case iCloudDriveUnavailable(URL)
    case iCloudDataRootConflict(URL)
    case iCloudAlreadyDisabled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .moaHomeMissing(let url):
            return MoaL10n.format("Moa data folder does not exist: %@", url.path)
        case .invalidPackage:
            return MoaL10n.text("The selected zip is not a valid Moa data package.")
        case .iCloudDriveUnavailable(let url):
            return MoaL10n.format("iCloud Drive is not available at %@. Make sure iCloud Drive is enabled for this Mac.", url.path)
        case .iCloudDataRootConflict(let url):
            return MoaL10n.format("The iCloud Moa data path already exists but is not a folder: %@", url.path)
        case .iCloudAlreadyDisabled:
            return MoaL10n.text("iCloud storage is not enabled for Moa data.")
        case .commandFailed(let message):
            return message
        }
    }
}

final class MoaDataPackageController {
    private static let runtimeOnlyDirectoryNames: Set<String> = []
    static let retainedRecoveryPackageCount = 12

    var recoveryDirectory: URL {
        supportDirectory.appendingPathComponent("Recovery", isDirectory: true)
    }

    private let fileManager = FileManager.default
    private let operationLock = NSRecursiveLock()
    private let dataAccess: MoaDataAccessCoordinator
    private let environment: [String: String]
    private let home: URL
    private let appVersion: String
    private let appBuild: String

    #if MOA_TESTING || MOA_TEST_SUPPORT
    var testingBeforeExportArchive: (() throws -> Void)?
    #endif

    private var moaHome: URL {
        MoaDataRoot.localURL(environment: environment)
    }

    private var currentMoaHome: URL {
        MoaDataRoot.currentURL(environment: environment)
    }

    private var downloadsDirectory: URL {
        home.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var supportDirectory: URL {
        MoaDataRoot.supportDirectory(environment: environment)
    }

    private var iCloudStorageStateURL: URL {
        MoaDataRoot.iCloudStorageStateURL(environment: environment)
    }

    private var legacyICloudSyncStateURL: URL {
        MoaDataRoot.legacyICloudSyncStateURL(environment: environment)
    }

    var iCloudDriveRoot: URL {
        MoaDataRoot.iCloudDriveRoot(environment: environment)
    }

    var iCloudMoaHome: URL {
        MoaDataRoot.iCloudURL(environment: environment)
    }

    private var legacyNestedICloudMoaHome: URL {
        MoaDataRoot.legacyNestedICloudURL(environment: environment)
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.environment = environment
        dataAccess = .shared(environment: environment)
        home = MoaDataRoot.homeDirectory(environment: environment)
        appVersion = MoaUpdateController.currentVersion ?? "dev"
        appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func isICloudStorageEnabled() -> Bool {
        // This reads only device-local state. Menu rendering must not wait for
        // the lock held by a long-running archive or data move.
        return MoaDataRoot.isICloudStorageEnabled(environment: environment)
    }

    var isDataOperationInProgress: Bool { dataAccess.isBusy }

    @discardableResult
    func repairLegacyICloudDataSplitIfNeeded() throws -> Bool {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            guard isICloudStorageEnabled() else {
                return false
            }
            let migrated = try migrateLegacyNestedICloudDataIfNeeded()
            let materialized = try materializeLegacyICloudSymlinkIfNeeded()
            return migrated || materialized
        }
    }

    func defaultDataPackageURL(prefix: String = "Moa-Data-Backup") -> URL {
        downloadsDirectory.appendingPathComponent("\(prefix)-\(Self.timestamp()).zip")
    }

    func defaultDiagnosticPackageURL() -> URL {
        downloadsDirectory.appendingPathComponent("Moa-Diagnostics-\(Self.timestamp()).zip")
    }

    @discardableResult
    func exportDataPackage(to destination: URL) throws -> URL {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            try migrateSensitiveStoresBeforeExport()
            let source = try resolvedMoaHome()
            let stagingRoot = try temporaryDirectory(prefix: "MoaDataPackage")
            defer { cleanupTemporaryDirectory(stagingRoot) }
            let packageRoot = stagingRoot
                .appendingPathComponent("MoaDataPackage", isDirectory: true)
            try fileManager.createDirectory(at: packageRoot, withIntermediateDirectories: true)

            let copiedMoaHome = packageRoot.appendingPathComponent(".moa", isDirectory: true)
            try runDitto(["--noextattr", "--noacl", source.path, copiedMoaHome.path])
            try removeRuntimeOnlyData(from: copiedMoaHome)

            let manifest = MoaDataPackageManifest(
                schemaVersion: 2,
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                appVersion: appVersion,
                appBuild: appBuild,
                dataRootName: ".moa",
                files: try fileEntries(under: copiedMoaHome)
            )
            try validatePackageLinks(manifest.files, root: copiedMoaHome)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: packageRoot.appendingPathComponent("MoaDataPackageManifest.json"), options: .atomic)

            try archiveDirectory(packageRoot, to: destination)
            return destination
        }
    }

    @discardableResult
    func importDataPackage(from packageURL: URL) throws -> URL {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            let extractRoot = try temporaryDirectory(prefix: "MoaDataImport")
            defer { cleanupTemporaryDirectory(extractRoot) }
            try runDitto(["-x", "-k", packageURL.path, extractRoot.path])
            let importedMoaHome = try validatedImportedMoaHome(in: extractRoot)

            let destination = currentMoaHome
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            }
            let rollbackURL = try createRecoveryPackage(prefix: "Moa-Data-Rollback")

            try replaceMoaHome(at: destination, with: importedMoaHome)
            return rollbackURL
        }
    }

    @discardableResult
    func exportDiagnosticPackage(to destination: URL) throws -> URL {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            let source = try resolvedMoaHome()
            let stagingRoot = try temporaryDirectory(prefix: "MoaDiagnostics")
            defer { cleanupTemporaryDirectory(stagingRoot) }
            let diagnosticRoot = stagingRoot
                .appendingPathComponent("MoaDiagnostics", isDirectory: true)
            try fileManager.createDirectory(at: diagnosticRoot, withIntermediateDirectories: true)

            let summary: [String: Any] = [
                "schemaVersion": 1,
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
                "appVersion": appVersion,
                "appBuild": appBuild,
                "moaLiteHome": diagnosticPathSummary(moaHome),
                "resolvedMoaHome": diagnosticPathSummary(source),
                "iCloudStorageEnabled": isICloudStorageEnabled(),
                "files": try fileEntries(under: source).map { ["path": $0.path, "size": $0.size] }
            ]
            let summaryData = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try summaryData.write(to: diagnosticRoot.appendingPathComponent("diagnostic-summary.json"), options: .atomic)

            let redactedDirectory = diagnosticRoot.appendingPathComponent("redacted", isDirectory: true)
            try fileManager.createDirectory(at: redactedDirectory, withIntermediateDirectories: true)
            for name in ["profiles.json", "claude_desktop_profiles.json", "codex_official_accounts.json", "config.toml", "auth.json"] {
                let url = source.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: url.path),
                      let text = try? String(contentsOf: url, encoding: .utf8)
                else {
                    continue
                }
                let redacted = name.hasSuffix(".toml") ? redactedTOMLText(text) : redactedText(text)
                try redacted.write(
                    to: redactedDirectory.appendingPathComponent(name),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try archiveDirectory(diagnosticRoot, to: destination)
            return destination
        }
    }

    @discardableResult
    func enableICloudStorage() throws -> URL {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            guard fileManager.fileExists(atPath: iCloudDriveRoot.path) else {
                throw MoaDataPackageError.iCloudDriveUnavailable(iCloudDriveRoot)
            }

            try materializeLegacyICloudSymlinkIfNeeded()
            _ = try migrateLegacyNestedICloudDataIfNeeded()
            if !fileManager.fileExists(atPath: moaHome.path) {
                try fileManager.createDirectory(at: moaHome, withIntermediateDirectories: true)
            }

            let rollbackURL = try createRecoveryPackage(prefix: "Moa-Data-Before-iCloud")
            let source = moaHome
            try fileManager.createDirectory(at: iCloudDriveRoot, withIntermediateDirectories: true)

            var isDirectory: ObjCBool = false
            let iCloudDataExists = fileManager.fileExists(atPath: iCloudMoaHome.path, isDirectory: &isDirectory)
            if iCloudDataExists, !isDirectory.boolValue {
                throw MoaDataPackageError.iCloudDataRootConflict(iCloudMoaHome)
            }

            let localHasUserData = containsMoaUserData(under: source)
            let cloudHasUserData = iCloudDataExists && containsMoaUserData(under: iCloudMoaHome)
            // Existing iCloud data may have come from another Mac. Treat it as authoritative
            // so a new device with empty/default local files cannot erase the shared data root.
            if !cloudHasUserData, localHasUserData {
                try mirrorDirectory(from: source, to: iCloudMoaHome)
            } else if !cloudHasUserData, !iCloudDataExists {
                try fileManager.createDirectory(at: iCloudMoaHome, withIntermediateDirectories: true)
            }

            try setICloudStorageEnabled(true)
            return rollbackURL
        }
    }

    @discardableResult
    func disableICloudStorage() throws -> URL {
        return try dataAccess.withExclusiveOperation {
            operationLock.lock()
            defer { operationLock.unlock() }
            guard isICloudStorageEnabled() else {
                throw MoaDataPackageError.iCloudAlreadyDisabled
            }
            guard fileManager.fileExists(atPath: iCloudDriveRoot.path) else {
                throw MoaDataPackageError.iCloudDriveUnavailable(iCloudDriveRoot)
            }

            try materializeLegacyICloudSymlinkIfNeeded()
            _ = try migrateLegacyNestedICloudDataIfNeeded()
            let rollbackURL = try createRecoveryPackage(prefix: "Moa-Data-Before-iCloud-Off")
            if fileManager.fileExists(atPath: iCloudMoaHome.path) {
                try replaceDirectory(at: moaHome, with: iCloudMoaHome)
            } else {
                try fileManager.createDirectory(at: moaHome, withIntermediateDirectories: true)
            }
            try setICloudStorageEnabled(false)
            return rollbackURL
        }
    }

    func openMoaHome() {
        let root = currentMoaHome
        let store = MoaDataStoreLock(environment: environment)
        try? store.withLock { try fileManager.createDirectory(at: root, withIntermediateDirectories: true) }
        _ = runProcess("/usr/bin/open", [root.path])
    }

    func openICloudMoaHome() {
        let store = MoaDataStoreLock(environment: environment)
        try? store.withLock { try fileManager.createDirectory(at: iCloudMoaHome, withIntermediateDirectories: true) }
        _ = runProcess("/usr/bin/open", [iCloudMoaHome.path])
    }

    private func resolvedMoaHome() throws -> URL {
        let root = currentMoaHome
        guard fileManager.fileExists(atPath: root.path) else {
            throw MoaDataPackageError.moaHomeMissing(root)
        }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func migrateSensitiveStoresBeforeExport() throws {}

    private func createRecoveryPackage(prefix: String) throws -> URL {
        try MoaSecureFile.ensurePrivateDirectory(recoveryDirectory)
        let url = recoveryDirectory.appendingPathComponent("\(prefix)-\(Self.timestamp())-\(UUID().uuidString).zip")
        try exportDataPackage(to: url)
        // Prune only after the replacement snapshot has been validated and saved.
        do { try pruneRecoveryPackages(preserving: url) }
        catch { NSLog("Moa could not prune old recovery packages: %@", error.localizedDescription) }
        return url
    }

    func pruneRecoveryPackages(preserving preservedURL: URL? = nil) throws {
        let prefixes = ["Moa-Data-Rollback-", "Moa-Data-Before-iCloud-"]
        let packages = try fileManager.contentsOfDirectory(
            at: recoveryDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        ).compactMap { url -> (URL, Date)? in
            guard url.pathExtension == "zip", prefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent > $1.0.lastPathComponent : $0.1 > $1.1 }
        let candidates = packages.filter { $0.0.standardizedFileURL != preservedURL?.standardizedFileURL }
        let retained = Self.retainedRecoveryPackageCount - (packages.count - candidates.count)
        for (url, _) in candidates.dropFirst(max(0, retained)) {
            try fileManager.removeItem(at: url)
        }
    }

    private func replaceMoaHome(at destination: URL, with importedMoaHome: URL) throws {
        try materializeLegacyICloudSymlinkIfNeeded()
        try replaceDirectory(at: destination, with: importedMoaHome)
    }

    private func replaceDirectory(at destination: URL, with source: URL) throws {
        let previousRoot = try temporaryDirectory(prefix: "MoaImportPrevious")
        let previousURL = previousRoot
            .appendingPathComponent(".moa-previous", isDirectory: true)
        var movedExisting = false
        var shouldCleanupPrevious = true
        defer {
            if shouldCleanupPrevious {
                cleanupTemporaryDirectory(previousRoot)
            }
        }

        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destinationValues = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            if fileManager.fileExists(atPath: destination.path) || destinationValues?.isSymbolicLink == true {
                try fileManager.moveItem(at: destination, to: previousURL)
                movedExisting = true
            }
            try runDitto(["--noextattr", "--noacl", source.path, destination.path])
        } catch let operationError {
            try? fileManager.removeItem(at: destination)
            if movedExisting, fileManager.fileExists(atPath: previousURL.path) {
                do {
                    try fileManager.moveItem(at: previousURL, to: destination)
                } catch let rollbackError {
                    shouldCleanupPrevious = false
                    throw NSError(
                        domain: "Moa",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: MoaL10n.format(
                            "Data replacement failed (%@), and the previous data could not be restored (%@). The previous data is preserved at %@.",
                            operationError.localizedDescription,
                            rollbackError.localizedDescription,
                            previousURL.path
                        )]
                    )
                }
            }
            throw operationError
        }
    }

    private func mirrorDirectory(from source: URL, to destination: URL) throws {
        try replaceDirectory(at: destination, with: source)
    }

    private func setICloudStorageEnabled(_ enabled: Bool) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        if enabled {
            try "enabled\n".write(to: iCloudStorageStateURL, atomically: true, encoding: .utf8)
            if fileManager.fileExists(atPath: legacyICloudSyncStateURL.path) {
                try fileManager.removeItem(at: legacyICloudSyncStateURL)
            }
        } else {
            if fileManager.fileExists(atPath: iCloudStorageStateURL.path) {
                try fileManager.removeItem(at: iCloudStorageStateURL)
            }
            if fileManager.fileExists(atPath: legacyICloudSyncStateURL.path) {
                try fileManager.removeItem(at: legacyICloudSyncStateURL)
            }
        }
    }

    @discardableResult
    private func materializeLegacyICloudSymlinkIfNeeded() throws -> Bool {
        guard let destination = MoaDataRoot.legacyICloudSymlinkDestination(environment: environment) else {
            return false
        }
        let temporaryLocal = try temporaryDirectory(prefix: "MoaICloudSymlinkMaterialize")
        defer { cleanupTemporaryDirectory(temporaryLocal) }
        let materializedMoaHome = temporaryLocal.appendingPathComponent(".moa", isDirectory: true)
        let source = fileManager.fileExists(atPath: destination.path)
            ? destination
            : (fileManager.fileExists(atPath: iCloudMoaHome.path) ? iCloudMoaHome : nil)
        if let source {
            try runDitto(["--noextattr", "--noacl", source.path, materializedMoaHome.path])
        } else {
            try fileManager.createDirectory(at: materializedMoaHome, withIntermediateDirectories: true)
        }
        try replaceDirectory(at: moaHome, with: materializedMoaHome)
        return true
    }

    private func migrateLegacyNestedICloudDataIfNeeded() throws -> Bool {
        let marker = iCloudMoaHome.appendingPathComponent(".moa-nested-migration-complete")
        guard !fileManager.fileExists(atPath: marker.path) else { return false }
        guard fileManager.fileExists(atPath: legacyNestedICloudMoaHome.path),
              containsMoaUserData(under: legacyNestedICloudMoaHome)
        else {
            return false
        }

        if containsMoaUserDataOutsideLegacyNested(under: iCloudMoaHome) {
            // Existing outer data may have intentionally removed entries from
            // the legacy copy. Keep both directories without replaying it.
            try Data().write(to: marker, options: .atomic)
            return false
        }

        let migrationRoot = try temporaryDirectory(prefix: "MoaLegacyICloudData")
        defer { cleanupTemporaryDirectory(migrationRoot) }
        let migrated = migrationRoot.appendingPathComponent("Moa", isDirectory: true)
        try runDitto(["--noextattr", "--noacl", legacyNestedICloudMoaHome.path, migrated.path])

        try replaceDirectory(at: iCloudMoaHome, with: migrated)
        try Data().write(to: marker, options: .atomic)
        return true
    }

    private func validatedImportedMoaHome(in extractRoot: URL) throws -> URL {
        guard let packageRoot = try findDataPackageRoot(in: extractRoot) else {
            throw MoaDataPackageError.invalidPackage
        }
        let manifestURL = packageRoot.appendingPathComponent("MoaDataPackageManifest.json")
        guard (try manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
            throw MoaDataPackageError.invalidPackage
        }
        let manifest = try JSONDecoder().decode(MoaDataPackageManifest.self, from: Data(contentsOf: manifestURL))
        guard (1...2).contains(manifest.schemaVersion), manifest.dataRootName == ".moa" else {
            throw MoaDataPackageError.invalidPackage
        }
        let importedMoaHome = packageRoot.appendingPathComponent(".moa", isDirectory: true)
        var isDirectory: ObjCBool = false
        let extractPath = extractRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let importedPath = importedMoaHome.resolvingSymlinksInPath().standardizedFileURL.path
        guard fileManager.fileExists(atPath: importedMoaHome.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              (try importedMoaHome.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              importedPath.hasPrefix(extractPath + "/")
        else {
            throw MoaDataPackageError.invalidPackage
        }
        try validateManifest(manifest, against: importedMoaHome)
        try removeRuntimeOnlyData(from: importedMoaHome)
        return importedMoaHome
    }

    private func findDataPackageRoot(in extractRoot: URL) throws -> URL? {
        let direct = extractRoot.appendingPathComponent("MoaDataPackage", isDirectory: true)
        if fileManager.fileExists(atPath: direct.appendingPathComponent("MoaDataPackageManifest.json").path),
           fileManager.fileExists(atPath: direct.appendingPathComponent(".moa", isDirectory: true).path) {
            return direct
        }
        if fileManager.fileExists(atPath: extractRoot.appendingPathComponent("MoaDataPackageManifest.json").path),
           fileManager.fileExists(atPath: extractRoot.appendingPathComponent(".moa", isDirectory: true).path) {
            return extractRoot
        }
        guard let enumerator = fileManager.enumerator(at: extractRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw MoaDataPackageError.invalidPackage
        }
        for case let url as URL in enumerator where url.lastPathComponent == "MoaDataPackageManifest.json" {
            let candidate = url.deletingLastPathComponent()
            let moa = candidate.appendingPathComponent(".moa", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: moa.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func validateManifest(_ manifest: MoaDataPackageManifest, against root: URL) throws {
        var manifestEntries: [String: MoaDataPackageManifest.FileEntry] = [:]
        for entry in manifest.files {
            guard isSafeRelativePath(entry.path), manifestEntries[entry.path] == nil else {
                throw MoaDataPackageError.invalidPackage
            }
            if manifest.schemaVersion >= 2 {
                guard let hash = entry.sha256, hash.utf8.count == 64,
                      hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
                    throw MoaDataPackageError.invalidPackage
                }
            }
            manifestEntries[entry.path] = entry
        }

        let files = try fileEntries(under: root)
        if manifest.schemaVersion == 1, files.contains(where: { $0.resolvedKind == .symbolicLink }) {
            throw MoaDataPackageError.invalidPackage
        }
        try validatePackageLinks(files, root: root)
        let actualEntries = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        guard Set(manifestEntries.keys) == Set(actualEntries.keys) else {
            throw MoaDataPackageError.invalidPackage
        }

        for (path, expected) in manifestEntries {
            guard let actual = actualEntries[path],
                  actual.size == expected.size,
                  actual.resolvedKind == expected.resolvedKind,
                  actual.symbolicLinkDestination == expected.symbolicLinkDestination
            else {
                throw MoaDataPackageError.invalidPackage
            }
            if let expectedHash = expected.sha256, let actualHash = actual.sha256,
               expectedHash.lowercased() != actualHash.lowercased() {
                throw MoaDataPackageError.invalidPackage
            }
        }
    }

    private func validatePackageLinks(_ entries: [MoaDataPackageManifest.FileEntry], root: URL) throws {
        for entry in entries where entry.resolvedKind == .symbolicLink {
            _ = try resolvedPackagePath(root.appendingPathComponent(entry.path), root: root, visited: [])
        }
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }
        return !path.split(separator: "/").contains("..")
    }

    private func resolvedPackagePath(_ url: URL, root: URL, visited: Set<String>) throws -> URL {
        let base = root.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate == base || candidate.path.hasPrefix(base.path + "/") else {
            throw MoaDataPackageError.invalidPackage
        }
        let relative = candidate.path.dropFirst(base.path.count)
        return try resolvePackageComponents(relative.split(separator: "/").map(String.init), from: base, root: base, visited: visited)
    }

    private func resolvePackageComponents(_ components: [String], from directory: URL, root: URL, visited: Set<String>) throws -> URL {
        var resolved = directory
        for component in components {
            if component == "." { continue }
            if component == ".." {
                resolved.deleteLastPathComponent()
                guard resolved == root || resolved.path.hasPrefix(root.path + "/") else {
                    throw MoaDataPackageError.invalidPackage
                }
                continue
            }
            resolved.appendPathComponent(String(component))
            let type = (try? fileManager.attributesOfItem(atPath: resolved.path)[.type]) as? FileAttributeType
            if type == .typeSymbolicLink {
                guard visited.count < 64, !visited.contains(resolved.path) else {
                    throw MoaDataPackageError.invalidPackage
                }
                let destination = try fileManager.destinationOfSymbolicLink(atPath: resolved.path)
                guard !destination.isEmpty, !destination.hasPrefix("/") else {
                    throw MoaDataPackageError.invalidPackage
                }
                var nextVisited = visited
                nextVisited.insert(resolved.path)
                // Resolve links before '..': lexical normalization before link
                // expansion can turn a path that escapes the root into a safe one.
                resolved = try resolvePackageComponents(
                    destination.split(separator: "/").map(String.init),
                    from: resolved.deletingLastPathComponent(), root: root, visited: nextVisited
                )
            }
        }
        return resolved
    }

    private func containsMoaUserData(under root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                continue
            }
            let relativePath = String(filePath.dropFirst(rootPath.count + 1))
            if isIgnorableCloudMetadata(relativePath) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true || values?.isSymbolicLink == true {
                return true
            }
        }

        return false
    }

    private func containsMoaUserDataOutsideLegacyNested(under root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                continue
            }
            let relativePath = String(filePath.dropFirst(rootPath.count + 1))
            if relativePath == ".moa" || relativePath.hasPrefix(".moa/") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isIgnorableCloudMetadata(relativePath) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true || values?.isSymbolicLink == true {
                return true
            }
        }

        return false
    }

    private func isIgnorableCloudMetadata(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            return true
        }
        return fileName == ".DS_Store"
            || fileName == ".localized"
            || components.contains(".TemporaryItems")
    }

    private func fileEntries(
        under root: URL,
        includeSymbolicLinks: Bool = true
    ) throws -> [MoaDataPackageManifest.FileEntry] {
        // Enumerate the canonical directory so URLs for dangling links cannot
        // differ from the root only by a system alias such as /var vs /private/var.
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            })
        else {
            throw CocoaError(.fileReadUnknown)
        }

        var entries: [MoaDataPackageManifest.FileEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isDirectoryKey])
            let filePath = url.deletingLastPathComponent().resolvingSymlinksInPath()
                .standardizedFileURL.appendingPathComponent(url.lastPathComponent).path
            guard filePath.hasPrefix(rootPath + "/") else {
                continue
            }
            let relative = String(filePath.dropFirst(rootPath.count + 1))
            guard !isRuntimeOnlyRelativePath(relative) else {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values.isSymbolicLink == true {
                guard includeSymbolicLinks else { continue }
                let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                let destinationData = Data(destination.utf8)
                let sha256 = SHA256.hash(data: destinationData).map { String(format: "%02x", $0) }.joined()
                entries.append(MoaDataPackageManifest.FileEntry(
                    path: relative,
                    size: Int64(destinationData.count),
                    sha256: sha256,
                    kind: .symbolicLink,
                    symbolicLinkDestination: destination
                ))
                continue
            }
            guard values.isRegularFile == true else {
                if shouldSkipDataPackagePath(url, rootPath: rootPath),
                   values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let sha256 = try fileSHA256(url)
            entries.append(MoaDataPackageManifest.FileEntry(
                path: relative,
                size: Int64(values.fileSize ?? 0),
                sha256: sha256,
                kind: .file
            ))
        }
        if let enumerationError {
            throw enumerationError
        }
        return entries.sorted { $0.path < $1.path }
    }

    private func shouldSkipDataPackagePath(_ url: URL, rootPath: String) -> Bool {
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return false
        }
        let relative = String(filePath.dropFirst(rootPath.count + 1))
        return isRuntimeOnlyRelativePath(relative)
    }

    private func isRuntimeOnlyRelativePath(_ relativePath: String) -> Bool {
        let first = relativePath.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
        guard let first else {
            return false
        }
        return Self.runtimeOnlyDirectoryNames.contains(first)
    }

    private func removeRuntimeOnlyData(from moaHome: URL) throws {
        for name in Self.runtimeOnlyDirectoryNames {
            let url = moaHome.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func fileSHA256(_ url: URL) throws -> String {
        try MoaFileHash.sha256(url)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try MoaSecureFile.ensurePrivateDirectory(url)
        return url
    }

    private func cleanupTemporaryDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func redactedText(_ text: String) -> String {
        redactedJSONText(text) ?? "[Unparseable content omitted]"
    }

    private func redactedTOMLText(_ text: String) -> String {
        // Export configuration shape only. An inline table, multiline value or
        // custom header may contain credentials under otherwise harmless keys.
        var lines: [String] = []
        for context in MoaTomlEditor.lineContexts(in: text) where context.isStatementStart {
            if context.isStructural, let table = MoaTomlEditor.tableName(from: context.text) {
                lines.append("[\(table)]")
            } else if let entry = MoaTomlEditor.keyValue(from: context.text) {
                lines.append("\(entry.key) = \"[REDACTED]\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func diagnosticPathSummary(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let localPath = moaHome.resolvingSymlinksInPath().standardizedFileURL.path
        let iCloudPath = iCloudMoaHome.resolvingSymlinksInPath().standardizedFileURL.path

        if path == localPath {
            return "~/.moa"
        }
        if path == iCloudPath {
            return "iCloud Drive/Moa"
        }

        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "[redacted-path]" : "[redacted-path]/\(name)"
    }

    private func redactedJSONText(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        let redacted = redactedJSONValue(object, key: nil)
        guard JSONSerialization.isValidJSONObject(redacted),
              let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: redactedData, encoding: .utf8)
    }

    private func redactedJSONValue(_ value: Any, key: String?) -> Any {
        if let key, isSensitiveDiagnosticKey(key) {
            return "[REDACTED]"
        }
        if let key, key.lowercased().replacingOccurrences(of: "_", with: "").hasSuffix("url"), value is String {
            return "[REDACTED]"
        }

        if let dictionary = value as? [String: Any] {
            var output: [String: Any] = [:]
            for (childKey, childValue) in dictionary {
                output[childKey] = redactedJSONValue(childValue, key: childKey)
            }
            return output
        }

        if let array = value as? [Any] {
            return array.map { redactedJSONValue($0, key: nil) }
        }

        if let string = value as? String,
           var components = URLComponents(string: string),
           components.scheme != nil, components.host != nil {
            components.user = nil
            components.password = nil
            components.path = ""
            components.query = nil
            components.fragment = nil
            return components.string ?? "[REDACTED]"
        }
        return value
    }

    private func isSensitiveDiagnosticKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        let compact = normalized.replacingOccurrences(of: "_", with: "")

        return normalized.contains("api_key")
            || compact.contains("apikey")
            || normalized.contains("access_token")
            || compact.contains("accesstoken")
            || normalized.contains("refresh_token")
            || compact.contains("refreshtoken")
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("authorization")
            || normalized.contains("auth")
            || normalized.contains("password")
    }

    private func runDitto(_ arguments: [String]) throws {
        let status = runProcess("/usr/bin/ditto", arguments)
        guard status == 0 else {
            throw MoaDataPackageError.commandFailed("ditto failed with status \(status): \(arguments.joined(separator: " "))")
        }
    }

    private func archiveDirectory(_ source: URL, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".moa-export-\(UUID().uuidString)", isDirectory: true)
        try MoaSecureFile.ensurePrivateDirectory(staging)
        let temporary = staging.appendingPathComponent("export.zip")
        defer { try? fileManager.removeItem(at: staging) }
        #if MOA_TESTING || MOA_TEST_SUPPORT
        try testingBeforeExportArchive?()
        #endif
        try runDitto(["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, temporary.path])
        guard runProcess("/usr/bin/unzip", ["-tq", temporary.path]) == 0 else {
            throw MoaDataPackageError.commandFailed(MoaL10n.text("Failed to validate the exported archive."))
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    @discardableResult
    private func runProcess(_ executable: String, _ arguments: [String]) -> Int32 {
        MoaProcessRunner.run(executable, arguments, timeout: 300)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
