import Foundation

enum MoaCustomPriceError: Error, Equatable {
    case invalidField(Field)
    case noPositivePrice

    enum Field: Equatable {
        case input, output, cacheRead, cacheCreation
    }
}

struct MoaCustomPrices: Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheCreation: Double?

    static func parse(input: String, output: String, cacheRead: String, cacheCreation: String) throws -> Self {
        func value(_ text: String, field: MoaCustomPriceError.Field) throws -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let number = Double(trimmed), number.isFinite, number >= 0 else {
                throw MoaCustomPriceError.invalidField(field)
            }
            return number
        }

        let inputValue = try value(input, field: .input) ?? 0
        let outputValue = try value(output, field: .output) ?? 0
        let cacheReadValue = try value(cacheRead, field: .cacheRead)
        let cacheCreationValue = try value(cacheCreation, field: .cacheCreation)
        guard inputValue > 0 || outputValue > 0 else { throw MoaCustomPriceError.noPositivePrice }
        return Self(input: inputValue, output: outputValue, cacheRead: cacheReadValue, cacheCreation: cacheCreationValue)
    }
}

struct MoaUsagePricingOverride: Identifiable, Codable, Equatable {
    var source: MoaUsageSource
    var model: String
    var inputUSDPerMillion: Double
    var outputUSDPerMillion: Double
    var cacheReadUSDPerMillion: Double?
    var cacheCreationUSDPerMillion: Double?
    var updatedAt: Date

    var id: String {
        "\(source.rawValue)|\(model)"
    }
}

final class MoaUsagePricingOverrideController {
    private struct Payload: Codable {
        var overrides: [MoaUsagePricingOverride]
    }

    private let fileManager = FileManager.default
    private let environment: [String: String]
    private let dataAccess: MoaDataStoreLock
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lock = NSRecursiveLock()
    private var cachedOverrides: [MoaUsagePricingOverride]?
    private var cachedModified: Date?
    private var cachedURL: URL?
    private var cachedRevision: UInt64?
    private var dataRootObserver: NSObjectProtocol?

    private var url: URL {
        MoaDataRoot.currentURL(environment: environment)
            .appendingPathComponent("usage-pricing-overrides.json")
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        dataAccess = MoaDataStoreLock(environment: environment)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        decoder.dateDecodingStrategy = .iso8601
        dataRootObserver = NotificationCenter.default.addObserver(
            forName: MoaDataRoot.didChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                self.cachedOverrides = nil
                self.cachedModified = nil
                self.cachedURL = nil
            }
        }
    }

    deinit {
        if let dataRootObserver { NotificationCenter.default.removeObserver(dataRootObserver) }
    }

    func overrides() -> [MoaUsagePricingOverride] {
        lock.lock()
        defer { lock.unlock() }

        let url = self.url.standardizedFileURL
        if dataAccess.isBusy { return cachedOverrides ?? [] }
        do {
            return try loadOverrides(at: url, allowCache: true)
        } catch {
            guard cachedURL == url, cachedRevision == dataAccess.revision else { return [] }
            return cachedOverrides ?? []
        }
    }

    private func loadOverrides(at url: URL, allowCache: Bool) throws -> [MoaUsagePricingOverride] {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain &&
                (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError) {
                cachedOverrides = []
                cachedModified = nil
                cachedURL = url
                cachedRevision = dataAccess.revision
                return []
            }
            throw error
        }
        let modified = attributes[.modificationDate] as? Date
        if allowCache, let cachedOverrides, cachedURL == url, cachedModified == modified, cachedRevision == dataAccess.revision {
            return cachedOverrides
        }

        let data = try Data(contentsOf: url)
        let loaded: [MoaUsagePricingOverride]
        if let payload = try? decoder.decode(Payload.self, from: data) {
            loaded = payload.overrides
        } else {
            loaded = try decoder.decode([MoaUsagePricingOverride].self, from: data)
        }
        cachedOverrides = loaded
        cachedModified = modified
        cachedURL = url
        cachedRevision = dataAccess.revision
        return loaded
    }

    func override(source: MoaUsageSource, model: String) -> MoaUsagePricingOverride? {
        let normalized = normalizedModel(source: source, model: model)
        return overrides().first { $0.source == source && $0.model == normalized }
    }

    func upsert(
        source: MoaUsageSource,
        model: String,
        inputUSDPerMillion: Double,
        outputUSDPerMillion: Double,
        cacheReadUSDPerMillion: Double?,
        cacheCreationUSDPerMillion: Double?
    ) throws {
        guard inputUSDPerMillion.isFinite, inputUSDPerMillion >= 0,
              outputUSDPerMillion.isFinite, outputUSDPerMillion >= 0,
              cacheReadUSDPerMillion.map({ $0.isFinite && $0 >= 0 }) ?? true,
              cacheCreationUSDPerMillion.map({ $0.isFinite && $0 >= 0 }) ?? true,
              inputUSDPerMillion > 0 || outputUSDPerMillion > 0 else {
            throw NSError(domain: "MoaUsagePricing", code: 1, userInfo: [
                NSLocalizedDescriptionKey: MoaL10n.text("Enter nonnegative finite prices, with a positive input or output price.")
            ])
        }
        try dataAccess.lock()
        defer { dataAccess.unlock() }
        lock.lock()
        defer { lock.unlock() }
        let normalized = normalizedModel(source: source, model: model)
        var overrides = try loadOverrides(at: url.standardizedFileURL, allowCache: false)
            .filter { !($0.source == source && $0.model == normalized) }
        overrides.append(MoaUsagePricingOverride(
            source: source,
            model: normalized,
            inputUSDPerMillion: inputUSDPerMillion,
            outputUSDPerMillion: outputUSDPerMillion,
            cacheReadUSDPerMillion: cacheReadUSDPerMillion,
            cacheCreationUSDPerMillion: cacheCreationUSDPerMillion,
            updatedAt: Date()
        ))
        try save(overrides)
    }

    func remove(source: MoaUsageSource, model: String) throws {
        try dataAccess.lock()
        defer { dataAccess.unlock() }
        lock.lock()
        defer { lock.unlock() }
        let normalized = normalizedModel(source: source, model: model)
        let overrides = try loadOverrides(at: url.standardizedFileURL, allowCache: false)
        try save(overrides.filter { !($0.source == source && $0.model == normalized) })
    }

    func codexCostEstimate(model: String, inputTokens: Int, cachedInputTokens: Int, cacheWriteInputTokens: Int = 0, outputTokens: Int) -> MoaUsagePricing.CostEstimate? {
        guard let override = override(source: .codex, model: model) else { return nil }
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let cacheWrite = min(max(0, cacheWriteInputTokens), max(0, inputTokens - cached))
        let nonCached = max(0, inputTokens - cached - cacheWrite)
        let cachedRate = override.cacheReadUSDPerMillion
            ?? MoaUsagePricing.codexCacheReadUSDPerMillion(model: override.model, inputTokens: inputTokens)
            ?? override.inputUSDPerMillion
        let writeRate = override.cacheCreationUSDPerMillion
            ?? MoaUsagePricing.codexCacheWriteUSDPerMillion(model: override.model, inputTokens: inputTokens)
            ?? override.inputUSDPerMillion
        let cost = Self.cost(tokens: nonCached, perMillion: override.inputUSDPerMillion)
            + Self.cost(tokens: cached, perMillion: cachedRate)
            + Self.cost(tokens: cacheWrite, perMillion: writeRate)
            + Self.cost(tokens: outputTokens, perMillion: override.outputUSDPerMillion)
        return MoaUsagePricing.CostEstimate(
            costUSD: cost,
            normalizedModel: override.model,
            pricingModel: MoaL10n.text("Custom"),
            usesFallbackPricing: false
        )
    }

    func claudeCostEstimate(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int
    ) -> MoaUsagePricing.CostEstimate? {
        guard let override = override(source: .claude, model: model) else { return nil }
        let promptTokens = max(0, inputTokens) + max(0, cacheReadInputTokens) + max(0, cacheCreationInputTokens)
        let readRate = override.cacheReadUSDPerMillion
            ?? MoaUsagePricing.claudeCacheReadUSDPerMillion(model: override.model, promptTokens: promptTokens)
            ?? override.inputUSDPerMillion
        let creationRate = override.cacheCreationUSDPerMillion
            ?? MoaUsagePricing.claudeCacheCreationUSDPerMillion(model: override.model, promptTokens: promptTokens)
            ?? override.inputUSDPerMillion
        let cost = Self.cost(tokens: inputTokens, perMillion: override.inputUSDPerMillion)
            + Self.cost(tokens: cacheReadInputTokens, perMillion: readRate)
            + Self.cost(tokens: cacheCreationInputTokens, perMillion: creationRate)
            + Self.cost(tokens: outputTokens, perMillion: override.outputUSDPerMillion)
        return MoaUsagePricing.CostEstimate(
            costUSD: cost,
            normalizedModel: override.model,
            pricingModel: MoaL10n.text("Custom"),
            usesFallbackPricing: false
        )
    }

    func zcodeCostEstimate(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int
    ) -> MoaUsagePricing.CostEstimate? {
        guard let override = override(source: .zcode, model: model) else { return nil }
        let promptTokens = max(0, inputTokens) + max(0, cacheReadInputTokens) + max(0, cacheCreationInputTokens)
        let readRate = override.cacheReadUSDPerMillion
            ?? MoaUsagePricing.zcodeCacheReadUSDPerMillion(model: override.model, promptTokens: promptTokens)
            ?? override.inputUSDPerMillion
        let creationRate = override.cacheCreationUSDPerMillion
            ?? MoaUsagePricing.zcodeCacheCreationUSDPerMillion(model: override.model, promptTokens: promptTokens)
            ?? override.inputUSDPerMillion
        let cost = Self.cost(tokens: inputTokens, perMillion: override.inputUSDPerMillion)
            + Self.cost(tokens: cacheReadInputTokens, perMillion: readRate)
            + Self.cost(tokens: cacheCreationInputTokens, perMillion: creationRate)
            + Self.cost(tokens: outputTokens, perMillion: override.outputUSDPerMillion)
        return MoaUsagePricing.CostEstimate(
            costUSD: cost,
            normalizedModel: override.model,
            pricingModel: MoaL10n.text("Custom"),
            usesFallbackPricing: false
        )
    }

    private func save(_ overrides: [MoaUsagePricingOverride]) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = self.url.standardizedFileURL
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = Payload(overrides: overrides.sorted { $0.id < $1.id })
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        cachedOverrides = payload.overrides
        cachedModified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        cachedURL = url
        cachedRevision = dataAccess.revision
    }

    private func normalizedModel(source: MoaUsageSource, model: String) -> String {
        switch source {
        case .codex:
            return MoaUsagePricing.normalizeCodexModel(model)
        case .claude:
            return MoaUsagePricing.normalizeClaudeModel(model)
        case .zcode:
            return MoaUsagePricing.normalizeZCodeModel(model)
        case .workbuddy, .workbuddyCN:
            return model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func cost(tokens: Int, perMillion: Double) -> Double {
        Double(max(0, tokens)) * max(0, perMillion) / 1_000_000
    }
}
