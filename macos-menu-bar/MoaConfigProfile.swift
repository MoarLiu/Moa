import Foundation

struct ConfigProfile: Codable, Equatable {
    let id: String
    var name: String
    var baseURL: String
    var apiKey: String
    var schemaVersion: Int? = nil
    var model: String? = nil
    var testModel: String? = nil
    var models: [String]? = nil

    init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String,
        schemaVersion: Int? = nil,
        model: String? = nil,
        testModel: String? = nil,
        models: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.schemaVersion = schemaVersion
        self.model = model
        self.testModel = testModel
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, schemaVersion, model, testModel, models
    }

    init(from decoder: Decoder) throws {
        guard try MoaProviderProfileCompatibility.supportsDirectResponses(decoder) else {
            throw ProviderProfileExportError.unsupportedProtocol
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        testModel = try container.decodeIfPresent(String.self, forKey: .testModel)
        models = try container.decodeIfPresent([String].self, forKey: .models)
    }

    var resolvedModel: String? {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var resolvedTestModel: String? {
        let trimmed = testModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? resolvedModel : trimmed
    }
}

// Read only the old routing discriminator so retired configurations are never
// reinterpreted as direct Responses providers. No legacy secrets are retained.
enum MoaProviderProfileCompatibility {
    private enum LegacyKeys: String, CodingKey {
        case bridgeMode, upstreamProtocol
    }

    static func supportsDirectResponses(_ decoder: Decoder) throws -> Bool {
        let container = try decoder.container(keyedBy: LegacyKeys.self)
        let mode = try container.decodeIfPresent(String.self, forKey: .bridgeMode)
        let api = try container.decodeIfPresent(String.self, forKey: .upstreamProtocol)
        return (mode == nil || mode == "direct") && (api == nil || api == "responses")
    }
}
