import CryptoKit
import Foundation

private struct SessionFileChange {
    let url: URL
    let backupURL: URL
    let afterHash: String
}

struct CodexSessionProviderMigrationResult {
    let providerID: String
    let jsonlFilesUpdated: Int
    let sqliteRowsUpdated: Int
    let backupURL: URL
}

enum CodexSessionProviderMigrationError: LocalizedError {
    case missingModelProvider
    case sqliteUpdateFailed(path: String)
    case historyChanged(path: String)
    case migrationFailedAndRestored(reason: String, backupPath: String)
    case migrationFailedRollbackFailed(reason: String, backupPath: String, rollbackReason: String)

    var errorDescription: String? {
        switch self {
        case .missingModelProvider:
            return MoaL10n.text("The current model_provider field is missing. Migration failed.")
        case .sqliteUpdateFailed(let path):
            return MoaL10n.format("Failed to update Codex SQLite history index: %@", path)
        case .historyChanged(let path):
            return MoaL10n.format("Codex history changed during migration: %@. Close all Codex instances and try again.", path)
        case .migrationFailedAndRestored(let reason, let backupPath):
            return MoaL10n.format(
                "Migration failed and the previous Codex history was restored.\nReason: %@\nBackup: %@",
                reason,
                backupPath
            )
        case .migrationFailedRollbackFailed(let reason, let backupPath, let rollbackReason):
            return MoaL10n.format(
                "Migration failed and automatic rollback failed.\nReason: %@\nBackup: %@\nRollback error: %@",
                reason,
                backupPath,
                rollbackReason
            )
        }
    }
}

extension ConfigProfileController {
    func currentCodexRootModelProvider() throws -> String {
        guard fileManager.fileExists(atPath: codexConfigURL.path),
              let config = try? String(contentsOf: codexConfigURL, encoding: .utf8),
              let provider = rootTomlStringValue(in: config, key: "model_provider")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !provider.isEmpty
        else {
            throw CodexSessionProviderMigrationError.missingModelProvider
        }

        return provider
    }

    func migrateCodexSessionModelProviderToCurrentConfig() throws -> CodexSessionProviderMigrationResult {
        let providerID = try currentCodexRootModelProvider()
        return try migrateCodexSessionModelProvider(to: providerID)
    }

    func migrateCodexSessionModelProvider(to providerID: String, verifyQuiescence: () throws -> Void = {}) throws -> CodexSessionProviderMigrationResult {
        try stateLock.withLock {
            let trimmedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProviderID.isEmpty else {
                throw CodexSessionProviderMigrationError.missingModelProvider
            }

            try verifyQuiescence()
            let backupURL = try backupCodexSessionProviderMigrationFiles()
            let jsonlFilesUpdated: Int
            let sqliteRowsUpdated: Int
            var changedFiles: [SessionFileChange] = []

            do {
                jsonlFilesUpdated = try migrateCodexSessionJSONLFiles(to: trimmedProviderID, backupURL: backupURL, changedFiles: &changedFiles, verifyQuiescence: verifyQuiescence)
                try verifyQuiescence()
                sqliteRowsUpdated = try migrateCodexSessionSQLiteIndexes(to: trimmedProviderID)
            } catch {
                let originalReason = error.localizedDescription
                do {
                    try restoreChangedSessionFiles(changedFiles, verifyQuiescence: verifyQuiescence)
                } catch {
                    throw CodexSessionProviderMigrationError.migrationFailedRollbackFailed(
                        reason: originalReason,
                        backupPath: backupURL.path,
                        rollbackReason: error.localizedDescription
                    )
                }
                throw CodexSessionProviderMigrationError.migrationFailedAndRestored(
                    reason: originalReason,
                    backupPath: backupURL.path
                )
            }

            return CodexSessionProviderMigrationResult(
                providerID: trimmedProviderID,
                jsonlFilesUpdated: jsonlFilesUpdated,
                sqliteRowsUpdated: sqliteRowsUpdated,
                backupURL: backupURL
            )
        }
    }

    private func backupCodexSessionProviderMigrationFiles() throws -> URL {
        let destinationRoot = backupDir
            .appendingPathComponent("codex-session-provider-migration-\(Self.timestamp())-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destinationRoot.path)

        for directory in codexSessionHistoryDirectories() where fileManager.fileExists(atPath: directory.path) {
            let destination = destinationRoot.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: directory, to: destination)
        }

        for database in codexSessionStateDatabaseURLs() where fileManager.fileExists(atPath: database.path) {
            let destination = destinationRoot.appendingPathComponent(databaseBackupName(for: database))
            try? fileManager.removeItem(at: destination)
            let escapedPath = destination.path.replacingOccurrences(of: "'", with: "''")
            _ = try runSQLite(databaseURL: database, sql: "VACUUM INTO '\(escapedPath)';")
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }

        return destinationRoot
    }

    private func restoreChangedSessionFiles(_ changes: [SessionFileChange], verifyQuiescence: () throws -> Void) throws {
        for change in changes.reversed() {
            try verifyQuiescence()
            guard (try? MoaFileHash.sha256(change.url)) == change.afterHash else {
                throw CodexSessionProviderMigrationError.historyChanged(path: change.url.path)
            }
            try Data(contentsOf: change.backupURL).write(to: change.url, options: .atomic)
        }
    }

    private func migrateCodexSessionJSONLFiles(to providerID: String, backupURL: URL, changedFiles: inout [SessionFileChange], verifyQuiescence: () throws -> Void) throws -> Int {
        var updated = 0

        for directory in codexSessionHistoryDirectories() where fileManager.fileExists(atPath: directory.path) {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
                let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard filePath.hasPrefix(directoryPath + "/") else {
                    throw CodexSessionProviderMigrationError.historyChanged(path: fileURL.path)
                }
                let relativePath = String(filePath.dropFirst(directoryPath.count + 1))
                let backupFile = backupURL.appendingPathComponent(directory.lastPathComponent).appendingPathComponent(relativePath)
                if try migrateCodexSessionJSONLFile(fileURL, backupFile: backupFile, to: providerID, changedFiles: &changedFiles, verifyQuiescence: verifyQuiescence) {
                    updated += 1
                }
            }
        }

        return updated
    }

    private func migrateCodexSessionJSONLFile(_ fileURL: URL, backupFile: URL, to providerID: String, changedFiles: inout [SessionFileChange], verifyQuiescence: () throws -> Void) throws -> Bool {
        let original = try Data(contentsOf: fileURL)
        guard original == (try? Data(contentsOf: backupFile)) else {
            throw CodexSessionProviderMigrationError.historyChanged(path: fileURL.path)
        }
        guard let text = String(data: original, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        guard let firstLineEnd = text.firstIndex(of: "\n") else {
            return try migrateCodexSessionJSONLText(text, rest: "", fileURL: fileURL, backupFile: backupFile, original: original, providerID: providerID, changedFiles: &changedFiles, verifyQuiescence: verifyQuiescence)
        }

        let firstLine = String(text[..<firstLineEnd])
        let rest = String(text[firstLineEnd...])
        return try migrateCodexSessionJSONLText(firstLine, rest: rest, fileURL: fileURL, backupFile: backupFile, original: original, providerID: providerID, changedFiles: &changedFiles, verifyQuiescence: verifyQuiescence)
    }

    private func migrateCodexSessionJSONLText(_ firstLine: String, rest: String, fileURL: URL, backupFile: URL, original: Data, providerID: String, changedFiles: inout [SessionFileChange], verifyQuiescence: () throws -> Void) throws -> Bool {
        guard let data = firstLine.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              var object = parsed as? [String: Any]
        else {
            return false
        }

        guard var payload = object["payload"] as? [String: Any],
              payload["model_provider"] is String
        else {
            return false
        }

        if (payload["model_provider"] as? String) == providerID {
            return false
        }

        payload["model_provider"] = providerID
        object["payload"] = payload

        let outputData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let outputLine = String(data: outputData, encoding: .utf8) else {
            return false
        }

        let output = Data("\(outputLine)\(rest)".utf8)
        try verifyQuiescence()
        guard (try? Data(contentsOf: fileURL)) == original else {
            throw CodexSessionProviderMigrationError.historyChanged(path: fileURL.path)
        }
        try output.write(to: fileURL, options: .atomic)
        let hash = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
        changedFiles.append(SessionFileChange(url: fileURL, backupURL: backupFile, afterHash: hash))
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return true
    }

    private func migrateCodexSessionSQLiteIndexes(to providerID: String) throws -> Int {
        var databases: [URL] = []
        for database in codexSessionStateDatabaseURLs() where fileManager.fileExists(atPath: database.path) {
            if try sqliteThreadsTableHasModelProvider(in: database) { databases.append(database) }
        }
        guard let first = databases.first else { return 0 }

        let escapedProvider = providerID.replacingOccurrences(of: "'", with: "''")
        var sql = ""
        for (index, database) in databases.dropFirst().enumerated() {
            let path = database.path.replacingOccurrences(of: "'", with: "''")
            sql += "ATTACH DATABASE '\(path)' AS migration_\(index);\n"
        }
        sql += "BEGIN IMMEDIATE;\n"
        for index in databases.indices {
            let schema = index == 0 ? "main" : "migration_\(index - 1)"
            sql += "UPDATE \(schema).threads SET model_provider = '\(escapedProvider)' WHERE model_provider IS NOT '\(escapedProvider)';\nSELECT changes();\n"
        }
        sql += "COMMIT;"
        let output = try runSQLite(databaseURL: first, sql: sql)
        return output.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }.reduce(0, +)
    }

    private func sqliteThreadsTableHasModelProvider(in databaseURL: URL) throws -> Bool {
        let output = try runSQLite(databaseURL: databaseURL, sql: "PRAGMA table_info(threads);")
        return output.components(separatedBy: "\n").contains { line in
            line.components(separatedBy: "|").dropFirst().first == "model_provider"
        }
    }

    private func runSQLite(databaseURL: URL, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-batch", "-bail", databaseURL.path]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CodexSessionProviderMigrationError.sqliteUpdateFailed(path: databaseURL.path)
        }

        try inputPipe.fileHandleForWriting.write(contentsOf: Data((sql + "\n").utf8))
        try inputPipe.fileHandleForWriting.close()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            NSLog("Moa Codex SQLite migration failed for \(databaseURL.path): \(errorOutput)")
            throw CodexSessionProviderMigrationError.sqliteUpdateFailed(path: databaseURL.path)
        }

        return output
    }

    private func codexSessionHistoryDirectories() -> [URL] {
        [
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
    }

    private func codexSessionStateDatabaseURLs() -> [URL] {
        [
            codexHome.appendingPathComponent("state_5.sqlite"),
            codexHome.appendingPathComponent("sqlite", isDirectory: true).appendingPathComponent("state_5.sqlite")
        ]
    }

    private func databaseBackupName(for databaseURL: URL) -> String {
        if databaseURL.deletingLastPathComponent().lastPathComponent == "sqlite" {
            return "sqlite-\(databaseURL.lastPathComponent)"
        }
        return databaseURL.lastPathComponent
    }
}
