import Foundation

/// Read-only local usage scanner for DeepSeek Harness (`$DSH_HOME/storages/session_projcache/sessions/session-*.json`).
/// Reads ONLY session token totals, model selection, and timestamps; never reads conversation content or prompts.
final class DeepSeekUsageScanner {
    private struct SessionRecord {
        let dayKey: String
        let model: String
        let uncachedInput: Int
        let cacheRead: Int
        let cacheWrite: Int
        let output: Int
    }

    private struct CachedSession {
        let modified: Date?
        let size: Int
        let calendarSignature: String
        let record: SessionRecord?
    }

    private let sessionsDir: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cache: [URL: CachedSession] = [:]
    private let overrides: MoaUsagePricingOverrideController
    private let catalog: MoaUsagePricingCatalogStore
    private let calendarProvider: () -> Calendar

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendarProvider: @escaping () -> Calendar = { Calendar.current }
    ) {
        let home = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath()
        let override = environment["DSH_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dshHome = (override.hasPrefix("/") ? URL(fileURLWithPath: override) : home.appendingPathComponent(".dsh")).standardizedFileURL
        sessionsDir = dshHome
            .appendingPathComponent("storages", isDirectory: true)
            .appendingPathComponent("session_projcache", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        overrides = MoaUsagePricingOverrideController(environment: environment)
        catalog = MoaUsagePricingCatalogStore(environment: environment)
        self.calendarProvider = calendarProvider
    }

    func loadSummary(forceRefresh: Bool = false, now: Date = Date()) throws -> CodexUsageSummary {
        let calendar = calendarProvider()
        let report = try loadReport(forceRefresh: forceRefresh, now: now, calendar: calendar)
        let todayKey = MoaUsageReport.dayKey(from: now, calendar: calendar)
        let today = report.rows.filter { $0.dayKey == todayKey }
        let models = Dictionary(grouping: report.rows, by: \.model).mapValues { $0.reduce(0) { $0 + $1.totalTokens } }
        let top = models.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        return CodexUsageSummary(
            todayCostUSD: today.reduce(0) { $0 + $1.costUSD },
            totalCostUSD: report.totalCostUSD,
            todayTokens: today.reduce(0) { $0 + $1.totalTokens },
            totalTokens: report.totalTokens,
            cacheHitPercent: report.cacheHitPercent,
            topModelName: top?.key,
            topModelTokens: top?.value ?? 0,
            topModelPercent: report.totalTokens > 0 ? Double(top?.value ?? 0) / Double(report.totalTokens) * 100 : 0,
            updatedAt: now
        )
    }

    func loadReport(forceRefresh: Bool = false, now: Date = Date()) throws -> MoaUsageReport {
        try loadReport(forceRefresh: forceRefresh, now: now, calendar: calendarProvider())
    }

    private func loadReport(forceRefresh: Bool, now: Date, calendar: Calendar) throws -> MoaUsageReport {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: sessionsDir.path) else {
            cache.removeAll()
            return MoaUsageReport(rows: [], generatedAt: now)
        }
        guard (try? sessionsDir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return MoaUsageReport(rows: [], generatedAt: now)
        }

        let signature = "\(calendar.identifier)|\(calendar.timeZone.identifier)"
        let files = (try? fileManager.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var activeFiles = Set<URL>()
        var buckets: [String: MoaUsageDetailRow] = [:]

        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            activeFiles.insert(url)

            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            let modified = attrs[.modificationDate] as? Date
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0

            let record: SessionRecord?
            if !forceRefresh,
               let cached = cache[url],
               cached.modified == modified,
               cached.size == size,
               cached.calendarSignature == signature {
                record = cached.record
            } else {
                record = parseSession(url, calendar: calendar)
                cache[url] = CachedSession(modified: modified, size: size, calendarSignature: signature, record: record)
            }

            guard let record else { continue }
            let priced = price(record)
            let row = MoaUsageDetailRow(
                source: .deepseek,
                dayKey: record.dayKey,
                model: record.model,
                input: record.uncachedInput,
                cachedInput: 0,
                cacheReadInput: record.cacheRead,
                cacheCreationInput: record.cacheWrite,
                output: record.output,
                costUSD: priced?.cost ?? 0,
                pricingModel: priced?.model ?? "unpriced",
                usesFallbackPricing: priced == nil
            )
            if var existing = buckets[row.id] {
                existing.merge(row)
                buckets[row.id] = existing
            } else {
                buckets[row.id] = row
            }
        }

        cache = cache.filter { activeFiles.contains($0.key) }
        return MoaUsageReport(rows: Array(buckets.values), generatedAt: now)
    }

    private func parseSession(_ url: URL, calendar: Calendar) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url),
              data.count <= 8 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = root["record"] as? [String: Any],
              let rows = record["rows"] as? [String: Any],
              let tokenUsage = rows["tokenUsage"] as? [String: Any],
              let tokenVal = tokenUsage["val"] as? [String: Any],
              let totals = tokenVal["totals"] as? [String: Any] else {
            return nil
        }

        let uncachedInput = max(0, intValue(totals["uncachedInputTokens"]) ?? 0)
        let output = max(0, intValue(totals["outputTokens"]) ?? 0)
        let cacheRead = max(0, intValue(totals["cacheReadTokens"]) ?? 0)
        let cacheWrite = max(0, intValue(totals["cacheWriteTokens"]) ?? 0)
        guard uncachedInput + output + cacheRead + cacheWrite > 0 else { return nil }

        let identity = record["identity"] as? [String: Any]
        let listMeta = (rows["sessionListMetadata"] as? [String: Any])?["val"] as? [String: Any]
        let timestampMs = doubleValue(listMeta?["lastPromptAt"]) ?? doubleValue(identity?["createdAt"])
        guard let timestampMs, timestampMs > 0 else { return nil }
        let seconds = timestampMs > 100_000_000_000 ? timestampMs / 1000.0 : timestampMs
        let date = Date(timeIntervalSince1970: seconds)

        let modelSelection = (rows["modelSelection"] as? [String: Any])?["val"] as? [String: Any]
        let lastUsed = modelSelection?["lastUsed"] as? [String: Any]
        let rawModel = (lastUsed?["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = Self.normalizedModelName(rawModel)

        return SessionRecord(
            dayKey: MoaUsageReport.dayKey(from: date, calendar: calendar),
            model: model,
            uncachedInput: uncachedInput,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            output: output
        )
    }

    static func normalizedModelName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.isEmpty { return "deepseek-chat" }
        // Strip proxy/provider namespaces such as "workbuddy/" or "magpie/".
        if let slash = cleaned.lastIndex(of: "/") {
            let tail = String(cleaned[cleaned.index(after: slash)...])
            if !tail.isEmpty { cleaned = tail }
        }
        return cleaned
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value, !(value is Bool && CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()) else {
            return nil
        }
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite, number >= 0, number < Double(Int.max / 16) else {
            return nil
        }
        return Int(number)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard let value, !(value is Bool && CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()) else {
            return nil
        }
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite else { return nil }
        return number
    }

    private func price(_ record: SessionRecord) -> (cost: Double, model: String)? {
        let canonical = MoaUsagePricingSeed.canonicalModel(record.model)
        let custom = overrides.override(source: .deepseek, model: record.model)
            ?? overrides.override(source: .deepseek, model: canonical)
        let remote = MoaUsagePricing.catalogPricing(source: .deepseek, model: record.model, store: catalog)
            ?? MoaUsagePricing.catalogPricing(source: .workbuddy, model: record.model, store: catalog)

        if custom != nil || remote != nil {
            let promptTokens = record.uncachedInput + record.cacheRead + record.cacheWrite
            let above = remote?.usesLongContext(promptTokens: promptTokens) ?? false
            let inputRate = custom?.inputUSDPerMillion ?? (above ? remote?.inputUSDPerMillionAboveThreshold : nil) ?? remote?.inputUSDPerMillion ?? 0
            let outputRate = custom?.outputUSDPerMillion ?? (above ? remote?.outputUSDPerMillionAboveThreshold : nil) ?? remote?.outputUSDPerMillion ?? 0
            let readRate = custom?.cacheReadUSDPerMillion ?? (above ? remote?.cacheReadUSDPerMillionAboveThreshold : nil) ?? remote?.cacheReadUSDPerMillion ?? inputRate
            let writeRate = custom?.cacheCreationUSDPerMillion ?? (above ? remote?.cacheCreationUSDPerMillionAboveThreshold : nil) ?? remote?.cacheCreationUSDPerMillion ?? inputRate
            let cost = (Double(record.uncachedInput) * inputRate
                + Double(record.cacheRead) * readRate
                + Double(record.cacheWrite) * writeRate
                + Double(record.output) * outputRate) / 1_000_000
            let pricingLabel = custom != nil ? MoaL10n.text("Custom") : canonical
            return (cost, pricingLabel)
        }
        return nil
    }
}
