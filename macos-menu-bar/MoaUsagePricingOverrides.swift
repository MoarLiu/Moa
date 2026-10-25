import Foundation

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
        let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cachedOverrides, cachedURL == url, cachedModified == modified, cachedRevision == dataAccess.revision {
            return cachedOverrides
        }

        let loaded: [MoaUsagePricingOverride]
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            loaded = []
            cachedOverrides = loaded
            cachedModified = modified
            cachedURL = url
            cachedRevision = dataAccess.revision
            return loaded
        }
        if let payload = try? decoder.decode(Payload.self, from: data) {
            loaded = payload.overrides
        } else {
            loaded = (try? decoder.decode([MoaUsagePricingOverride].self, from: data)) ?? []
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
        try dataAccess.lock()
        defer { dataAccess.unlock() }
        lock.lock()
        defer { lock.unlock() }
        let normalized = normalizedModel(source: source, model: model)
        var overrides = overrides().filter { !($0.source == source && $0.model == normalized) }
        overrides.append(MoaUsagePricingOverride(
            source: source,
            model: normalized,
            inputUSDPerMillion: max(0, inputUSDPerMillion),
            outputUSDPerMillion: max(0, outputUSDPerMillion),
            cacheReadUSDPerMillion: cacheReadUSDPerMillion.map { max(0, $0) },
            cacheCreationUSDPerMillion: cacheCreationUSDPerMillion.map { max(0, $0) },
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
        try save(overrides().filter { !($0.source == source && $0.model == normalized) })
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
