import AppKit
import Foundation

enum MoaBackupKind: String, Codable, Equatable {
    case recoveryImportRollback
    case recoveryBeforeICloudOn
    case recoveryBeforeICloudOff
    case codexSnapshot
    case legacyDownloadsBackup

    var triggerTitle: String {
        switch self {
        case .recoveryImportRollback: return MoaL10n.text("Before Data Import")
        case .recoveryBeforeICloudOn: return MoaL10n.text("Before Enabling iCloud")
        case .recoveryBeforeICloudOff: return MoaL10n.text("Before Disabling iCloud")
        case .codexSnapshot: return MoaL10n.text("Codex Config Snapshot")
        case .legacyDownloadsBackup: return MoaL10n.text("Legacy Downloads Backup")
        }
    }
}

struct MoaBackupEntry: Identifiable, Codable, Equatable {
    let id: String
    let kind: MoaBackupKind
    let name: String
    let path: String
    let createdAt: Date
    let sizeBytes: Int64
    let isDirectory: Bool
    let containsItemsSummary: String?

    var url: URL { URL(fileURLWithPath: path) }
}

struct MoaBackupInventory: Equatable {
    var recoveryPackages: [MoaBackupEntry] = []
    var codexSnapshots: [MoaBackupEntry] = []
    var legacyDownloadsBackups: [MoaBackupEntry] = []

    var totalCount: Int {
        recoveryPackages.count + codexSnapshots.count + legacyDownloadsBackups.count
    }
}

/// Manages visibility, restore, cleanup, and legacy-Downloads security hygiene
/// for Moa's automatic recovery packages and Codex backups.
final class MoaBackupManager {
    private let fileManager = FileManager.default
    private let environment: [String: String]
    private let dataPackages: MoaDataPackageController

    var recoveryDirectory: URL { dataPackages.recoveryDirectory }
    var codexBackupsDirectory: URL {
        MoaDataRoot.currentURL(environment: environment).appendingPathComponent("backups", isDirectory: true)
    }
    var downloadsDirectory: URL {
        MoaDataRoot.homeDirectory(environment: environment).appendingPathComponent("Downloads", isDirectory: true)
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dataPackages: MoaDataPackageController? = nil
    ) {
        self.environment = environment
        self.dataPackages = dataPackages ?? MoaDataPackageController(environment: environment)
    }

    func loadInventory() -> MoaBackupInventory {
        MoaBackupInventory(
            recoveryPackages: listRecoveryPackages(),
            codexSnapshots: listCodexSnapshots(),
            legacyDownloadsBackups: listLegacyDownloadsBackups()
        )
    }

    func restoreRecoveryPackage(_ entry: MoaBackupEntry) throws -> URL {
        guard entry.kind == .recoveryImportRollback
            || entry.kind == .recoveryBeforeICloudOn
            || entry.kind == .recoveryBeforeICloudOff else {
            throw MoaDataPackageError.invalidPackage
        }
        return try dataPackages.importDataPackage(from: entry.url)
    }

    func deleteBackup(_ entry: MoaBackupEntry) throws {
        let allowedRoots = [recoveryDirectory, codexBackupsDirectory, downloadsDirectory]
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let targetPath = entry.url.resolvingSymlinksInPath().standardizedFileURL.path
        guard allowedRoots.contains(where: { targetPath.hasPrefix($0 + "/") }) else {
            throw MoaDataPackageError.invalidPackage
        }
        if entry.kind == .legacyDownloadsBackup {
            // Safely move user Downloads files to Trash when possible.
            var trashedURL: NSURL?
            if (try? fileManager.trashItem(at: entry.url, resultingItemURL: &trashedURL)) != nil {
                return
            }
        }
        try fileManager.removeItem(at: entry.url)
    }

    func revealInFinder(_ entry: MoaBackupEntry) {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    // MARK: - Private Enumerators

    private func listRecoveryPackages() -> [MoaBackupEntry] {
        guard fileManager.fileExists(atPath: recoveryDirectory.path),
              let items = try? fileManager.contentsOfDirectory(
                  at: recoveryDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        return items.compactMap { url -> MoaBackupEntry? in
            guard url.pathExtension == "zip" else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            let name = url.lastPathComponent
            let kind: MoaBackupKind
            if name.hasPrefix("Moa-Data-Before-iCloud-Off-") {
                kind = .recoveryBeforeICloudOff
            } else if name.hasPrefix("Moa-Data-Before-iCloud-") {
                kind = .recoveryBeforeICloudOn
            } else if name.hasPrefix("Moa-Data-Rollback-") {
                kind = .recoveryImportRollback
            } else {
                return nil
            }
            return MoaBackupEntry(
                id: "recovery|\(name)",
                kind: kind,
                name: name,
                path: url.path,
                createdAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: Int64(values.fileSize ?? 0),
                isDirectory: false,
                containsItemsSummary: nil
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func listCodexSnapshots() -> [MoaBackupEntry] {
        guard fileManager.fileExists(atPath: codexBackupsDirectory.path),
              let items = try? fileManager.contentsOfDirectory(
                  at: codexBackupsDirectory,
                  includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        return items.compactMap { url -> MoaBackupEntry? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isSymbolicLink != true else { return nil }
            let isDir = values.isDirectory == true
            let size: Int64
            let summary: String?
            if isDir {
                let children = (try? fileManager.contentsOfDirectory(atPath: url.path))?.sorted() ?? []
                summary = children.prefix(4).joined(separator: ", ")
                size = directorySize(url)
            } else {
                summary = nil
                size = Int64(values.fileSize ?? 0)
            }
            return MoaBackupEntry(
                id: "codex|\(url.lastPathComponent)",
                kind: .codexSnapshot,
                name: url.lastPathComponent,
                path: url.path,
                createdAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: size,
                isDirectory: isDir,
                containsItemsSummary: summary
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func listLegacyDownloadsBackups() -> [MoaBackupEntry] {
        guard fileManager.fileExists(atPath: downloadsDirectory.path),
              let items = try? fileManager.contentsOfDirectory(
                  at: downloadsDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        let legacyPrefixes = ["Moa-Data-Rollback-", "Moa-Data-Before-iCloud-", "Moa-Data-Backup-"]
        return items.compactMap { url -> MoaBackupEntry? in
            let name = url.lastPathComponent
            guard url.pathExtension == "zip",
                  name.hasPrefix("Moa-Data-"),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            // Only flag unencrypted Moa data packages (Schema 1/2); skip encrypted Schema 3 archives.
            if let inspection = try? dataPackages.inspectDataPackage(at: url) {
                if inspection.isEncrypted { return nil }
            } else if !legacyPrefixes.contains(where: { name.hasPrefix($0) }) {
                return nil
            }
            return MoaBackupEntry(
                id: "legacy|\(name)",
                kind: .legacyDownloadsBackup,
                name: name,
                path: url.path,
                createdAt: values.contentModificationDate ?? .distantPast,
                sizeBytes: Int64(values.fileSize ?? 0),
                isDirectory: false,
                containsItemsSummary: MoaL10n.text("Unencrypted archive in Downloads")
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func directorySize(_ dir: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
