import Foundation

/// Read-only token accounting for one edition's projects and sessions logs.
/// No auth decryption, database writes, transcript exports, or billing API calls.
final class WorkBuddyUsageScanner {
    private struct Request: Hashable {
        var identity: String?
        var timestamp: Double
        var model: String
        var input: Int
        var read: Int
        var write: Int
        var output: Int
    }
    private struct CachedFile {
        var modified: Date?
        var size: Int
        var requests: [Request]
    }

    private let root: URL
    let edition: WorkBuddyEdition
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cache: [URL: CachedFile] = [:]
    private let overrides: MoaUsagePricingOverrideController
    private let catalog: MoaUsagePricingCatalogStore
    private let isoDateParser = ISO8601DateFormatter()
    private let fractionalDateParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    init(environment: [String: String] = ProcessInfo.processInfo.environment, edition: WorkBuddyEdition = .international) {
        self.edition = edition
        root = MoaDataRoot.homeDirectory(environment: environment).appendingPathComponent(edition.dataDirectoryName)
        overrides = MoaUsagePricingOverrideController(environment: environment)
        catalog = MoaUsagePricingCatalogStore(environment: environment)
    }

    func loadSummary(forceRefresh: Bool = false, now: Date = Date()) throws -> CodexUsageSummary {
        let report = try loadReport(forceRefresh: forceRefresh, now: now)
        let today = report.rows.filter { $0.dayKey == MoaUsageReport.dayKey(from: now) }
        let models = Dictionary(grouping: report.rows, by: \.model).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }
        let top = models.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        return CodexUsageSummary(
            todayCostUSD: today.reduce(0) { $0 + $1.costUSD }, totalCostUSD: report.totalCostUSD,
            todayTokens: today.reduce(0) { $0 + $1.totalTokens }, totalTokens: report.totalTokens,
            cacheHitPercent: report.cacheHitPercent, topModelName: top?.key, topModelTokens: top?.value ?? 0,
            topModelPercent: report.totalTokens > 0 ? Double(top?.value ?? 0) / Double(report.totalTokens) * 100 : 0,
            updatedAt: now
        )
    }

    func loadReport(forceRefresh: Bool = false, now: Date = Date()) throws -> MoaUsageReport {
        lock.lock(); defer { lock.unlock() }
        var files = Set<URL>()
        for name in ["projects", "sessions"] {
            let directory = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            var traversalError: Error?
            guard let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles], errorHandler: { _, error in traversalError = error; return false }
            ) else { continue }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if url.lastPathComponent == "subagents" || values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathExtension == "jsonl", values.isRegularFile == true { files.insert(url) }
            }
            if let traversalError { throw traversalError }
        }
        cache = cache.filter { files.contains($0.key) }
        var identified: [String: Request] = [:]
        var anonymous = Set<Request>()
        var buckets: [String: MoaUsageDetailRow] = [:]
        for url in files.sorted(by: { $0.path < $1.path }) {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let modified = attributes[.modificationDate] as? Date
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let requests: [Request]
            if !forceRefresh, let cached = cache[url], cached.modified == modified, cached.size == size {
                requests = cached.requests
            } else {
                requests = try readRequests(url)
                cache[url] = CachedFile(modified: modified, size: size, requests: requests)
            }
            for request in requests {
                if let identity = request.identity {
                    if let existing = identified[identity] {
                        // Logs may replay or update a request. Prefer the most
                        // complete usage, then the later record for equal totals.
                        let oldTotal = existing.input + existing.output
                        let newTotal = request.input + request.output
                        if newTotal < oldTotal || (newTotal == oldTotal && request.timestamp < existing.timestamp) { continue }
                    }
                    identified[identity] = request
                } else {
                    anonymous.insert(request)
                }
            }
        }
        for request in Array(identified.values) + Array(anonymous) {
            let estimate = price(request)
            let row = MoaUsageDetailRow(
                source: edition.usageSource, dayKey: MoaUsageReport.dayKey(from: Date(timeIntervalSince1970: request.timestamp)),
                model: request.model, input: request.input - request.read - request.write,
                cachedInput: 0, cacheReadInput: request.read, cacheCreationInput: request.write,
                output: request.output, costUSD: estimate?.cost ?? 0,
                pricingModel: estimate?.model ?? "unpriced", usesFallbackPricing: estimate == nil
            )
            if var existing = buckets[row.id] { existing.merge(row); buckets[row.id] = existing }
            else { buckets[row.id] = row }
        }
        return MoaUsageReport(rows: Array(buckets.values), generatedAt: now)
    }

    private func readRequests(_ url: URL) throws -> [Request] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        var result: [Request] = []
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0a) {
                if let request = decode(Data(buffer[start..<newline])) { result.append(request) }
                start = buffer.index(after: newline)
            }
            buffer.removeSubrange(..<start)
        }
        if !buffer.isEmpty, let request = decode(buffer) { result.append(request) }
        return result
    }

    private func decode(_ data: Data) -> Request? {
        guard data.range(of: Data("\"usage\"".utf8)) != nil,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let provider = value["providerData"] as? [String: Any] ?? [:]
        let message = value["message"] as? [String: Any] ?? [:]
        let candidates = [message["usage"], provider["usage"], value["usage"]].compactMap { $0 as? [String: Any] }
        guard let usage = candidates.first(where: { number($0, ["input_tokens", "inputTokens", "prompt_tokens"]) != nil }),
              let timestamp = timestamp(value["timestamp"] ?? value["ts"]) else { return nil }
        let input = number(usage, ["input_tokens", "inputTokens", "prompt_tokens"]) ?? 0
        let output = number(usage, ["output_tokens", "outputTokens", "completion_tokens"]) ?? 0
        let details = usage["prompt_tokens_details"] as? [String: Any] ?? [:]
        let camelDetails = usage["inputTokensDetails"] as? [[String: Any]] ?? []
        let read = min(input,
            positive(usage, ["cache_read_input_tokens", "cacheReadInputTokens", "prompt_cache_hit_tokens", "cached_tokens"])
            ?? positive(details, ["cached_tokens"])
            ?? camelDetails.compactMap { positive($0, ["cached_tokens"]) }.first ?? 0
        )
        let writeKeys = ["cache_write_input_tokens", "cacheWriteInputTokens", "cache_creation_input_tokens", "cacheCreationInputTokens", "prompt_cache_write_tokens"]
        let raw = provider["rawUsage"] as? [String: Any] ?? [:]
        let write = min(input - read, (candidates + [raw]).compactMap { positive($0, writeKeys) }.first ?? 0)
        // Cache miss is ordinary input, and reasoning tokens are already part of output.
        let model = ([provider["model"], value["model"], message["model"], provider["requestModelId"]]
            .compactMap { $0 as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "unknown")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard input > 0 || output > 0 else { return nil }
        let messageID = (provider["messageId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventID = (value["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity: String?
        if let messageID, !messageID.isEmpty {
            identity = "message|\(messageID)|\(provider["stepSeq"] ?? "")"
        } else if let eventID, !eventID.isEmpty {
            identity = "event|\(eventID)"
        } else { identity = nil }
        return Request(identity: identity, timestamp: timestamp, model: model, input: input, read: read, write: write, output: output)
    }

    private func number(_ object: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            guard let value = object[key], !(value is Bool && CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()) else { continue }
            let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
            if let number, number.isFinite, number >= 0, number < Double(Int.max / 16) { return Int(number) }
        }
        return nil
    }

    private func positive(_ object: [String: Any], _ keys: [String]) -> Int? {
        keys.compactMap { number(object, [$0]) }.first { $0 > 0 }
    }

    private func timestamp(_ value: Any?) -> Double? {
        if let text = value as? String,
           let date = fractionalDateParser.date(from: text) ?? isoDateParser.date(from: text) {
            return date.timeIntervalSince1970
        }
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite, number > 0 else { return nil }
        let seconds = number > 100_000_000_000 ? number / 1000 : number
        return seconds < 253_402_300_800 ? seconds : nil
    }

    private func price(_ request: Request) -> (cost: Double, model: String)? {
        let canonical = MoaUsagePricingSeed.canonicalModel(request.model)
        let custom = overrides.override(source: edition.usageSource, model: request.model)
            ?? overrides.override(source: edition.usageSource, model: canonical)
        let remote = MoaUsagePricing.catalogPricing(source: edition.usageSource, model: request.model, store: catalog)
        if custom != nil || remote != nil {
            let above = remote?.usesLongContext(promptTokens: request.input) ?? false
            let input = custom?.inputUSDPerMillion ?? (above ? remote?.inputUSDPerMillionAboveThreshold : nil) ?? remote?.inputUSDPerMillion ?? 0
            let output = custom?.outputUSDPerMillion ?? (above ? remote?.outputUSDPerMillionAboveThreshold : nil) ?? remote?.outputUSDPerMillion ?? 0
            let read = custom?.cacheReadUSDPerMillion ?? (above ? remote?.cacheReadUSDPerMillionAboveThreshold : nil) ?? remote?.cacheReadUSDPerMillion ?? input
            let write = custom?.cacheCreationUSDPerMillion ?? (above ? remote?.cacheCreationUSDPerMillionAboveThreshold : nil) ?? remote?.cacheCreationUSDPerMillion ?? input
            let cost = (Double(request.input - request.read - request.write) * input + Double(request.read) * read
                + Double(request.write) * write + Double(request.output) * output) / 1_000_000
            return (cost, custom?.model ?? canonical)
        }
        // Only use a built-in price when the model is recognized. Never substitute GPT pricing for an unknown WorkBuddy model.
        let estimate: MoaUsagePricing.CostEstimate?
        if request.model.hasPrefix("claude-") {
            estimate = MoaUsagePricing.claudeCostEstimate(model: request.model,
                inputTokens: request.input - request.read - request.write, cacheReadInputTokens: request.read,
                cacheCreationInputTokens: request.write, outputTokens: request.output)
        } else if request.model.hasPrefix("gpt-") || request.model.hasPrefix("o3") || request.model.hasPrefix("o4") {
            estimate = MoaUsagePricing.codexCostEstimate(model: request.model, inputTokens: request.input,
                cachedInputTokens: request.read, cacheWriteInputTokens: request.write, outputTokens: request.output)
        } else { estimate = nil }
        guard let estimate, !estimate.usesFallbackPricing else { return nil }
        return (estimate.costUSD, estimate.pricingModel)
    }
}
