import AppKit
import Darwin
import Foundation

private enum FastModeError: LocalizedError {
    case invalidStateFile(URL)
    case clientStillRunning

    var errorDescription: String? {
        switch self {
        case .clientStillRunning:
            return MoaL10n.text("ChatGPT could not be closed. Finish the active task and try again.")
        case .invalidStateFile(let url):
            return MoaL10n.format("Invalid JSON state file: %@", url.path)
        }
    }
}

enum CodexDesktopApplication {
    static let bundleIdentifier = "com.openai.codex"

    static func applicationURL(environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        if let override = environment["CODEX_APP"], !override.isEmpty {
            let url = URL(fileURLWithPath: override).resolvingSymlinksInPath().standardizedFileURL
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           fileManager.fileExists(atPath: installed.path) {
            return installed.resolvingSymlinksInPath().standardizedFileURL
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        for path in ["/Applications/ChatGPT.app", "\(home)/Applications/ChatGPT.app",
                     "/Applications/Codex.app", "\(home)/Applications/Codex.app"] {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: path), Bundle(url: url)?.bundleIdentifier == bundleIdentifier {
                return url
            }
        }
        return nil
    }
}

final class FastStateController: Sendable {
    private let environment: [String: String]
    private let codexHome: URL
    private var codexApp: URL? { CodexDesktopApplication.applicationURL(environment: environment) }
    private let backupDir: URL

    private var fileManager: FileManager { .default }

    private var stateURL: URL {
        codexHome.appendingPathComponent(".codex-global-state.json")
    }

    private var stateBackupURL: URL {
        codexHome.appendingPathComponent(".codex-global-state.json.bak")
    }

    private var codexConfigURL: URL {
        codexHome.appendingPathComponent("config.toml")
    }

    private var moaConfigURL: URL {
        moaHome.appendingPathComponent("config.toml")
    }

    private var moaHome: URL {
        MoaDataRoot.currentURL(environment: environment)
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        let codexHomePath = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.codex"

        codexHome = URL(fileURLWithPath: codexHomePath).standardizedFileURL
        backupDir = codexHome.appendingPathComponent("fast-toggle-backups")
    }

    func serviceTier() -> String? {
        let config = try? String(contentsOf: codexConfigURL, encoding: .utf8)
        if let config,
           let desktopTier = MoaTomlEditor.stringValue(in: config, table: "desktop", key: "default-service-tier") {
            return desktopTier
        }
        // Match the desktop migration: an unmigrated persisted preference wins
        // over the root config fallback when the desktop key is absent.
        if let root = try? loadState(from: stateURL),
           let atom = root["electron-persisted-atom-state"] as? [String: Any],
           let tier = atom["default-service-tier"] as? String, !tier.isEmpty {
            return tier
        }
        guard let config, !usesLegacyServiceTierStorage else { return nil }
        return MoaTomlEditor.stringValue(in: config, table: "", key: "service_tier")
    }

    func isFastEnabled() -> Bool {
        serviceTier().map { ["fast", "priority"].contains($0.lowercased()) } ?? false
    }

    private var usesLegacyServiceTierStorage: Bool {
        if let config = try? String(contentsOf: codexConfigURL, encoding: .utf8),
           MoaTomlEditor.lineContexts(in: config).contains(where: {
               $0.isStructural && MoaTomlEditor.tableName(from: $0.text) == "desktop"
           }) { return false }
        guard let codexApp else { return false }
        return Bundle(url: codexApp)?.executableURL?.lastPathComponent == "Codex"
    }

    func applyFastMode(_ enabled: Bool) throws {
        guard quitCodexIfNeeded() else { throw FastModeError.clientStillRunning }
        defer { openCodexIfAvailable() }
        let legacy = usesLegacyServiceTierStorage
        var targets = legacy ? [stateURL, stateBackupURL] : [codexConfigURL]
        if !legacy, fileManager.fileExists(atPath: moaConfigURL.path) { targets.append(moaConfigURL) }
        let snapshots = try targets.map { url -> (url: URL, data: Data?, permissions: Any?) in
            guard fileManager.fileExists(atPath: url.path) else { return (url, nil, nil) }
            return (url, try Data(contentsOf: url), try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions])
        }
        if legacy { try backupExistingFiles() } else { try backupConfigFiles() }
        do {
            for url in targets {
                if legacy { try rewriteStateFile(url, enabled: enabled) }
                else { try rewriteServiceTierConfig(url, enabled: enabled) }
            }
        } catch {
            let originalError = error
            for snapshot in snapshots {
                if let data = snapshot.data {
                    try data.write(to: snapshot.url, options: .atomic)
                    if let permissions = snapshot.permissions {
                        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: snapshot.url.path)
                    }
                } else if fileManager.fileExists(atPath: snapshot.url.path) {
                    try fileManager.removeItem(at: snapshot.url)
                }
            }
            throw originalError
        }
    }

    func openRemoteConnectionsSettings() {
        guard let codexApp else { return }
        _ = run("/usr/bin/open", ["-a", codexApp.path, "codex://settings/connections"])
    }

    private func rewriteServiceTierConfig(_ url: URL, enabled: Bool) throws {
        let config: String
        if fileManager.fileExists(atPath: url.path) {
            config = try String(contentsOf: url, encoding: .utf8)
        } else {
            config = ""
        }
        let tier = enabled ? "priority" : "default"
        var output = MoaTomlEditor.upsertingString(tier, in: config, table: "desktop", key: "default-service-tier")
        // Explicitly reset the root fallback as well, so disabling Fast cannot
        // reveal an older priority preference when the desktop setting is cleared.
        output = MoaTomlEditor.upsertingString(tier, in: output, table: "", key: "service_tier")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func reopenCodex() {
        guard quitCodexIfNeeded() else { return }
        openCodexIfAvailable()
    }

    func quitCodex() throws {
        guard quitCodexIfNeeded() else { throw FastModeError.clientStillRunning }
    }

    func openCodex() {
        openCodexIfAvailable()
    }

    private func backupExistingFiles() throws {
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for url in [stateURL, stateBackupURL] where fileManager.fileExists(atPath: url.path) {
            let stamp = Self.timestamp()
            let backupName = "\(url.lastPathComponent).\(stamp)"
            let destination = backupDir.appendingPathComponent(backupName)
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: url, to: destination)
        }
    }

    private func backupConfigFiles() throws {
        let existingFiles = [
            (label: "codex", url: codexConfigURL),
            (label: "moa", url: moaConfigURL)
        ].filter { fileManager.fileExists(atPath: $0.url.path) }

        guard !existingFiles.isEmpty else {
            return
        }

        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = Self.timestamp()

        for file in existingFiles {
            let destination = backupDir.appendingPathComponent("\(file.label)-\(file.url.lastPathComponent).\(stamp)")
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: file.url, to: destination)
        }
    }

    private func rewriteStateFile(_ url: URL, enabled: Bool) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

        var root = try loadState(from: url)
        var atom = root["electron-persisted-atom-state"] as? [String: Any] ?? [:]

        if enabled {
            atom["has-user-changed-service-tier"] = true
            atom["default-service-tier"] = "fast"
            atom["has-seen-fast-mode-announcement"] = true
        } else {
            atom.removeValue(forKey: "has-user-changed-service-tier")
            atom.removeValue(forKey: "default-service-tier")
            atom.removeValue(forKey: "has-seen-fast-mode-announcement")
        }

        root["electron-persisted-atom-state"] = atom
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        var output = Data(data)
        output.append(0x0a)
        try output.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // Legacy TOML transformations are retained for importing older configurations.
    // Live desktop connections are managed through the client's settings page.
    func remoteConnectionsEnabled(in text: String) -> Bool {
        tomlBoolValue(in: text, table: "features", key: "remote_connections") == true
            && tomlBoolValue(in: text, table: "features", key: "remote_control") == true
    }

    func setRemoteConnections(_ enabled: Bool, in text: String) -> String {
        enabled ? enableRemoteConnections(in: text) : disableRemoteConnections(in: text)
    }

    private func enableRemoteConnections(in text: String) -> String {
        let featureLines = [
            "[features]",
            "remote_connections = true",
            "remote_control = true"
        ]
        var output: [String] = []
        var inFeatures = false
        var foundFeatures = false

        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if context.isStructural, let table = parseTomlTableName(from: trimmed) {
                inFeatures = table == "features"
                if inFeatures {
                    foundFeatures = true
                    output.append(contentsOf: featureLines)
                } else {
                    output.append(line)
                }
                continue
            }

            if inFeatures, context.isStructural,
               let keyValue = parseTomlKeyValue(from: line),
               keyValue.key == "remote_connections" || keyValue.key == "remote_control" {
                continue
            }

            output.append(line)
        }

        if !foundFeatures {
            if !output.isEmpty, output.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                output.append("")
            }
            output.append(contentsOf: featureLines)
        }

        return collapseBlankLines(output.joined(separator: "\n"))
    }

    private func disableRemoteConnections(in text: String) -> String {
        var output: [String] = []
        var featureHeader: String?
        var featureLines: [MoaTomlEditor.LineContext] = []
        var inFeatures = false

        func flushFeatures() {
            guard let featureHeader else {
                return
            }

            let remaining = featureLines.filter { context in
                guard context.isStructural,
                      let keyValue = parseTomlKeyValue(from: context.text)
                else {
                    return true
                }
                return keyValue.key != "remote_connections" && keyValue.key != "remote_control"
            }
            let hasNonEmptyContent = remaining.contains { context in
                let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }

            if hasNonEmptyContent {
                output.append(featureHeader)
                output.append(contentsOf: remaining.map(\.text))
            }
        }

        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if context.isStructural, let table = parseTomlTableName(from: trimmed) {
                if inFeatures {
                    flushFeatures()
                    featureHeader = nil
                    featureLines = []
                }

                inFeatures = table == "features"
                if inFeatures {
                    featureHeader = line
                } else {
                    output.append(line)
                }
                continue
            }

            if inFeatures {
                featureLines.append(context)
            } else {
                output.append(line)
            }
        }

        if inFeatures {
            flushFeatures()
        }

        return collapseBlankLines(output.joined(separator: "\n"))
    }

    private func tomlBoolValue(in text: String, table: String, key: String) -> Bool? {
        var currentTable = ""

        for context in MoaTomlEditor.lineContexts(in: text) where context.isStructural {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tableName = parseTomlTableName(from: trimmed) {
                currentTable = tableName
                continue
            }

            guard currentTable == table,
                  let keyValue = parseTomlKeyValue(from: line),
                  keyValue.key == key
            else {
                continue
            }

            switch keyValue.value.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private func parseTomlTableName(from line: String) -> String? {
        MoaTomlEditor.tableName(from: line)
    }

    private func parseTomlKeyValue(from line: String) -> (key: String, value: String)? {
        MoaTomlEditor.keyValue(from: line)
    }

    private func collapseBlankLines(_ text: String) -> String {
        MoaTomlEditor.collapseBlankLines(text)
    }

    private func loadState(from url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return ["electron-persisted-atom-state": [String: Any]()]
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return ["electron-persisted-atom-state": [String: Any]()]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw FastModeError.invalidStateFile(url)
        }

        return root
    }

    @discardableResult
    private func quitCodexIfNeeded() -> Bool {
        let applications = runningCodexApplications()
        guard !applications.isEmpty else { return true }
        applications.forEach { _ = $0.terminate() }
        if waitForCodexRunning(false, timeout: 4) { return true }
        runningCodexApplications().forEach { _ = $0.forceTerminate() }
        return waitForCodexRunning(false, timeout: 3)
    }

    private func openCodexIfAvailable() {
        guard let codexApp else { return }
        _ = run("/usr/bin/open", [codexApp.path])
    }

    private func runningCodexApplications() -> [NSRunningApplication] {
        guard let codexApp else { return [] }
        let identifier = Bundle(url: codexApp)?.bundleIdentifier ?? CodexDesktopApplication.bundleIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { application in
            guard application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == codexApp.resolvingSymlinksInPath().standardizedFileURL.path,
                  application.processIdentifier > 0 else { return false }
            // AppKit termination state waits for a main run-loop turn. Check
            // process existence too so synchronous reopen cannot poll stale apps.
            return Darwin.kill(application.processIdentifier, 0) == 0 || errno == EPERM
        }
    }

    private func isCodexRunning() -> Bool {
        !runningCodexApplications().isEmpty
    }

    private func waitForCodexRunning(_ running: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCodexRunning() == running {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return isCodexRunning() == running
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
