import Foundation

private typealias CodexUsagePricing = MoaUsagePricing

final class CodexUsageScanner {
    private static let cacheVersion = 4

    private struct TokenCounts: Codable, Equatable {
        var input: Int = 0
        var cached: Int = 0
        var cacheWrite: Int = 0
        var output: Int = 0

        init(_ values: [String: Any]) {
            input = max(0, CodexUsageScanner.intValue(values["input_tokens"]))
            cached = min(input, max(0, CodexUsageScanner.intValue(values["cached_input_tokens"] ?? values["cache_read_input_tokens"])))
            cacheWrite = min(input - cached, max(0, CodexUsageScanner.intValue(values["cache_write_input_tokens"])))
            output = max(0, CodexUsageScanner.intValue(values["output_tokens"]))
        }

        init(input: Int = 0, cached: Int = 0, cacheWrite: Int = 0, output: Int = 0) {
            self.input = max(0, input)
            self.cached = min(self.input, max(0, cached))
            self.cacheWrite = min(self.input - self.cached, max(0, cacheWrite))
            self.output = max(0, output)
        }

        func difference(from previous: Self) -> Self {
            Self(input: max(0, input - previous.input), cached: max(0, cached - previous.cached),
                 cacheWrite: max(0, cacheWrite - previous.cacheWrite), output: max(0, output - previous.output))
        }

        func decreased(from previous: Self) -> Bool {
            input < previous.input || cached < previous.cached || cacheWrite < previous.cacheWrite || output < previous.output
        }
    }

    private struct TokenUsage: Codable, Equatable {
        var input: Int = 0
        var cached: Int = 0
        var cacheWrite: Int = 0
        var output: Int = 0
        // Preserve request boundaries: long-context pricing applies per request,
        // not to the sum of every request in a day. Prices can still refresh
        // without rereading the source rollouts.
        var requests: [TokenCounts] = []

        mutating func add(_ counts: TokenCounts) {
            input += counts.input
            cached += counts.cached
            cacheWrite += counts.cacheWrite
            output += counts.output
            requests.append(counts)
        }
    }

    private struct PendingUsage {
        var day: String
        var model: String
        var counts: TokenCounts
    }

    private struct CachedFile: Codable, Equatable {
        var mtime: TimeInterval
        var size: Int64
        var days: [String: [String: TokenUsage]]
    }

    private struct Cache: Codable, Equatable {
        var version: Int
        var codexHomePath: String
        var calendarSignature: String
        var files: [String: CachedFile]
    }

    private let fileManager = FileManager.default
    private let environment: [String: String]
    private let codexHome: URL
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let calendarProvider: () -> Calendar
    private let cacheLock = NSLock()

    private var cacheURL: URL {
        MoaDataRoot.currentURL(environment: environment)
            .appendingPathComponent("codex-usage-cache-v3.json")
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment, calendarProvider: @escaping () -> Calendar = { .current }) {
        self.environment = environment
        self.calendarProvider = calendarProvider
        let home = environment["HOME"] ?? NSHomeDirectory()
        let codexHomePath = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.codex"
        codexHome = URL(fileURLWithPath: codexHomePath).standardizedFileURL
        pricingOverrides = MoaUsagePricingOverrideController(environment: environment)
    }

    func loadSummary(forceRefresh: Bool = false, now: Date = Date()) throws -> CodexUsageSummary {
        let calendar = calendarProvider()
        return summary(from: try loadReport(forceRefresh: forceRefresh, now: now, persistCache: true, calendar: calendar), now: now, calendar: calendar)
    }

    func loadReport(
        forceRefresh: Bool = false,
        now: Date = Date(),
        persistCache: Bool = true
    ) throws -> MoaUsageReport {
        try loadReport(forceRefresh: forceRefresh, now: now, persistCache: persistCache, calendar: calendarProvider())
    }

    private func loadReport(forceRefresh: Bool, now: Date, persistCache: Bool, calendar: Calendar) throws -> MoaUsageReport {
        let roots = [
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        let files = sessionFiles(in: roots)
        let validPaths = Set(files.map(\.path))
        var cache = lockedLoadCache()
        let signature = Self.calendarSignature(calendar)
        if cache.version != Self.cacheVersion || cache.codexHomePath != codexHome.path || cache.calendarSignature != signature {
            cache = Cache(version: Self.cacheVersion, codexHomePath: codexHome.path, calendarSignature: signature, files: [:])
        }
        let originalCache = cache

        var nextFiles: [String: CachedFile] = [:]
        for fileURL in files {
            guard let metadata = fileMetadata(for: fileURL) else { continue }
            let path = fileURL.path
            if !forceRefresh,
               let cached = cache.files[path],
               cached.mtime == metadata.mtime,
               cached.size == metadata.size
            {
                nextFiles[path] = cached
                continue
            }

            let days = try parseSessionFile(fileURL, calendar: calendar)
            nextFiles[path] = CachedFile(mtime: metadata.mtime, size: metadata.size, days: days)
        }

        cache.files = nextFiles.filter { validPaths.contains($0.key) }
        if persistCache && cache != originalCache {
            lockedSaveCache(cache)
        }
        return report(from: cache, now: now)
    }

    private func sessionFiles(in roots: [URL]) -> [URL] {
        var files: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
                files.append(fileURL.standardizedFileURL)
            }
        }
        return files
    }

    private func fileMetadata(for url: URL) -> (mtime: TimeInterval, size: Int64)? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = values.contentModificationDate?.timeIntervalSince1970,
              let size = values.fileSize
        else { return nil }
        return (mtime, Int64(size))
    }

    private func parseSessionFile(_ fileURL: URL, calendar: Calendar) throws -> [String: [String: TokenUsage]] {
        var days: [String: [String: TokenUsage]] = [:]
        var currentModel: String?
        var previousTotals: TokenCounts?
        var legacyEvents: [PendingUsage] = []
        var usageRecords: [PendingUsage] = []
        var hasUsageRecords = false
        var seenResponses = Set<String>()

        func flushTurn() {
            // New clients emit both formats. Select one source for each model
            // context, retaining legacy-only turns in upgraded session files.
            for event in hasUsageRecords ? usageRecords : legacyEvents {
                guard event.counts.input > 0 || event.counts.output > 0 else { continue }
                let model = CodexUsagePricing.normalizeModel(event.model)
                days[event.day, default: [:]][model, default: TokenUsage()].add(event.counts)
            }
            legacyEvents.removeAll(keepingCapacity: true)
            usageRecords.removeAll(keepingCapacity: true)
            hasUsageRecords = false
        }

        try MoaJSONLReader.scan(fileURL: fileURL) { line, truncated in
                guard shouldInspect(line) else { return }
                if truncated || line.count > 512 * 1024 {
                    let prefix = Data(line.prefix(1024))
                    if prefix.containsASCII(#""type":"turn_context""#) || prefix.containsASCII(#""type": "turn_context""#) {
                        flushTurn()
                        currentModel = extractStringField("model", fromPrefixOf: line)
                    }
                    return
                }
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let type = object["type"] as? String,
                      let payload = object["payload"] as? [String: Any] else { return }
                if type == "turn_context" {
                    flushTurn()
                    currentModel = payload["model"] as? String
                        ?? (payload["info"] as? [String: Any])?["model"] as? String
                    return
                }
                guard let timestamp = object["timestamp"] as? String,
                      let day = Self.dayKey(from: timestamp, calendar: calendar) else { return }

                if type == "token_usage_record" {
                    guard let values = payload["usage"] as? [String: Any],
                          let model = payload["model"] as? String ?? currentModel, !model.isEmpty else { return }
                    hasUsageRecords = true
                    let counts = TokenCounts(values)
                    let identity: String
                    if let responseID = payload["response_id"] as? String, !responseID.isEmpty {
                        identity = "response:\(responseID)"
                    } else {
                        let total = TokenCounts(payload["thread_token_usage"] as? [String: Any] ?? values)
                        let turn = payload["turn_id"] as? String ?? timestamp
                        identity = "usage:\(turn):\(total.input):\(total.cached):\(total.cacheWrite):\(total.output)"
                    }
                    guard seenResponses.insert(identity).inserted else { return }
                    usageRecords.append(PendingUsage(day: day, model: model, counts: counts))
                    return
                }

                guard type == "event_msg", payload["type"] as? String == "token_count" else { return }
                let info = payload["info"] as? [String: Any]
                let total = (info?["total_token_usage"] as? [String: Any]).map(TokenCounts.init)
                let last = (info?["last_token_usage"] as? [String: Any]).map(TokenCounts.init)
                let previous = previousTotals
                // Advance the baseline even when copied parent history has no
                // model context and must not be counted for this rollout.
                if let total { previousTotals = total }
                if let total, let previous, total == previous { return }

                let model = currentModel
                    ?? info?["model"] as? String
                    ?? info?["model_name"] as? String
                    ?? payload["model"] as? String
                    ?? object["model"] as? String
                guard let model, !model.isEmpty else { return }
                let delta: TokenCounts?
                if let total, let previous, !total.decreased(from: previous) {
                    delta = total.difference(from: previous)
                } else {
                    delta = last ?? total
                }
                guard let delta else { return }
                if total == nil {
                    let previous = previousTotals ?? TokenCounts()
                    previousTotals = TokenCounts(input: previous.input + delta.input, cached: previous.cached + delta.cached,
                                                 cacheWrite: previous.cacheWrite + delta.cacheWrite, output: previous.output + delta.output)
                }
                legacyEvents.append(PendingUsage(day: day, model: model, counts: delta))
        }
        flushTurn()
        return days
    }

    private func shouldInspect(_ line: Data) -> Bool {
        line.containsASCII(#""token_count""#)
            || line.containsASCII(#""token_usage_record""#)
            || line.containsASCII(#""turn_context""#)
    }

    private static let modelFieldRegex = try! NSRegularExpression(pattern: #""model"\s*:\s*"([^"]+)""#)

    private func extractStringField(_ field: String, fromPrefixOf line: Data) -> String? {
        let prefix = line.prefix(32 * 1024)
        guard let text = String(data: Data(prefix), encoding: .utf8) else { return nil }
        guard field == "model" else { return nil }
        let regex = Self.modelFieldRegex
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[valueRange])
    }

    private func report(from cache: Cache, now: Date) -> MoaUsageReport {
        var buckets: [String: MoaUsageDetailRow] = [:]
        for cachedFile in cache.files.values {
            for (dayKey, models) in cachedFile.days {
                for (model, usage) in models {
                    let estimates = usage.requests.compactMap { request in
                        pricingOverrides.codexCostEstimate(
                            model: model, inputTokens: request.input, cachedInputTokens: request.cached,
                            cacheWriteInputTokens: request.cacheWrite, outputTokens: request.output
                        ) ?? CodexUsagePricing.codexCostEstimate(
                            model: model, inputTokens: request.input, cachedInputTokens: request.cached,
                            cacheWriteInputTokens: request.cacheWrite, outputTokens: request.output
                        )
                    }
                    let metadata = estimates.first
                    let row = MoaUsageDetailRow(
                        source: .codex,
                        dayKey: dayKey,
                        model: metadata?.normalizedModel ?? model,
                        input: max(0, usage.input - usage.cached - usage.cacheWrite),
                        cachedInput: usage.cached,
                        cacheReadInput: 0,
                        cacheCreationInput: usage.cacheWrite,
                        output: usage.output,
                        costUSD: estimates.reduce(0) { $0 + $1.costUSD },
                        pricingModel: metadata?.pricingModel ?? model,
                        usesFallbackPricing: estimates.contains { $0.usesFallbackPricing }
                    )
                    if var existing = buckets[row.id] {
                        existing.merge(row)
                        buckets[row.id] = existing
                    } else {
                        buckets[row.id] = row
                    }
                }
            }
        }
        return MoaUsageReport(rows: Array(buckets.values), generatedAt: now)
    }

    private func summary(from report: MoaUsageReport, now: Date, calendar: Calendar) -> CodexUsageSummary {
        let todayKey = Self.dayKey(from: now, calendar: calendar)
        var todayCost = 0.0
        var todayTokens = 0
        var totalCost = 0.0
        var totalTokens = 0
        var cacheHitTokens = 0
        var modelTotals: [String: Int] = [:]

        for row in report.rows {
            let tokens = row.totalTokens
            totalCost += row.costUSD
            totalTokens += tokens
            cacheHitTokens += row.cacheHitTokens
            modelTotals[row.model, default: 0] += tokens

            if row.dayKey == todayKey {
                todayCost += row.costUSD
                todayTokens += tokens
            }
        }

        let top = modelTotals.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }
        let topPercent = if let top, totalTokens > 0 {
            (Double(top.value) / Double(totalTokens)) * 100
        } else {
            0.0
        }
        let cacheHitPercent = totalTokens > 0
            ? Double(cacheHitTokens) / Double(totalTokens) * 100
            : 0.0

        return CodexUsageSummary(
            todayCostUSD: todayCost,
            totalCostUSD: totalCost,
            todayTokens: todayTokens,
            totalTokens: totalTokens,
            cacheHitPercent: cacheHitPercent,
            topModelName: top?.key,
            topModelTokens: top?.value ?? 0,
            topModelPercent: topPercent,
            updatedAt: now)
    }

    private func loadCache() -> Cache {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(Cache.self, from: data)
        else {
            return Cache(version: Self.cacheVersion, codexHomePath: codexHome.path, calendarSignature: Self.calendarSignature(calendarProvider()), files: [:])
        }
        return decoded
    }

    private func lockedLoadCache() -> Cache {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return loadCache()
    }

    private func lockedSaveCache(_ cache: Cache) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        saveCache(cache)
    }

    private func saveCache(_ cache: Cache) {
        do {
            let store = MoaDataStoreLock(environment: environment)
            try store.lock()
            defer { store.unlock() }
            try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            return
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    private static func calendarSignature(_ calendar: Calendar) -> String {
        "\(calendar.identifier)|\(calendar.timeZone.identifier)"
    }

    private static func dayKey(from timestamp: String, calendar: Calendar) -> String? {
        guard let date = CodexUsageDateParser.parse(timestamp) else { return nil }
        return dayKey(from: date, calendar: calendar)
    }

    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
