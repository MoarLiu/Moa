import Foundation

/// Read-only local usage scanner for Antigravity (`~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl`).
/// Extracts ONLY token counts, model identifiers, step indices, and UTC timestamps; never stores conversation text or prompts.
final class AntigravityUsageScanner {
    private struct StepRecord: Hashable {
        let stepIndex: Int
        let dayKey: String
        let model: String
        let input: Int
        let cacheRead: Int
        let cacheCreation: Int
        let output: Int
    }

    private struct CachedFile {
        let modified: Date?
        let size: Int
        let calendarSignature: String
        let records: [StepRecord]
    }

    private static let maxLineBytes = 4 * 1024 * 1024

    private let brainRoot: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cache: [URL: CachedFile] = [:]
    private let overrides: MoaUsagePricingOverrideController
    private let catalog: MoaUsagePricingCatalogStore
    private let calendarProvider: () -> Calendar
    private let isoParser = ISO8601DateFormatter()
    private let fractionalISOParser: ISO8601DateFormatter = {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser
    }()

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendarProvider: @escaping () -> Calendar = { Calendar.current }
    ) {
        let home = MoaDataRoot.homeDirectory(environment: environment)
        brainRoot = home.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true).standardizedFileURL
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

        guard fileManager.fileExists(atPath: brainRoot.path) else {
            cache.removeAll()
            return MoaUsageReport(rows: [], generatedAt: now)
        }
        guard (try? brainRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return MoaUsageReport(rows: [], generatedAt: now)
        }

        let signature = "\(calendar.identifier)|\(calendar.timeZone.identifier)"
        let conversations = (try? fileManager.contentsOfDirectory(
            at: brainRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var activeFiles = Set<URL>()
        var buckets: [String: MoaUsageDetailRow] = [:]

        for conversationDir in conversations.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let dirValues = try? conversationDir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  dirValues.isDirectory == true, dirValues.isSymbolicLink != true else {
                continue
            }
            let transcriptURL = conversationDir
                .appendingPathComponent(".system_generated", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
                .appendingPathComponent("transcript.jsonl")
            guard fileManager.fileExists(atPath: transcriptURL.path),
                  let fileValues = try? transcriptURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else {
                continue
            }
            activeFiles.insert(transcriptURL)

            let attrs = try fileManager.attributesOfItem(atPath: transcriptURL.path)
            let modified = attrs[.modificationDate] as? Date
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0

            let records: [StepRecord]
            if !forceRefresh,
               let cached = cache[transcriptURL],
               cached.modified == modified,
               cached.size == size,
               cached.calendarSignature == signature {
                records = cached.records
            } else {
                records = try readTranscript(transcriptURL, calendar: calendar)
                cache[transcriptURL] = CachedFile(modified: modified, size: size, calendarSignature: signature, records: records)
            }

            for record in records {
                let priced = price(record)
                let row = MoaUsageDetailRow(
                    source: .antigravity,
                    dayKey: record.dayKey,
                    model: record.model,
                    input: record.input,
                    cachedInput: 0,
                    cacheReadInput: record.cacheRead,
                    cacheCreationInput: record.cacheCreation,
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
        }

        cache = cache.filter { activeFiles.contains($0.key) }
        return MoaUsageReport(rows: Array(buckets.values), generatedAt: now)
    }

    private func readTranscript(_ url: URL, calendar: Calendar) throws -> [StepRecord] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var byStep: [Int: StepRecord] = [:]
        var buffer = Data()
        var skippingOversizedLine = false

        func processLine(_ lineData: Data) {
            guard !lineData.isEmpty,
                  lineData.range(of: Data("\"input_tokens\"".utf8)) != nil
                    || lineData.range(of: Data("\"output_tokens\"".utf8)) != nil,
                  let record = decodeLine(lineData, calendar: calendar) else {
                return
            }
            if let existing = byStep[record.stepIndex] {
                let oldTotal = existing.input + existing.cacheRead + existing.cacheCreation + existing.output
                let newTotal = record.input + record.cacheRead + record.cacheCreation + record.output
                if newTotal >= oldTotal {
                    byStep[record.stepIndex] = record
                }
            } else {
                byStep[record.stepIndex] = record
            }
        }

        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if skippingOversizedLine {
                if let newline = chunk.firstIndex(of: 0x0a) {
                    skippingOversizedLine = false
                    let tail = chunk.index(after: newline)
                    if tail < chunk.endIndex {
                        buffer.append(contentsOf: chunk[tail...])
                    }
                }
                continue
            }
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0a) {
                processLine(Data(buffer[start..<newline]))
                start = buffer.index(after: newline)
            }
            buffer.removeSubrange(..<start)
            if buffer.count > Self.maxLineBytes {
                buffer.removeAll(keepingCapacity: false)
                skippingOversizedLine = true
            }
        }
        if !skippingOversizedLine && !buffer.isEmpty {
            processLine(buffer)
        }
        return byStep.values.sorted { $0.stepIndex < $1.stepIndex }
    }

    private func decodeLine(_ data: Data, calendar: Calendar) -> StepRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let status = object["status"] as? String, status.uppercased() != "DONE" {
            return nil
        }
        guard let stepIndex = intValue(object["step_index"]),
              let createdRaw = object["created_at"] as? String,
              let date = fractionalISOParser.date(from: createdRaw) ?? isoParser.date(from: createdRaw) else {
            return nil
        }
        let input = max(0, intValue(object["input_tokens"]) ?? 0)
        let cacheRead = max(0, intValue(object["cache_read_tokens"]) ?? 0)
        let cacheCreation = max(0, intValue(object["cache_creation_tokens"]) ?? 0)
        let output = max(0, intValue(object["output_tokens"]) ?? 0)
        guard input + cacheRead + cacheCreation + output > 0 else { return nil }

        let rawModel = (object["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = rawModel.isEmpty ? "unknown" : rawModel.lowercased()
        let dayKey = MoaUsageReport.dayKey(from: date, calendar: calendar)
        return StepRecord(
            stepIndex: stepIndex,
            dayKey: dayKey,
            model: model,
            input: input,
            cacheRead: cacheRead,
            cacheCreation: cacheCreation,
            output: output
        )
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

    static func normalizedPricingCandidate(_ model: String) -> String {
        var value = MoaUsagePricingSeed.canonicalModel(model)
        for suffix in ["-xhigh", "-high", "-medium", "-low", "-thinking"] where value.hasSuffix(suffix) {
            let trimmed = String(value.dropLast(suffix.count))
            if !trimmed.isEmpty {
                value = trimmed
                break
            }
        }
        return value
    }

    private func price(_ record: StepRecord) -> (cost: Double, model: String)? {
        let canonical = MoaUsagePricingSeed.canonicalModel(record.model)
        let baseCandidate = Self.normalizedPricingCandidate(record.model)
        let custom = overrides.override(source: .antigravity, model: record.model)
            ?? overrides.override(source: .antigravity, model: canonical)
            ?? overrides.override(source: .antigravity, model: baseCandidate)
        let remote = MoaUsagePricing.catalogPricing(source: .antigravity, model: record.model, store: catalog)
            ?? MoaUsagePricing.catalogPricing(source: .antigravity, model: baseCandidate, store: catalog)

        if custom != nil || remote != nil {
            let promptTokens = record.input + record.cacheRead + record.cacheCreation
            let above = remote?.usesLongContext(promptTokens: promptTokens) ?? false
            let inputRate = custom?.inputUSDPerMillion ?? (above ? remote?.inputUSDPerMillionAboveThreshold : nil) ?? remote?.inputUSDPerMillion ?? 0
            let outputRate = custom?.outputUSDPerMillion ?? (above ? remote?.outputUSDPerMillionAboveThreshold : nil) ?? remote?.outputUSDPerMillion ?? 0
            let readRate = custom?.cacheReadUSDPerMillion ?? (above ? remote?.cacheReadUSDPerMillionAboveThreshold : nil) ?? remote?.cacheReadUSDPerMillion ?? inputRate
            let writeRate = custom?.cacheCreationUSDPerMillion ?? (above ? remote?.cacheCreationUSDPerMillionAboveThreshold : nil) ?? remote?.cacheCreationUSDPerMillion ?? inputRate
            let cost = (Double(record.input) * inputRate
                + Double(record.cacheRead) * readRate
                + Double(record.cacheCreation) * writeRate
                + Double(record.output) * outputRate) / 1_000_000
            let pricingLabel = custom != nil ? MoaL10n.text("Custom") : baseCandidate
            return (cost, pricingLabel)
        }

        if baseCandidate.hasPrefix("claude-") {
            if let est = MoaUsagePricing.claudeCostEstimate(
                model: baseCandidate,
                inputTokens: record.input,
                cacheReadInputTokens: record.cacheRead,
                cacheCreationInputTokens: record.cacheCreation,
                outputTokens: record.output
            ), !est.usesFallbackPricing {
                return (est.costUSD, est.pricingModel)
            }
        } else if baseCandidate.hasPrefix("gpt-") {
            if let est = MoaUsagePricing.codexCostEstimate(
                model: baseCandidate,
                inputTokens: record.input + record.cacheRead + record.cacheCreation,
                cachedInputTokens: record.cacheRead,
                cacheWriteInputTokens: record.cacheCreation,
                outputTokens: record.output
            ), !est.usesFallbackPricing {
                return (est.costUSD, est.pricingModel)
            }
        }
        return nil
    }
}
