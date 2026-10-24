import Foundation

/// Sub2API's public LiteLLM-compatible catalog uses USD/token. Moa stores USD/MTok.
enum MoaSub2APIPricingParser {
    static func parse(_ object: [String: Any], sourceURL: URL, fetchedAt: Date) throws -> MoaUsagePricingCatalogSnapshot {
        var models: [String: [String: MoaUsageRemotePricing]] = [:]
        for (id, value) in object {
            guard let entry = value as? [String: Any],
                  let input = number(entry, "input_cost_per_token"),
                  let output = number(entry, "output_cost_per_token"),
                  let provider = entry["litellm_provider"] as? String,
                  ["chat", "responses"].contains(entry["mode"] as? String ?? "chat") else { continue }
            let sources: [MoaUsageSource]
            switch provider {
            case "openai": sources = [.codex, .workbuddy]
            case "anthropic": sources = [.claude, .workbuddy]
            case "zhipu", "zai": sources = [.zcode, .workbuddy]
            case "deepseek", "gemini", "xai", "moonshot", "minimax", "stepfun", "hunyuan", "tencent": sources = [.workbuddy]
            default: continue // Cloud resellers and other currencies are not interchangeable SKUs.
            }
            let key = id.lowercased()
            guard !key.contains("/"), !["audio", "realtime", "embedding", "image"].contains(where: key.contains) else { continue }
            let thresholds = entry.keys.compactMap { key -> Int? in
                guard let range = key.range(of: #"^input_cost_per_token_above_(\d+)k_tokens$"#, options: .regularExpression) else { return nil }
                let text = key[range].dropFirst("input_cost_per_token_above_".count).dropLast("k_tokens".count)
                return Int(text).flatMap { $0 > 0 && $0 < 100_000 ? $0 * 1000 : nil }
            }
            let declaredThreshold = number(entry, "long_context_input_token_threshold").flatMap { $0 > 0 && $0 < 100_000_000 ? Int($0) : nil }
            let threshold = declaredThreshold ?? thresholds.min()
            let suffix = threshold.map { "_above_\($0 / 1000)k_tokens" } ?? ""
            let inputMultiplier = number(entry, "long_context_input_cost_multiplier")
            let outputMultiplier = number(entry, "long_context_output_cost_multiplier")
            func rate(_ name: String, tier: Bool = false, priority: Bool = false) -> Double? {
                let tierSuffix = tier ? suffix : ""
                let service = priority ? "_priority" : ""
                if tier && threshold == nil { return nil }
                if let exact = number(entry, name + tierSuffix + service) { return exact * 1_000_000 }
                guard tier, let base = number(entry, name + service),
                      let multiplier = name == "output_cost_per_token" ? outputMultiplier : inputMultiplier,
                      multiplier > 0 else { return nil }
                return base * multiplier * 1_000_000
            }
            var price = MoaUsageRemotePricing(
                inputUSDPerMillion: input * 1_000_000, outputUSDPerMillion: output * 1_000_000,
                cacheReadUSDPerMillion: rate("cache_read_input_token_cost"),
                cacheCreationUSDPerMillion: rate("cache_creation_input_token_cost"),
                thresholdTokens: threshold,
                inputUSDPerMillionAboveThreshold: rate("input_cost_per_token", tier: true),
                outputUSDPerMillionAboveThreshold: rate("output_cost_per_token", tier: true),
                cacheReadUSDPerMillionAboveThreshold: rate("cache_read_input_token_cost", tier: true),
                cacheCreationUSDPerMillionAboveThreshold: rate("cache_creation_input_token_cost", tier: true)
            )
            price.priorityInputUSDPerMillion = rate("input_cost_per_token", priority: true)
            price.priorityOutputUSDPerMillion = rate("output_cost_per_token", priority: true)
            price.priorityCacheReadUSDPerMillion = rate("cache_read_input_token_cost", priority: true)
            price.priorityCacheCreationUSDPerMillion = rate("cache_creation_input_token_cost", priority: true)
            price.priorityInputUSDPerMillionAboveThreshold = rate("input_cost_per_token", tier: true, priority: true)
            price.priorityOutputUSDPerMillionAboveThreshold = rate("output_cost_per_token", tier: true, priority: true)
            price.priorityCacheReadUSDPerMillionAboveThreshold = rate("cache_read_input_token_cost", tier: true, priority: true)
            price.priorityCacheCreationUSDPerMillionAboveThreshold = rate("cache_creation_input_token_cost", tier: true, priority: true)
            if provider == "xai", threshold != nil { price.thresholdInclusive = true }
            for source in sources { models[source.rawValue, default: [:]][key] = price }
        }
        guard (models["codex"]?.count ?? 0) >= 5, (models["claude"]?.count ?? 0) >= 3,
              (models["zcode"]?.count ?? 0) >= 1 else { throw MoaUsagePricingRemoteParser.ParseError.invalidCatalog }
        return MoaUsagePricingCatalogSnapshot(sourceURL: sourceURL.absoluteString, fetchedAt: fetchedAt, models: models)
    }

    private static func number(_ entry: [String: Any], _ key: String) -> Double? {
        guard let number = entry[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite && value >= 0 && value < 1_000_000 ? value : nil
    }
}
