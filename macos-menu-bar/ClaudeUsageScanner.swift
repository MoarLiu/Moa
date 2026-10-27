import Foundation

final class ClaudeUsageScanner {
    private struct TokenUsage: Codable, Equatable {
        var input: Int = 0
        var cacheRead: Int = 0
        var cacheCreation: Int = 0
        var output: Int = 0
        var costUSD: Double = 0

        var totalTokens: Int {
            input + cacheRead + cacheCreation + output
        }

        mutating func add(input: Int, cacheRead: Int, cacheCreation: Int, output: Int, costUSD: Double) {
            self.input += input
            self.cacheRead += cacheRead
            self.cacheCreation += cacheCreation
            self.output += output
            self.costUSD += costUSD
        }
    }

    private struct UsageRow: Codable, Equatable {
        let dayKey: String
        let model: String
        let sessionId: String?
        let messageId: String?
        let requestId: String?
        let input: Int
        let cacheRead: Int
        let cacheCreation: Int
        let output: Int
        let costUSD: Double

        var totalTokens: Int {
            input + cacheRead + cacheCreation + output
        }
    }

    private struct CachedFile: Codable, Equatable {
        var mtime: TimeInterval
        var size: Int64
        var rows: [UsageRow]
    }

    private struct Cache: Codable, Equatable {
        var version: Int
        var roots: [String]
        var calendarSignature: String?
        var files: [String: CachedFile]
    }

    private let fileManager = FileManager.default
    private let home: String
    private let environment: [String: String]
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let calendarProvider: () -> Calendar
    private let cacheLock = NSLock()

    #if MOA_TESTING || MOA_TEST_SUPPORT
    var testingBeforeScan: ((URL) throws -> Void)?
    #endif

    private var cacheURL: URL {
        MoaDataRoot.currentURL(environment: environment)
            .appendingPathComponent("claude-usage-cache-v1.json")
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         calendarProvider: @escaping () -> Calendar = { Calendar.current }) {
        home = environment["HOME"] ?? NSHomeDirectory()
        self.environment = environment
        self.calendarProvider = calendarProvider
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
        let projectsRoots = Self.defaultProjectsRoots(home: home, environment: environment)
        let files = sessionFiles(in: projectsRoots)
        let validPaths = Set(files.map(\.path))
        let rootPaths = projectsRoots.map(\.path).sorted()
        let signature = "\(calendar.identifier)|\(calendar.timeZone.identifier)"
        var cache = lockedLoadCache(rootPaths: rootPaths)
        if cache.version != 3 || cache.calendarSignature != signature {
            cache = Cache(version: 3, roots: rootPaths, calendarSignature: signature, files: [:])
        }
        cache.roots = rootPaths
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

            let rows = try parseSessionFile(fileURL, calendar: calendar)
            nextFiles[path] = CachedFile(mtime: metadata.mtime, size: metadata.size, rows: rows)
        }

        cache.files = nextFiles.filter { validPaths.contains($0.key) }
        if persistCache && cache != originalCache {
            lockedSaveCache(cache)
        }
        return report(from: cache, now: now)
    }

    private static func defaultProjectsRoots(home: String, environment: [String: String]) -> [URL] {
        var roots: [URL] = []
        if let raw = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            roots.append(contentsOf: raw.split(separator: ",").compactMap { part in
                let path = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { return nil }
                let url = URL(fileURLWithPath: path).standardizedFileURL
                if url.lastPathComponent == "projects" {
                    return url
                }
                return url.appendingPathComponent("projects", isDirectory: true).standardizedFileURL
            })
        }

        roots.append(contentsOf: [
            URL(fileURLWithPath: "\(home)/.config/claude/projects", isDirectory: true).standardizedFileURL,
            URL(fileURLWithPath: "\(home)/.claude/projects", isDirectory: true).standardizedFileURL
        ])

        let appSupport = URL(fileURLWithPath: "\(home)/Library/Application Support", isDirectory: true)
        for appName in ["Claude", "Claude-3p"] {
            let appRoot = appSupport.appendingPathComponent(appName, isDirectory: true)
            roots.append(contentsOf: discoverNestedProjectRoots(
                under: appRoot.appendingPathComponent("local-agent-mode-sessions", isDirectory: true)))
            roots.append(contentsOf: discoverNestedProjectRoots(
                under: appRoot.appendingPathComponent("claude-code-sessions", isDirectory: true)))
        }

        var seen: Set<String> = []
        return roots.filter { root in
            guard !seen.contains(root.path) else { return false }
            seen.insert(root.path)
            return true
        }
    }

    private static func discoverNestedProjectRoots(under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants])
        else {
            return []
        }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "projects",
                  url.deletingLastPathComponent().lastPathComponent == ".claude",
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else {
                continue
            }
            roots.append(url.standardizedFileURL)
            enumerator.skipDescendants()
        }
        return roots
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

    private func parseSessionFile(_ fileURL: URL, calendar: Calendar) throws -> [UsageRow] {
        var keyedRows: [String: UsageRow] = [:]
        var unkeyedRows: [UsageRow] = []

        #if MOA_TESTING || MOA_TEST_SUPPORT
        try testingBeforeScan?(fileURL)
        #endif
        try scanLines(fileURL: fileURL) { line in
                guard shouldInspect(line) else { return }
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      (object["type"] as? String) == "assistant",
                      let timestamp = object["timestamp"] as? String,
                      let dayKey = Self.dayKey(from: timestamp, calendar: calendar),
                      let message = object["message"] as? [String: Any],
                      let model = message["model"] as? String,
                      model != "<synthetic>",
                      let usage = message["usage"] as? [String: Any]
                else { return }

                let input = max(0, Self.intValue(usage["input_tokens"]))
                let cacheRead = max(0, Self.intValue(usage["cache_read_input_tokens"]))
                let cacheCreation = max(0, Self.intValue(usage["cache_creation_input_tokens"]))
                let output = max(0, Self.intValue(usage["output_tokens"]))
                guard input > 0 || cacheRead > 0 || cacheCreation > 0 || output > 0 else { return }

                let normalizedModel = MoaUsagePricing.normalizeClaudeModel(model)
                let estimate = pricingOverrides.claudeCostEstimate(
                    model: normalizedModel,
                    inputTokens: input,
                    cacheReadInputTokens: cacheRead,
                    cacheCreationInputTokens: cacheCreation,
                    outputTokens: output
                ) ?? MoaUsagePricing.claudeCostEstimate(
                    model: normalizedModel,
                    inputTokens: input,
                    cacheReadInputTokens: cacheRead,
                    cacheCreationInputTokens: cacheCreation,
                    outputTokens: output
                )
                let sessionId = object["sessionId"] as? String
                    ?? object["session_id"] as? String
                    ?? (object["metadata"] as? [String: Any])?["sessionId"] as? String
                    ?? (message["metadata"] as? [String: Any])?["sessionId"] as? String
                let messageId = message["id"] as? String
                let requestId = object["requestId"] as? String
                let row = UsageRow(
                    dayKey: dayKey,
                    model: normalizedModel,
                    sessionId: sessionId,
                    messageId: messageId,
                    requestId: requestId,
                    input: input,
                    cacheRead: cacheRead,
                    cacheCreation: cacheCreation,
                    output: output,
                    costUSD: estimate?.costUSD ?? 0)

                if let key = Self.rowKey(row) {
                    if let existing = keyedRows[key], existing.totalTokens > row.totalTokens {
                        return
                    }
                    keyedRows[key] = row
                } else {
                    unkeyedRows.append(row)
                }
        }

        return keyedRows.keys.sorted().compactMap { keyedRows[$0] } + unkeyedRows
    }

    private func scanLines(fileURL: URL, onLine: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var consumedUntil = buffer.startIndex
            var searchStart = buffer.startIndex
            while searchStart < buffer.endIndex,
                  let newline = buffer[searchStart...].firstIndex(of: 10) {
                var line = buffer.subdata(in: consumedUntil..<newline)
                if line.last == 13 {
                    line.removeLast()
                }
                onLine(line)
                consumedUntil = buffer.index(after: newline)
                searchStart = consumedUntil
            }
            if consumedUntil > buffer.startIndex {
                buffer = buffer.subdata(in: consumedUntil..<buffer.endIndex)
            }
        }

        if !buffer.isEmpty {
            onLine(buffer)
        }
    }

    private func shouldInspect(_ line: Data) -> Bool {
        line.containsASCII(#""usage""#)
    }

    private func report(from cache: Cache, now: Date) -> MoaUsageReport {
        var winners: [String: UsageRow] = [:]
        var unkeyedRows: [UsageRow] = []
        for cachedFile in cache.files.values {
            for row in cachedFile.rows {
                if let key = Self.rowKey(row) {
                    if let existing = winners[key], existing.totalTokens > row.totalTokens {
                        continue
                    }
                    winners[key] = row
                } else {
                    unkeyedRows.append(row)
                }
            }
        }

        var buckets: [String: MoaUsageDetailRow] = [:]
        for usageRow in Array(winners.values) + unkeyedRows {
            let estimate = pricingOverrides.claudeCostEstimate(
                model: usageRow.model,
                inputTokens: usageRow.input,
                cacheReadInputTokens: usageRow.cacheRead,
                cacheCreationInputTokens: usageRow.cacheCreation,
                outputTokens: usageRow.output
            ) ?? MoaUsagePricing.claudeCostEstimate(
                model: usageRow.model,
                inputTokens: usageRow.input,
                cacheReadInputTokens: usageRow.cacheRead,
                cacheCreationInputTokens: usageRow.cacheCreation,
                outputTokens: usageRow.output
            )
            let row = MoaUsageDetailRow(
                source: .claude,
                dayKey: usageRow.dayKey,
                model: estimate?.normalizedModel ?? usageRow.model,
                input: usageRow.input,
                cachedInput: 0,
                cacheReadInput: usageRow.cacheRead,
                cacheCreationInput: usageRow.cacheCreation,
                output: usageRow.output,
                costUSD: estimate?.costUSD ?? usageRow.costUSD,
                pricingModel: estimate?.pricingModel ?? usageRow.model,
                usesFallbackPricing: estimate?.usesFallbackPricing ?? false
            )
            if var existing = buckets[row.id] {
                existing.merge(row)
                buckets[row.id] = existing
            } else {
                buckets[row.id] = row
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

    private func loadCache(rootPaths: [String]) -> Cache {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(Cache.self, from: data)
        else {
            return Cache(version: 3, roots: rootPaths, calendarSignature: nil, files: [:])
        }
        return decoded
    }

    private func lockedLoadCache(rootPaths: [String]) -> Cache {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return loadCache(rootPaths: rootPaths)
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

    private static func rowKey(_ row: UsageRow) -> String? {
        guard let messageId = row.messageId, !messageId.isEmpty else { return nil }
        let session = row.sessionId ?? ""
        let request = row.requestId ?? ""
        return "\(session)|\(messageId)|\(request)"
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

    private static func dayKey(from timestamp: String, calendar: Calendar) -> String? {
        guard let date = CodexUsageDateParser.parse(timestamp) else { return nil }
        return dayKey(from: date, calendar: calendar)
    }

    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
