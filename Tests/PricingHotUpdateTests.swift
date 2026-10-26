import Foundation

#if !MOA_TESTING
@testable import Moa
#endif

enum PricingHotUpdateTests {
    static let tests: [(String, () throws -> Void)] = [
        ("Grok Build aliases and Fast context rates price local usage", grokPrices),
        ("full pricing downloads preserve all records and accept new model IDs", fullCatalog),
        ("pricing commits immediately invalidate independent catalog caches", cacheInvalidation),
        ("manual price updates coalesce and reprice unchanged downloads", manualRefresh),
        ("failed price downloads keep prior catalogs and custom prices", failedDownload),
        ("stopping price updates releases requests and suppresses stale callbacks", stoppedRefresh),
        ("new remote models reprice unchanged WorkBuddy logs without a release", repriceLogs)
    ]
    private struct Failure: Error { let description: String }
    private static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(description: message) }
    }
    private static func close(_ actual: Double?, _ expected: Double, _ message: String) throws {
        try check(abs((actual ?? -1) - expected) < 0.00000001, message)
    }
    private static func withHome(_ body: (URL, [String: String], MoaUsagePricingCatalogStore) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-pricing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        try body(home, environment, MoaUsagePricingCatalogStore(environment: environment))
    }
    private static func fixture() throws -> Data {
        var entries: [String: Any] = [:]
        for index in 0..<5 {
            entries["gpt-hot-\(index)"] = ["litellm_provider": "openai", "mode": "responses", "input_cost_per_token": 2e-6, "output_cost_per_token": 10e-6]
        }
        for index in 0..<3 {
            entries["claude-hot-\(index)"] = ["litellm_provider": "anthropic", "input_cost_per_token": 3e-6, "output_cost_per_token": 15e-6]
        }
        entries["glm-hot"] = ["litellm_provider": "zhipu", "input_cost_per_token": 1e-6, "output_cost_per_token": 4e-6]
        entries["new-lab/future-build"] = ["litellm_provider": "new-lab", "mode": "chat", "input_cost_per_token": 1.1e-6, "output_cost_per_token": 7e-6]
        entries["future-image"] = ["litellm_provider": "new-lab", "mode": "image_generation", "output_cost_per_image": 0.1, "unknown_future_field": ["quality": "high"]]
        entries["regional-cny"] = ["litellm_provider": "new-lab", "currency": "CNY", "input_cost_per_token": 1e-6, "output_cost_per_token": 7e-6]
        return try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
    }
    private static func parsed(_ data: Data, date: Date = Date()) throws -> MoaUsagePricingCatalogSnapshot {
        try MoaUsagePricingRemoteParser.parse(data: data, sourceURL: MoaUsagePricingUpdater.defaultSourceURL, fetchedAt: date)
    }

    private static func grokPrices() throws {
        try withHome { home, environment, store in
            MoaUsagePricing.useRemoteCatalogStoreForTesting(store)
            defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
            let standard = MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build", store: store)
            let fast = MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build-fast", store: store)
            try close(standard?.inputUSDPerMillion, 2, "Build must resolve the standard Grok price")
            try close(standard?.outputUSDPerMillion, 6, "Build output must have a price")
            try close(fast?.inputUSDPerMillion, 4, "Fast short input is 2x")
            try close(fast?.outputUSDPerMillion, 12, "Fast short output is 2x")
            try close(fast?.cacheReadUSDPerMillion, 1, "Fast cache reads have their own rate")
            try close(fast?.inputUSDPerMillionAboveThreshold, 6, "Fast long input is 1.5x long standard")
            try close(fast?.outputUSDPerMillionAboveThreshold, 18, "Fast long output is 1.5x long standard")
            try close(fast?.cacheReadUSDPerMillionAboveThreshold, 1.5, "Fast long cache rate must be retained")
            try check(fast?.usesLongContext(promptTokens: 199999) == false && fast?.usesLongContext(promptTokens: 200000) == true, "Grok long-context rates begin at exactly 200K")
            try close(MoaUsagePricing.codexCostEstimate(model: "grok-4.7-build-fast", inputTokens: 200000, cachedInputTokens: 0, outputTokens: 0)?.costUSD, 1.2, "other client scanners must retain Grok's inclusive 200K boundary")
            try close(MoaUsagePricing.catalogPricing(source: .codex, model: "x-ai/grok-4.7-build-fast", store: store)?.inputUSDPerMillion, 4, "vendor prefixes and other client sources must share prices")
            let log = home.appendingPathComponent(".workbuddy-ai/projects/grok-build.jsonl")
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            let rows: [[String: Any]] = [
                ["id": "standard", "model": "grok-4.7-build", "timestamp": Date().timeIntervalSince1970 * 1000, "usage": ["input_tokens": 1000, "cache_read_input_tokens": 100, "output_tokens": 100]],
                ["id": "fast-short", "model": "grok-4.7-build-fast", "timestamp": Date().timeIntervalSince1970 * 1000, "usage": ["input_tokens": 1000, "cache_read_input_tokens": 100, "output_tokens": 100]],
                ["id": "fast-long", "model": "grok-4.7-build-fast", "timestamp": Date().timeIntervalSince1970 * 1000, "usage": ["input_tokens": 200000, "cache_read_input_tokens": 100000, "output_tokens": 100]]
            ]
            let lines = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: log)
            let scanner = WorkBuddyUsageScanner(environment: environment)
            let report = try scanner.loadReport()
            try close(report.rows.first { $0.model == "grok-4.7-build" }?.costUSD, 0.00245, "actual Build log names must receive their standard prices")
            try close(report.rows.first { $0.model == "grok-4.7-build-fast" }?.costUSD, 0.7567, "Fast logs must price each request's context tier before aggregation")
            var newer = standard!
            newer.inputUSDPerMillion = 3
            newer.inputUSDPerMillionAboveThreshold = 6
            _ = try store.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date(), models: ["all": ["grok-4.7": newer]]))
            try close(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build-fast", store: store)?.inputUSDPerMillion, 6, "derived Fast rates must follow a hot-updated standard price")
            let exact = MoaUsageRemotePricing(inputUSDPerMillion: 7, outputUSDPerMillion: 21)
            _ = try store.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date(), models: ["all": ["grok-4.7-build-fast": exact, "grok-4.7-build": exact]]))
            try close(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build-fast", store: store)?.inputUSDPerMillion, 7, "an explicit remote Fast SKU must replace derived rates")
            try close(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build", store: store)?.inputUSDPerMillion, 7, "an exact remote Build ID must win over its alias")
            try close(try scanner.loadReport().rows.first { $0.model == "grok-4.7-build" }?.costUSD, 0.0091, "the scanner must preserve an exact remote Build SKU rather than erase it during alias normalization")
        }
    }

    private static func fullCatalog() throws {
        let data = try fixture()
        let snapshot = try parsed(data)
        try check(snapshot.rawCatalog == data && snapshot.modelCount == 12, "the complete source must survive without dropping unsupported pricing records")
        try close(snapshot.models["all"]?["new-lab/future-build"]?.inputUSDPerMillion, 1.1, "new vendors and qualified model IDs must import without a release")
        try check(snapshot.models["all"]?["future-image"] == nil && snapshot.models["all"]?["regional-cny"] == nil, "non-token and non-USD prices must not be treated as USD/token")
        try withHome { _, environment, store in
            _ = try store.merge(snapshot)
            let restarted = MoaUsagePricingCatalogStore(environment: environment)
            try check(restarted.snapshot()?.rawCatalog == data, "a restart must retain the full downloaded table")
            try close(MoaUsagePricing.catalogPricing(source: .claude, model: "new-lab/future-build", store: restarted)?.outputUSDPerMillion, 7, "new token prices must be shared across clients")
        }
    }

    private static func cacheInvalidation() throws {
        try withHome { _, environment, writer in
            let reader = MoaUsagePricingCatalogStore(environment: environment)
            let old = MoaUsageRemotePricing(inputUSDPerMillion: 2, outputUSDPerMillion: 10, cacheReadUSDPerMillion: 0.2, thresholdTokens: 200000, inputUSDPerMillionAboveThreshold: 4)
            _ = try writer.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date().addingTimeInterval(-10), models: ["all": ["gpt-hot": old]]))
            try close(reader.pricing(source: .codex, model: "gpt-hot")?.inputUSDPerMillion, 2, "prime an independent scanner cache")
            let fresh = MoaUsageRemotePricing(inputUSDPerMillion: 3, outputUSDPerMillion: 15)
            _ = try writer.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date(), models: ["all": ["gpt-hot": fresh]]))
            try close(reader.pricing(source: .codex, model: "gpt-hot")?.inputUSDPerMillion, 3, "committed prices must invalidate other stores immediately")
            try check(reader.pricing(source: .codex, model: "gpt-hot")?.thresholdTokens == nil, "a newer full record must remove obsolete context tiers")
        }
    }

    private static func pump(_ predicate: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return predicate()
    }
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PricingProtocol.self]
        return URLSession(configuration: config)
    }
    private static func manualRefresh() throws {
        try withHome { _, _, store in
            let data = try fixture()
            _ = try store.merge(parsed(data, date: Date().addingTimeInterval(-10)))
            try store.recordSuccessfulCheck(at: Date())
            PricingProtocol.reset(data: data, delay: 0.05)
            let session = session()
            defer { session.invalidateAndCancel() }
            let coordinator = MoaUsagePricingUpdateCoordinator(updater: .init(store: store, session: session))
            defer { coordinator.stop() }
            var updates = 0
            var callbacks = 0
            var successes = 0
            var states: [Bool] = []
            coordinator.onCatalogUpdated = { updates += 1 }
            coordinator.onRefreshStateChanged = { states.append($0) }
            coordinator.start()
            for _ in 0..<2 {
                coordinator.refreshNow { result in callbacks += 1; if case .success(.unchanged) = result { successes += 1 } }
            }
            try check(coordinator.isRefreshing, "manual refresh must report progress immediately")
            try check(pump { callbacks == 2 }, "all coalesced manual requests must finish")
            try check(PricingProtocol.requestCount == 1 && successes == 2, "one full download must serve repeated clicks")
            try check(updates == 1 && states == [true, false] && !coordinator.isRefreshing, "same-price successful checks must reprice and release progress")
            try check(coordinator.modelCount == 12, "manual success must report the full remote model count")
        }
    }

    private final class Outcome: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: Result<MoaUsagePricingCatalogUpdate, Error>?
        func set(_ value: Result<MoaUsagePricingCatalogUpdate, Error>) { lock.lock(); self.value = value; lock.unlock(); done.signal() }
        func get() -> Result<MoaUsagePricingCatalogUpdate, Error>? { lock.lock(); defer { lock.unlock() }; return value }
    }
    private static func failedDownload() throws {
        try withHome { home, environment, store in
            let data = try fixture()
            let session = session()
            defer { session.invalidateAndCancel() }
            let updater = MoaUsagePricingUpdater(store: store, session: session)
            PricingProtocol.reset(data: data)
            let initial = Outcome()
            updater.refresh { initial.set($0) }
            try check(initial.done.wait(timeout: .now() + 5) == .success, "initial full download timed out")
            if case .failure = initial.get() { throw Failure(description: "initial download failed") }
            let path = home.appendingPathComponent(".moa/usage-pricing-catalog-v1.json")
            let previous = try Data(contentsOf: path)
            let overrides = MoaUsagePricingOverrideController(environment: environment)
            try overrides.upsert(source: .workbuddy, model: "gpt-hot-0", inputUSDPerMillion: 8, outputUSDPerMillion: 16, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            for (status, body) in [(500, data), (200, Data("invalid json".utf8)), (200, Data(#"{"one":{"input_cost_per_token":1,"output_cost_per_token":1,"litellm_provider":"openai"}}"#.utf8)), (200, Data(repeating: 32, count: 8 * 1024 * 1024 + 1))] {
                PricingProtocol.reset(data: body, status: status)
                let outcome = Outcome()
                updater.refresh { outcome.set($0) }
                try check(outcome.done.wait(timeout: .now() + 5) == .success, "failed download must complete")
                guard case .failure = outcome.get() else { throw Failure(description: "invalid download was accepted") }
                try check(try Data(contentsOf: path) == previous, "failed downloads must retain the previous complete catalog")
                try close(overrides.override(source: .workbuddy, model: "gpt-hot-0")?.inputUSDPerMillion, 8, "remote updates must not alter custom prices")
            }
        }
    }

    private static func stoppedRefresh() throws {
        try withHome { _, _, store in
            let data = try fixture()
            _ = try store.merge(parsed(data))
            try store.recordSuccessfulCheck(at: Date())
            PricingProtocol.reset(data: data, delay: 0.3)
            let session = session()
            defer { session.invalidateAndCancel() }
            let coordinator = MoaUsagePricingUpdateCoordinator(updater: .init(store: store, session: session))
            coordinator.start()
            var released = false
            coordinator.refreshNow { if case .failure = $0 { released = true } }
            coordinator.stop()
            try check(released && !coordinator.isRefreshing, "stop must finish pending manual requests")
            PricingProtocol.reset(data: data)
            var finished = false
            var updates = 0
            coordinator.onCatalogUpdated = { updates += 1 }
            coordinator.start()
            coordinator.refreshNow { if case .success = $0 { finished = true } }
            try check(pump { finished }, "a restarted updater must accept a new manual request")
            try check(updates == 1 && !coordinator.isRefreshing, "old canceled callbacks must not complete or reset the restarted operation")
            coordinator.stop()
        }
    }

    private static func repriceLogs() throws {
        try withHome { home, environment, store in
            let file = home.appendingPathComponent(".workbuddy-ai/projects/pricing.jsonl")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let record: [String: Any] = ["id": "unchanged-log", "timestamp": Date().timeIntervalSince1970 * 1000, "model": "future-hot-model", "usage": ["input_tokens": 1000, "output_tokens": 100]]
            let original = try JSONSerialization.data(withJSONObject: record)
            try original.write(to: file)
            let scanner = WorkBuddyUsageScanner(environment: environment)
            try check(try scanner.loadReport().rows.first?.pricingModel == "unpriced", "new model starts without a known price")
            _ = try store.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date(), models: ["all": ["future-hot-model": .init(inputUSDPerMillion: 2, outputUSDPerMillion: 10)]]))
            try close(try scanner.loadReport().rows.first?.costUSD, 0.003, "an unchanged log must immediately use newly downloaded prices")
            let overrides = MoaUsagePricingOverrideController(environment: environment)
            try overrides.upsert(source: .workbuddy, model: "future-hot-model", inputUSDPerMillion: 5, outputUSDPerMillion: 6, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            _ = try store.merge(.init(sourceURL: "https://example.invalid/prices", fetchedAt: Date(), models: ["all": ["future-hot-model": .init(inputUSDPerMillion: 99, outputUSDPerMillion: 99)]]))
            try close(try scanner.loadReport().rows.first?.costUSD, 0.0056, "custom prices must retain precedence after a hot update")
            try check(try Data(contentsOf: file) == original, "repricing must never rewrite the original usage log")
        }
    }
}

private final class PricingProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var data = Data()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var delay: TimeInterval = 0
    nonisolated(unsafe) private static var count = 0
    private let stateLock = NSLock()
    private var canceled = false
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset(data: Data, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        self.data = data; self.status = status; self.delay = delay; count = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let (data, status, delay) = (Self.data, Self.status, Self.delay)
        Self.count += 1
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self.stateLock.lock(); let canceled = self.canceled; self.stateLock.unlock()
            guard !canceled else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); canceled = true; stateLock.unlock() }
}
