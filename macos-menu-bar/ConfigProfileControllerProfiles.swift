import Foundation

extension ConfigProfileController {
    func profiles() throws -> [ConfigProfile] {
        try loadDatabase().profiles
    }

    func selectedProfileID() throws -> String? {
        try loadDatabase().selectedProfileID
    }

    func selectedProfileName() -> String? {
        guard let database = try? loadDatabase(), let selectedID = database.selectedProfileID else {
            return nil
        }

        guard let profile = database.profiles.first(where: { $0.id == selectedID }) else {
            return MoaL10n.text("Select a Responses Provider")
        }
        return profile.name
    }

    func selectedProfile() throws -> ConfigProfile? {
        let database = try loadDatabase()
        guard let selectedID = database.selectedProfileID else {
            return nil
        }

        return database.profiles.first(where: { $0.id == selectedID })
    }

    func recoveredAPIKeyFromProfileJSON(for profile: ConfigProfile) -> String? {
        let rawCandidates = profileRecoveryDatabaseURLs()
            .compactMap { url -> [ConfigProfile]? in
                guard let data = try? Data(contentsOf: url),
                      let database = try? JSONDecoder().decode(ProfileDatabase.self, from: data)
                else {
                    return nil
                }
                return database.profiles
            }
            .flatMap { $0 }
            .filter { !$0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var seenCandidates = Set<String>()
        let candidates = rawCandidates.filter { candidate in
            let key = [
                candidate.id,
                candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                Self.profileRecoveryBaseURLKey(candidate.baseURL),
                candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            ].joined(separator: "\u{1F}")
            guard !seenCandidates.contains(key) else {
                return false
            }
            seenCandidates.insert(key)
            return true
        }

        if let exact = candidates.first(where: { $0.id == profile.id }) {
            return exact.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let targetName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetBaseURL = Self.profileRecoveryBaseURLKey(profile.baseURL)
        let nameAndBaseMatches = candidates.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetName
                && Self.profileRecoveryBaseURLKey($0.baseURL) == targetBaseURL
        }
        if nameAndBaseMatches.count == 1 {
            return nameAndBaseMatches[0].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let baseMatches = candidates.filter {
            Self.profileRecoveryBaseURLKey($0.baseURL) == targetBaseURL
        }
        if baseMatches.count == 1 {
            return baseMatches[0].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let nameMatches = candidates.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetName
        }
        if nameMatches.count == 1 {
            return nameMatches[0].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    func profileRecoveryDatabaseURLs() -> [URL] {
        let urls = [
            MoaDataRoot.legacyNestedICloudURL(environment: environment).appendingPathComponent("profiles.json"),
            MoaDataRoot.localURL(environment: environment).appendingPathComponent("profiles.json"),
            MoaDataRoot.iCloudURL(environment: environment).appendingPathComponent("profiles.json")
        ]
        let currentPath = databaseURL.standardizedFileURL.path
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard path != currentPath, !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }

    static func profileRecoveryBaseURLKey(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while key.hasSuffix("/") {
            key.removeLast()
        }
        if key.hasSuffix("/v1") {
            key.removeLast(3)
        }
        return key
    }

    func addProfile(
        name: String,
        baseURL: String,
        apiKey: String,
        model: String? = nil,
        testModel: String? = nil,
        models: [String]? = nil
    ) throws -> ConfigProfile {
        try stateLock.withLock {
            try ensureStore()

            var database = try loadDatabase()
            let validatedBaseURL = try Self.validatedProfileBaseURL(baseURL)
            let profile = ConfigProfile(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: validatedBaseURL,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                model: Self.normalizedOptionalString(model),
                testModel: Self.normalizedOptionalString(testModel),
                models: models
            )

            database.profiles.append(profile)
            try saveDatabase(database)
            return profile
        }
    }

    func updateProfile(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String,
        model: String? = nil,
        testModel: String? = nil,
        models: [String]? = nil
    ) throws -> ConfigProfile {
        try stateLock.withLock {
            try ensureStore()

            var database = try loadDatabase()
            guard let index = database.profiles.firstIndex(where: { $0.id == id }) else {
                throw NSError(domain: "Moa", code: 404, userInfo: [NSLocalizedDescriptionKey: MoaL10n.text("Configuration not found.")])
            }

            let current = database.profiles[index]
            let validatedBaseURL = try Self.validatedProfileBaseURL(baseURL)
            database.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            database.profiles[index].baseURL = validatedBaseURL
            database.profiles[index].apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            database.profiles[index].model = Self.normalizedOptionalString(model) ?? current.model
            database.profiles[index].testModel = Self.normalizedOptionalString(testModel) ?? current.testModel
            database.profiles[index].models = models ?? current.models
            let profile = database.profiles[index]
            try saveDatabase(database)
            return profile
        }
    }

    /// Keep the selection check and application serialized with menu switches.
    /// The caller permits application only after confirming a live edit.
    func updateProfileApplyingIfSelected(id: String, name: String, baseURL: String, apiKey: String, applyToCurrent: Bool) throws -> Bool {
        try stateLock.withLock {
            try ensureStore()
            guard applyToCurrent, try selectedProfileID() == id else {
                _ = try updateProfile(id: id, name: name, baseURL: baseURL, apiKey: apiKey)
                return false
            }
            // applyProfile restores live files on failure; this outer snapshot
            // also restores the profile values saved before that transaction.
            return try withCodexStateTransaction(files: [databaseURL]) {
                _ = try updateProfile(id: id, name: name, baseURL: baseURL, apiKey: apiKey)
                _ = try applyProfile(id: id)
                return true
            }
        }
    }

    @discardableResult
    func deleteProfile(id: String) throws -> ConfigProfile {
        try stateLock.withLock {
            try ensureStore()

            var database = try loadDatabase()
            guard let index = database.profiles.firstIndex(where: { $0.id == id }) else {
                throw NSError(domain: "Moa", code: 404, userInfo: [NSLocalizedDescriptionKey: MoaL10n.text("Configuration not found.")])
            }

            let profile = database.profiles.remove(at: index)
            if database.selectedProfileID == id {
                database.selectedProfileID = nil
            }

            try saveDatabase(database)
            return profile
        }
    }
}
