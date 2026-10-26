import Foundation

extension ConfigProfileController {
    func exportProfiles(includingAPIKeys: Bool) throws -> Data {
        try ensureStore()
        let entries = try loadDatabase().profiles.map { profile in
            ProviderProfileExportEntry(
                name: profile.name,
                baseURL: profile.baseURL,
                apiKey: includingAPIKeys ? profile.apiKey : nil,
                models: profile.models,
                oneMModels: nil,
                model: profile.model,
                testModel: profile.testModel)
        }
        let document = ProviderProfileExportDocument(
            schemaVersion: 2,
            provider: Self.exportProviderID,
            exportedAt: Self.isoTimestamp(),
            profiles: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    @discardableResult
    func importProfiles(from data: Data) throws -> Int {
        try stateLock.withLock {
            try ensureStore()
            let document = try JSONDecoder().decode(ProviderProfileExportDocument.self, from: data)
            guard document.provider == Self.exportProviderID else {
                throw ProviderProfileExportError.providerMismatch(expected: "Codex", actual: document.provider)
            }
            guard !document.profiles.isEmpty else {
                throw ProviderProfileExportError.emptyDocument
            }

            var database = try loadDatabase()
            for entry in document.profiles {
                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseURL = entry.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let validatedBaseURL = try? Self.validatedProfileBaseURL(baseURL) else {
                    throw ProviderProfileExportError.invalidProfile(entry.name)
                }

                let profile = ConfigProfile(
                    id: UUID().uuidString,
                    name: name,
                    baseURL: validatedBaseURL,
                    apiKey: entry.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    schemaVersion: document.schemaVersion,
                    model: entry.model,
                    testModel: entry.testModel,
                    models: entry.models)
                database.profiles.append(profile)
            }

            try saveDatabase(database)
            return document.profiles.count
        }
    }
}
