import Foundation

struct MoaUsageRemotePricing: Codable, Equatable, Sendable {
    var inputUSDPerMillion: Double
    var outputUSDPerMillion: Double
    var cacheReadUSDPerMillion: Double?
    var cacheCreationUSDPerMillion: Double?
    var thresholdTokens: Int?
    var inputUSDPerMillionAboveThreshold: Double?
    var outputUSDPerMillionAboveThreshold: Double?
    var cacheReadUSDPerMillionAboveThreshold: Double?
    var cacheCreationUSDPerMillionAboveThreshold: Double?
    var priorityInputUSDPerMillion: Double? = nil
    var priorityOutputUSDPerMillion: Double? = nil
    var priorityCacheReadUSDPerMillion: Double? = nil
    var priorityCacheCreationUSDPerMillion: Double? = nil
    var priorityInputUSDPerMillionAboveThreshold: Double? = nil
    var priorityOutputUSDPerMillionAboveThreshold: Double? = nil
    var priorityCacheReadUSDPerMillionAboveThreshold: Double? = nil
    var priorityCacheCreationUSDPerMillionAboveThreshold: Double? = nil
    var thresholdInclusive: Bool? = nil

    func usesLongContext(promptTokens: Int) -> Bool {
        guard let thresholdTokens else { return false }
        return thresholdInclusive == true ? promptTokens >= thresholdTokens : promptTokens > thresholdTokens
    }

    func mergingMissingFields(from existing: Self) -> Self {
        Self(
            inputUSDPerMillion: inputUSDPerMillion,
            outputUSDPerMillion: outputUSDPerMillion,
            cacheReadUSDPerMillion: cacheReadUSDPerMillion ?? existing.cacheReadUSDPerMillion,
            cacheCreationUSDPerMillion: cacheCreationUSDPerMillion ?? existing.cacheCreationUSDPerMillion,
            thresholdTokens: thresholdTokens ?? existing.thresholdTokens,
            inputUSDPerMillionAboveThreshold: inputUSDPerMillionAboveThreshold ?? existing.inputUSDPerMillionAboveThreshold,
            outputUSDPerMillionAboveThreshold: outputUSDPerMillionAboveThreshold ?? existing.outputUSDPerMillionAboveThreshold,
            cacheReadUSDPerMillionAboveThreshold: cacheReadUSDPerMillionAboveThreshold ?? existing.cacheReadUSDPerMillionAboveThreshold,
            cacheCreationUSDPerMillionAboveThreshold: cacheCreationUSDPerMillionAboveThreshold ?? existing.cacheCreationUSDPerMillionAboveThreshold,
            priorityInputUSDPerMillion: priorityInputUSDPerMillion ?? existing.priorityInputUSDPerMillion,
            priorityOutputUSDPerMillion: priorityOutputUSDPerMillion ?? existing.priorityOutputUSDPerMillion,
            priorityCacheReadUSDPerMillion: priorityCacheReadUSDPerMillion ?? existing.priorityCacheReadUSDPerMillion,
            priorityCacheCreationUSDPerMillion: priorityCacheCreationUSDPerMillion ?? existing.priorityCacheCreationUSDPerMillion,
            priorityInputUSDPerMillionAboveThreshold: priorityInputUSDPerMillionAboveThreshold ?? existing.priorityInputUSDPerMillionAboveThreshold,
            priorityOutputUSDPerMillionAboveThreshold: priorityOutputUSDPerMillionAboveThreshold ?? existing.priorityOutputUSDPerMillionAboveThreshold,
            priorityCacheReadUSDPerMillionAboveThreshold: priorityCacheReadUSDPerMillionAboveThreshold ?? existing.priorityCacheReadUSDPerMillionAboveThreshold,
            priorityCacheCreationUSDPerMillionAboveThreshold: priorityCacheCreationUSDPerMillionAboveThreshold ?? existing.priorityCacheCreationUSDPerMillionAboveThreshold,
            thresholdInclusive: thresholdInclusive ?? existing.thresholdInclusive
        )
    }
}

struct MoaUsagePricingCatalogSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var sourceURL: String
    var fetchedAt: Date
    var models: [String: [String: MoaUsageRemotePricing]]
    var modelFetchedAt: [String: [String: Date]]?
    // Preserve the complete upstream table, including non-token pricing fields
    // which current usage scanners do not consume. This travels atomically with
    // the validated token-price projection, never as a partially updated sidecar.
    var rawCatalog: Data?
    var downloadedModelCount: Int?

    var modelCount: Int {
        downloadedModelCount ?? Set(models.values.flatMap { $0.keys }).count
    }

    init(
        sourceURL: String,
        fetchedAt: Date,
        models: [String: [String: MoaUsageRemotePricing]],
        modelFetchedAt: [String: [String: Date]]? = nil,
        rawCatalog: Data? = nil,
        downloadedModelCount: Int? = nil
    ) {
        version = Self.currentVersion
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.models = models
        self.modelFetchedAt = modelFetchedAt ?? models.mapValues { $0.mapValues { _ in fetchedAt } }
        self.rawCatalog = rawCatalog
        self.downloadedModelCount = downloadedModelCount
    }
}

enum MoaUsagePricingCatalogUpdate: Equatable, Sendable {
    case unchanged
    case updated(added: Int, changed: Int)

    var didUpdate: Bool {
        if case .updated = self { return true }
        return false
    }
}

final class MoaUsagePricingCatalogStore: @unchecked Sendable {
    static let shared = MoaUsagePricingCatalogStore()
    static let didUpdate = Notification.Name("MoaUsagePricingCatalogDidUpdate")

    private struct UpdateState: Codable {
        var lastSuccessfulCheck: Date
    }

    private let environment: [String: String]
    private let dataAccess: MoaDataStoreLock
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var cachedSnapshot: MoaUsagePricingCatalogSnapshot?
    private var cachedURL: URL?
    private var cachedModifiedAt: Date?
    private var lastFileCheckAt: Date?
    private var cachedRevision: UInt64?
    private var updateObserver: NSObjectProtocol?

    private var catalogURL: URL {
        MoaDataRoot.currentURL(environment: environment)
            .appendingPathComponent("usage-pricing-catalog-v1.json")
    }

    private var stateURL: URL {
        // Check cadence is device-local so an iCloud state-file race cannot make one Mac
        // skip a refresh before the shared catalog has finished downloading on that device.
        MoaDataRoot.supportDirectory(environment: environment)
            .appendingPathComponent("usage-pricing-update-state.json")
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        dataAccess = MoaDataStoreLock(environment: environment)
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        updateObserver = NotificationCenter.default.addObserver(forName: Self.didUpdate, object: nil, queue: nil) { [weak self] notification in
            guard let self, let url = notification.object as? URL,
                  url.standardizedFileURL == self.catalogURL.standardizedFileURL else { return }
            self.lock.lock()
            self.cachedSnapshot = nil
            self.cachedURL = nil
            self.lastFileCheckAt = nil
            self.lock.unlock()
        }
    }

    deinit { if let updateObserver { NotificationCenter.default.removeObserver(updateObserver) } }

    func pricing(source: MoaUsageSource, model: String, notBefore: Date? = nil) -> MoaUsageRemotePricing? {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot = loadSnapshotIfNeeded() else { return nil }
        let key = model.lowercased()
        return [source.rawValue, "all"].compactMap { group -> (MoaUsageRemotePricing, Date)? in
            guard let price = snapshot.models[group]?[key] else { return nil }
            let checkedAt = snapshot.modelFetchedAt?[group]?[key] ?? snapshot.fetchedAt
            guard notBefore.map({ checkedAt >= $0 }) ?? true else { return nil }
            return (price, checkedAt)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    func snapshot() -> MoaUsagePricingCatalogSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return loadSnapshotIfNeeded()
    }

    func merge(_ remote: MoaUsagePricingCatalogSnapshot) throws -> MoaUsagePricingCatalogUpdate {
        try dataAccess.lock()
        lock.lock()
        var writtenURL: URL?
        defer {
            lock.unlock()
            dataAccess.unlock()
            if let writtenURL { NotificationCenter.default.post(name: Self.didUpdate, object: writtenURL) }
        }

        // Read the current catalog under the store lock before writing. A
        // transient read or decode failure must never turn a merge into a
        // replacement that silently discards the existing models.
        let current = try readSnapshot(at: catalogURL)
        var mergedModels = current?.models ?? [:]
        var modelDates = current?.modelFetchedAt
            ?? current?.models.mapValues { $0.mapValues { _ in current?.fetchedAt ?? .distantPast } } ?? [:]
        var freshnessChanged = false
        var added = 0
        var changed = 0

        for (source, models) in remote.models {
            var mergedSource = mergedModels[source] ?? [:]
            for (model, pricing) in models {
                // Only models actually present in this response become fresh;
                // omitted entries retain their previous verification date.
                let previousDate = modelDates[source]?[model] ?? .distantPast
                guard remote.fetchedAt >= previousDate else { continue }
                if remote.fetchedAt > previousDate {
                    modelDates[source, default: [:]][model] = remote.fetchedAt
                    freshnessChanged = true
                }
                if let existing = mergedSource[model] {
                    // A newer full download is authoritative for each present
                    // model. Equal-date partial imports retain legacy merge behavior.
                    let mergedPricing = remote.fetchedAt > previousDate ? pricing : pricing.mergingMissingFields(from: existing)
                    if existing != mergedPricing {
                        mergedSource[model] = mergedPricing
                        changed += 1
                    }
                } else {
                    mergedSource[model] = pricing
                    added += 1
                }
            }
            mergedModels[source] = mergedSource
        }

        let rawChanged = remote.rawCatalog.map { $0 != current?.rawCatalog } ?? false
        guard added > 0 || changed > 0 || freshnessChanged || rawChanged else {
            return .unchanged
        }

        let merged = MoaUsagePricingCatalogSnapshot(
            sourceURL: remote.sourceURL,
            fetchedAt: max(remote.fetchedAt, current?.fetchedAt ?? .distantPast),
            models: mergedModels,
            modelFetchedAt: modelDates,
            rawCatalog: remote.rawCatalog ?? current?.rawCatalog,
            downloadedModelCount: remote.downloadedModelCount ?? current?.downloadedModelCount
        )
        try write(merged, to: catalogURL)
        cachedSnapshot = merged
        cachedURL = catalogURL
        cachedModifiedAt = modificationDate(of: catalogURL)
        lastFileCheckAt = Date()
        cachedRevision = dataAccess.revision
        writtenURL = catalogURL
        return added > 0 || changed > 0 ? .updated(added: added, changed: changed) : .unchanged
    }

    func lastSuccessfulCheck() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(UpdateState.self, from: data)
        else {
            return nil
        }
        return state.lastSuccessfulCheck
    }

    func recordSuccessfulCheck(at date: Date) throws {
        try dataAccess.lock()
        defer { dataAccess.unlock() }
        lock.lock()
        defer { lock.unlock() }
        try write(UpdateState(lastSuccessfulCheck: date), to: stateURL)
    }

    private func loadSnapshotIfNeeded(now: Date = Date()) -> MoaUsagePricingCatalogSnapshot? {
        if dataAccess.isBusy { return cachedSnapshot }
        if cachedRevision != dataAccess.revision {
            cachedSnapshot = nil
            cachedURL = nil
            lastFileCheckAt = nil
            cachedModifiedAt = nil
            cachedRevision = dataAccess.revision
        }
        let url = catalogURL
        if cachedURL == url,
           let lastFileCheckAt,
           now.timeIntervalSince(lastFileCheckAt) < 60
        {
            return cachedSnapshot
        }

        let modifiedAt = modificationDate(of: url)
        if cachedURL == url, cachedModifiedAt == modifiedAt, cachedSnapshot != nil {
            lastFileCheckAt = now
            return cachedSnapshot
        }

        do {
            let snapshot = try readSnapshot(at: url)
            cachedURL = url
            cachedModifiedAt = modifiedAt
            lastFileCheckAt = now
            cachedSnapshot = snapshot
            return snapshot
        } catch {
            // Retry on the next lookup, including when permissions change
            // without updating the file's modification date.
            lastFileCheckAt = nil
            return cachedURL == url ? cachedSnapshot : nil
        }
    }

    private func readSnapshot(at url: URL) throws -> MoaUsagePricingCatalogSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        let snapshot = try decoder.decode(MoaUsagePricingCatalogSnapshot.self, from: data)
        guard snapshot.version == MoaUsagePricingCatalogSnapshot.currentVersion else {
            throw NSError(domain: "MoaPricingCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: MoaL10n.text("The saved pricing catalog has an unsupported version.")])
        }
        return snapshot
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum MoaUsagePricingRemoteParser {
    enum ParseError: LocalizedError {
        case invalidCatalog

        var errorDescription: String? {
            MoaL10n.text("The remote model pricing catalog is incomplete or invalid.")
        }
    }

    private struct Provider: Decodable {
        var models: [String: Model]
    }

    private struct Model: Decodable {
        var cost: Cost?
    }

    private struct Cost: Decodable {
        var input: Double?
        var output: Double?
        var cacheRead: Double?
        var cacheWrite: Double?
        var tiers: [Tier]?
        var contextOver200K: ThresholdCost?

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
            case tiers
            case contextOver200K = "context_over_200k"
        }
    }

    private struct Tier: Decodable {
        var input: Double?
        var output: Double?
        var cacheRead: Double?
        var cacheWrite: Double?
        var tier: TierDescriptor?

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
            case tier
        }
    }

    private struct TierDescriptor: Decodable {
        var type: String?
        var size: Int?
    }

    private struct ThresholdCost: Decodable {
        var input: Double?
        var output: Double?
        var cacheRead: Double?
        var cacheWrite: Double?

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    static func parse(data: Data, sourceURL: URL, fetchedAt: Date) throws -> MoaUsagePricingCatalogSnapshot {
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           object.values.contains(where: { ($0 as? [String: Any])?["input_cost_per_token"] != nil }) {
            var snapshot = try MoaSub2APIPricingParser.parse(object, sourceURL: sourceURL, fetchedAt: fetchedAt)
            snapshot.rawCatalog = data
            return snapshot
        }
        let providers = try JSONDecoder().decode([String: Provider].self, from: data)
        let mappings: [(provider: String, source: MoaUsageSource)] = [
            ("openai", .codex),
            ("anthropic", .claude),
            ("zai", .zcode),
            ("openai", .workbuddy),
            ("anthropic", .workbuddy),
            ("deepseek", .workbuddy),
            ("zai", .workbuddy),
            ("moonshotai", .workbuddy),
            ("minimax", .workbuddy),
            ("google", .workbuddy),
            ("xai", .workbuddy)
        ]
        var result: [String: [String: MoaUsageRemotePricing]] = [:]

        for mapping in mappings {
            guard let provider = providers[mapping.provider] else { continue }
            var prices: [String: MoaUsageRemotePricing] = [:]
            for (modelID, model) in provider.models {
                guard let cost = model.cost,
                      let input = validated(cost.input),
                      let output = validated(cost.output)
                else {
                    continue
                }

                let tier = cost.tiers?
                    .filter { $0.tier?.type == "context" && ($0.tier?.size ?? 0) > 0 }
                    .sorted { ($0.tier?.size ?? .max) < ($1.tier?.size ?? .max) }
                    .first
                let threshold = tier?.tier?.size ?? (cost.contextOver200K == nil ? nil : 200_000)
                let thresholdCost = tier.map {
                    ThresholdCost(input: $0.input, output: $0.output, cacheRead: $0.cacheRead, cacheWrite: $0.cacheWrite)
                } ?? cost.contextOver200K

                prices[modelID.lowercased()] = MoaUsageRemotePricing(
                    inputUSDPerMillion: input,
                    outputUSDPerMillion: output,
                    cacheReadUSDPerMillion: validated(cost.cacheRead),
                    cacheCreationUSDPerMillion: validated(cost.cacheWrite),
                    thresholdTokens: threshold,
                    inputUSDPerMillionAboveThreshold: validated(thresholdCost?.input),
                    outputUSDPerMillionAboveThreshold: validated(thresholdCost?.output),
                    cacheReadUSDPerMillionAboveThreshold: validated(thresholdCost?.cacheRead),
                    cacheCreationUSDPerMillionAboveThreshold: validated(thresholdCost?.cacheWrite)
                )
            }
            if !prices.isEmpty {
                result[mapping.source.rawValue, default: [:]].merge(prices) { existing, _ in existing }
            }
        }

        guard (result[MoaUsageSource.codex.rawValue]?.count ?? 0) >= 5,
              (result[MoaUsageSource.claude.rawValue]?.count ?? 0) >= 3,
              (result[MoaUsageSource.zcode.rawValue]?.count ?? 0) >= 1
        else {
            throw ParseError.invalidCatalog
        }

        return MoaUsagePricingCatalogSnapshot(
            sourceURL: sourceURL.absoluteString,
            fetchedAt: fetchedAt,
            models: result,
            rawCatalog: data,
            downloadedModelCount: providers.values.reduce(0) { $0 + $1.models.count }
        )
    }

    private static func validated(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

final class MoaUsagePricingUpdater: Sendable {
    enum UpdateError: LocalizedError {
        case invalidResponse
        case payloadTooLarge
        case stopped

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return MoaL10n.text("The model pricing server returned an invalid response.")
            case .payloadTooLarge:
                return MoaL10n.text("The model pricing response exceeded the allowed size.")
            case .stopped:
                return MoaL10n.text("The model pricing update was canceled.")
            }
        }
    }

    static let defaultSourceURL = URL(string: "https://raw.githubusercontent.com/Wei-Shaw/model-price-repo/main/model_prices_and_context_window.json")!
    private static let maximumPayloadBytes = 8 * 1024 * 1024

    let store: MoaUsagePricingCatalogStore
    let sourceURL: URL
    private let session: URLSession

    init(
        store: MoaUsagePricingCatalogStore = .shared,
        sourceURL: URL = MoaUsagePricingUpdater.defaultSourceURL,
        session: URLSession = .shared
    ) {
        self.store = store
        self.sourceURL = sourceURL
        self.session = session
    }

    @discardableResult
    func refresh(completion: @escaping (Result<MoaUsagePricingCatalogUpdate, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request) { data, response, error in
            let result = Result<MoaUsagePricingCatalogUpdate, Error> {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data
                else {
                    throw UpdateError.invalidResponse
                }
                guard data.count <= Self.maximumPayloadBytes else {
                    throw UpdateError.payloadTooLarge
                }
                let checkedAt = Date()
                let snapshot = try MoaUsagePricingRemoteParser.parse(
                    data: data,
                    sourceURL: self.sourceURL,
                    fetchedAt: checkedAt
                )
                let update = try self.store.merge(snapshot)
                // The catalog has committed successfully. A device-local cadence
                // write failure must not report that successful download as failed.
                do { try self.store.recordSuccessfulCheck(at: checkedAt) }
                catch { NSLog("Moa could not save the pricing check schedule: \(error.localizedDescription)") }
                return update
            }
            completion(result)
        }
        task.resume()
        return task
    }
}

final class MoaUsagePricingUpdateCoordinator {
    var onCatalogUpdated: (() -> Void)?
    var onRefreshStateChanged: ((Bool) -> Void)?
    var isRefreshing: Bool { refreshInFlight }

    private let updater: MoaUsagePricingUpdater
    private let notificationCenter: NotificationCenter
    private var calendar: Calendar
    private var timer: Timer?
    private var timeZoneObserver: NSObjectProtocol?
    private var started = false
    private var refreshInFlight = false
    private var refreshGeneration = UUID()
    private var task: URLSessionDataTask?
    private var completions: [(Result<MoaUsagePricingCatalogUpdate, Error>) -> Void] = []

    init(
        updater: MoaUsagePricingUpdater = MoaUsagePricingUpdater(),
        calendar: Calendar = .autoupdatingCurrent,
        notificationCenter: NotificationCenter = .default
    ) {
        self.updater = updater
        self.calendar = calendar
        self.notificationCenter = notificationCenter
    }

    deinit {
        timer?.invalidate()
        if let timeZoneObserver {
            notificationCenter.removeObserver(timeZoneObserver)
        }
    }

    func start(now: Date = Date()) {
        guard !started else { return }
        started = true
        timeZoneObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.started else { return }
            let now = Date()
            self.refreshIfNeeded(now: now)
            self.scheduleNextCheck(after: now)
        }
        refreshIfNeeded(now: now)
        scheduleNextCheck(after: now)
    }

    func stop() {
        started = false
        refreshGeneration = UUID()
        task?.cancel()
        task = nil
        refreshInFlight = false
        let callbacks = completions
        completions.removeAll()
        onRefreshStateChanged?(false)
        callbacks.forEach { $0(.failure(MoaUsagePricingUpdater.UpdateError.stopped)) }
        timer?.invalidate()
        timer = nil
        if let timeZoneObserver {
            notificationCenter.removeObserver(timeZoneObserver)
            self.timeZoneObserver = nil
        }
        onCatalogUpdated = nil
    }

    /// Manual requests bypass the daily cadence, sharing any active download.
    func refreshNow(completion: @escaping (Result<MoaUsagePricingCatalogUpdate, Error>) -> Void) {
        guard started else { completion(.failure(MoaUsagePricingUpdater.UpdateError.stopped)); return }
        completions.append(completion)
        refresh()
    }

    var modelCount: Int { updater.store.snapshot()?.modelCount ?? 0 }

    static func shouldCheck(
        now: Date,
        lastSuccessfulCheck: Date?,
        calendar: Calendar
    ) -> Bool {
        if let lastSuccessfulCheck, calendar.isDate(lastSuccessfulCheck, inSameDayAs: now) {
            return false
        }
        return now >= scheduledDate(onDayContaining: now, calendar: calendar)
    }

    static func nextScheduledDate(after date: Date, calendar: Calendar) -> Date {
        let today = scheduledDate(onDayContaining: date, calendar: calendar)
        if today > date { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? date.addingTimeInterval(86_400)
    }

    private static func scheduledDate(onDayContaining date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
        components.hour = 0
        components.minute = 20
        components.second = 1
        return calendar.date(from: components) ?? date
    }

    private func refreshIfNeeded(now: Date) {
        if let snapshot = updater.store.snapshot(), snapshot.sourceURL != updater.sourceURL.absoluteString {
            refresh()
            return
        }
        let lastSuccessfulCheck = updater.store.snapshot() == nil
            ? nil
            : updater.store.lastSuccessfulCheck()
        guard Self.shouldCheck(
            now: now,
            lastSuccessfulCheck: lastSuccessfulCheck,
            calendar: calendar
        ) else {
            return
        }
        refresh()
    }

    private func refresh() {
        guard started, !refreshInFlight else { return }
        refreshInFlight = true
        onRefreshStateChanged?(true)
        let generation = UUID()
        refreshGeneration = generation
        task = updater.refresh { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                let callbacks = self.completions
                self.completions.removeAll()
                self.refreshInFlight = false
                self.task = nil
                self.onRefreshStateChanged?(false)
                guard self.started else { return }
                switch result {
                case .success(let update):
                    if case .updated(let added, let changed) = update {
                        NSLog("Moa model pricing updated: %d added, %d changed", added, changed)
                    }
                    // A same-price download may make a formerly stale entry
                    // eligible again; successful checks always reprice reports.
                    self.onCatalogUpdated?()
                case .failure(let error):
                    NSLog("Moa model pricing update failed: \(error.localizedDescription)")
                }
                callbacks.forEach { $0(result) }
            }
        }
    }

    private func scheduleNextCheck(after date: Date) {
        timer?.invalidate()
        let next = Self.nextScheduledDate(after: date, calendar: calendar)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.refreshIfNeeded(now: Date())
            self.scheduleNextCheck(after: Date())
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
