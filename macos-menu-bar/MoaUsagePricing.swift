import Foundation

enum MoaUsagePricing {
    struct CostEstimate {
        let costUSD: Double
        let normalizedModel: String
        let pricingModel: String
        let usesFallbackPricing: Bool
    }

    private static let codexPriorityInputTokenLimit = 272_000
    // 全新模型未内置价格时的回退参考模型：Codex 侧用 gpt-5.5，Claude 侧用 claude-opus-4-7，
    // 避免未知模型的成本被静默计为 0、导致总额偏低。
    private static let fallbackCodexPricingModel = "gpt-5.5"
    private static let fallbackClaudePricingModel = "claude-opus-4-7"
    private static let fallbackZCodePricingModel = "GLM-5.2"
    private static let redirectedDeepSeekIDs: Set<String> = ["deepseek-v4-flash", "deepseek-v4-flash-vision-exp"]
    private static let catalogStoreLock = NSLock()
    nonisolated(unsafe) private static var catalogStore = MoaUsagePricingCatalogStore.shared

    private struct CodexPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadInputCostPerToken: Double?
        let displayLabel: String?
        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
        let priorityInputCostPerToken: Double?
        let priorityOutputCostPerToken: Double?
        let priorityCacheReadInputCostPerToken: Double?
        var cacheWriteInputCostPerToken: Double? = nil
        var cacheWriteInputCostPerTokenAboveThreshold: Double? = nil
        var priorityCacheWriteInputCostPerToken: Double? = nil
        var priorityInputCostPerTokenAboveThreshold: Double? = nil
        var priorityOutputCostPerTokenAboveThreshold: Double? = nil
        var priorityCacheReadInputCostPerTokenAboveThreshold: Double? = nil
        var priorityCacheWriteInputCostPerTokenAboveThreshold: Double? = nil
        var thresholdInclusive = false
    }

    private struct ClaudePricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationInputCostPerToken: Double
        let cacheReadInputCostPerToken: Double
        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheCreationInputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
        var thresholdInclusive = false
    }

    private struct ZCodePricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationInputCostPerToken: Double
        let cacheReadInputCostPerToken: Double
        var thresholdTokens: Int? = nil
        var inputCostPerTokenAboveThreshold: Double? = nil
        var outputCostPerTokenAboveThreshold: Double? = nil
        var cacheReadInputCostPerTokenAboveThreshold: Double? = nil
        var cacheCreationInputCostPerTokenAboveThreshold: Double? = nil
        var thresholdInclusive = false
    }

    private static let codex: [String: CodexPricing] = [
        "gpt-5": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5-codex": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5-mini": CodexPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5-nano": CodexPricing(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadInputCostPerToken: 5e-9, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5-pro": CodexPricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadInputCostPerToken: nil, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.1": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.1-codex": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.1-codex-max": CodexPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.1-codex-mini": CodexPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.2": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.2-codex": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.2-pro": CodexPricing(inputCostPerToken: 2.1e-5, outputCostPerToken: 1.68e-4, cacheReadInputCostPerToken: nil, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.3-codex": CodexPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.3-codex-spark": CodexPricing(inputCostPerToken: 0, outputCostPerToken: 0, cacheReadInputCostPerToken: 0, displayLabel: "Research Preview", thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.4": CodexPricing(inputCostPerToken: 2.5e-6, outputCostPerToken: 1.5e-5, cacheReadInputCostPerToken: 2.5e-7, displayLabel: nil, thresholdTokens: 272_000, inputCostPerTokenAboveThreshold: 5e-6, outputCostPerTokenAboveThreshold: 2.25e-5, cacheReadInputCostPerTokenAboveThreshold: 5e-7, priorityInputCostPerToken: 5e-6, priorityOutputCostPerToken: 3e-5, priorityCacheReadInputCostPerToken: 5e-7),
        "gpt-5.4-mini": CodexPricing(inputCostPerToken: 7.5e-7, outputCostPerToken: 4.5e-6, cacheReadInputCostPerToken: 7.5e-8, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: 1.5e-6, priorityOutputCostPerToken: 9e-6, priorityCacheReadInputCostPerToken: 1.5e-7),
        "gpt-5.4-nano": CodexPricing(inputCostPerToken: 2e-7, outputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 2e-8, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.4-pro": CodexPricing(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadInputCostPerToken: nil, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        "gpt-5.5": CodexPricing(inputCostPerToken: 5e-6, outputCostPerToken: 3e-5, cacheReadInputCostPerToken: 5e-7, displayLabel: nil, thresholdTokens: 272_000, inputCostPerTokenAboveThreshold: 1e-5, outputCostPerTokenAboveThreshold: 4.5e-5, cacheReadInputCostPerTokenAboveThreshold: 1e-6, priorityInputCostPerToken: 1.25e-5, priorityOutputCostPerToken: 7.5e-5, priorityCacheReadInputCostPerToken: 1.25e-6),
        "gpt-5.5-pro": CodexPricing(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadInputCostPerToken: nil, displayLabel: nil, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil, priorityInputCostPerToken: nil, priorityOutputCostPerToken: nil, priorityCacheReadInputCostPerToken: nil),
        // Official standard/Fast pricing and 272K request threshold, checked
        // 2026-09-07: https://developers.openai.com/api/docs/pricing.md
        // Cache writes for GPT-5.6+ cost 1.25x uncached input; reads cost 0.1x.
        "gpt-6-astra": modernCodexPricing(inputPerMillion: 10, outputPerMillion: 50),
        "gpt-5.6": modernCodexPricing(inputPerMillion: 4, outputPerMillion: 20),
        "gpt-5.6-sol": modernCodexPricing(inputPerMillion: 4, outputPerMillion: 20),
        "gpt-5.6-terra": modernCodexPricing(inputPerMillion: 2, outputPerMillion: 12),
        "gpt-5.6-luna": modernCodexPricing(inputPerMillion: 0.2, outputPerMillion: 1.2)
    ]

    private static func modernCodexPricing(inputPerMillion: Double, outputPerMillion: Double) -> CodexPricing {
        let input = inputPerMillion / 1_000_000
        let output = outputPerMillion / 1_000_000
        return CodexPricing(
            inputCostPerToken: input, outputCostPerToken: output, cacheReadInputCostPerToken: input * 0.1,
            displayLabel: nil, thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: input * 2, outputCostPerTokenAboveThreshold: output * 1.5,
            cacheReadInputCostPerTokenAboveThreshold: input * 0.2,
            priorityInputCostPerToken: input * 2, priorityOutputCostPerToken: output * 2,
            priorityCacheReadInputCostPerToken: input * 0.2,
            cacheWriteInputCostPerToken: input * 1.25, cacheWriteInputCostPerTokenAboveThreshold: input * 2.5,
            priorityCacheWriteInputCostPerToken: input * 2.5,
            priorityInputCostPerTokenAboveThreshold: input * 4, priorityOutputCostPerTokenAboveThreshold: output * 3,
            priorityCacheReadInputCostPerTokenAboveThreshold: input * 0.4,
            priorityCacheWriteInputCostPerTokenAboveThreshold: input * 5
        )
    }

    private static let claude: [String: ClaudePricing] = [
        "claude-haiku-4-5-20251001": ClaudePricing(inputCostPerToken: 1e-6, outputCostPerToken: 5e-6, cacheCreationInputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 1e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-haiku-4-5": ClaudePricing(inputCostPerToken: 1e-6, outputCostPerToken: 5e-6, cacheCreationInputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 1e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-5-20251101": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-5": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-6-20260205": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-6": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-7": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-8": ClaudePricing(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationInputCostPerToken: 6.25e-6, cacheReadInputCostPerToken: 5e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-5": ClaudePricing(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationInputCostPerToken: 3.75e-6, cacheReadInputCostPerToken: 3e-7, thresholdTokens: 200_000, inputCostPerTokenAboveThreshold: 6e-6, outputCostPerTokenAboveThreshold: 2.25e-5, cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6, cacheReadInputCostPerTokenAboveThreshold: 6e-7),
        "claude-sonnet-4-6": ClaudePricing(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationInputCostPerToken: 3.75e-6, cacheReadInputCostPerToken: 3e-7, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-5-20250929": ClaudePricing(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationInputCostPerToken: 3.75e-6, cacheReadInputCostPerToken: 3e-7, thresholdTokens: 200_000, inputCostPerTokenAboveThreshold: 6e-6, outputCostPerTokenAboveThreshold: 2.25e-5, cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6, cacheReadInputCostPerTokenAboveThreshold: 6e-7),
        "claude-opus-4-20250514": ClaudePricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 7.5e-5, cacheCreationInputCostPerToken: 1.875e-5, cacheReadInputCostPerToken: 1.5e-6, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-opus-4-1": ClaudePricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 7.5e-5, cacheCreationInputCostPerToken: 1.875e-5, cacheReadInputCostPerToken: 1.5e-6, thresholdTokens: nil, inputCostPerTokenAboveThreshold: nil, outputCostPerTokenAboveThreshold: nil, cacheCreationInputCostPerTokenAboveThreshold: nil, cacheReadInputCostPerTokenAboveThreshold: nil),
        "claude-sonnet-4-20250514": ClaudePricing(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationInputCostPerToken: 3.75e-6, cacheReadInputCostPerToken: 3e-7, thresholdTokens: 200_000, inputCostPerTokenAboveThreshold: 6e-6, outputCostPerTokenAboveThreshold: 2.25e-5, cacheCreationInputCostPerTokenAboveThreshold: 7.5e-6, cacheReadInputCostPerTokenAboveThreshold: 6e-7)
    ]

    private static let zcode: [String: ZCodePricing] = [
        "glm-5.2": ZCodePricing(inputCostPerToken: 1.4e-6, outputCostPerToken: 4.4e-6, cacheCreationInputCostPerToken: 0, cacheReadInputCostPerToken: 0.26e-6),
        "glm-5.1": ZCodePricing(inputCostPerToken: 1.4e-6, outputCostPerToken: 4.4e-6, cacheCreationInputCostPerToken: 0, cacheReadInputCostPerToken: 0.26e-6),
        "glm-5-turbo": ZCodePricing(inputCostPerToken: 1.2e-6, outputCostPerToken: 4.0e-6, cacheCreationInputCostPerToken: 0, cacheReadInputCostPerToken: 0.24e-6)
    ]

#if MOA_TESTING || MOA_TEST_SUPPORT
    static func useRemoteCatalogStoreForTesting(_ store: MoaUsagePricingCatalogStore) {
        catalogStoreLock.lock()
        catalogStore = store
        catalogStoreLock.unlock()
    }

    static func resetRemoteCatalogStoreForTesting() {
        useRemoteCatalogStoreForTesting(.shared)
    }
#endif

    static func catalogPricing(source: MoaUsageSource, model: String, store suppliedStore: MoaUsagePricingCatalogStore? = nil) -> MoaUsageRemotePricing? {
        // Share public USD reference prices, never edition-specific user overrides or usage.
        let source: MoaUsageSource = source == .workbuddyCN ? .workbuddy : source
        let key = MoaUsagePricingSeed.canonicalModel(model)
        catalogStoreLock.lock()
        let store = suppliedStore ?? catalogStore
        catalogStoreLock.unlock()
        let seed = MoaUsagePricingSeed.price(source: source, model: key)
        let raw = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let notBefore = seed == nil ? nil : MoaUsagePricingSeed.checkedAt
        // These retired IDs redirect to DeepSeek Flash rather than identifying
        // separate SKUs, so an obsolete exact entry must never override Flash.
        let unqualifiedRaw = raw.hasPrefix("deepseek/") ? String(raw.dropFirst("deepseek/".count)) : raw
        let remote = redirectedDeepSeekIDs.contains(unqualifiedRaw)
            ? store.pricing(source: source, model: key, notBefore: notBefore)
            : (store.pricing(source: source, model: raw, notBefore: notBefore)
                ?? store.pricing(source: source, model: key, notBefore: notBefore))
        if let remote {
            if MoaUsagePricingSeed.unpricedModels.contains(key), remote.inputUSDPerMillion == 0, remote.outputUSDPerMillion == 0 { return nil }
            return remote
        }
        if key == "grok-4.7-build-fast", var base = catalogPricing(source: source, model: "grok-4.7", store: store)
            ?? MoaUsagePricingSeed.price(source: .workbuddy, model: "grok-4.7") {
            // Official Grok Build Fast multipliers: 2x standard context and
            // 1.5x the long-context rates. An exact remote Fast entry wins above.
            base.inputUSDPerMillion *= 2
            base.outputUSDPerMillion *= 2
            base.cacheReadUSDPerMillion = base.cacheReadUSDPerMillion.map { $0 * 2 }
            base.cacheCreationUSDPerMillion = base.cacheCreationUSDPerMillion.map { $0 * 2 }
            base.inputUSDPerMillionAboveThreshold = base.inputUSDPerMillionAboveThreshold.map { $0 * 1.5 }
            base.outputUSDPerMillionAboveThreshold = base.outputUSDPerMillionAboveThreshold.map { $0 * 1.5 }
            base.cacheReadUSDPerMillionAboveThreshold = base.cacheReadUSDPerMillionAboveThreshold.map { $0 * 1.5 }
            base.cacheCreationUSDPerMillionAboveThreshold = base.cacheCreationUSDPerMillionAboveThreshold.map { $0 * 1.5 }
            return base
        }
        return seed
    }

    private static func remotePricing(source: MoaUsageSource, model: String) -> MoaUsageRemotePricing? {
        catalogPricing(source: source, model: model)
    }

    private static func codexPricing(model: String) -> CodexPricing? {
        let builtIn = codex[model]
        guard let remote = remotePricing(source: .codex, model: model) else { return builtIn }
        return CodexPricing(
            inputCostPerToken: perToken(remote.inputUSDPerMillion),
            outputCostPerToken: perToken(remote.outputUSDPerMillion),
            cacheReadInputCostPerToken: remote.cacheReadUSDPerMillion.map(perToken),
            displayLabel: builtIn?.displayLabel,
            thresholdTokens: remote.thresholdTokens,
            inputCostPerTokenAboveThreshold: remote.inputUSDPerMillionAboveThreshold.map(perToken),
            outputCostPerTokenAboveThreshold: remote.outputUSDPerMillionAboveThreshold.map(perToken),
            cacheReadInputCostPerTokenAboveThreshold: remote.cacheReadUSDPerMillionAboveThreshold.map(perToken),
            priorityInputCostPerToken: remote.priorityInputUSDPerMillion.map(perToken),
            priorityOutputCostPerToken: remote.priorityOutputUSDPerMillion.map(perToken),
            priorityCacheReadInputCostPerToken: remote.priorityCacheReadUSDPerMillion.map(perToken),
            cacheWriteInputCostPerToken: remote.cacheCreationUSDPerMillion.map(perToken),
            cacheWriteInputCostPerTokenAboveThreshold: remote.cacheCreationUSDPerMillionAboveThreshold.map(perToken),
            priorityCacheWriteInputCostPerToken: remote.priorityCacheCreationUSDPerMillion.map(perToken),
            priorityInputCostPerTokenAboveThreshold: remote.priorityInputUSDPerMillionAboveThreshold.map(perToken),
            priorityOutputCostPerTokenAboveThreshold: remote.priorityOutputUSDPerMillionAboveThreshold.map(perToken),
            priorityCacheReadInputCostPerTokenAboveThreshold: remote.priorityCacheReadUSDPerMillionAboveThreshold.map(perToken),
            priorityCacheWriteInputCostPerTokenAboveThreshold: remote.priorityCacheCreationUSDPerMillionAboveThreshold.map(perToken),
            thresholdInclusive: remote.thresholdInclusive ?? false
        )
    }

    private static func claudePricing(model: String) -> ClaudePricing? {
        let builtIn = claude[model]
        guard let remote = remotePricing(source: .claude, model: model) else { return builtIn }
        return ClaudePricing(
            inputCostPerToken: perToken(remote.inputUSDPerMillion),
            outputCostPerToken: perToken(remote.outputUSDPerMillion),
            cacheCreationInputCostPerToken: remote.cacheCreationUSDPerMillion.map(perToken) ?? perToken(remote.inputUSDPerMillion),
            cacheReadInputCostPerToken: remote.cacheReadUSDPerMillion.map(perToken) ?? perToken(remote.inputUSDPerMillion),
            thresholdTokens: remote.thresholdTokens,
            inputCostPerTokenAboveThreshold: remote.inputUSDPerMillionAboveThreshold.map(perToken),
            outputCostPerTokenAboveThreshold: remote.outputUSDPerMillionAboveThreshold.map(perToken),
            cacheCreationInputCostPerTokenAboveThreshold: remote.cacheCreationUSDPerMillionAboveThreshold.map(perToken),
            cacheReadInputCostPerTokenAboveThreshold: remote.cacheReadUSDPerMillionAboveThreshold.map(perToken),
            thresholdInclusive: remote.thresholdInclusive ?? false
        )
    }

    private static func zcodePricing(model: String) -> ZCodePricing? {
        let key = model.lowercased()
        let builtIn = zcode[key]
        guard let remote = remotePricing(source: .zcode, model: key) else { return builtIn }
        return ZCodePricing(
            inputCostPerToken: perToken(remote.inputUSDPerMillion),
            outputCostPerToken: perToken(remote.outputUSDPerMillion),
            cacheCreationInputCostPerToken: remote.cacheCreationUSDPerMillion.map(perToken) ?? perToken(remote.inputUSDPerMillion),
            cacheReadInputCostPerToken: remote.cacheReadUSDPerMillion.map(perToken) ?? perToken(remote.inputUSDPerMillion),
            thresholdTokens: remote.thresholdTokens,
            inputCostPerTokenAboveThreshold: remote.inputUSDPerMillionAboveThreshold.map(perToken),
            outputCostPerTokenAboveThreshold: remote.outputUSDPerMillionAboveThreshold.map(perToken),
            cacheReadInputCostPerTokenAboveThreshold: remote.cacheReadUSDPerMillionAboveThreshold.map(perToken),
            cacheCreationInputCostPerTokenAboveThreshold: remote.cacheCreationUSDPerMillionAboveThreshold.map(perToken),
            thresholdInclusive: remote.thresholdInclusive ?? false
        )
    }

    private static func perToken(_ perMillion: Double) -> Double {
        perMillion / 1_000_000
    }

    static func normalizeModel(_ raw: String) -> String {
        normalizeCodexModel(raw)
    }

    static func normalizeCodexModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }

        if codexPricing(model: trimmed) != nil {
            return trimmed
        }

        if let range = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<range.lowerBound])
            if codexPricing(model: base) != nil {
                return base
            }
        }
        return trimmed
    }

    static func normalizeClaudeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("anthropic.") {
            trimmed = String(trimmed.dropFirst("anthropic.".count))
        }

        for suffix in ["[1m]", "(1m)", "+1m"] where trimmed.lowercased().hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        if let lastDot = trimmed.lastIndex(of: "."),
           trimmed.contains("claude-")
        {
            let tail = String(trimmed[trimmed.index(after: lastDot)...])
            if tail.hasPrefix("claude-") {
                trimmed = tail
            }
        }

        if let range = trimmed.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            trimmed.removeSubrange(range)
        }

        if let range = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
            let base = String(trimmed[..<range.lowerBound])
            if claudePricing(model: base) != nil {
                return base
            }
        }

        return trimmed
    }

    static func normalizeZCodeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = trimmed.lastIndex(of: "/") {
            trimmed = String(trimmed[trimmed.index(after: slash)...])
        }

        switch trimmed.lowercased() {
        case "glm-5.2":
            return "GLM-5.2"
        case "glm-5.1":
            return "GLM-5.1"
        case "glm-5-turbo", "glm-5turbo":
            return "GLM-5-Turbo"
        default:
            return trimmed
        }
    }

    static func codexDisplayLabel(model: String) -> String? {
        codexPricing(model: normalizeCodexModel(model))?.displayLabel
    }

    static func costUSD(model: String, inputTokens: Int, cachedInputTokens: Int, outputTokens: Int) -> Double? {
        codexCostUSD(
            model: model,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    static func codexCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int) -> Double?
    {
        codexCostEstimate(
            model: model,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            outputTokens: outputTokens
        )?.costUSD
    }

    static func codexCostEstimate(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int) -> CostEstimate?
    {
        let normalized = normalizeCodexModel(model)
        if MoaUsagePricingSeed.unpricedModels.contains(normalized), remotePricing(source: .codex, model: normalized) == nil {
            return CostEstimate(costUSD: 0, normalizedModel: normalized, pricingModel: "unpriced", usesFallbackPricing: true)
        }
        let usesFallback = codexPricing(model: normalized) == nil
        let pricingModel = usesFallback ? fallbackCodexPricingModel : normalized
        guard let pricing = codexPricing(model: pricingModel) else { return nil }
        let cost = codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            outputTokens: outputTokens)
        return CostEstimate(
            costUSD: cost,
            normalizedModel: normalized,
            pricingModel: pricingModel,
            usesFallbackPricing: usesFallback
        )
    }

    static func codexCacheReadUSDPerMillion(model: String, inputTokens: Int = 1) -> Double? {
        let normalized = normalizeCodexModel(model)
        let pricingModel = codexPricing(model: normalized) == nil ? fallbackCodexPricingModel : normalized
        guard let pricing = codexPricing(model: pricingModel) else { return nil }
        let baseRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
        let usesLongContextRates = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, inputTokens) >= $0 : max(0, inputTokens) > $0 } ?? false
        let rate = usesLongContextRates ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? baseRate : baseRate
        return rate * 1_000_000
    }

    static func codexCacheWriteUSDPerMillion(model: String, inputTokens: Int = 1) -> Double? {
        let normalized = normalizeCodexModel(model)
        let pricingModel = codexPricing(model: normalized) == nil ? fallbackCodexPricingModel : normalized
        guard let pricing = codexPricing(model: pricingModel) else { return nil }
        let longContext = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, inputTokens) >= $0 : max(0, inputTokens) > $0 } ?? false
        let rate = longContext
            ? pricing.cacheWriteInputCostPerTokenAboveThreshold ?? pricing.inputCostPerTokenAboveThreshold ?? pricing.cacheWriteInputCostPerToken ?? pricing.inputCostPerToken
            : pricing.cacheWriteInputCostPerToken ?? pricing.inputCostPerToken
        return rate * 1_000_000
    }

    static func codexPriorityCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int) -> Double?
    {
        let normalized = normalizeCodexModel(model)
        guard let pricing = codexPricing(model: normalized),
              let priorityInput = pricing.priorityInputCostPerToken,
              let priorityOutput = pricing.priorityOutputCostPerToken,
              (max(0, inputTokens) <= codexPriorityInputTokenLimit || pricing.priorityInputCostPerTokenAboveThreshold != nil)
        else {
            return nil
        }

        let priorityPricing = CodexPricing(
            inputCostPerToken: priorityInput,
            outputCostPerToken: priorityOutput,
            cacheReadInputCostPerToken: pricing.priorityCacheReadInputCostPerToken,
            displayLabel: nil,
            thresholdTokens: pricing.thresholdTokens,
            inputCostPerTokenAboveThreshold: pricing.priorityInputCostPerTokenAboveThreshold,
            outputCostPerTokenAboveThreshold: pricing.priorityOutputCostPerTokenAboveThreshold,
            cacheReadInputCostPerTokenAboveThreshold: pricing.priorityCacheReadInputCostPerTokenAboveThreshold,
            priorityInputCostPerToken: nil,
            priorityOutputCostPerToken: nil,
            priorityCacheReadInputCostPerToken: nil,
            cacheWriteInputCostPerToken: pricing.priorityCacheWriteInputCostPerToken,
            cacheWriteInputCostPerTokenAboveThreshold: pricing.priorityCacheWriteInputCostPerTokenAboveThreshold)
        return codexCostUSD(
            pricing: priorityPricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheWriteInputTokens: cacheWriteInputTokens,
            outputTokens: outputTokens)
    }

    static func claudeCostUSD(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> Double?
    {
        claudeCostEstimate(
            model: model,
            inputTokens: inputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            outputTokens: outputTokens
        )?.costUSD
    }

    static func claudeCostEstimate(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> CostEstimate?
    {
        let normalized = normalizeClaudeModel(model)
        let usesFallback = claudePricing(model: normalized) == nil
        let pricingModel = usesFallback ? fallbackClaudePricingModel : normalized
        guard let pricing = claudePricing(model: pricingModel) else { return nil }
        let cost = claudeCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            outputTokens: outputTokens)
        return CostEstimate(
            costUSD: cost,
            normalizedModel: normalized,
            pricingModel: pricingModel,
            usesFallbackPricing: usesFallback
        )
    }

    static func claudeCacheReadUSDPerMillion(model: String, promptTokens: Int = 1) -> Double? {
        let normalized = normalizeClaudeModel(model)
        let pricingModel = claudePricing(model: normalized) == nil ? fallbackClaudePricingModel : normalized
        guard let pricing = claudePricing(model: pricingModel) else { return nil }
        let usesLongContextRates = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, promptTokens) >= $0 : max(0, promptTokens) > $0 } ?? false
        let rate = usesLongContextRates ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken : pricing.cacheReadInputCostPerToken
        return rate * 1_000_000
    }

    static func claudeCacheCreationUSDPerMillion(model: String, promptTokens: Int = 1) -> Double? {
        let normalized = normalizeClaudeModel(model)
        let pricingModel = claudePricing(model: normalized) == nil ? fallbackClaudePricingModel : normalized
        guard let pricing = claudePricing(model: pricingModel) else { return nil }
        let usesLongContextRates = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, promptTokens) >= $0 : max(0, promptTokens) > $0 } ?? false
        let rate = usesLongContextRates ? pricing.cacheCreationInputCostPerTokenAboveThreshold ?? pricing.cacheCreationInputCostPerToken : pricing.cacheCreationInputCostPerToken
        return rate * 1_000_000
    }

    static func zcodeCostEstimate(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> CostEstimate?
    {
        let normalized = normalizeZCodeModel(model)
        let usesFallback = zcodePricing(model: normalized) == nil
        let pricingModel = usesFallback ? fallbackZCodePricingModel : normalized
        guard let pricing = zcodePricing(model: pricingModel) else { return nil }
        let cost = zcodeCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            outputTokens: outputTokens)
        return CostEstimate(
            costUSD: cost,
            normalizedModel: normalized,
            pricingModel: pricingModel,
            usesFallbackPricing: usesFallback
        )
    }

    static func zcodeCacheReadUSDPerMillion(model: String, promptTokens: Int = 1) -> Double? {
        let normalized = normalizeZCodeModel(model)
        let pricingModel = zcodePricing(model: normalized) == nil ? fallbackZCodePricingModel : normalized
        guard let pricing = zcodePricing(model: pricingModel) else { return nil }
        let above = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, promptTokens) >= $0 : max(0, promptTokens) > $0 } ?? false
        return (above ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken : pricing.cacheReadInputCostPerToken) * 1_000_000
    }

    static func zcodeCacheCreationUSDPerMillion(model: String, promptTokens: Int = 1) -> Double? {
        let normalized = normalizeZCodeModel(model)
        let pricingModel = zcodePricing(model: normalized) == nil ? fallbackZCodePricingModel : normalized
        guard let pricing = zcodePricing(model: pricingModel) else { return nil }
        let above = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, promptTokens) >= $0 : max(0, promptTokens) > $0 } ?? false
        return (above ? pricing.cacheCreationInputCostPerTokenAboveThreshold ?? pricing.cacheCreationInputCostPerToken : pricing.cacheCreationInputCostPerToken) * 1_000_000
    }

    private static func codexCostUSD(
        pricing: CodexPricing,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int) -> Double
    {
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let cacheWrite = min(max(0, cacheWriteInputTokens), max(0, inputTokens - cached))
        let nonCached = max(0, inputTokens - cached - cacheWrite)
        let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
        let usesLongContextRates = pricing.thresholdTokens.map { pricing.thresholdInclusive ? max(0, inputTokens) >= $0 : max(0, inputTokens) > $0 } ?? false
        let inputRate = usesLongContextRates ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken : pricing.inputCostPerToken
        let cachedInputRate = usesLongContextRates ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? cachedRate : cachedRate
        let outputRate = usesLongContextRates ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken : pricing.outputCostPerToken

        let cacheWriteRate = usesLongContextRates
            ? pricing.cacheWriteInputCostPerTokenAboveThreshold ?? inputRate
            : pricing.cacheWriteInputCostPerToken ?? inputRate

        return Double(nonCached) * inputRate
            + Double(cached) * cachedInputRate
            + Double(cacheWrite) * cacheWriteRate
            + Double(max(0, outputTokens)) * outputRate
    }

    private static func claudeCostUSD(
        pricing: ClaudePricing,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> Double
    {
        let input = max(0, inputTokens)
        let cacheRead = max(0, cacheReadInputTokens)
        let cacheCreation = max(0, cacheCreationInputTokens)
        let output = max(0, outputTokens)
        let promptTokens = input + cacheRead + cacheCreation
        let usesLongContextRates = pricing.thresholdTokens.map { pricing.thresholdInclusive ? promptTokens >= $0 : promptTokens > $0 } ?? false
        let inputRate = usesLongContextRates ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken : pricing.inputCostPerToken
        let cacheReadRate = usesLongContextRates ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken : pricing.cacheReadInputCostPerToken
        let cacheCreationRate = usesLongContextRates ? pricing.cacheCreationInputCostPerTokenAboveThreshold ?? pricing.cacheCreationInputCostPerToken : pricing.cacheCreationInputCostPerToken
        let outputRate = usesLongContextRates ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken : pricing.outputCostPerToken

        return Double(input) * inputRate
            + Double(cacheRead) * cacheReadRate
            + Double(cacheCreation) * cacheCreationRate
            + Double(output) * outputRate
    }

    private static func zcodeCostUSD(
        pricing: ZCodePricing,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        outputTokens: Int) -> Double
    {
        let prompt = max(0, inputTokens) + max(0, cacheReadInputTokens) + max(0, cacheCreationInputTokens)
        let above = pricing.thresholdTokens.map { pricing.thresholdInclusive ? prompt >= $0 : prompt > $0 } ?? false
        return Double(max(0, inputTokens)) * (above ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken : pricing.inputCostPerToken)
            + Double(max(0, cacheReadInputTokens)) * (above ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken : pricing.cacheReadInputCostPerToken)
            + Double(max(0, cacheCreationInputTokens)) * (above ? pricing.cacheCreationInputCostPerTokenAboveThreshold ?? pricing.cacheCreationInputCostPerToken : pricing.cacheCreationInputCostPerToken)
            + Double(max(0, outputTokens)) * (above ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken : pricing.outputCostPerToken)
    }
}
