import Foundation

struct ClaudeCodeProviderProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var smallFastModel: String?
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        smallFastModel: String? = nil,
        updatedAt: Date? = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.smallFastModel = smallFastModel
        self.updatedAt = updatedAt
    }

    var effectiveSmallFastModel: String {
        let trimmed = smallFastModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? model : trimmed
    }
}

private struct ClaudeCodeProviderDatabase: Codable {
    var version: Int = 1
    var selectedProfileID: String?
    var profiles: [ClaudeCodeProviderProfile] = []
}

enum ClaudeCodeSettingsError: LocalizedError {
    case profileNotFound
    case missingRequiredFields
    case invalidBaseURL
    case invalidSettingsJSON(URL)
    case symlinkRejected(URL)

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return MoaL10n.text("Claude Code provider preset not found.")
        case .missingRequiredFields:
            return MoaL10n.text("Name, base URL, and API key are required.")
        case .invalidBaseURL:
            return MoaL10n.text("Claude Code API Base URL must use https://; only localhost, 127.0.0.1, and ::1 may use http://.")
        case .invalidSettingsJSON(let url):
            return MoaL10n.format("Claude Code settings file is not a valid JSON object: %@", url.path)
        case .symlinkRejected(let url):
            return MoaL10n.format("Refusing to write through a symbolic link: %@", url.path)
        }
    }
}

/// Manages independent Claude Code provider presets via safe, field-level JSON edits
/// to `~/.claude/settings.json` (`env.ANTHROPIC_*`), strictly isolated from Claude Desktop.
final class ClaudeCodeSettingsController {
    static let managedEnvKeys: [String] = [
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_SMALL_FAST_MODEL"
    ]

    private let fileManager = FileManager.default
    private let environment: [String: String]
    private let stateLock: MoaDataStoreLock
    let claudeDir: URL
    let settingsURL: URL

    private var moaHome: URL {
        MoaDataRoot.currentURL(environment: environment)
    }

    var databaseURL: URL {
        moaHome.appendingPathComponent("claude_code_profiles.json")
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        self.stateLock = MoaDataStoreLock(environment: environment)
        let home = MoaDataRoot.homeDirectory(environment: environment)
        if let rawConfigDir = environment["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }),
           !rawConfigDir.isEmpty {
            claudeDir = URL(fileURLWithPath: rawConfigDir, isDirectory: true).standardizedFileURL
        } else {
            claudeDir = home.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
        }
        settingsURL = claudeDir.appendingPathComponent("settings.json")
    }

    func profiles() throws -> [ClaudeCodeProviderProfile] {
        try stateLock.withLock { try loadDatabase().profiles }
    }

    func selectedProfileID() throws -> String? {
        try stateLock.withLock { try loadDatabase().selectedProfileID }
    }

    func selectedProfile() throws -> ClaudeCodeProviderProfile? {
        try stateLock.withLock {
            let db = try loadDatabase()
            guard let id = db.selectedProfileID else { return nil }
            return db.profiles.first { $0.id == id }
        }
    }

    /// Reads only the managed `env` keys from `~/.claude/settings.json` for health/drift checks.
    func liveManagedEnv() -> [String: String]? {
        guard fileManager.fileExists(atPath: settingsURL.path),
              (try? settingsURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = object["env"] as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for key in Self.managedEnvKeys {
            if let value = env[key] as? String {
                result[key] = value
            }
        }
        return result.isEmpty ? nil : result
    }

    @discardableResult
    func addProfile(
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        smallFastModel: String? = nil
    ) throws -> ClaudeCodeProviderProfile {
        try stateLock.withLock {
            let validated = try validatedFields(name: name, baseURL: baseURL, apiKey: apiKey, model: model, smallFastModel: smallFastModel)
            var db = try loadDatabase()
            let profile = ClaudeCodeProviderProfile(
                name: validated.name,
                baseURL: validated.baseURL,
                apiKey: validated.apiKey,
                model: validated.model,
                smallFastModel: validated.smallFastModel,
                updatedAt: Date()
            )
            db.profiles.append(profile)
            try saveDatabase(db)
            return profile
        }
    }

    @discardableResult
    func updateProfile(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        smallFastModel: String? = nil,
        applyToCurrent: Bool = false
    ) throws -> ClaudeCodeProviderProfile {
        try stateLock.withLock {
            let validated = try validatedFields(name: name, baseURL: baseURL, apiKey: apiKey, model: model, smallFastModel: smallFastModel)
            var db = try loadDatabase()
            guard let index = db.profiles.firstIndex(where: { $0.id == id }) else {
                throw ClaudeCodeSettingsError.profileNotFound
            }
            db.profiles[index].name = validated.name
            db.profiles[index].baseURL = validated.baseURL
            db.profiles[index].apiKey = validated.apiKey
            db.profiles[index].model = validated.model
            db.profiles[index].smallFastModel = validated.smallFastModel
            db.profiles[index].updatedAt = Date()
            let updated = db.profiles[index]
            if applyToCurrent && db.selectedProfileID == id {
                try withSettingsTransaction(database: db) {
                    try applyManagedEnv(for: updated)
                }
            } else {
                try saveDatabase(db)
            }
            return updated
        }
    }

    @discardableResult
    func renameProfile(id: String, name: String) throws -> ClaudeCodeProviderProfile {
        try stateLock.withLock {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ClaudeCodeSettingsError.missingRequiredFields }
            var db = try loadDatabase()
            guard let index = db.profiles.firstIndex(where: { $0.id == id }) else {
                throw ClaudeCodeSettingsError.profileNotFound
            }
            db.profiles[index].name = trimmed
            db.profiles[index].updatedAt = Date()
            try saveDatabase(db)
            return db.profiles[index]
        }
    }

    @discardableResult
    func applyProfile(id: String) throws -> ClaudeCodeProviderProfile {
        try stateLock.withLock {
            var db = try loadDatabase()
            guard let profile = db.profiles.first(where: { $0.id == id }) else {
                throw ClaudeCodeSettingsError.profileNotFound
            }
            _ = try validatedFields(
                name: profile.name,
                baseURL: profile.baseURL,
                apiKey: profile.apiKey,
                model: profile.model,
                smallFastModel: profile.smallFastModel
            )
            db.selectedProfileID = profile.id
            try withSettingsTransaction(database: db) {
                try applyManagedEnv(for: profile)
            }
            return profile
        }
    }

    func restoreOfficialMode() throws {
        try stateLock.withLock {
            var db = try loadDatabase()
            db.selectedProfileID = nil
            try withSettingsTransaction(database: db) {
                try removeManagedEnvKeys()
            }
        }
    }

    @discardableResult
    func deleteProfile(id: String) throws -> ClaudeCodeProviderProfile {
        try stateLock.withLock {
            var db = try loadDatabase()
            guard let index = db.profiles.firstIndex(where: { $0.id == id }) else {
                throw ClaudeCodeSettingsError.profileNotFound
            }
            let removed = db.profiles.remove(at: index)
            let wasSelected = db.selectedProfileID == id
            if wasSelected {
                db.selectedProfileID = nil
            }
            try withSettingsTransaction(database: db) {
                if wasSelected {
                    try removeManagedEnvKeys()
                }
            }
            return removed
        }
    }

    /// Creates or returns a Claude Code preset copied from a Claude Desktop provider.
    @discardableResult
    func importFromDesktopProvider(_ desktop: ClaudeDesktopProviderProfile) throws -> ClaudeCodeProviderProfile {
        let model = desktop.models.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = (model?.isEmpty == false ? model! : ProviderConnectionTester.claudeDefaultTestModel)
        return try addProfile(
            name: desktop.name,
            baseURL: desktop.baseURL,
            apiKey: desktop.apiKey,
            model: effectiveModel,
            smallFastModel: effectiveModel
        )
    }

    static func environmentSnippet(for profile: ClaudeCodeProviderProfile) -> String {
        """
        # Claude Code (\(profile.name))
        export ANTHROPIC_BASE_URL="\(AppDelegate.shellEscaped(profile.baseURL))"
        export ANTHROPIC_AUTH_TOKEN="\(AppDelegate.shellEscaped(profile.apiKey))"
        export ANTHROPIC_MODEL="\(AppDelegate.shellEscaped(profile.model))"
        export ANTHROPIC_SMALL_FAST_MODEL="\(AppDelegate.shellEscaped(profile.effectiveSmallFastModel))"
        """
    }

    func exportProfiles(includingAPIKeys: Bool) throws -> Data {
        try stateLock.withLock {
            let db = try loadDatabase()
            let entries = db.profiles.map { profile in
                ProviderProfileExportEntry(
                    name: profile.name,
                    baseURL: profile.baseURL,
                    apiKey: includingAPIKeys ? profile.apiKey : nil,
                    models: [profile.model],
                    oneMModels: nil,
                    model: profile.model,
                    testModel: profile.smallFastModel
                )
            }
            let document = ProviderProfileExportDocument(
                schemaVersion: 1,
                provider: "claudeCode",
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                profiles: entries
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(document)
        }
    }

    @discardableResult
    func importProfiles(from data: Data) throws -> Int {
        try stateLock.withLock {
            let document = try JSONDecoder().decode(ProviderProfileExportDocument.self, from: data)
            guard document.provider == "claudeCode" || document.provider == "claudeDesktop" else {
                throw ProviderProfileExportError.providerMismatch(expected: "Claude Code", actual: document.provider)
            }
            guard !document.profiles.isEmpty else {
                throw ProviderProfileExportError.emptyDocument
            }
            var db = try loadDatabase()
            for entry in document.profiles {
                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawURL = entry.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let validatedURL = try? MoaProviderBaseURLPolicy.validate(rawURL).normalizedString else {
                    throw ProviderProfileExportError.invalidProfile(entry.name)
                }
                let model = (entry.model ?? entry.models?.first ?? ProviderConnectionTester.claudeDefaultTestModel)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveModel = model.isEmpty ? ProviderConnectionTester.claudeDefaultTestModel : model
                let smallFast = entry.testModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                db.profiles.append(ClaudeCodeProviderProfile(
                    name: name,
                    baseURL: validatedURL,
                    apiKey: entry.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    model: effectiveModel,
                    smallFastModel: smallFast?.isEmpty == false ? smallFast : nil,
                    updatedAt: Date()
                ))
            }
            try saveDatabase(db)
            return document.profiles.count
        }
    }

    func openClaudeCodeFolder() {
        try? fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        _ = MoaProcessRunner.run("/usr/bin/open", [claudeDir.path])
    }

    // MARK: - Private Helpers

    private func validatedFields(
        name: String,
        baseURL: String,
        apiKey: String,
        model: String,
        smallFastModel: String?
    ) throws -> (name: String, baseURL: String, apiKey: String, model: String, smallFastModel: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmall = smallFastModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            throw ClaudeCodeSettingsError.missingRequiredFields
        }
        let normalizedURL: String
        do {
            normalizedURL = try MoaProviderBaseURLPolicy.validate(trimmedURL).normalizedString
        } catch {
            throw ClaudeCodeSettingsError.invalidBaseURL
        }
        let finalModel = trimmedModel.isEmpty ? ProviderConnectionTester.claudeDefaultTestModel : trimmedModel
        return (
            name: trimmedName,
            baseURL: normalizedURL,
            apiKey: trimmedKey,
            model: finalModel,
            smallFastModel: (trimmedSmall?.isEmpty == false) ? trimmedSmall : nil
        )
    }

    private func loadDatabase() throws -> ClaudeCodeProviderDatabase {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return ClaudeCodeProviderDatabase()
        }
        let data = try Data(contentsOf: databaseURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClaudeCodeProviderDatabase.self, from: data)
    }

    private func saveDatabase(_ database: ClaudeCodeProviderDatabase) throws {
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)
        try MoaSecureFile.write(data, to: databaseURL)
    }

    private func withSettingsTransaction(
        database: ClaudeCodeProviderDatabase,
        operation: () throws -> Void
    ) throws {
        try rejectSymlinks(settingsURL)
        let priorSettings = fileManager.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
        let priorDatabase = fileManager.fileExists(atPath: databaseURL.path) ? try Data(contentsOf: databaseURL) : nil
        do {
            try operation()
            try saveDatabase(database)
        } catch let operationError {
            do {
                if let priorSettings {
                    try MoaSecureFile.write(priorSettings, to: settingsURL)
                } else if fileManager.fileExists(atPath: settingsURL.path) {
                    try fileManager.removeItem(at: settingsURL)
                }
                if let priorDatabase {
                    try MoaSecureFile.write(priorDatabase, to: databaseURL)
                } else if fileManager.fileExists(atPath: databaseURL.path) {
                    try fileManager.removeItem(at: databaseURL)
                }
            } catch let rollbackError {
                throw NSError(
                    domain: "MoaClaudeCode",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: MoaL10n.format(
                        "Claude Code settings update failed (%@), and rollback also failed: %@",
                        operationError.localizedDescription,
                        rollbackError.localizedDescription
                    )]
                )
            }
            throw operationError
        }
    }

    private func applyManagedEnv(for profile: ClaudeCodeProviderProfile) throws {
        var root = try readSettingsObject()
        var env = root["env"] as? [String: Any] ?? [:]
        env["ANTHROPIC_BASE_URL"] = profile.baseURL
        env["ANTHROPIC_AUTH_TOKEN"] = profile.apiKey
        env["ANTHROPIC_MODEL"] = profile.model
        env["ANTHROPIC_SMALL_FAST_MODEL"] = profile.effectiveSmallFastModel
        root["env"] = env
        try writeSettingsObject(root)
    }

    private func removeManagedEnvKeys() throws {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return }
        var root = try readSettingsObject()
        guard var env = root["env"] as? [String: Any] else { return }
        for key in Self.managedEnvKeys {
            env.removeValue(forKey: key)
        }
        if env.isEmpty {
            root.removeValue(forKey: "env")
        } else {
            root["env"] = env
        }
        try writeSettingsObject(root)
    }

    private func readSettingsObject() throws -> [String: Any] {
        try rejectSymlinks(settingsURL)
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCodeSettingsError.invalidSettingsJSON(settingsURL)
        }
        return object
    }

    private func writeSettingsObject(_ object: [String: Any]) throws {
        try rejectSymlinks(claudeDir)
        try rejectSymlinks(settingsURL)
        try fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try MoaSecureFile.write(data, to: settingsURL)
    }

    private func rejectSymlinks(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            throw ClaudeCodeSettingsError.symlinkRejected(url)
        }
    }
}
