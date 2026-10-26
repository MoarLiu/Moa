import Foundation

struct ProfileDatabase: Codable {
    var selectedProfileID: String?
    var profiles: [ConfigProfile]
    var retiredProfiles: [MoaStoredJSONValue]

    init(selectedProfileID: String?, profiles: [ConfigProfile], retiredProfiles: [MoaStoredJSONValue] = []) {
        self.selectedProfileID = selectedProfileID
        self.profiles = profiles
        self.retiredProfiles = retiredProfiles
    }

    private enum CodingKeys: String, CodingKey { case selectedProfileID, profiles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProfileID = try container.decodeIfPresent(String.self, forKey: .selectedProfileID)
        var entries = try container.nestedUnkeyedContainer(forKey: .profiles)
        profiles = []
        retiredProfiles = []
        while !entries.isAtEnd {
            let entry = try entries.superDecoder()
            if try MoaProviderProfileCompatibility.supportsDirectResponses(entry) {
                profiles.append(try ConfigProfile(from: entry))
            } else {
                retiredProfiles.append(try MoaStoredJSONValue(from: entry))
            }
        }
        // Preserve an unavailable selection as a prompt to choose a provider,
        // rather than claiming the live client has already switched to Official.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedProfileID, forKey: .selectedProfileID)
        var entries = container.nestedUnkeyedContainer(forKey: .profiles)
        for profile in profiles {
            try entries.encode(profile)
        }
        for profile in retiredProfiles {
            try entries.encode(profile)
        }
    }
}

// Opaque data kept only for recovery when ordinary profile writes save the
// database. These entries never participate in configuration or exports.
indirect enum MoaStoredJSONValue: Codable {
    case object([String: MoaStoredJSONValue])
    case array([MoaStoredJSONValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [MoaStoredJSONValue] = []
            while !array.isAtEnd { values.append(try array.decode(MoaStoredJSONValue.self)) }
            self = .array(values)
            return
        }
        if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values: [String: MoaStoredJSONValue] = [:]
            for key in object.allKeys { values[key.stringValue] = try object.decode(MoaStoredJSONValue.self, forKey: key) }
            self = .object(values)
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else { self = .string(try value.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values { try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!) }
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case .string(let value): var container = encoder.singleValueContainer(); try container.encode(value)
        case .number(let value): var container = encoder.singleValueContainer(); try container.encode(value)
        case .bool(let value): var container = encoder.singleValueContainer(); try container.encode(value)
        case .null: var container = encoder.singleValueContainer(); try container.encodeNil()
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

struct CodexOfficialAccount: Codable, Equatable {
    var id: String
    var name: String
    var email: String?
    var authPath: String
    var createdAt: String
    var lastUsedAt: String?

    var displayTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = normalizedEmail else {
            return trimmedName
        }

        if trimmedName.isEmpty || trimmedName == email || Self.isDefaultDisplayName(trimmedName) {
            return email
        }

        if trimmedName.hasSuffix("(\(email))") {
            return trimmedName
        }

        return "\(trimmedName)(\(email))"
    }

    static func isDefaultDisplayName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "OpenAI Current Account"
            || trimmed == MoaL10n.text("OpenAI Current Account")
    }

    private var normalizedEmail: String? {
        guard let email else {
            return nil
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CodexOfficialAccountDatabase: Codable {
    var selectedAccountID: String?
    var accounts: [CodexOfficialAccount]
}

enum CodexOfficialAccountError: LocalizedError {
    case accountNotFound
    case noSelectedAccount
    case noCurrentLogin
    case invalidAccountName
    case duplicateCurrentLogin(String)
    case invalidAuthPath(String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return MoaL10n.text("Codex official account not found.")
        case .noSelectedAccount:
            return MoaL10n.text("Select a Codex official account first.")
        case .noCurrentLogin:
            return MoaL10n.text("No Codex official login was found. Log in with Codex Official first, then add the account.")
        case .invalidAccountName:
            return MoaL10n.text("Account name is required.")
        case .duplicateCurrentLogin(let name):
            return MoaL10n.format("The current Codex official login is already saved as \"%@\".", name)
        case .invalidAuthPath(let path):
            return MoaL10n.format("The saved Codex official account path is invalid: %@", path)
        }
    }
}

struct ProviderProfileExportDocument: Codable {
    var schemaVersion: Int
    var provider: String
    var exportedAt: String
    var profiles: [ProviderProfileExportEntry]

    init(schemaVersion: Int, provider: String, exportedAt: String, profiles: [ProviderProfileExportEntry]) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.exportedAt = exportedAt
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, provider, exportedAt, profiles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        provider = try container.decode(String.self, forKey: .provider)
        exportedAt = try container.decode(String.self, forKey: .exportedAt)
        var entries = try container.nestedUnkeyedContainer(forKey: .profiles)
        profiles = []
        while !entries.isAtEnd {
            let entry = try entries.superDecoder()
            if provider == ConfigProfileController.exportProviderID,
               try !MoaProviderProfileCompatibility.supportsDirectResponses(entry) {
                throw ProviderProfileExportError.unsupportedProtocol
            }
            profiles.append(try ProviderProfileExportEntry(from: entry))
        }
    }
}

struct ProviderProfileExportEntry: Codable {
    var name: String
    var baseURL: String
    var apiKey: String?
    var models: [String]?
    var oneMModels: [String]?
    var model: String?
    var testModel: String?
}

enum ProviderProfileExportError: LocalizedError {
    case providerMismatch(expected: String, actual: String)
    case emptyDocument
    case unsupportedProtocol
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .providerMismatch(let expected, let actual):
            return MoaL10n.format("This import file belongs to %@ and cannot be imported into %@.", actual, expected)
        case .unsupportedProtocol:
            return MoaL10n.text("Only direct Responses-compatible Codex profiles are supported. Add a Responses endpoint or select Codex Official Mode.")
        case .emptyDocument:
            return MoaL10n.text("The import file does not contain any available profiles.")
        case .invalidProfile(let name):
            return MoaL10n.format("\"%@\" has incomplete profile information. Check its name and API Base URL.", name)
        }
    }
}
