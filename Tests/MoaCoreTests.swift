import Foundation

#if !MOA_TESTING
@testable import Moa
#endif

private enum TestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            return message
        }
    }
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else {
        throw TestError.failure(message)
    }
}

private func expectClose(_ actual: Double, _ expected: Double, _ message: String, tolerance: Double = 0.000001) throws {
    guard abs(actual - expected) <= tolerance else {
        throw TestError.failure("\(message): expected \(expected), got \(actual)")
    }
}

private func temporaryHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("moa-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private final class WorkBuddyFakeRuntime: WorkBuddyAppManaging {
    var isRunning = true
    var events: [String] = []
    var onQuit: (() throws -> Void)?
    var onLaunch: (() throws -> Void)?
    var rejectQuit = false
    func quit() throws {
        events.append("quit")
        if rejectQuit { throw TestError.failure("quit refused") }
        try onQuit?()
        isRunning = false
    }
    func launch() throws {
        events.append("launch")
        try onLaunch?()
        isRunning = true
    }
}

#if MOA_TESTING
@main
#endif
enum MoaCoreTests {
    static var tests: [(String, () throws -> Void)] {
        [
            ("WorkBuddy saves exact encrypted login after quit", testWorkBuddySnapshot),
            ("WorkBuddy switching preserves refreshed outgoing accounts", testWorkBuddySwitch),
            ("WorkBuddy new-account login and launch rollback", testWorkBuddyNewLoginAndRollback),
            ("WorkBuddy rejects key mismatch, invalid auth and symlinks", testWorkBuddyCredentialGuards),
            ("WorkBuddy credentials stay outside packages and iCloud", testWorkBuddyStorageIsolation),
            ("WorkBuddy usage normalizes and deduplicates logs", testWorkBuddyUsage),
            ("WorkBuddy usage prices requests and custom overrides", testWorkBuddyUsagePricing),
            ("WorkBuddy account writes exclude other instances", testWorkBuddyConcurrentControllers),
            ("WorkBuddy rollback retains tokens rotated during launch", testWorkBuddyRollbackPreservesTarget),
            ("WorkBuddy distinct requests survive cross-file deduplication", testWorkBuddyDistinctRequests),
            ("usage sources load independently after a source fails", testUsageSourceFailureIsolation),
            ("Sub2API pricing units, Fast rates and context tiers parse", testSub2APIPricingParser),
            ("WorkBuddy aliases use API list prices without credit discounts", testWorkBuddyOriginalAPIPrices),
            ("GPT-6 Sol and Luna use current standard and Fast rates", testCurrentGPT6Prices),
            ("Claude current models apply correct context and cache prices", testCurrentClaudePrices),
            ("fresh remote prices replace seeds while stale mirrors cannot", testPricingCorrectionsAndPreview),
            ("ZCode context prices apply to requests before aggregation", testZCodeRequestPricingTiers),
            ("WorkBuddy editions have separate identities and state paths", testWorkBuddyEditionPaths),
            ("WorkBuddy China switching and recovery preserve the AI client", testWorkBuddyChinaSwitchIsolation),
            ("WorkBuddy cross-edition snapshots are rejected and old AI data loads", testWorkBuddyEditionGuardsAndLegacy),
            ("WorkBuddy China usage and prices remain separate from AI", testWorkBuddyChinaUsageIsolation),
            ("WorkBuddy China and AI daily alerts are independent", testWorkBuddyEditionAlertIsolation),
            ("WorkBuddy operation locks are scoped to their own client", testWorkBuddyEditionLockIsolation),
            ("data root paths are Moa scoped", testDataRootPaths),
            ("profile caches distinguish data root paths", testProfileCacheDistinguishesDataRoots),
            ("legacy Moa-Lite local data migrates without overwrite", testLegacyMoaLiteLocalDataMigration),
            ("legacy Moa-Lite iCloud data migrates to Moa", testLegacyMoaLiteICloudDataMigration),
            ("legacy nested iCloud directories merge recursively", testLegacyNestedICloudDirectoryMigration),
            ("recursive migration does not follow destination symlinks", testRecursiveMigrationRejectsDestinationSymlinks),
            ("TOML multiline strings survive structural edits", testTomlMultilineStringsSurviveStructuralEdits),
            ("Fast state TOML edits preserve multiline strings", testFastStateTomlMultilineStrings),
            ("official restore keeps selected provider identity", testOfficialRestoreKeepsSelectedProviderIdentity),
            ("official restore strips selected direct provider credentials", testOfficialRestoreStripsSelectedDirectProviderCredentials),
            ("Codex session provider migration requires current provider", testCodexSessionProviderMigrationRequiresCurrentProvider),
            ("Codex session provider migration updates JSONL and SQLite", testCodexSessionProviderMigrationUpdatesJSONLAndSQLite),
            ("Codex session provider migration rolls back on failure", testCodexSessionProviderMigrationRollsBackOnFailure),
            ("official account displays email from auth token", testOfficialAccountDisplaysEmailFromAuthToken),
            ("official account auth paths stay contained", testOfficialAccountAuthPathValidation),
            ("official no-account mode preserves third-party config without login", testOfficialNoAccountPreservesThirdPartyConfigWithoutLogin),
            ("official no-account mode captures current login without selecting it", testOfficialNoAccountCapturesCurrentLoginWithoutSelectingIt),
            ("official no-account mode selects first direct config when none selected", testOfficialNoAccountSelectsFirstDirectConfigWhenNoneSelected),
            ("official no-account mode deduplicates current login by email", testOfficialNoAccountDeduplicatesCurrentLoginByEmail),
            ("official account list syncs selected account email", testOfficialAccountListSyncsSelectedAccountEmail),
            ("updater compares versions and parses release feed", testUpdaterVersionComparisonAndFeedParsing),
            ("updater prunes old backups", testUpdaterBackupPruning),
            ("GPT-5.6 family uses current local pricing", testGPT56Pricing),
            ("ChatGPT application override respects renamed bundles", testChatGPTApplicationOverride),
            ("Fast mode updates desktop and root config safely", testChatGPTFastMode),
            ("provider switching preserves live desktop and unrelated tables", testLiveConfigPreservation),
            ("TOML scalar updates respect quoted keys and arrays", testDesktopTomlScalarStyles),
            ("Codex new records deduplicate mirrored legacy events", testCodexNewUsageRecords),
            ("GPT-6 prices include cache writes and request boundaries", testGPT6PricingAndCatalogFreshness),
            ("updater orders RC versions and keeps stable feed isolated", testPrereleaseUpdates),
            ("Codex usage ignores inherited model-less token history", testCodexUsageIgnoresInheritedHistory),
            ("remote pricing catalog parses, merges, and overrides fallback", testRemotePricingCatalog),
            ("pricing updater schedules the daily local check", testPricingUpdateSchedule),
            ("ZCode GLM pricing is estimated from usage tokens", testZCodePricing),
            ("ZCode usage scanner aggregates local SQLite usage", testZCodeUsageScanner),
            ("Claude live files and selected state roll back together", testClaudeStateTransactionRollback),
            ("Codex profile state rolls back together", testCodexStateTransactionRollback),
            ("Codex official account state rolls back together", testCodexOfficialAccountTransactionRollback),
            ("data packages round trip without temporary leaks", testDataPackageRoundTripAndCleanup),
            ("ZCode scanner drains large subprocess output", testZCodeUsageScannerLargeOutput)
        ] + MoaReviewRegressionTests.tests + MoaOptimizationTests.tests + DeepSeekTests.tests + PricingHotUpdateTests.tests
    }

    static func main() {
        var failures: [String] = []
        for (name, test) in tests {
            let pricingHome = FileManager.default.temporaryDirectory.appendingPathComponent("moa-test-pricing-\(UUID().uuidString)")
            MoaUsagePricing.useRemoteCatalogStoreForTesting(.init(environment: ["HOME": pricingHome.path]))
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL \(name): \(error)")
            }
            MoaUsagePricing.resetRemoteCatalogStoreForTesting()
            try? FileManager.default.removeItem(at: pricingHome)
        }

        if !failures.isEmpty {
            fputs(failures.joined(separator: "\n") + "\n", stderr)
            exit(1)
        }
    }

    private static func workbuddyLogin(_ uid: String, token: String = "fixture") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "account": ["uid": uid, "nickname": ["$wbEncrypted": 1, "envelope": "test-name"]],
            "auth": ["accessToken": ["$wbEncrypted": 1, "envelope": "access-" + token],
                     "refreshToken": ["$wbEncrypted": 1, "envelope": "refresh-" + token]],
            "accounts": [], "allAccounts": [], "unknown": ["preserved": true]
        ], options: [.prettyPrinted, .sortedKeys])
    }

    private static func workbuddyFixture(_ home: URL, _ runtime: WorkBuddyFakeRuntime, edition: WorkBuddyEdition = .international) throws -> WorkBuddyController {
        let controller = WorkBuddyController(environment: ["HOME": home.path], edition: edition, runtime: runtime)
        try FileManager.default.createDirectory(at: controller.authURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: controller.keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((edition == .china ? "synthetic-cn-device-key" : "synthetic-device-key").utf8).write(to: controller.keyURL)
        return controller
    }

    private static func testWorkBuddySnapshot() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        try workbuddyLogin("A", token: "old").write(to: controller.authURL)
        let fresh = try workbuddyLogin("A", token: "rotated-on-quit")
        runtime.onQuit = { try fresh.write(to: controller.authURL) }
        let a = try controller.saveCurrent(name: "  Personal  ")
        try expect(a.name == "Personal", "display names should be trimmed")
        try expect(a.snapshot == fresh, "save must capture final tokens after the client exits")
        try expect(runtime.events == ["quit", "launch"], "save should restore a previously running client")
        try expect(a.keyFingerprint?.count == 64, "encrypted snapshots should be bound to their local keyblob")
        _ = try controller.saveCurrent(name: "Renamed")
        let accounts = try controller.accounts()
        try expect(accounts.count == 1 && accounts[0].id == a.id, "UID identity must deduplicate renamed accounts")
        let mode = try FileManager.default.attributesOfItem(atPath: controller.storageURL.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: controller.storageURL.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        try expect(mode?.intValue == 0o600 && directoryMode?.intValue == 0o700, "credential file and directory permissions must be private")
        try expect(try Data(contentsOf: controller.authURL) == fresh, "saving must not reconstruct or strip encrypted fields")
    }

    private static func testWorkBuddySwitch() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        let domestic = controller.authURL.deletingLastPathComponent().appendingPathComponent("workbuddy-desktop.info")
        try Data("domestic-sentinel".utf8).write(to: domestic)
        let session = home.appendingPathComponent(".workbuddy-ai/workbuddy.db")
        try Data("session-sentinel".utf8).write(to: session)
        let aData = try workbuddyLogin("A")
        try aData.write(to: controller.authURL)
        let a = try controller.saveCurrent(name: "A")
        try workbuddyLogin("B").write(to: controller.authURL)
        let b = try controller.saveCurrent(name: "B")
        let freshB = try workbuddyLogin("B", token: "new-refresh")
        runtime.onQuit = { try freshB.write(to: controller.authURL) }
        runtime.onLaunch = { try expect(try Data(contentsOf: controller.authURL) == aData, "launch must happen after the target login is installed") }
        _ = try controller.apply(id: a.id)
        let accounts = try controller.accounts()
        try expect(accounts.first(where: { $0.id == b.id })?.snapshot == freshB, "switch must save the actual outgoing account's rotated tokens")
        runtime.onQuit = nil; runtime.onLaunch = nil
        let sameA = try workbuddyLogin("A", token: "newest-A")
        try sameA.write(to: controller.authURL)
        _ = try controller.apply(id: a.id)
        try expect(try Data(contentsOf: controller.authURL) == sameA, "selecting the current account must not restore stale tokens")
        try workbuddyLogin("C").write(to: controller.authURL)
        _ = try controller.apply(id: a.id)
        try expect(try controller.accounts().contains(where: { $0.uid == "C" }), "unsaved outgoing accounts must not be lost")
        try expect(try Data(contentsOf: domestic) == Data("domestic-sentinel".utf8), "international switching must not touch domestic auth")
        try expect(try Data(contentsOf: session) == Data("session-sentinel".utf8), "switching must not modify conversation databases")
        try controller.rename(id: a.id, name: "Personal")
        try controller.delete(id: a.id)
        try expect(try Data(contentsOf: controller.authURL) == sameA, "forgetting a saved account must leave the live login intact")
    }

    private static func testWorkBuddyNewLoginAndRollback() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        let original = try workbuddyLogin("A")
        try original.write(to: controller.authURL)
        runtime.onLaunch = { try expect(!FileManager.default.fileExists(atPath: controller.authURL.path), "new-account startup needs a clean login") }
        try controller.prepareNewLogin()
        let a = try controller.accounts()[0]
        try expect(a.snapshot == original, "new login must save the outgoing account without revoking it")
        runtime.onLaunch = nil
        _ = try controller.apply(id: a.id)
        try workbuddyLogin("B").write(to: controller.authURL)
        let b = try controller.saveCurrent(name: "B")
        _ = try controller.apply(id: a.id)
        var failures = 1
        runtime.onLaunch = {
            if failures > 0 { failures -= 1; throw TestError.failure("launch failed") }
        }
        do { _ = try controller.apply(id: b.id); throw TestError.failure("launch failure must surface") }
        catch TestError.failure(let message) where message == "launch failed" { }
        try expect(try Data(contentsOf: controller.authURL) == original, "failed startup must restore the original login")
        failures = 1
        do { try controller.prepareNewLogin(); throw TestError.failure("new-login launch failure must surface") }
        catch TestError.failure(let message) where message == "launch failed" { }
        try expect(try Data(contentsOf: controller.authURL) == original, "failed new-login startup must also restore auth")
        runtime.rejectQuit = true
        do { _ = try controller.apply(id: b.id); throw TestError.failure("quit refusal must surface") }
        catch TestError.failure(let message) where message == "quit refused" { }
        try expect(try Data(contentsOf: controller.authURL) == original, "a running client must never have credentials replaced")
    }

    private static func testWorkBuddyCredentialGuards() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        let original = try workbuddyLogin("A")
        try original.write(to: controller.authURL)
        let a = try controller.saveCurrent(name: "A")
        let eventCount = runtime.events.count
        try Data("different-key".utf8).write(to: controller.keyURL)
        do { _ = try controller.apply(id: a.id); throw TestError.failure("different keyblob must be rejected") }
        catch is WorkBuddyError { }
        try expect(runtime.events.count == eventCount, "key mismatch should be rejected before quitting")
        try Data("synthetic-device-key".utf8).write(to: controller.keyURL)
        try Data("not-json".utf8).write(to: controller.authURL)
        do { _ = try controller.apply(id: a.id); throw TestError.failure("invalid live auth must not be overwritten") }
        catch is WorkBuddyError { }
        try expect(try Data(contentsOf: controller.authURL) == Data("not-json".utf8), "invalid outgoing auth should be preserved for recovery")
        try FileManager.default.removeItem(at: controller.authURL)
        let outside = home.appendingPathComponent("outside-auth")
        try original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: controller.authURL, withDestinationURL: outside)
        do { _ = try controller.saveCurrent(name: "symlink"); throw TestError.failure("auth symlinks must be rejected") }
        catch is WorkBuddyError { }
        try expect(try Data(contentsOf: outside) == original, "symlink targets must not be modified")
        try FileManager.default.removeItem(at: controller.authURL)
        try original.write(to: controller.authURL)
        try FileManager.default.removeItem(at: controller.storageURL)
        try FileManager.default.createSymbolicLink(at: controller.storageURL, withDestinationURL: outside)
        do { _ = try controller.accounts(); throw TestError.failure("database symlinks must be rejected") }
        catch is WorkBuddyError { }
    }

    private static func testWorkBuddyStorageIsolation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        try workbuddyLogin("private-synthetic-account").write(to: controller.authURL)
        _ = try controller.saveCurrent(name: "private-synthetic-name")
        let cnController = try workbuddyFixture(home, WorkBuddyFakeRuntime(), edition: .china)
        try workbuddyLogin("private-synthetic-cn-account").write(to: cnController.authURL)
        _ = try cnController.saveCurrent(name: "private-synthetic-cn-name")
        let storage = controller.storageURL
        let packages = MoaDataPackageController(environment: environment)
        let moaHome = MoaDataRoot.localURL(environment: environment)
        try FileManager.default.createDirectory(at: moaHome, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: moaHome.appendingPathComponent("profiles.json"))
        let zip = home.appendingPathComponent("data.zip")
        _ = try packages.exportDataPackage(to: zip)
        let diagnostic = home.appendingPathComponent("diagnostic.zip")
        _ = try packages.exportDiagnosticPackage(to: diagnostic)
        for (index, archive) in [zip, diagnostic].enumerated() {
            let extract = home.appendingPathComponent("extract-" + String(index))
            try runProcess("/usr/bin/ditto", ["-x", "-k", archive.path, extract.path])
            let enumerator = FileManager.default.enumerator(at: extract, includingPropertiesForKeys: nil)!
            for case let url as URL in enumerator {
                guard !url.hasDirectoryPath, let data = try? Data(contentsOf: url) else { continue }
                try expect(!url.path.contains("workbuddy-accounts") && !url.path.contains("workbuddy-cn-accounts") && data.range(of: Data("private-synthetic".utf8)) == nil, "packages must exclude both WorkBuddy editions' credential metadata and snapshots")
            }
        }
        try FileManager.default.createDirectory(at: MoaDataRoot.iCloudDriveRoot(environment: environment), withIntermediateDirectories: true)
        _ = try packages.enableICloudStorage()
        let cloudController = WorkBuddyController(environment: environment, runtime: runtime)
        try expect(cloudController.storageURL == storage, "iCloud toggles must not move device-bound snapshots")
        try expect(try cloudController.accounts().count == 1, "saved accounts should remain available after data-root changes")
        let cnAfterMove = WorkBuddyController(environment: environment, edition: .china, runtime: runtime)
        try expect(cnAfterMove.storageURL == cnController.storageURL && (try cnAfterMove.accounts().count) == 1, "China credentials must also remain local after an iCloud data-root change")
        _ = try packages.disableICloudStorage()
    }

    private static func writeWorkBuddyLogs(_ values: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = try values.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func testWorkBuddyUsage() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = WorkBuddyUsageScanner(environment: ["HOME": home.path])
        try expect(try scanner.loadReport().rows.isEmpty, "uninstalled clients should produce an empty source")
        let timestamp: Int = 1_790_000_000_123
        var values: [[String: Any]] = [
            ["id": "one", "timestamp": timestamp, "type": "function_call",
             "message": ["usage": ["input_tokens": 1000, "cache_read_input_tokens": 0, "prompt_cache_hit_tokens": 300, "output_tokens": 100]],
             "providerData": ["model": "future-model", "usage": ["inputTokens": 9999, "outputTokens": 999], "rawUsage": ["cache_write_input_tokens": 100]]],
            ["id": "two", "timestamp": timestamp + 1000, "providerData": ["model": "future-model", "usage": ["inputTokens": "500", "outputTokens": 50, "inputTokensDetails": [["cached_tokens": 200]], "prompt_cache_miss_tokens": 300]]],
            ["id": "three", "timestamp": timestamp + 2000, "model": "future-model", "usage": ["prompt_tokens": 200, "completion_tokens": 20, "prompt_tokens_details": ["cached_tokens": 80]]],
            ["id": "four", "timestamp": timestamp + 3000, "model": "future-model", "usage": ["input_tokens": 0, "output_tokens": 10]],
            // A distinct event can have the same timestamp and counters.
            ["id": "five", "timestamp": timestamp + 3000, "model": "future-model", "usage": ["input_tokens": 0, "output_tokens": 10]],
            ["model": "ignored", "usage": ["input_tokens": 1000, "output_tokens": 100]],
            ["timestamp": timestamp, "usage": ["requests": 1]]
        ]
        values = values.map { value in
            var record = value
            if let id = record["id"] as? String {
                var provider = record["providerData"] as? [String: Any] ?? [:]
                provider["messageId"] = id
                record["providerData"] = provider
            }
            return record
        }
        let project = home.appendingPathComponent(".workbuddy-ai/projects/example/session.jsonl")
        try writeWorkBuddyLogs(values, to: project)
        let copied = values.enumerated().map { index, value -> [String: Any] in
            var copy = value
            if copy["id"] is String { copy["id"] = "copied-\(index)" }
            return copy
        }
        try writeWorkBuddyLogs(copied, to: home.appendingPathComponent(".workbuddy-ai/sessions/copied.jsonl"))
        try writeWorkBuddyLogs(values, to: home.appendingPathComponent(".workbuddy-ai/projects/example/subagents/agent.jsonl"))
        let now = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let report = try scanner.loadReport(now: now)
        try expect(report.rows.count == 1 && report.rows[0].source == .workbuddy, "logs should aggregate by local day and model")
        let row = report.rows[0]
        try expect(row.input == 1020 && row.cacheReadInput == 580 && row.cacheCreationInput == 100 && row.output == 190, "aliases, precedence and cache splits must not double count tokens")
        try expect(row.totalTokens == 1890, "mirror copies and subagent context must not inflate total tokens")
        try expect(row.pricingModel == "unpriced" && row.costUSD == 0 && row.usesFallbackPricing, "unknown models must report tokens without fabricated prices")
        let summary = try scanner.loadSummary(now: now)
        try expect(summary.todayTokens == 1890 && summary.totalTokens == 1890, "summary should use the same accounting as details")
        try expectClose(summary.cacheHitPercent, 580.0 / 1890 * 100, "cache percentage should match the Codex report denominator")
        try expect(MoaUsageReportExporter.csv(report: report).contains("WorkBuddy AI"), "CSV should include WorkBuddy rows")
        try expect(MoaUsageReportExporter.markdown(report: report).contains("unpriced"), "exports should retain missing-price markers")
        try writeWorkBuddyLogs(values + [["id": "six", "timestamp": timestamp + 4000, "model": "future-model", "usage": ["input_tokens": 10, "output_tokens": 1]]], to: project)
        try expect(try scanner.loadReport(now: now).totalTokens == 1901, "changed files must invalidate in-memory caches")
        try FileManager.default.removeItem(at: project)
        try expect(try scanner.loadReport(now: now).totalTokens == 1890, "deleted files must be evicted from the cache")
    }

    private static func testWorkBuddyUsagePricing() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let scanner = WorkBuddyUsageScanner(environment: environment)
        let timestamp: Int = 1_790_000_000_123
        let values: [[String: Any]] = [
            ["id": "one", "timestamp": timestamp, "model": "future-model", "usage": ["input_tokens": 1000, "cache_read_input_tokens": 300, "cache_write_input_tokens": 100, "output_tokens": 100]],
            ["id": "two", "timestamp": timestamp + 1000, "model": "future-model", "usage": ["input_tokens": 1000, "cache_read_input_tokens": 300, "cache_write_input_tokens": 100, "output_tokens": 100]]
        ]
        try writeWorkBuddyLogs(values, to: home.appendingPathComponent(".workbuddy-ai/projects/session.jsonl"))
        let store = MoaUsagePricingCatalogStore(environment: environment)
        let remote = MoaUsageRemotePricing(inputUSDPerMillion: 2, outputUSDPerMillion: 10, cacheReadUSDPerMillion: 0.5, cacheCreationUSDPerMillion: 3, thresholdTokens: 1500, inputUSDPerMillionAboveThreshold: 4, outputUSDPerMillionAboveThreshold: 20, cacheReadUSDPerMillionAboveThreshold: 1, cacheCreationUSDPerMillionAboveThreshold: 6)
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://models.dev/api.json", fetchedAt: Date(), models: ["workbuddy": ["future-model": remote]]))
        let now = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let report = try scanner.loadReport(now: now)
        try expectClose(report.totalCostUSD, 0.0053, "long-context prices must apply per request, never to the aggregated day")
        try expect(report.rows[0].usesFallbackPricing == false, "recognized remote prices should be marked known")
        let overrides = MoaUsagePricingOverrideController(environment: environment)
        try overrides.upsert(source: .workbuddy, model: "future-model", inputUSDPerMillion: 1, outputUSDPerMillion: 2, cacheReadUSDPerMillion: 0.1, cacheCreationUSDPerMillion: 1.5)
        try expectClose(try scanner.loadReport(now: now).totalCostUSD, 0.00196, "WorkBuddy custom prices must override remote prices on cached records")
        try expect(overrides.override(source: .codex, model: "future-model") == nil, "WorkBuddy overrides must remain source scoped")
    }

    private static func testWorkBuddyConcurrentControllers() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let first = try workbuddyFixture(home, runtime)
        try workbuddyLogin("A").write(to: first.authURL)
        let a = try first.saveCurrent(name: "A")
        let secondRuntime = WorkBuddyFakeRuntime()
        let second = WorkBuddyController(environment: ["HOME": home.path], runtime: secondRuntime)
        var blocked = false
        runtime.onQuit = {
            do { try second.rename(id: a.id, name: "concurrent edit") }
            catch is WorkBuddyError { blocked = true }
        }
        _ = try first.saveCurrent(name: "updated A")
        try expect(blocked, "a second controller must not mutate credentials during an active operation")
        try expect(secondRuntime.events.isEmpty, "competing operations must fail before touching the client")
        try second.rename(id: a.id, name: "after unlock")
        try expect(try first.accounts().first?.name == "after unlock", "the credential lock must release after success")
        runtime.onQuit = { throw TestError.failure("quit failed") }
        do { _ = try first.saveCurrent(name: "A"); throw TestError.failure("quit failure must surface") }
        catch TestError.failure(let message) where message == "quit failed" { }
        try second.rename(id: a.id, name: "after failure")
        try expect(try first.accounts().first?.name == "after failure", "the credential lock must also release on failure")
    }

    private static func testWorkBuddyRollbackPreservesTarget() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = WorkBuddyFakeRuntime()
        let controller = try workbuddyFixture(home, runtime)
        let original = try workbuddyLogin("A")
        try original.write(to: controller.authURL)
        let a = try controller.saveCurrent(name: "A")
        try workbuddyLogin("B").write(to: controller.authURL)
        let b = try controller.saveCurrent(name: "B")
        _ = try controller.apply(id: a.id)
        let rotated = try workbuddyLogin("B", token: "rotated-before-launch-error")
        var failLaunch = true
        runtime.onLaunch = {
            if failLaunch {
                failLaunch = false
                runtime.isRunning = true
                try rotated.write(to: controller.authURL)
                throw TestError.failure("launch status failed")
            }
        }
        do { _ = try controller.apply(id: b.id); throw TestError.failure("launch error must surface") }
        catch TestError.failure(let message) where message == "launch status failed" { }
        try expect(try Data(contentsOf: controller.authURL) == original, "rollback must restore the original account")
        try expect(try controller.accounts().first(where: { $0.id == b.id })?.snapshot == rotated, "rollback must not discard the target's newly rotated refresh token")
        runtime.onLaunch = nil
        _ = try controller.apply(id: b.id)
        try expect(try Data(contentsOf: controller.authURL) == rotated, "the target must remain switchable after recovery")
    }

    private static func testWorkBuddyDistinctRequests() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = WorkBuddyUsageScanner(environment: ["HOME": home.path])
        let timestamp: Int = 1_790_000_000_123
        let usage = ["input_tokens": 100, "output_tokens": 10]
        let root = home.appendingPathComponent(".workbuddy-ai/projects")
        let one: [String: Any] = ["id": "event-one", "timestamp": timestamp, "providerData": ["messageId": "request-one", "stepSeq": 1, "model": "unknown"], "usage": usage]
        let two: [String: Any] = ["id": "event-two", "timestamp": timestamp, "providerData": ["messageId": "request-two", "stepSeq": 1, "model": "unknown"], "usage": usage]
        try writeWorkBuddyLogs([one], to: root.appendingPathComponent("one.jsonl"))
        try writeWorkBuddyLogs([two], to: root.appendingPathComponent("two.jsonl"))
        var copied = one
        copied["id"] = "rewritten-copy-id"
        try writeWorkBuddyLogs([copied], to: root.appendingPathComponent("copy.jsonl"))
        let report = try scanner.loadReport()
        try expect(report.totalTokens == 220, "different stable request IDs must count separately even when timestamps and token counts match")
    }

    private static func testUsageSourceFailureIsolation() throws {
        let now = Date()
        let row = MoaUsageDetailRow(source: .codex, dayKey: MoaUsageReport.dayKey(from: now), model: "fixture",
            input: 100, cachedInput: 0, cacheReadInput: 0, cacheCreationInput: 0, output: 10,
            costUSD: 0.1, pricingModel: "fixture", usesFallbackPricing: false)
        let codex = MoaUsageReport(rows: [row], generatedAt: now)
        let result = MoaUsageReportBatch.load(now: now, sources: [
            (.workbuddy, { throw TestError.failure("unreadable log") }),
            (.codex, { codex })
        ])
        try expect(result.report?.totalTokens == 110, "a WorkBuddy read failure must not suppress other clients' usage")
        try expect(result.failures.count == 1 && result.failures[0].hasPrefix("WorkBuddy AI:"), "partial reports must identify the failed source")
        let failed = MoaUsageReportBatch.load(now: now, sources: [(.workbuddy, { throw TestError.failure("unreadable log") })])
        try expect(failed.report == nil && !failed.failures.isEmpty, "complete failure must keep the previous report instead of publishing an empty replacement")
    }

    private static func testSub2APIPricingParser() throws {
        var entries: [String: Any] = [:]
        for index in 0..<5 {
            entries["gpt-fixture-\(index)"] = ["litellm_provider": "openai", "mode": "responses", "input_cost_per_token": 2e-6, "output_cost_per_token": 10e-6]
        }
        for index in 0..<3 {
            entries["claude-fixture-\(index)"] = ["litellm_provider": "anthropic", "input_cost_per_token": 2e-6, "output_cost_per_token": 10e-6]
        }
        entries["glm-fixture"] = ["litellm_provider": "zhipu", "input_cost_per_token": 1.4e-6, "output_cost_per_token": 4.4e-6]
        entries["gpt-tiered"] = [
            "litellm_provider": "openai", "input_cost_per_token": 2e-6, "output_cost_per_token": 10e-6,
            "cache_read_input_token_cost": 0.1e-6, "cache_creation_input_token_cost": 2.5e-6,
            "input_cost_per_token_priority": 4e-6, "output_cost_per_token_priority": 20e-6,
            "cache_read_input_token_cost_priority": 0.2e-6, "cache_creation_input_token_cost_priority": 5e-6,
            "long_context_input_token_threshold": 272000, "long_context_input_cost_multiplier": 2,
            "long_context_output_cost_multiplier": 1.5,
            "cache_read_input_token_cost_above_272k_tokens": 0.2e-6
        ]
        entries["gpt-invalid"] = ["litellm_provider": "openai", "input_cost_per_token": true, "output_cost_per_token": -1]
        entries["cloud-reseller"] = ["litellm_provider": "bedrock", "input_cost_per_token": 99, "output_cost_per_token": 99]
        let snapshot = try MoaUsagePricingRemoteParser.parse(data: JSONSerialization.data(withJSONObject: entries),
            sourceURL: MoaUsagePricingUpdater.defaultSourceURL, fetchedAt: Date())
        let price = snapshot.models["codex"]?["gpt-tiered"]
        try expectClose(price?.inputUSDPerMillion ?? -1, 2, "Sub2API USD/token must convert to USD/MTok exactly once")
        try expectClose(price?.cacheCreationUSDPerMillion ?? -1, 2.5, "cache-write price must retain its independent rate")
        try expectClose(price?.priorityOutputUSDPerMillion ?? -1, 20, "Fast output must not be confused with the standard rate")
        try expect(price?.thresholdTokens == 272000, "explicit request threshold must survive parsing")
        try expectClose(price?.outputUSDPerMillionAboveThreshold ?? -1, 15, "long-context multipliers should fill missing absolute prices")
        try expectClose(price?.priorityCacheCreationUSDPerMillionAboveThreshold ?? -1, 10, "Fast cache writes should retain the context multiplier")
        try expect(snapshot.models["workbuddy"]?["gpt-tiered"] == price, "clients must use the same underlying API price")
        try expect(snapshot.models.values.allSatisfy { $0["gpt-invalid"] == nil && $0["cloud-reseller"] == nil }, "invalid values and cloud-reseller SKUs must not become direct API prices")
        let legacyJSON = Data(#"{"inputUSDPerMillion":2,"outputUSDPerMillion":10}"#.utf8)
        let legacy = try JSONDecoder().decode(MoaUsageRemotePricing.self, from: legacyJSON)
        try expect(legacy.priorityInputUSDPerMillion == nil, "existing local catalogs must decode without the new optional Fast fields")
    }

    private static func testWorkBuddyOriginalAPIPrices() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let scanner = WorkBuddyUsageScanner(environment: environment)
        let expected: [(String, Double, String)] = [
            ("deepseek-v4.1-flash", 0.0003318, "deepseek-flash"),
            ("deepseek-v4.1-flash-sg", 0.0003318, "deepseek-flash"),
            ("hy4-preview-f", 0.0008465, "hy4-preview"),
            ("step-5-preview", 0.001, "step-5-preview"),
            ("gpt-6-luna", 0.000123, "gpt-6-luna"),
            ("glm-5.3", 0.001498, "glm-5.3"),
            ("kimi-k2.8-preview", 0.001175, "kimi-k2.8-preview")
        ]
        var values = expected.enumerated().map { index, entry -> [String: Any] in
            ["id": "original-\(index)", "timestamp": 1_790_000_000_000 + index, "model": entry.0,
             "providerData": ["credit": 0, "discount": 0],
             "usage": ["input_tokens": 1000, "cache_read_input_tokens": 300, "output_tokens": 100]]
        }
        values.append(["id": "unresolved", "timestamp": 1_790_000_001_000, "model": "default-model", "usage": ["input_tokens": 1000, "output_tokens": 100]])
        try writeWorkBuddyLogs(values, to: home.appendingPathComponent(".workbuddy-ai/projects/prices.jsonl"))
        let report = try scanner.loadReport()
        for (model, cost, canonical) in expected {
            guard let row = report.rows.first(where: { $0.model == model }) else { throw TestError.failure("missing \(model)") }
            try expectClose(row.costUSD, cost, "\(model) must use original API token prices despite zero WorkBuddy credits")
            try expect(!row.usesFallbackPricing && row.pricingModel == canonical, "\(model) should expose its verified price mapping")
        }
        try expect(report.rows.first(where: { $0.model == "default-model" })?.pricingModel == "unpriced", "unresolved routing aliases must not be assigned an invented model price")
        let overrides = MoaUsagePricingOverrideController(environment: environment)
        try overrides.upsert(source: .workbuddy, model: "hy4-preview-f", inputUSDPerMillion: 1, outputUSDPerMillion: 2, cacheReadUSDPerMillion: 0.5, cacheCreationUSDPerMillion: nil)
        let custom = try scanner.loadReport().rows.first { $0.model == "hy4-preview-f" }
        try expectClose(custom?.costUSD ?? -1, 0.00105, "explicit user prices must remain above official alias corrections")
        let grok: [[String: Any]] = [
            ["id": "short-grok", "timestamp": 1_790_000_002_000, "model": "grok-4.7", "usage": ["input_tokens": 199999, "output_tokens": 0]],
            ["id": "long-grok", "timestamp": 1_790_000_003_000, "model": "grok-4.7", "usage": ["input_tokens": 200000, "output_tokens": 0]]
        ]
        try writeWorkBuddyLogs(grok, to: home.appendingPathComponent(".workbuddy-ai/projects/grok.jsonl"))
        let grokCost = try scanner.loadReport().rows.first { $0.model == "grok-4.7" }?.costUSD
        try expectClose(grokCost ?? -1, 1.199998, "Grok's long-context price starts at exactly 200K tokens")
    }

    private static func testCurrentGPT6Prices() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        MoaUsagePricing.useRemoteCatalogStoreForTesting(MoaUsagePricingCatalogStore(environment: ["HOME": home.path]))
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let sol = MoaUsagePricing.codexCostUSD(model: "gpt-6.1-sol", inputTokens: 1000, cachedInputTokens: 500, outputTokens: 1000)
        try expectClose(sol ?? -1, 0.01105, "GPT-6.1 Sol must use its 5% cache-read rate")
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-sol", inputTokens: 1000, cachedInputTokens: 500, outputTokens: 1000) ?? -1, 0.0111, "GPT-6 Sol retains its separate 10% cache-read rate")
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-luna", inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 1_000_000) ?? -1, 0.95, "Luna long context must use its own standard API prices")
        try expectClose(MoaUsagePricing.codexPriorityCostUSD(model: "gpt-6.1-sol", inputTokens: 300000, cachedInputTokens: 100000, outputTokens: 100000) ?? -1, 4.64, "Fast and long-context prices must both apply")
    }

    private static func testCurrentClaudePrices() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        MoaUsagePricing.useRemoteCatalogStoreForTesting(MoaUsagePricingCatalogStore(environment: ["HOME": home.path]))
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let sonnet = MoaUsagePricing.claudeCostEstimate(model: "claude-sonnet-4-6", inputTokens: 300000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 100000)
        try expectClose(sonnet?.costUSD ?? -1, 2.4, "Sonnet 4.6 no longer has a long-context premium")
        let latest = MoaUsagePricing.claudeCostEstimate(model: "claude-sonnet-5-5", inputTokens: 10000, cacheReadInputTokens: 30000, cacheCreationInputTokens: 10000, outputTokens: 10000)
        try expectClose(latest?.costUSD ?? -1, 0.148, "Sonnet 5.5 must use its current cache-hit price")
        let short = MoaUsagePricing.claudeCostEstimate(model: "claude-haiku-5-5", inputTokens: 100000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 0)
        let long = MoaUsagePricing.claudeCostEstimate(model: "claude-haiku-5-5", inputTokens: 100001, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, outputTokens: 0)
        try expectClose(short?.costUSD ?? -1, 0.01, "Haiku 5.5 should retain its inclusive 100K boundary")
        try expectClose(long?.costUSD ?? -1, 0.0500005, "Haiku 5.5 higher prices should apply above 100K")
    }

    private static func testPricingCorrectionsAndPreview() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = MoaUsagePricingCatalogStore(environment: ["HOME": home.path])
        let wrong = MoaUsageRemotePricing(inputUSDPerMillion: 99, outputUSDPerMillion: 99)
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://models.dev/api.json", fetchedAt: MoaUsagePricingSeed.checkedAt.addingTimeInterval(-1), models: ["workbuddy": ["step-5-preview": wrong, "hy3": wrong], "codex": ["gpt-5.6-sol": wrong]]))
        try expectClose(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "step-5-preview", store: store)?.inputUSDPerMillion ?? -1, 1, "a currency-converted catalog must not override verified USD list prices")
        try expectClose(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "hy3", store: store)?.inputUSDPerMillion ?? -1, 0.132, "free plan promotions must not replace Hy3's original API list price")
        try expectClose(MoaUsagePricing.catalogPricing(source: .codex, model: "gpt-5.6-sol", store: store)?.inputUSDPerMillion ?? -1, 4, "the verified snapshot must take precedence over an older mirror")
        let updated = MoaUsageRemotePricing(inputUSDPerMillion: 3, outputUSDPerMillion: 8)
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.com/pricing", fetchedAt: Date(), models: ["workbuddy": ["step-5-preview": updated], "codex": ["gpt-5.6-sol": updated]]))
        try expectClose(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "step-5-preview", store: store)?.inputUSDPerMillion ?? -1, 3, "fresh downloads must replace formerly hardcoded corrections without an app release")
        try expectClose(MoaUsagePricing.catalogPricing(source: .codex, model: "gpt-5.6-sol", store: store)?.inputUSDPerMillion ?? -1, 3, "all seeded models must remain hot-updatable")
        let preview = MoaUsagePricing.codexCostEstimate(model: "gpt-5.3-codex-spark", inputTokens: 1000, cachedInputTokens: 0, outputTokens: 100)
        try expect(preview?.pricingModel == "unpriced" && preview?.usesFallbackPricing == true, "a preview without a public API rate must not be labeled free")
    }

    private static func testZCodeRequestPricingTiers() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let store = MoaUsagePricingCatalogStore(environment: environment)
        let price = MoaUsageRemotePricing(inputUSDPerMillion: 2, outputUSDPerMillion: 10, cacheReadUSDPerMillion: 0.5, cacheCreationUSDPerMillion: 3, thresholdTokens: 1500, inputUSDPerMillionAboveThreshold: 4, outputUSDPerMillionAboveThreshold: 20, cacheReadUSDPerMillionAboveThreshold: 1, cacheCreationUSDPerMillionAboveThreshold: 6)
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.com/prices", fetchedAt: Date(), models: ["zcode": ["glm-tier-fixture": price]]))
        MoaUsagePricing.useRemoteCatalogStoreForTesting(store)
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let db = home.appendingPathComponent(".zcode/cli/db/db.sqlite")
        try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runSQLite(db: db, sql: """
        create table model_usage (status text, started_at integer, model_id text, input_tokens integer, cache_read_input_tokens integer, cache_creation_input_tokens integer, output_tokens integer);
        insert into model_usage values ('completed',1790000000000,'glm-tier-fixture',1000,300,100,100);
        insert into model_usage values ('completed',1790000001000,'glm-tier-fixture',1000,300,100,100);
        """)
        let report = try ZCodeUsageScanner(environment: environment).loadReport()
        try expectClose(report.totalCostUSD, 0.0053, "ZCode must price each 1K request before combining them into a 2K day")
        try expectClose(MoaUsagePricing.zcodeCacheReadUSDPerMillion(model: "glm-tier-fixture", promptTokens: 1501) ?? -1, 1, "cache-price helpers must honor the same context boundary")
    }

    private static func testWorkBuddyEditionPaths() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let ai = try workbuddyFixture(home, WorkBuddyFakeRuntime())
        let cn = try workbuddyFixture(home, WorkBuddyFakeRuntime(), edition: .china)
        try expect(ai.authURL.lastPathComponent == "workbuddy-desktop-ai.info", "the AI credential path must remain backward compatible")
        try expect(cn.authURL.lastPathComponent == "workbuddy-desktop.info", "China must address its own auth file")
        try expect(ai.keyURL.path.hasSuffix("/.workbuddy-ai/keyblob") && cn.keyURL.path.hasSuffix("/.workbuddy/keyblob"), "each client must use its own keyblob")
        try expect(ai.storageURL.path.hasSuffix("/workbuddy-accounts/accounts.json") && cn.storageURL.path.hasSuffix("/workbuddy-cn-accounts/accounts.json"), "saved accounts and lock directories must be isolated without moving old AI data")
        try expect(WorkBuddyAppManager(edition: .china).bundleID == "com.tencent.workbuddy.mac", "China app actions must select the domestic bundle")
        try expect(WorkBuddyAppManager().bundleID == "com.workbuddy.workbuddy-ai", "default app actions must continue targeting AI")
        try expect(MoaUsageSource.workbuddy.rawValue == "workbuddy" && DailyUsageAlertKind.workbuddy.rawValue == "workbuddy", "existing AI pricing and alert keys must not change")
        try expect(MoaUsageSource.workbuddyCN.rawValue == "workbuddy-cn" && DailyUsageAlertKind.workbuddyCN.rawValue == "workbuddy-cn", "China needs a separate persistent usage namespace")
        try expect(WorkBuddyEdition.china.acceptsAuthDomain("https://www.workbuddy.cn"), "China should accept its own product domain")
        try expect(!WorkBuddyEdition.china.acceptsAuthDomain("www.workbuddy.ai"), "China must reject known international login domains")
        try expect(!WorkBuddyEdition.international.acceptsAuthDomain("www.codebuddy.cn"), "AI must reject known domestic login domains")
    }

    private static func testWorkBuddyChinaSwitchIsolation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let aiRuntime = WorkBuddyFakeRuntime()
        let cnRuntime = WorkBuddyFakeRuntime()
        let ai = try workbuddyFixture(home, aiRuntime)
        let cn = try workbuddyFixture(home, cnRuntime, edition: .china)
        let aiAuth = try workbuddyLogin("same-uid", token: "ai-only")
        try aiAuth.write(to: ai.authURL)
        let aiAccount = try ai.saveCurrent(name: "AI account")
        let aiDatabase = try Data(contentsOf: ai.storageURL)
        let aiEvents = aiRuntime.events
        let cnAuth = try workbuddyLogin("same-uid", token: "cn-only")
        try cnAuth.write(to: cn.authURL)
        let cnAccount = try cn.saveCurrent(name: "CN account")
        try expect(cnAccount.id != aiAccount.id && cnAccount.keyFingerprint != aiAccount.keyFingerprint, "same UID in different clients must produce separate saved accounts and key bindings")
        try workbuddyLogin("cn-B").write(to: cn.authURL)
        let b = try cn.saveCurrent(name: "CN B")
        let rotatedB = try workbuddyLogin("cn-B", token: "rotated-cn-B")
        cnRuntime.onQuit = { try rotatedB.write(to: cn.authURL) }
        _ = try cn.apply(id: cnAccount.id)
        cnRuntime.onQuit = nil
        try expect(try Data(contentsOf: cn.authURL) == cnAuth, "China switching must restore its own account snapshot")
        try expect(try cn.accounts().first(where: { $0.id == b.id })?.snapshot == rotatedB, "China must capture its own rotated outgoing token")
        var failures = 1
        cnRuntime.onLaunch = { if failures > 0 { failures -= 1; throw TestError.failure("domestic launch failed") } }
        do { _ = try cn.apply(id: b.id); throw TestError.failure("China launch failure must surface") }
        catch TestError.failure(let message) where message == "domestic launch failed" { }
        try expect(try Data(contentsOf: cn.authURL) == cnAuth, "China launch recovery must restore the domestic login")
        cnRuntime.onLaunch = { try expect(!FileManager.default.fileExists(atPath: cn.authURL.path), "China enrollment should start with a fresh domestic login") }
        try cn.prepareNewLogin()
        cnRuntime.onLaunch = nil
        _ = try cn.apply(id: cnAccount.id)
        try cn.rename(id: cnAccount.id, name: "CN Personal")
        try cn.delete(id: b.id)
        try expect(try cn.accounts().count == 1, "China account management must remain within its own database")
        try expect(try Data(contentsOf: ai.authURL) == aiAuth && (try Data(contentsOf: ai.storageURL)) == aiDatabase, "every China operation must leave international auth and saved accounts byte-for-byte intact")
        try expect(aiRuntime.events == aiEvents, "China actions must never quit or launch WorkBuddy AI")
    }

    private static func testWorkBuddyEditionGuardsAndLegacy() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let ai = try workbuddyFixture(home, WorkBuddyFakeRuntime())
        let cnRuntime = WorkBuddyFakeRuntime()
        let cn = try workbuddyFixture(home, cnRuntime, edition: .china)
        try workbuddyLogin("A").write(to: ai.authURL)
        let aiAccount = try ai.saveCurrent(name: "legacy AI")
        try workbuddyLogin("A", token: "domestic").write(to: cn.authURL)
        _ = try cn.saveCurrent(name: "CN A")
        let cnDatabase = try Data(contentsOf: cn.storageURL)
        let originalEvents = cnRuntime.events
        do { _ = try cn.apply(id: aiAccount.id); throw TestError.failure("cross-client account IDs must be rejected") }
        catch is WorkBuddyError { }
        try Data(contentsOf: ai.storageURL).write(to: cn.storageURL)
        do { _ = try cn.accounts(); throw TestError.failure("a copied AI database must be rejected by China") }
        catch is WorkBuddyError { }
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: ai.storageURL)) as! [String: Any]
        var entries = legacy["accounts"] as! [[String: Any]]
        entries[0].removeValue(forKey: "edition")
        legacy["accounts"] = entries
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try legacyData.write(to: ai.storageURL)
        try expect(try ai.accounts().first?.id == aiAccount.id, "AI accounts created before edition tags must still load")
        try legacyData.write(to: cn.storageURL)
        do { _ = try cn.accounts(); throw TestError.failure("untagged legacy AI data must not be adopted by China") }
        catch is WorkBuddyError { }
        try cnDatabase.write(to: cn.storageURL)
        var wrongLogin = try JSONSerialization.jsonObject(with: workbuddyLogin("A")) as! [String: Any]
        var auth = wrongLogin["auth"] as! [String: Any]
        auth["domain"] = "www.workbuddy.ai"
        wrongLogin["auth"] = auth
        try JSONSerialization.data(withJSONObject: wrongLogin).write(to: cn.authURL)
        do { _ = try cn.currentUID(); throw TestError.failure("known AI auth domains must be rejected in the domestic path") }
        catch is WorkBuddyError { }
        try expect(cnRuntime.events == originalEvents, "cross-client validation must fail before changing any client process")
        _ = try ai.apply(id: aiAccount.id)
        try expect(try ai.accounts().first?.edition == .international, "re-saving old AI data should add the correct edition without changing its identity")
    }

    private static func testWorkBuddyChinaUsageIsolation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let ai = WorkBuddyUsageScanner(environment: environment)
        let cn = WorkBuddyUsageScanner(environment: environment, edition: .china)
        let values: [[String: Any]] = [["id": "identical-event", "timestamp": 1_790_000_000_000,
            "providerData": ["messageId": "same-message", "stepSeq": 1, "model": "gpt-6-luna"],
            "usage": ["input_tokens": 1000, "cache_read_input_tokens": 300, "output_tokens": 100]]]
        try writeWorkBuddyLogs(values, to: home.appendingPathComponent(".workbuddy-ai/projects/session.jsonl"))
        try writeWorkBuddyLogs(values, to: home.appendingPathComponent(".workbuddy/projects/session.jsonl"))
        let aiReport = try ai.loadReport()
        let cnReport = try cn.loadReport()
        try expect(aiReport.totalTokens == 1100 && cnReport.totalTokens == 1100, "each scanner must read only its own data root")
        try expect(aiReport.rows[0].source == .workbuddy && cnReport.rows[0].source == .workbuddyCN, "each row must keep an edition-specific source ID")
        try expect(aiReport.rows[0].id != cnReport.rows[0].id, "matching request and model IDs must never collide across clients")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let combined = MoaUsageReport(rows: aiReport.rows + cnReport.rows, generatedAt: now)
        try expect(combined.filtered(source: .workbuddyCN, recentDays: 1, now: now).rows.map(\.source) == [.workbuddyCN], "the China tab must exclude AI rows")
        try expect(combined.filtered(source: .workbuddy, recentDays: 1, now: now).rows.map(\.source) == [.workbuddy], "the AI tab must exclude China rows")
        let prices = MoaUsagePricingOverrideController(environment: environment)
        try prices.upsert(source: .workbuddyCN, model: "gpt-6-luna", inputUSDPerMillion: 1, outputUSDPerMillion: 2, cacheReadUSDPerMillion: 0.5, cacheCreationUSDPerMillion: nil)
        try expectClose(try cn.loadReport().totalCostUSD, 0.00105, "China must use its own custom price")
        try expectClose(try ai.loadReport().totalCostUSD, 0.000123, "China custom prices must not leak into AI")
        try prices.upsert(source: .workbuddy, model: "gpt-6-luna", inputUSDPerMillion: 10, outputUSDPerMillion: 20, cacheReadUSDPerMillion: 5, cacheCreationUSDPerMillion: nil)
        try expectClose(try ai.loadReport().totalCostUSD, 0.0105, "AI must keep its original pricing namespace")
        try expectClose(try cn.loadReport().totalCostUSD, 0.00105, "AI custom prices must not leak into China")
        let csv = MoaUsageReportExporter.csv(report: cnReport)
        let markdown = MoaUsageReportExporter.markdown(report: cnReport)
        try expect(csv.contains(MoaUsageSource.workbuddyCN.title) && !csv.contains("WorkBuddy AI"), "China CSV exports must contain only the domestic source")
        try expect(!markdown.contains("WorkBuddy AI"), "a domestic-only Markdown report must not be labeled international")
    }

    private static func testWorkBuddyEditionAlertIsolation() throws {
        let suite = "Moa.Tests.WorkBuddyEditions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DailyUsageAlertController.setThreshold(50, for: .workbuddy, defaults: defaults)
        DailyUsageAlertController.setThreshold(10, for: .workbuddyCN, defaults: defaults)
        try expect(DailyUsageAlertController.threshold(for: .workbuddy, defaults: defaults) == 50 && DailyUsageAlertController.threshold(for: .workbuddyCN, defaults: defaults) == 10, "each client must have its own alert threshold")
        let summary = CodexUsageSummary(todayCostUSD: 20, totalCostUSD: 20, todayTokens: 1, totalTokens: 1,
            cacheHitPercent: 0, topModelName: nil, topModelTokens: 0, topModelPercent: 0, updatedAt: Date())
        try expect(DailyUsageAlertController.shouldAlert(kind: .workbuddyCN, summary: summary, defaults: defaults), "the domestic threshold should trigger")
        try expect(!DailyUsageAlertController.shouldAlert(kind: .workbuddy, summary: summary, defaults: defaults), "the international threshold should remain untriggered")
        DailyUsageAlertController.setThreshold(10, for: .workbuddy, defaults: defaults)
        try expect(DailyUsageAlertController.shouldAlert(kind: .workbuddy, summary: summary, defaults: defaults), "China's delivered alert must not suppress the AI alert")
        DailyUsageAlertController.setThreshold(nil, for: .workbuddyCN, defaults: defaults)
        try expect(DailyUsageAlertController.threshold(for: .workbuddy, defaults: defaults) == 10, "turning off China alerts must preserve AI settings")
        try expect(!DailyUsageAlertController.shouldAlert(kind: .workbuddy, summary: summary, defaults: defaults), "clearing China alert state must not clear AI's delivered-alert marker")
    }

    private static func testWorkBuddyEditionLockIsolation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let aiRuntime = WorkBuddyFakeRuntime()
        let cnRuntime = WorkBuddyFakeRuntime()
        let ai = try workbuddyFixture(home, aiRuntime)
        let cn = try workbuddyFixture(home, cnRuntime, edition: .china)
        try workbuddyLogin("A").write(to: ai.authURL)
        try workbuddyLogin("A", token: "cn-only").write(to: cn.authURL)
        _ = try ai.saveCurrent(name: "AI")
        let cnAccount = try cn.saveCurrent(name: "CN")
        let events = cnRuntime.events
        aiRuntime.onQuit = { try cn.rename(id: cnAccount.id, name: "CN independent edit") }
        _ = try ai.saveCurrent(name: "AI updated")
        try expect(try cn.accounts().first?.name == "CN independent edit", "an AI operation must not hold China's operation lock")
        try expect(cnRuntime.events == events, "an international operation must not control domestic client processes")
    }

    private static func testDataRootPaths() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let environment = ["HOME": home.path]
        try expect(MoaDataRoot.localURL(environment: environment).lastPathComponent == ".moa", "local data root should be ~/.moa")
        try expect(MoaDataRoot.supportDirectory(environment: environment).lastPathComponent == "Moa", "Application Support root should be Moa")
        try expect(MoaDataRoot.iCloudURL(environment: environment).lastPathComponent == "Moa", "iCloud folder should be Moa")
        try expect(MoaDataRoot.legacyNestedICloudURL(environment: environment).lastPathComponent == ".moa", "legacy nested iCloud folder should be .moa")
        try expect(MoaDataRoot.currentURL(environment: environment).path.hasSuffix("/.moa"), "default current root should stay local")
    }

    private static func testProfileCacheDistinguishesDataRoots() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let environment = [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex", isDirectory: true).path
        ]
        let controller = ConfigProfileController(environment: environment)
        _ = try controller.profiles()

        let localRoot = MoaDataRoot.localURL(environment: environment)
        let cloudRoot = MoaDataRoot.iCloudURL(environment: environment)
        try fileManager.createDirectory(at: cloudRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: localRoot, to: cloudRoot)
        let cloudProfile = ConfigProfile(
            id: UUID().uuidString,
            name: "Cloud Profile",
            baseURL: "https://cloud.example/v1",
            apiKey: "cloud-key"
        )
        let cloudDatabase = ProfileDatabase(selectedProfileID: cloudProfile.id, profiles: [cloudProfile])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let cloudDatabaseURL = cloudRoot.appendingPathComponent("profiles.json")
        try encoder.encode(cloudDatabase).write(to: cloudDatabaseURL, options: .atomic)
        let sharedModified = Date(timeIntervalSince1970: 1_700_000_000)
        try fileManager.setAttributes([.modificationDate: sharedModified], ofItemAtPath: controller.databaseURL.path)
        _ = try controller.profiles()
        try fileManager.setAttributes([.modificationDate: sharedModified], ofItemAtPath: cloudDatabaseURL.path)

        let support = MoaDataRoot.supportDirectory(environment: environment)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: support.appendingPathComponent("icloud-data-root-enabled"))
        let cloudProfiles = try controller.profiles()
        try expect(cloudProfiles.map(\.id) == [cloudProfile.id], "cache lookup must include the active data-root path, not only mtime")
    }

    private static func testLegacyMoaLiteLocalDataMigration() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let fileManager = FileManager.default
        let environment = ["HOME": home.path]
        let oldLocal = home.appendingPathComponent(".moa", isDirectory: true)
        let newLocal = MoaDataRoot.localURL(environment: environment)
        let legacyLocal = home.appendingPathComponent(".moa-lite", isDirectory: true)
        try fileManager.createDirectory(at: legacyLocal, withIntermediateDirectories: true)
        try "legacy".write(to: legacyLocal.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)

        let migrated = try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment)
        try expect(migrated, "legacy local data should migrate")
        let migratedProfileData = try String(contentsOf: newLocal.appendingPathComponent("profiles.json"), encoding: .utf8)
        try expect(migratedProfileData == "legacy", "legacy profile data should copy to ~/.moa")
        try expect(fileManager.fileExists(atPath: legacyLocal.path), "migration should leave ~/.moa-lite in place")

        try fileManager.removeItem(at: newLocal)
        try fileManager.createDirectory(at: oldLocal, withIntermediateDirectories: true)
        try "existing".write(to: oldLocal.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
        try "changed-legacy".write(to: legacyLocal.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)

        _ = try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment)
        let existingProfileData = try String(contentsOf: newLocal.appendingPathComponent("profiles.json"), encoding: .utf8)
        try expect(existingProfileData == "existing", "migration should not overwrite existing ~/.moa data")
    }

    private static func testLegacyMoaLiteICloudDataMigration() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let fileManager = FileManager.default
        let environment = ["HOME": home.path]
        let oldSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Moa-Lite", isDirectory: true)
        let oldICloud = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("Moa-Lite", isDirectory: true)
        try fileManager.createDirectory(at: oldSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: oldICloud, withIntermediateDirectories: true)
        try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
        try "icloud".write(to: oldICloud.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
        let existingAccounts = oldICloud.appendingPathComponent("codex-auth/accounts", isDirectory: true)
        let nestedAccounts = oldICloud.appendingPathComponent(".moa-lite/codex-auth/accounts", isDirectory: true)
        try fileManager.createDirectory(at: existingAccounts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedAccounts, withIntermediateDirectories: true)
        try "existing".write(to: existingAccounts.appendingPathComponent("existing.json"), atomically: true, encoding: .utf8)
        try "missing".write(to: nestedAccounts.appendingPathComponent("missing.json"), atomically: true, encoding: .utf8)

        let migrated = try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment)
        let newSupport = MoaDataRoot.supportDirectory(environment: environment)
        let newICloud = MoaDataRoot.iCloudURL(environment: environment)
        try expect(migrated, "legacy iCloud data should migrate")
        try expect(fileManager.fileExists(atPath: newSupport.appendingPathComponent("icloud-data-root-enabled").path), "iCloud state should migrate to Moa support directory")
        let migratedICloudProfileData = try String(contentsOf: newICloud.appendingPathComponent("profiles.json"), encoding: .utf8)
        try expect(migratedICloudProfileData == "icloud", "legacy iCloud data should copy to iCloud Drive/Moa")
        let copiedAfterMigration = try MoaDataRoot.copyMissingContents(
            from: newICloud.appendingPathComponent(".moa-lite", isDirectory: true),
            to: newICloud,
            fileManager: fileManager
        )
        try expect(
            fileManager.fileExists(atPath: newICloud.appendingPathComponent("codex-auth/accounts/missing.json").path),
            "legacy nested migration should descend into existing destination directories"
        )
        try expect(!copiedAfterMigration, "the migration itself should merge nested content without a second pass")
        try expect(MoaDataRoot.currentURL(environment: environment).lastPathComponent == "Moa", "current root should use migrated Moa iCloud folder")
    }

    private static func testLegacyNestedICloudDirectoryMigration() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let environment = ["HOME": home.path]
        let cloudRoot = MoaDataRoot.iCloudURL(environment: environment)
        let nestedRoot = MoaDataRoot.legacyNestedICloudURL(environment: environment)
        try fileManager.createDirectory(at: cloudRoot.appendingPathComponent("codex-auth/accounts"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedRoot.appendingPathComponent("codex-auth/accounts"), withIntermediateDirectories: true)
        try "authoritative".write(
            to: cloudRoot.appendingPathComponent("codex-auth/accounts/existing.json"),
            atomically: true,
            encoding: .utf8
        )
        try "legacy".write(
            to: nestedRoot.appendingPathComponent("codex-auth/accounts/missing.json"),
            atomically: true,
            encoding: .utf8
        )
        let support = MoaDataRoot.supportDirectory(environment: environment)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: support.appendingPathComponent("icloud-data-root-enabled"))

        let controller = MoaDataPackageController(environment: environment)
        let repaired = try controller.repairLegacyICloudDataSplitIfNeeded()
        try expect(repaired, "legacy nested directory data should be merged")
        try expect(
            fileManager.fileExists(atPath: cloudRoot.appendingPathComponent("codex-auth/accounts/missing.json").path),
            "nested account files should be copied recursively"
        )
        let existing = try String(
            contentsOf: cloudRoot.appendingPathComponent("codex-auth/accounts/existing.json"),
            encoding: .utf8
        )
        try expect(existing == "authoritative", "recursive merge must not overwrite current cloud files")
    }

    private static func testRecursiveMigrationRejectsDestinationSymlinks() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let source = home.appendingPathComponent("source", isDirectory: true)
        let destination = home.appendingPathComponent("destination", isDirectory: true)
        let external = home.appendingPathComponent("external", isDirectory: true)
        try fileManager.createDirectory(at: source.appendingPathComponent("accounts"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        try "legacy".write(
            to: source.appendingPathComponent("accounts/missing.json"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createSymbolicLink(
            atPath: destination.appendingPathComponent("accounts").path,
            withDestinationPath: external.path
        )

        let copied = try MoaDataRoot.copyMissingContents(from: source, to: destination, fileManager: fileManager)
        try expect(!copied, "a symlinked destination directory should not be treated as a merge target")
        try expect(
            !fileManager.fileExists(atPath: external.appendingPathComponent("missing.json").path),
            "recursive migration must not copy files through destination symlinks"
        )
    }

    private static func testTomlMultilineStringsSurviveStructuralEdits() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex", isDirectory: true).path
        ])
        let multilineBlock = #"""
        instructions = """
        Keep this text exactly.


        [model_providers.moa-not-a-real-table]
        experimental_bearer_token = "keep-inside-basic-string"
        """
        literal_instructions = '''
        [features]
        remote_connections = false
        base_url = "keep-inside-literal-string"
        '''
        """#
        let featureMultilineBlock = #"""
        feature_note = """
        remote_connections = false


        remote_control = false
        """
        """#
        let config = #"""
        model_provider = "one"
        model = "gpt-test"

        """# + multilineBlock + #"""

        [features]
        remote_connections = true
        remote_control = true
        """# + featureMultilineBlock + #"""

        [model_providers.one]
        name = "One"
        base_url = "https://one.example/v1"
        experimental_bearer_token = "remove-real-token"
        wire_api = "responses"
        """#

        let profile = ConfigProfile(
            id: UUID().uuidString,
            name: "Replacement",
            baseURL: "https://replacement.example/v1",
            apiKey: "replacement-token"
        )
        let generated = controller.generateConfig(config, selecting: profile)
        try expect(generated.contains(multilineBlock), "profile generation must preserve multiline basic and literal strings byte-for-byte")
        try expect(generated.contains(featureMultilineBlock), "feature normalization must preserve multiline content and blank lines")
        try expect(!generated.contains("https://one.example/v1"), "profile generation should still replace the real provider table")

        let restored = MoaCodexConfigEditor.restoringOfficialMode(from: config)
        try expect(restored.contains(multilineBlock), "official restore must not interpret table-like multiline content as TOML structure")
        try expect(!restored.contains("remove-real-token"), "official restore should still remove the real selected provider credential")
        try expect(restored.contains("keep-inside-basic-string"), "official restore should preserve managed-looking keys inside basic multiline strings")
        try expect(restored.contains("keep-inside-literal-string"), "official restore should preserve managed-looking keys inside literal multiline strings")

        let remoteConnectionsRemoved = controller.setRemoteConnections(false, in: config)
        try expect(remoteConnectionsRemoved.contains(featureMultilineBlock), "disabling remote connections must preserve same-named keys inside feature multiline strings")
        try expect(!remoteConnectionsRemoved.contains("remote_connections = true"), "disabling remote connections should remove the real feature key")
    }

    private static func testFastStateTomlMultilineStrings() throws {
        let controller = FastStateController(environment: ["HOME": "/tmp/moa-fast-state-test"])
        let multilineBlock = #"""
        instructions = """
        [features]
        remote_connections = false
        remote_control = false
        """
        literal = '''
        [features]
        remote_connections = true
        '''
        """#
        let config = multilineBlock + #"""

        [features]
        remote_connections = true
        remote_control = true
        """#

        let disabled = controller.setRemoteConnections(false, in: config)
        try expect(disabled.contains(multilineBlock), "FastStateController must preserve table-like content inside multiline strings")
        try expect(controller.remoteConnectionsEnabled(in: disabled) == false, "FastStateController should remove the real remote feature keys")

        let enabled = controller.setRemoteConnections(true, in: disabled)
        try expect(enabled.contains(multilineBlock), "enabling remote connections must also preserve multiline strings")
        try expect(controller.remoteConnectionsEnabled(in: enabled), "FastStateController should restore both real remote feature keys")
    }

    private static func testOfficialRestoreKeepsSelectedProviderIdentity() throws {
        let config = """
        model = "deepseek-chat"
        model_provider = "moa-deepseek"

        [model_providers.moa-deepseek]
        name = "Moa DeepSeek"
        base_url = "http://127.0.0.1:19360/v1"
        experimental_bearer_token = "moa-token"
        wire_api = "responses"
        """

        let restored = MoaCodexConfigEditor.restoringOfficialMode(from: config)
        try expect(restored.contains(#"model_provider = "moa-deepseek""#), "official restore should preserve root provider selection")
        try expect(restored.contains("[model_providers.moa-deepseek]"), "selected provider table should stay available for session continuity")
        try expect(restored.contains(#"name = "Moa DeepSeek""#), "selected provider display name should be preserved")
        try expect(!restored.contains("http://127.0.0.1:19360/v1"), "selected provider base URL should be removed")
        try expect(!restored.contains("moa-token"), "selected provider token should be removed")
    }

    private static func testOfficialRestoreStripsSelectedDirectProviderCredentials() throws {
        let config = """
        model_reasoning_effort = "xhigh"
        disable_response_storage = true
        model_provider = "one"

        [model_providers.one]
        name = "one"
        base_url = "https://gateway.example.invalid"
        experimental_bearer_token = "sk-test"
        wire_api = "responses"
        requires_openai_auth = true

        [model_providers.backup]
        name = "backup"
        base_url = "https://backup.example.com"
        experimental_bearer_token = "backup-token"
        wire_api = "responses"
        requires_openai_auth = true
        """

        let restored = MoaCodexConfigEditor.restoringOfficialMode(from: config)
        try expect(restored.contains(#"model_provider = "one""#), "official restore should keep the selected provider id")
        try expect(restored.contains("[model_providers.one]"), "official restore should keep the selected provider table")
        try expect(restored.contains(#"name = "one""#), "official restore should keep the selected provider name")
        try expect(restored.contains(#"wire_api = "responses""#), "official restore should keep non-secret provider metadata")
        try expect(restored.contains("requires_openai_auth = true"), "official restore should keep OpenAI auth mode metadata")
        try expect(!restored.contains("https://gateway.example.invalid"), "official restore should remove the selected provider base URL")
        try expect(!restored.contains("sk-test"), "official restore should remove the selected provider token")
        try expect(restored.contains("https://backup.example.com"), "official restore should leave unselected custom providers alone")
        try expect(restored.contains("backup-token"), "official restore should not alter unselected custom provider tokens")
    }

    private static func testCodexSessionProviderMigrationRequiresCurrentProvider() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try """
        model = "gpt-test"

        [model_providers.one]
        name = "one"
        """.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])

        do {
            _ = try controller.currentCodexRootModelProvider()
            throw TestError.failure("missing root model_provider should fail")
        } catch CodexSessionProviderMigrationError.missingModelProvider {
            return
        }
    }

    private static func testCodexSessionProviderMigrationUpdatesJSONLAndSQLite() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let fileManager = FileManager.default
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/06/29", isDirectory: true)
        let archivedSessions = codexHome.appendingPathComponent("archived_sessions/2026/06/28", isDirectory: true)
        let nestedSQLite = codexHome.appendingPathComponent("sqlite", isDirectory: true)
        try fileManager.createDirectory(at: sessions, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: archivedSessions, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedSQLite, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let activeJSONL = sessions.appendingPathComponent("rollout-active.jsonl")
        try """
        {"timestamp":"2026-06-29T00:00:00Z","payload":{"model_provider":"codex_local_access","id":"active"}}
        {"type":"message","payload":{"text":"keep codex_local_access in body text"}}
        """.write(to: activeJSONL, atomically: true, encoding: .utf8)

        let archivedJSONL = archivedSessions.appendingPathComponent("rollout-archived.jsonl")
        try """
        {"timestamp":"2026-06-28T00:00:00Z","payload":{"model_provider":"openai","id":"archived"}}
        """.write(to: archivedJSONL, atomically: true, encoding: .utf8)

        let unchangedJSONL = sessions.appendingPathComponent("rollout-current.jsonl")
        try """
        {"timestamp":"2026-06-29T01:00:00Z","payload":{"model_provider":"one","id":"current"}}
        """.write(to: unchangedJSONL, atomically: true, encoding: .utf8)

        let missingPayloadJSONL = sessions.appendingPathComponent("rollout-missing-payload.jsonl")
        let missingPayloadText = """
        {"timestamp":"2026-06-29T02:00:00Z","id":"missing-payload"}
        """
        try missingPayloadText.write(to: missingPayloadJSONL, atomically: true, encoding: .utf8)

        let missingProviderJSONL = sessions.appendingPathComponent("rollout-missing-provider.jsonl")
        let missingProviderText = """
        {"timestamp":"2026-06-29T03:00:00Z","payload":{"id":"missing-provider"}}
        """
        try missingProviderText.write(to: missingProviderJSONL, atomically: true, encoding: .utf8)

        let mainDB = codexHome.appendingPathComponent("state_5.sqlite")
        let nestedDB = nestedSQLite.appendingPathComponent("state_5.sqlite")
        try createSessionProviderTestDatabase(at: mainDB, providers: ["codex_local_access", "openai", "one"])
        try createSessionProviderTestDatabase(at: nestedDB, providers: ["openai", "one"])

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        let result = try controller.migrateCodexSessionModelProviderToCurrentConfig()

        try expect(result.providerID == "one", "migration should use current root model_provider")
        try expect(result.jsonlFilesUpdated == 2, "migration should update only JSONL files with non-current providers")
        try expect(result.sqliteRowsUpdated == 3, "migration should update non-current SQLite rows in both indexes")
        try expect(fileManager.fileExists(atPath: result.backupURL.path), "migration should create a rollback backup")
        let activeProvider = try firstJSONLPayloadProvider(in: activeJSONL)
        let archivedProvider = try firstJSONLPayloadProvider(in: archivedJSONL)
        let unchangedProvider = try firstJSONLPayloadProvider(in: unchangedJSONL)
        try expect(activeProvider == "one", "active JSONL payload provider should be updated")
        try expect(archivedProvider == "one", "archived JSONL payload provider should be updated")
        try expect(unchangedProvider == "one", "current JSONL provider should remain one")
        let activeText = try String(contentsOf: activeJSONL, encoding: .utf8)
        try expect(activeText.contains("keep codex_local_access in body text"), "migration should not rewrite JSONL body text")
        let missingPayloadAfterMigration = try String(contentsOf: missingPayloadJSONL, encoding: .utf8)
        let missingProviderAfterMigration = try String(contentsOf: missingProviderJSONL, encoding: .utf8)
        try expect(missingPayloadAfterMigration == missingPayloadText, "migration should not add payloads to non-session metadata")
        try expect(missingProviderAfterMigration == missingProviderText, "migration should not add missing model_provider fields")
        let mainCounts = try sqliteProviderCounts(in: mainDB)
        let nestedCounts = try sqliteProviderCounts(in: nestedDB)
        try expect(mainCounts == ["one": 3], "main SQLite index should only contain one")
        try expect(nestedCounts == ["one": 2], "nested SQLite index should only contain one")
    }

    private static func testCodexSessionProviderMigrationRollsBackOnFailure() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let fileManager = FileManager.default
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/06/29", isDirectory: true)
        try fileManager.createDirectory(at: sessions, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let activeJSONL = sessions.appendingPathComponent("rollout-active.jsonl")
        try """
        {"timestamp":"2026-06-29T00:00:00Z","payload":{"model_provider":"openai","id":"active"}}
        """.write(to: activeJSONL, atomically: true, encoding: .utf8)

        let malformedDB = codexHome.appendingPathComponent("state_5.sqlite")
        try "not a sqlite database".write(to: malformedDB, atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])

        do {
            _ = try controller.migrateCodexSessionModelProviderToCurrentConfig()
            throw TestError.failure("migration should fail when SQLite index is unreadable")
        } catch let error as CodexSessionProviderMigrationError {
            switch error {
            case .migrationFailedAndRestored(_, _):
                break
            default:
                throw TestError.failure("expected restored migration failure, got \(error.localizedDescription)")
            }
        }

        let restoredProvider = try firstJSONLPayloadProvider(in: activeJSONL)
        let restoredDB = try String(contentsOf: malformedDB, encoding: .utf8)
        try expect(restoredProvider == "openai", "failed migration should restore JSONL changes")
        try expect(restoredDB == "not a sqlite database", "failed migration should restore SQLite files")
    }

    private static func testOfficialAccountDisplaysEmailFromAuthToken() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let email = "user@example.com"
        let idToken = try testJWT(email: email)
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(idToken)",
            "refresh_token": "refresh-token"
          },
          "last_refresh": "2026-06-26T00:00:00Z"
        }
        """.write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        let accounts = try controller.officialAccounts()
        try expect(accounts.count == 1, "bootstrap should save the current Codex official login")
        guard let account = accounts.first else {
            throw TestError.failure("saved account should be available")
        }

        try expect(account.email == email, "saved official account should record the email from id_token")
        try expect(account.displayTitle == email, "default saved account should display the email")
        try expect(controller.selectedOfficialAccountName() == email, "selected official account should expose the email display title")

        let renamed = try controller.renameSelectedOfficialAccount(name: "Plus")
        try expect(renamed.displayTitle == "Plus(\(email))", "renamed official account should display name plus email")
        try expect(controller.selectedOfficialAccountName() == "Plus(\(email))", "selected renamed official account should expose name plus email")
    }

    private static func testOfficialAccountAuthPathValidation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let environment = ["HOME": home.path, "CODEX_HOME": codexHome.path]
        let controller = ConfigProfileController(environment: environment)

        let safe = controller.makeOfficialAccount(name: "Safe")
        let safeURL = try controller.officialAuthURL(for: safe)
        try expect(safeURL.deletingLastPathComponent().lastPathComponent == "accounts", "generated auth paths should resolve inside the accounts directory")
        try expect(safeURL.lastPathComponent == "\(safe.id).json", "generated auth filename should match the account UUID")

        for invalidPath in ["../outside.json", "/tmp/outside.json", "codex-auth/accounts/other.json"] {
            var invalid = safe
            invalid.authPath = invalidPath
            do {
                _ = try controller.officialAuthURL(for: invalid)
                throw TestError.failure("invalid official auth path should be rejected: \(invalidPath)")
            } catch CodexOfficialAccountError.invalidAuthPath {
                continue
            }
        }

        let externalAccounts = home.appendingPathComponent("external-accounts", isDirectory: true)
        try fileManager.createDirectory(at: externalAccounts, withIntermediateDirectories: true)
        try fileManager.removeItem(at: controller.officialAuthAccountsDir)
        try fileManager.createSymbolicLink(
            atPath: controller.officialAuthAccountsDir.path,
            withDestinationPath: externalAccounts.path
        )
        do {
            _ = try controller.officialAuthURL(for: safe)
            throw TestError.failure("a symlinked official account directory should be rejected")
        } catch CodexOfficialAccountError.invalidAuthPath {
            try fileManager.removeItem(at: controller.officialAuthAccountsDir)
            try fileManager.createDirectory(at: controller.officialAuthAccountsDir, withIntermediateDirectories: true)
        }

        var persistedInvalid = safe
        persistedInvalid.authPath = "codex-auth/accounts/../outside.json"
        let database = CodexOfficialAccountDatabase(selectedAccountID: safe.id, accounts: [persistedInvalid])
        let data = try JSONEncoder().encode(database)
        try data.write(to: controller.officialAccountsDatabaseURL, options: .atomic)
        let reloaded = ConfigProfileController(environment: environment)
        do {
            _ = try reloaded.selectedOfficialAccountID()
            throw TestError.failure("persisted invalid official auth path should fail database loading")
        } catch CodexOfficialAccountError.invalidAuthPath {
            return
        }
    }

    private static func testOfficialNoAccountPreservesThirdPartyConfigWithoutLogin() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        let account = try controller.applyOfficialNoAccountMode()
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        let auth = try String(contentsOf: codexHome.appendingPathComponent("auth.json"), encoding: .utf8)
        let selectedProfileID = try controller.selectedProfileID()
        let selectedAccountID = try controller.selectedOfficialAccountID()

        try expect(account == nil, "no-account mode should not create an account when Codex is not logged in")
        try expect(selectedProfileID != nil, "no-account mode should preserve selected direct profile state")
        try expect(selectedAccountID == nil, "no-account mode should select the no-account option")
        try expect(config.contains(#"base_url = "https://gateway.example.invalid""#), "no-account mode should preserve config.toml base_url")
        try expect(config.contains(#"experimental_bearer_token = "sk-test""#), "no-account mode should preserve config.toml token")
        try expect(auth == noAccountAuthJSONText, "no-account mode should write Codex auth in API key mode")
    }

    private static func testOfficialNoAccountCapturesCurrentLoginWithoutSelectingIt() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let email = "user@example.com"
        let idToken = try testJWT(email: email)
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(idToken)",
            "refresh_token": "refresh-token"
          },
          "last_refresh": "2026-06-26T00:00:00Z"
        }
        """.write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        let account = try controller.applyOfficialNoAccountMode()
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        let auth = try String(contentsOf: codexHome.appendingPathComponent("auth.json"), encoding: .utf8)
        let selectedProfileID = try controller.selectedProfileID()
        let selectedAccountID = try controller.selectedOfficialAccountID()
        let accountTitles = try controller.officialAccounts().map(\.displayTitle)

        try expect(account == nil, "logged-in no-account click should not keep using the current login")
        try expect(selectedProfileID != nil, "logged-in no-account click should preserve selected direct profile state")
        try expect(selectedAccountID == nil, "logged-in no-account click should select the no-account option")
        try expect(accountTitles.contains(email), "saved account should appear below the no-account option")
        try expect(config.contains(#"base_url = "https://gateway.example.invalid""#), "logged-in no-account mode should preserve config.toml base_url")
        try expect(config.contains(#"experimental_bearer_token = "sk-test""#), "logged-in no-account mode should preserve config.toml token")
        try expect(auth == noAccountAuthJSONText, "logged-in no-account mode should write Codex auth in API key mode")
    }

    private static func testOfficialNoAccountSelectsFirstDirectConfigWhenNoneSelected() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        let profile = try controller.addProfile(
            name: "First API",
            baseURL: "https://api.example.com/v1",
            apiKey: "sk-first"
        )
        let selectedProfileIDBeforeNoAccount = try controller.selectedProfileID()
        try expect(selectedProfileIDBeforeNoAccount == nil, "newly added direct profile should not be selected by setup")

        _ = try controller.applyOfficialNoAccountMode()
        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        let auth = try String(contentsOf: codexHome.appendingPathComponent("auth.json"), encoding: .utf8)
        let selectedProfileID = try controller.selectedProfileID()
        let selectedAccountID = try controller.selectedOfficialAccountID()

        try expect(selectedProfileID == profile.id, "no-account mode should select the first direct Codex config when none is selected")
        try expect(selectedAccountID == nil, "no-account fallback should not select an official account")
        try expect(config.contains(#"base_url = "https://api.example.com/v1""#), "first direct config should be written to config.toml")
        try expect(config.contains(#"experimental_bearer_token = "sk-first""#), "first direct config token should be written to config.toml")
        try expect(auth == noAccountAuthJSONText, "no-account fallback should write Codex auth in API key mode")
    }

    private static func testOfficialNoAccountDeduplicatesCurrentLoginByEmail() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let email = "user@example.com"
        try authJSON(email: email, refreshToken: "refresh-token-old")
            .write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        _ = try controller.renameSelectedOfficialAccount(name: "Plus_TR")

        try authJSON(email: email, refreshToken: "refresh-token-new")
            .write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        _ = try controller.applyOfficialNoAccountMode()
        let accounts = try controller.officialAccounts()
        let selectedAccountID = try controller.selectedOfficialAccountID()

        try expect(accounts.count == 1, "no-account mode should update the existing email-matched account instead of creating a duplicate")
        try expect(accounts.first?.displayTitle == "Plus_TR(\(email))", "existing renamed account should keep its name and email")
        try expect(selectedAccountID == nil, "no-account option should remain selected after deduplication")
    }

    private static func testOfficialAccountListSyncsSelectedAccountEmail() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try thirdPartyConfig.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "fixture-selected-account"
          },
          "last_refresh": "2026-06-26T00:00:00Z"
        }
        """.write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path
        ])
        _ = try controller.renameSelectedOfficialAccount(name: "K12")

        let email = "k12@example.com"
        try authJSON(email: email, refreshToken: "refresh-token-new", accountID: "fixture-selected-account")
            .write(to: codexHome.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let accounts = try controller.officialAccounts()

        try expect(accounts.count == 1, "selected account sync should not create another account")
        try expect(accounts.first?.displayTitle == "K12(\(email))", "selected account should show email after Codex relogin")
    }

    private static func testJWT(email: String) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["email": email], options: [])
        let payloadText = payload
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payloadText).signature"
    }

    private static func authJSON(email: String, refreshToken: String, accountID: String? = nil) throws -> String {
        let idToken = try testJWT(email: email)
        var tokens = ["access_token": "access-token", "id_token": idToken, "refresh_token": refreshToken]
        tokens["account_id"] = accountID
        let data = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt", "tokens": tokens, "last_refresh": "2026-06-26T00:00:00Z"
        ], options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func firstJSONLPayloadProvider(in fileURL: URL) throws -> String? {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        guard let firstLine = text.components(separatedBy: "\n").first,
              let data = firstLine.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }
        return payload["model_provider"] as? String
    }

    private static func createSessionProviderTestDatabase(at url: URL, providers: [String]) throws {
        let values = providers.enumerated().map { index, provider in
            "('thread-\(index)', '\(provider)', 0)"
        }.joined(separator: ",")
        _ = try runSQLite(
            url,
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                model_provider TEXT NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO threads (id, model_provider, archived) VALUES \(values);
            """
        )
    }

    private static func sqliteProviderCounts(in url: URL) throws -> [String: Int] {
        let output = try runSQLite(url, "SELECT model_provider, COUNT(*) FROM threads GROUP BY model_provider ORDER BY model_provider;")
        var counts: [String: Int] = [:]
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "|")
            guard parts.count == 2, let count = Int(parts[1]) else { continue }
            counts[parts[0]] = count
        }
        return counts
    }

    private static func runSQLite(_ url: URL, _ sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw TestError.failure("sqlite3 failed: \(errorOutput)")
        }
        return output
    }

    private static let thirdPartyConfig = """
    model_provider = "one"
    model = "gpt-5.5"

    [model_providers.one]
    name = "one"
    base_url = "https://gateway.example.invalid"
    experimental_bearer_token = "sk-test"
    wire_api = "responses"
    requires_openai_auth = true
    """

    private static let noAccountAuthJSONText = """
    {
      "auth_mode": "apikey",
      "OPENAI_API_KEY": "null"
    }
    """ + "\n"

    private static func testGPT56Pricing() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        MoaUsagePricing.useRemoteCatalogStoreForTesting(
            MoaUsagePricingCatalogStore(environment: ["HOME": home.path])
        )
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }

        let standardCases: [(model: String, expected: Double)] = [
            ("gpt-5.6", 2.62),
            ("gpt-5.6-sol", 2.62),
            ("openai/gpt-5.6-terra", 1.51),
            ("gpt-5.6-luna-2026-07-09", 0.151)
        ]
        for item in standardCases {
            let estimate = MoaUsagePricing.codexCostEstimate(
                model: item.model,
                inputTokens: 200_000,
                cachedInputTokens: 50_000,
                outputTokens: 100_000
            )
            try expect(estimate?.usesFallbackPricing == false, "\(item.model) should use its own GPT-5.6 price")
            try expectClose(estimate?.costUSD ?? -1, item.expected, "\(item.model) should use current standard pricing")
        }

        let longContextCases: [(model: String, expected: Double)] = [
            ("gpt-5.6-sol", 4.68),
            ("gpt-5.6-terra", 2.64),
            ("gpt-5.6-luna", 0.264)
        ]
        for item in longContextCases {
            let cost = MoaUsagePricing.codexCostUSD(
                model: item.model,
                inputTokens: 300_000,
                cachedInputTokens: 100_000,
                outputTokens: 100_000
            )
            try expectClose(cost ?? -1, item.expected, "\(item.model) should use current long-context pricing")
        }

        let priorityCases: [(model: String, expected: Double)] = [
            ("gpt-5.6", 5.24),
            ("gpt-5.6-sol", 5.24),
            ("gpt-5.6-terra", 3.02),
            ("gpt-5.6-luna", 0.302)
        ]
        for item in priorityCases {
            let cost = MoaUsagePricing.codexPriorityCostUSD(
                model: item.model,
                inputTokens: 200_000,
                cachedInputTokens: 50_000,
                outputTokens: 100_000
            )
            try expectClose(cost ?? -1, item.expected, "\(item.model) should use current priority pricing")
        }
    }

    private static func testChatGPTApplicationOverride() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Renamed Client.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.openai.codex", "CFBundleExecutable": "ChatGPT", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try expect(CodexDesktopApplication.applicationURL(environment: ["HOME": home.path, "CODEX_APP": app.path])?.path == app.resolvingSymlinksInPath().path, "explicit application path must support renamed bundles")
        try expect(CodexDesktopApplication.applicationURL(environment: ["HOME": home.path, "CODEX_APP": home.appendingPathComponent("Missing.app").path]) == nil, "missing explicit app must not fall back to a real running client")
    }

    private static func testChatGPTFastMode() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        let moa = home.appendingPathComponent(".moa")
        for directory in [codex, moa] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let config = codex.appendingPathComponent("config.toml")
        let mirror = moa.appendingPathComponent("config.toml")
        let state = codex.appendingPathComponent(".codex-global-state.json")
        let originalState = #"{"electron-persisted-atom-state":{"default-service-tier":"fast","unrelated":true}}"#
        try originalState.write(to: state, atomically: true, encoding: .utf8)
        let initial = "service_tier = \"default\"\n[desktop]\ndefault-service-tier = \"priority\"\nappearanceTheme = \"dark\"\n"
        try initial.write(to: config, atomically: true, encoding: .utf8)
        try initial.write(to: mirror, atomically: true, encoding: .utf8)
        let controller = FastStateController(environment: ["HOME": home.path, "CODEX_APP": home.appendingPathComponent("Missing.app").path])
        try expect(controller.isFastEnabled(), "desktop priority must report Fast enabled")
        try controller.applyFastMode(false)
        try expect(!controller.isFastEnabled(), "explicit desktop default must override legacy fast")
        let disabled = try String(contentsOf: config, encoding: .utf8)
        try expect(MoaTomlEditor.stringValue(in: disabled, table: "", key: "service_tier") == "default", "disabling Fast must clear the root fallback")
        try expect(MoaTomlEditor.stringValue(in: disabled, table: "desktop", key: "appearanceTheme") == "dark", "unrelated preferences must survive")
        let mirrored = try String(contentsOf: mirror, encoding: .utf8)
        try expect(mirrored == disabled, "Moa mirror must follow the speed change")
        let savedState = try String(contentsOf: state, encoding: .utf8)
        try expect(savedState == originalState, "modern changes must not rewrite legacy JSON")
        try controller.applyFastMode(true)
        try expect(controller.isFastEnabled(), "enabling Fast must update the current desktop setting")
        try expect(FileManager.default.fileExists(atPath: codex.appendingPathComponent("fast-toggle-backups").path), "Fast changes must create recovery backups")
    }

    private static func testLiveConfigPreservation() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = ConfigProfileController(environment: ["HOME": home.path])
        let live = #"""
        model_provider = "one"
        service_tier = "default"
        instructions = """
        keep this [desktop] text
        """
        [desktop]
        default-service-tier = "priority"
        appearanceTheme = "light"
        [model_providers.one]
        name = "One"
        base_url = "https://old.example/v1"
        [model_providers.backup]
        name = "Backup"
        base_url = "https://backup.example/v1"
        [[skills.config]]
        path = "example-skill"
        enabled = false
        """#
        let old = "obsolete = true\nservice_tier = \"priority\"\n[desktop]\ndefault-service-tier = \"default\"\n"
        try expect(controller.syncConfigStructure(from: live, into: old) == live, "live client text must be authoritative")
        try expect(controller.syncConfigStructure(from: "", into: old).isEmpty, "cleared config must not resurrect old preferences")
        let profile = ConfigProfile(id: "replacement", name: "Replacement", baseURL: "https://new.example/v1", apiKey: "example-test-key")
        let generated = controller.generateConfig(live, selecting: profile)
        try expect(generated.contains("https://new.example/v1") && !generated.contains("https://old.example/v1"), "selected provider must be replaced")
        try expect(generated.contains("https://backup.example/v1"), "unrelated provider must survive")
        try expect(generated.contains("[[skills.config]]") && generated.contains("example-skill"), "array tables after providers must survive")
        try expect(MoaTomlEditor.stringValue(in: generated, table: "desktop", key: "default-service-tier") == "priority", "desktop preference must remain current")
        try expect(!generated.contains("remote_connections = true"), "provider switching must not add obsolete connection flags")
        let stock = controller.generateConfig("model_provider = \"openai\"\n", selecting: profile)
        try expect(!stock.contains("[model_providers.openai]"), "built-in OpenAI provider must not be overridden")
    }

    private static func testDesktopTomlScalarStyles() throws {
        let dotted = "desktop.default-service-tier = 'fast'\n[[skills.config]]\nservice_tier = 'nested'\n"
        let updated = MoaTomlEditor.upsertingString("default", in: dotted, table: "desktop", key: "default-service-tier")
        try expect(MoaTomlEditor.stringValue(in: updated, table: "desktop", key: "default-service-tier") == "default", "dotted key should be updated in place")
        let root = MoaTomlEditor.upsertingString("priority", in: updated, table: "", key: "service_tier")
        try expect(MoaTomlEditor.stringValue(in: root, table: "", key: "service_tier") == "priority", "root insertion must occur before an array table")
        try expect(root.contains("service_tier = 'nested'"), "array member must not be overwritten as a root key")
        let quoted = "[\"desktop\"]\n\"default-service-tier\" = 'priority'\n"
        let changed = MoaTomlEditor.upsertingString("default", in: quoted, table: "desktop", key: "default-service-tier")
        try expect(MoaTomlEditor.stringValue(in: changed, table: "desktop", key: "default-service-tier") == "default", "quoted desktop keys must remain readable after editing")
    }

    private static func testCodexNewUsageRecords() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        MoaUsagePricing.useRemoteCatalogStoreForTesting(MoaUsagePricingCatalogStore(environment: ["HOME": home.path]))
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        func counts(_ multiplier: Int) -> [String: Int] {
            ["input_tokens": 200_000 * multiplier, "cached_input_tokens": 50_000 * multiplier,
             "cache_write_input_tokens": 100_000 * multiplier, "output_tokens": 10_000 * multiplier]
        }
        var events: [[String: Any]] = []
        func append(_ type: String, _ payload: [String: Any]) {
            events.append(["type": type, "timestamp": "2026-09-05T10:00:00Z", "payload": payload])
        }
        append("turn_context", ["model": "gpt-6-astra"])
        for index in 1...2 {
            let record: [String: Any] = ["response_id": "example-response-\(index)", "usage": counts(1), "thread_token_usage": counts(index)]
            append("token_usage_record", record)
            append("token_usage_record", record)
            let legacy: [String: Any] = ["type": "token_count", "info": ["last_token_usage": counts(1), "total_token_usage": counts(index)]]
            append("event_msg", legacy)
            append("event_msg", legacy)
        }
        // A legacy-only context in the same file must not disappear.
        append("turn_context", ["model": "gpt-5.6-luna"])
        let legacyCounts = ["input_tokens": 100_000, "cached_input_tokens": 20_000, "output_tokens": 1_000]
        let legacy: [String: Any] = ["type": "token_count", "info": ["last_token_usage": legacyCounts, "total_token_usage": legacyCounts]]
        append("event_msg", legacy)
        append("event_msg", legacy)
        let text = try events.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try text.write(to: sessions.appendingPathComponent("sample.jsonl"), atomically: true, encoding: .utf8)
        let scanner = CodexUsageScanner(environment: ["HOME": home.path])
        let report = try scanner.loadReport(forceRefresh: true)
        guard let astra = report.rows.first(where: { $0.model == "gpt-6-astra" }),
              let luna = report.rows.first(where: { $0.model == "gpt-5.6-luna" }) else { throw TestError.failure("both record formats must produce rows") }
        try expect(astra.totalTokens == 420_000 && astra.cacheCreationInput == 200_000 && astra.cachedInput == 100_000, "new records must count each response once and retain cache writes")
        try expectClose(astra.costUSD, 4.6, "two 200K requests must each use short-context prices")
        try expect(luna.totalTokens == 101_000, "duplicate legacy totals must not count twice")
        try expectClose(luna.costUSD, 0.0176, "legacy-only context must use its own model price")
        let cached = try scanner.loadReport(forceRefresh: false)
        try expectClose(cached.totalCostUSD, report.totalCostUSD, "persisted v3 cache must preserve request-level prices")
    }

    private static func testGPT6PricingAndCatalogFreshness() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = MoaUsagePricingCatalogStore(environment: ["HOME": home.path])
        MoaUsagePricing.useRemoteCatalogStoreForTesting(store)
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let cost = MoaUsagePricing.codexCostEstimate(model: "gpt-6-astra", inputTokens: 200_000, cachedInputTokens: 50_000, cacheWriteInputTokens: 100_000, outputTokens: 10_000)
        try expect(cost?.usesFallbackPricing == false, "Astra must not use GPT-5.5 fallback")
        try expectClose(cost?.costUSD ?? -1, 2.3, "Astra must charge cache writes at 1.25x input")
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-astra", inputTokens: 272_000, cachedInputTokens: 0, outputTokens: 0) ?? -1, 2.72, "272K request stays in short-context tier")
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-astra", inputTokens: 272_001, cachedInputTokens: 0, outputTokens: 0) ?? -1, 5.44002, "larger request uses long-context tier")
        try expectClose(MoaUsagePricing.codexPriorityCostUSD(model: "gpt-6-astra", inputTokens: 300_000, cachedInputTokens: 100_000, outputTokens: 100_000) ?? -1, 23.4, "Astra Fast mode supports long-context prices")
        let stale = MoaUsageRemotePricing(inputUSDPerMillion: 0.1, outputUSDPerMillion: 0.2)
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.com/pricing", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), models: ["codex": ["gpt-6-astra": stale]]))
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-astra", inputTokens: 100_000, cachedInputTokens: 0, outputTokens: 0) ?? -1, 1, "stale downloaded catalog must not replace verified built-in prices")
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.com/pricing", fetchedAt: Date(timeIntervalSince1970: 1_900_000_000), models: ["codex": ["example-future-model": stale]]))
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-astra", inputTokens: 100_000, cachedInputTokens: 0, outputTokens: 0) ?? -1, 1, "refreshing other models must not mark omitted old prices as fresh")
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.com/pricing", fetchedAt: Date(timeIntervalSince1970: 1_900_000_000), models: ["codex": ["gpt-6-astra": stale]]))
        try expectClose(MoaUsagePricing.codexCostUSD(model: "gpt-6-astra", inputTokens: 100_000, cachedInputTokens: 0, outputTokens: 0) ?? -1, 0.01, "newer catalog remains eligible to refresh prices")
    }

    private static func testPrereleaseUpdates() throws {
        try expect(MoaUpdateController.isRemoteVersion("1.2.0", remoteBuild: 117, newerThan: "1.2.0-rc.1", localBuild: 116), "stable release must supersede its RC")
        try expect(!MoaUpdateController.isRemoteVersion("1.2.0-rc.1", remoteBuild: 118, newerThan: "1.2.0", localBuild: 117), "a newer build number must not promote an RC over stable")
        try expect(MoaUpdateController.isRemoteVersion("1.2.0-rc.10", remoteBuild: nil, newerThan: "1.2.0-rc.2", localBuild: nil), "RC identifiers must compare numerically")
        let feed = """
        <feed>
        <entry><title>Moa 1.2.0-rc.1</title><link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.2.0-rc.1"/><content>Moa-1.2.0-rc.1-macos-arm64.dmg Moa-1.2.0-rc.1-macos-x86_64.dmg Build: 116</content></entry>
        <entry><title>Moa 1.1.8</title><link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.1.8"/><content>Moa-1.1.8-macos-arm64.dmg Moa-1.1.8-macos-x86_64.dmg Build: 115</content></entry>
        </feed>
        """
        let stable = try MoaUpdateController.releaseInfo(fromAtomFeed: feed)
        try expect(stable.version == "1.1.8", "stable feed fallback must skip RC entries")
        let candidate = try MoaUpdateController.releaseInfo(fromAtomFeed: feed, includePrereleases: true)
        try expect(candidate.version == "1.2.0-rc.1" && candidate.dmgURL.lastPathComponent.contains("-rc.1-"), "explicit prerelease parsing must retain complete RC asset names")
    }

    private static func testCodexUsageIgnoresInheritedHistory() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions/2026/07/11", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("rollout-subagent.jsonl")
        let lines = [
            #"{"timestamp":"2026-07-11T13:00:00Z","type":"session_meta","payload":{"id":"child","source":{"subagent":{}}}}"#,
            #"{"timestamp":"2026-07-11T13:00:00.001Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":900000,"output_tokens":10000}}}}"#,
            #"{"timestamp":"2026-07-11T13:00:01Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-07-11T13:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100}}}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let report = try CodexUsageScanner(environment: ["HOME": home.path])
            .loadReport(forceRefresh: true, now: Date(), persistCache: false)
        try expect(report.rows.count == 1, "only model-attributed usage should be reported")
        guard let row = report.rows.first else {
            throw TestError.failure("expected Codex usage row")
        }
        try expect(row.model == "gpt-5.6-sol", "usage should retain the verified turn model")
        try expect(row.input == 200, "non-cached input should exclude inherited history")
        try expect(row.cachedInput == 800, "cached input should exclude inherited history")
        try expect(row.output == 100, "output should exclude inherited history")
        try expect(!report.rows.contains { $0.model == "gpt-5" }, "unknown history must not be mislabeled as GPT-5")
    }

    private static func testRemotePricingCatalog() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let sourceURL = URL(string: "https://models.dev/api.json")!
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let data = Data(remotePricingFixture.utf8)
        var snapshot = try MoaUsagePricingRemoteParser.parse(
            data: data,
            sourceURL: sourceURL,
            fetchedAt: fetchedAt
        )
        let parsed = snapshot.models[MoaUsageSource.codex.rawValue]?["gpt-5.7"]
        try expect(parsed?.thresholdTokens == 272_000, "remote context tier should preserve its threshold")
        try expectClose(parsed?.inputUSDPerMillionAboveThreshold ?? -1, 4, "remote context tier should preserve input pricing")

        let store = MoaUsagePricingCatalogStore(environment: ["HOME": home.path])
        let firstUpdate = try store.merge(snapshot)
        guard case .updated(let firstAdded, let firstChanged) = firstUpdate else {
            throw TestError.failure("first remote catalog should create a local snapshot")
        }
        try expect(firstAdded == 18, "first remote catalog should add each fixture model to its source and WorkBuddy")
        try expect(snapshot.models["workbuddy"]?["gpt-5.7"] != nil, "WorkBuddy should share recognized API prices")
        try expect(firstChanged == 0, "first remote catalog should not report changed models")
        let identicalUpdate = try store.merge(snapshot)
        try expect(identicalUpdate == .unchanged, "identical remote catalogs should not rewrite the local snapshot")

        MoaUsagePricing.useRemoteCatalogStoreForTesting(store)
        defer { MoaUsagePricing.resetRemoteCatalogStoreForTesting() }
        let estimate = MoaUsagePricing.codexCostEstimate(
            model: "openai/gpt-5.7",
            inputTokens: 200_000,
            cachedInputTokens: 50_000,
            outputTokens: 100_000
        )
        try expect(estimate?.usesFallbackPricing == false, "remote-only models should not use fallback pricing")
        try expectClose(estimate?.costUSD ?? -1, 1.31, "remote-only models should use downloaded pricing")

        snapshot.models[MoaUsageSource.codex.rawValue]?["gpt-5.7"]?.inputUSDPerMillion = 3
        snapshot.models[MoaUsageSource.codex.rawValue]?["gpt-5.8"] = parsed
        let secondUpdate = try store.merge(snapshot)
        try expect(secondUpdate == .updated(added: 1, changed: 1), "catalog merge should distinguish additions from field changes")

        var sparse = snapshot
        sparse.models[MoaUsageSource.codex.rawValue]?["gpt-5.7"]?.cacheReadUSDPerMillion = nil
        let sparseUpdate = try store.merge(sparse)
        try expect(sparseUpdate == .unchanged, "missing remote fields should not erase the local incremental catalog")
        try expectClose(
            store.pricing(source: .codex, model: "gpt-5.7")?.cacheReadUSDPerMillion ?? -1,
            0.2,
            "existing optional prices should survive sparse remote responses"
        )

        var partial = snapshot
        partial.models[MoaUsageSource.codex.rawValue]?.removeValue(forKey: "gpt-5.7")
        _ = try store.merge(partial)
        try expect(store.pricing(source: .codex, model: "gpt-5.7") != nil, "incremental refresh should retain models omitted by a later response")

        try store.recordSuccessfulCheck(at: fetchedAt)
        try expect(store.lastSuccessfulCheck() == fetchedAt, "successful checks should be recorded separately from catalog changes")
    }

    private static func testPricingUpdateSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 0, minute: 20, second: 0))!
        let scheduled = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 0, minute: 20, second: 1))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 8))!

        try expect(
            MoaUsagePricingUpdateCoordinator.nextScheduledDate(after: before, calendar: calendar) == scheduled,
            "next pricing check should be scheduled at 00:20:01 local time"
        )
        try expect(
            !MoaUsagePricingUpdateCoordinator.shouldCheck(now: before, lastSuccessfulCheck: nil, calendar: calendar),
            "launches before the daily check time should wait for the timer"
        )
        try expect(
            MoaUsagePricingUpdateCoordinator.shouldCheck(now: after, lastSuccessfulCheck: nil, calendar: calendar),
            "launches after the daily check time should catch up"
        )
        try expect(
            !MoaUsagePricingUpdateCoordinator.shouldCheck(now: after, lastSuccessfulCheck: scheduled, calendar: calendar),
            "a successful check on the same local day should not repeat"
        )
    }

    private static let remotePricingFixture = #"""
    {
      "openai": {
        "models": {
          "gpt-5.3": {"cost":{"input":1,"output":5,"cache_read":0.1}},
          "gpt-5.4": {"cost":{"input":1,"output":5,"cache_read":0.1}},
          "gpt-5.5": {"cost":{"input":1,"output":5,"cache_read":0.1}},
          "gpt-5.6": {"cost":{"input":1,"output":5,"cache_read":0.1}},
          "gpt-5.7": {"cost":{"input":2,"output":10,"cache_read":0.2,"cache_write":2.5,"tiers":[{"input":4,"output":15,"cache_read":0.4,"cache_write":5,"tier":{"type":"context","size":272000}}]}}
        }
      },
      "anthropic": {
        "models": {
          "claude-haiku": {"cost":{"input":1,"output":5,"cache_read":0.1,"cache_write":1.25}},
          "claude-sonnet": {"cost":{"input":3,"output":15,"cache_read":0.3,"cache_write":3.75}},
          "claude-opus": {"cost":{"input":5,"output":25,"cache_read":0.5,"cache_write":6.25}}
        }
      },
      "zai": {
        "models": {
          "glm-5.2": {"cost":{"input":1.4,"output":4.4,"cache_read":0.26,"cache_write":0}}
        }
      }
    }
    """#

    private static func testZCodePricing() throws {
        let estimate = MoaUsagePricing.zcodeCostEstimate(
            model: "zhipu/glm-5-turbo",
            inputTokens: 1_000_000,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        try expect(estimate?.normalizedModel == "GLM-5-Turbo", "ZCode model names should normalize GLM-5-Turbo")
        try expect(estimate?.pricingModel == "GLM-5-Turbo", "known ZCode models should use their own pricing model")
        try expect(estimate?.usesFallbackPricing == false, "known ZCode models should not use fallback pricing")
        try expectClose(estimate?.costUSD ?? -1, 5.44, "GLM-5-Turbo cost should use input, cached input, free cache storage, and output prices")

        let fallback = MoaUsagePricing.zcodeCostEstimate(
            model: "glm-future",
            inputTokens: 1_000_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0
        )
        try expect(fallback?.pricingModel == "GLM-5.2", "unknown ZCode models should fall back to GLM-5.2 pricing")
        try expect(fallback?.usesFallbackPricing == true, "unknown ZCode models should be marked as fallback pricing")
    }

    private static func testZCodeUsageScanner() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let dbDirectory = home
            .appendingPathComponent(".zcode", isDirectory: true)
            .appendingPathComponent("cli", isDirectory: true)
            .appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        let db = dbDirectory.appendingPathComponent("db.sqlite")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let startedAt = Int(now.timeIntervalSince1970 * 1000)
        try runSQLite(db: db, sql: """
        create table model_usage (
          status text,
          started_at integer,
          model_id text,
          input_tokens integer,
          output_tokens integer,
          cache_read_input_tokens integer,
          cache_creation_input_tokens integer
        );
        insert into model_usage values ('completed', \(startedAt), 'glm-5.2', 1000, 50, 200, 100);
        insert into model_usage values ('error', \(startedAt), 'glm-5.2', 9999, 9999, 9999, 9999);
        """)

        let scanner = ZCodeUsageScanner(environment: [
            "HOME": home.path,
            "ZCODE_USAGE_DB": db.path,
            "SQLITE3_PATH": "/usr/bin/sqlite3"
        ])
        let report = try scanner.loadReport(now: now, persistCache: false)
        try expect(report.rows.count == 1, "ZCode scanner should aggregate only completed rows")
        guard let row = report.rows.first else {
            throw TestError.failure("ZCode scanner should return one aggregate row")
        }

        try expect(row.source == .zcode, "ZCode scanner rows should be marked as ZCode")
        try expect(row.dayKey == MoaUsageReport.dayKey(from: now), "ZCode scanner should bucket rows by local day")
        try expect(row.model == "GLM-5.2", "ZCode scanner should normalize GLM model IDs")
        try expect(row.input == 700, "ZCode scanner should subtract cache read and storage tokens from raw input")
        try expect(row.cacheReadInput == 200, "ZCode scanner should preserve cache read tokens")
        try expect(row.cacheCreationInput == 100, "ZCode scanner should preserve cache creation/storage tokens")
        try expect(row.output == 50, "ZCode scanner should preserve output tokens")
        try expect(row.totalTokens == 1050, "ZCode scanner total tokens should include raw prompt tokens plus output")
        try expect(row.cacheHitTokens == 200, "ZCode scanner cache hit tokens should include cache read tokens")
        try expectClose(row.costUSD, 0.001252, "ZCode scanner should estimate GLM-5.2 row cost")

        let summary = try scanner.loadSummary(now: now)
        try expect(summary.todayTokens == 1050, "ZCode summary should include today's tokens")
        try expect(summary.totalTokens == 1050, "ZCode summary should include total tokens")
        try expectClose(summary.cacheHitPercent, 19.047619, "ZCode summary should calculate cache hit percentage", tolerance: 0.00001)
    }

    private static func testClaudeStateTransactionRollback() throws {
        let home = try temporaryHome()
        defer {
            ClaudeDesktopProfileController.testingDatabaseSaveFailuresRemaining = 0
            try? FileManager.default.removeItem(at: home)
        }
        let environment = ["HOME": home.path]
        let controller = ClaudeDesktopProfileController(environment: environment)
        let profile = try controller.addProfile(
            name: "Claude Test",
            baseURL: "https://claude.example.com",
            apiKey: "test-key",
            models: ["claude-sonnet-4"],
            oneMModels: []
        )
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let stateURLs = [
            appSupport.appendingPathComponent("Claude/claude_desktop_config.json"),
            appSupport.appendingPathComponent("Claude-3p/claude_desktop_config.json"),
            appSupport.appendingPathComponent("Claude-3p/configLibrary/00000000-0000-4000-8000-000000157211.json"),
            appSupport.appendingPathComponent("Claude-3p/configLibrary/_meta.json"),
            home.appendingPathComponent(".moa/claude_desktop_profiles.json")
        ]

        let beforeFailedApply = try stateURLs.map(optionalData)
        ClaudeDesktopProfileController.testingDatabaseSaveFailuresRemaining = 1
        var applyFailed = false
        do {
            _ = try controller.applyProfile(id: profile.id)
        } catch {
            applyFailed = true
        }
        try expect(applyFailed, "injected Claude apply database failure should propagate")
        let afterFailedApply = try stateURLs.map(optionalData)
        let selectedAfterFailedApply = try controller.selectedProfileID()
        try expect(afterFailedApply == beforeFailedApply, "failed apply should restore live Claude files and profile database")
        try expect(selectedAfterFailedApply == nil, "failed apply should restore the cached selected profile state")

        _ = try controller.applyProfile(id: profile.id)
        let appliedState = try stateURLs.map(optionalData)
        ClaudeDesktopProfileController.testingDatabaseSaveFailuresRemaining = 1
        var restoreFailed = false
        do {
            try controller.restoreOfficial()
        } catch {
            restoreFailed = true
        }
        try expect(restoreFailed, "injected Claude restore database failure should propagate")
        let afterFailedRestore = try stateURLs.map(optionalData)
        let selectedAfterFailedRestore = try controller.selectedProfileID()
        try expect(afterFailedRestore == appliedState, "failed restore should restore the applied live files and database")
        try expect(selectedAfterFailedRestore == profile.id, "failed restore should keep the selected profile")

        ClaudeDesktopProfileController.testingDatabaseSaveFailuresRemaining = 1
        var deleteFailed = false
        do {
            _ = try controller.deleteProfile(id: profile.id)
        } catch {
            deleteFailed = true
        }
        try expect(deleteFailed, "injected Claude delete database failure should propagate")
        let afterFailedDelete = try stateURLs.map(optionalData)
        let profilesAfterFailedDelete = try controller.profiles()
        try expect(afterFailedDelete == appliedState, "failed selected-profile deletion should restore live files and database")
        try expect(profilesAfterFailedDelete.contains(where: { $0.id == profile.id }), "failed deletion should restore the cached profile list")
    }

    private static func testCodexStateTransactionRollback() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        defer { ConfigProfileController.testingProfileDatabaseSaveFailuresRemaining = 0 }
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": codexHome.path,
            "CODEX_APP": home.appendingPathComponent("MissingCodex.app").path
        ])
        let profile = try controller.addProfile(
            name: "Rollback",
            baseURL: "https://rollback.example/v1",
            apiKey: "rollback-key"
        )
        let stateURLs = [
            controller.moaConfigURL,
            controller.codexConfigURL,
            controller.moaAuthURL,
            controller.codexAuthURL,
            controller.databaseURL,
            controller.officialAccountsDatabaseURL
        ]
        let before = try stateURLs.map(optionalData)

        ConfigProfileController.testingProfileDatabaseSaveFailuresRemaining = 1
        do {
            _ = try controller.applyProfile(id: profile.id)
            throw TestError.failure("injected Codex profile database failure should propagate")
        } catch let error as TestError {
            throw error
        } catch {
            // Expected injected failure.
        }

        let after = try stateURLs.map(optionalData)
        try expect(after == before, "failed Codex profile activation should restore config, auth, and database files")
        let selectedProfileID = try controller.selectedProfileID()
        try expect(selectedProfileID == nil, "failed activation should restore the cached selected profile")
    }

    private static func testCodexOfficialAccountTransactionRollback() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        defer { ConfigProfileController.testingOfficialAccountDatabaseSaveFailuresRemaining = 0 }
        let controller = ConfigProfileController(environment: [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex", isDirectory: true).path
        ])
        let stateURLs = [controller.moaAuthURL, controller.codexAuthURL, controller.officialAccountsDatabaseURL]
        let before = try stateURLs.map(optionalData)
        let accountsBefore = try Set(FileManager.default.contentsOfDirectory(atPath: controller.officialAuthAccountsDir.path))

        ConfigProfileController.testingOfficialAccountDatabaseSaveFailuresRemaining = 1
        do {
            _ = try controller.saveNewOfficialAccount(
                auth: ["tokens": ["access_token": "rollback-token"]],
                name: "Rollback Account"
            )
            throw TestError.failure("injected official account database failure should propagate")
        } catch let error as TestError {
            throw error
        } catch {
            // Expected injected failure.
        }

        let after = try stateURLs.map(optionalData)
        let accountsAfter = try Set(FileManager.default.contentsOfDirectory(atPath: controller.officialAuthAccountsDir.path))
        try expect(after == before, "failed official account save should restore auth and database files")
        try expect(accountsAfter == accountsBefore, "failed official account save should remove newly-created account files")
    }

    private static func testDataPackageRoundTripAndCleanup() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fileManager = FileManager.default
        let moaHome = home.appendingPathComponent(".moa", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: moaHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try "snapshot-data".write(to: moaHome.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: moaHome.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try "nested-data".write(to: moaHome.appendingPathComponent("nested/config.txt"), atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            atPath: moaHome.appendingPathComponent("profiles-current.json").path,
            withDestinationPath: "profiles.json"
        )

        let prefixes = ["MoaDataPackage-", "MoaDataImport-", "MoaImportPrevious-"]
        let beforeTemporaryEntries = try temporaryEntries(withPrefixes: prefixes)
        let controller = MoaDataPackageController(environment: ["HOME": home.path])
        let packageURL = home.appendingPathComponent("round-trip.zip")
        _ = try controller.exportDataPackage(to: packageURL)
        try expect(fileManager.fileExists(atPath: packageURL.path), "data package export should create a zip")

        let extract = home.appendingPathComponent("extract", isDirectory: true)
        try runProcess("/usr/bin/ditto", ["-x", "-k", packageURL.path, extract.path])
        let packageRoot = extract.appendingPathComponent("MoaDataPackage", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            MoaDataPackageManifest.self,
            from: Data(contentsOf: packageRoot.appendingPathComponent("MoaDataPackageManifest.json"))
        )
        try expect(manifest.schemaVersion == 2, "new data packages should use the symlink-aware manifest schema")
        try expect(
            Set(manifest.files.map(\.path)) == ["profiles.json", "profiles-current.json", "nested/config.txt"],
            "manifest should describe files and symbolic links in the copied package snapshot"
        )
        try expect(manifest.files.allSatisfy { $0.sha256?.count == 64 }, "every exported file should have a SHA-256 hash")
        let linkEntry = manifest.files.first(where: { $0.path == "profiles-current.json" })
        try expect(linkEntry?.resolvedKind == .symbolicLink, "manifest should identify symbolic links")
        try expect(linkEntry?.symbolicLinkDestination == "profiles.json", "manifest should preserve the symbolic link destination")

        try "changed-after-export".write(to: moaHome.appendingPathComponent("profiles.json"), atomically: true, encoding: .utf8)
        let rollbackURL = try controller.importDataPackage(from: packageURL)
        try expect(fileManager.fileExists(atPath: rollbackURL.path), "import should retain the user-facing rollback zip")
        let restored = try String(contentsOf: moaHome.appendingPathComponent("profiles.json"), encoding: .utf8)
        try expect(restored == "snapshot-data", "import should restore the exact exported snapshot")
        let restoredLink = try fileManager.destinationOfSymbolicLink(atPath: moaHome.appendingPathComponent("profiles-current.json").path)
        try expect(restoredLink == "profiles.json", "import should restore the validated symbolic link")
        let afterTemporaryEntries = try temporaryEntries(withPrefixes: prefixes)
        try expect(afterTemporaryEntries == beforeTemporaryEntries, "successful export/import should not leak staging or previous-data directories")
    }

    private static func testZCodeUsageScannerLargeOutput() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let db = home.appendingPathComponent("db.sqlite")
        try Data().write(to: db)
        let fakeSQLite = home.appendingPathComponent("fake-sqlite.sh")
        let script = """
        #!/bin/sh
        i=0
        while [ "$i" -lt 20000 ]; do
          printf '2023-11-14\\037glm-5.2\\0371000\\037200\\037100\\03750\\n'
          i=$((i + 1))
        done
        """
        try script.write(to: fakeSQLite, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSQLite.path)

        let scanner = ZCodeUsageScanner(environment: [
            "HOME": home.path,
            "ZCODE_USAGE_DB": db.path,
            "SQLITE3_PATH": fakeSQLite.path
        ])
        let report = try scanner.loadReport(now: Date(timeIntervalSince1970: 1_700_000_000), persistCache: false)
        try expect(report.rows.count == 1, "large sqlite output should be fully drained and aggregated")
        try expect(report.rows.first?.totalTokens == 21_000_000, "large sqlite output should not be truncated")
    }

    private static func optionalData(at url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    private static func temporaryEntries(withPrefixes prefixes: [String]) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        return Set(names.filter { name in prefixes.contains(where: name.hasPrefix) })
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? executable
            throw TestError.failure(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func testUpdaterVersionComparisonAndFeedParsing() throws {
        try expect(
            MoaUpdateController.isRemoteVersion("1.1.5", remoteBuild: nil, newerThan: "1.1.4", localBuild: 111),
            "newer patch version should be an update"
        )
        try expect(
            MoaUpdateController.isRemoteVersion("1.1.5", remoteBuild: 113, newerThan: "1.1.5", localBuild: 112),
            "newer build on the same version should be an update"
        )
        try expect(
            !MoaUpdateController.isRemoteVersion("1.1.4", remoteBuild: 111, newerThan: "1.1.5", localBuild: 112),
            "older remote version should not be an update"
        )

        let feed = """
        <feed>
          <entry>
            <title>Moa 1.2.0</title>
            <id>tag:github.com,2026:Release/v1.2.0 Build: 123</id>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.2.0"/>
            <content>Moa-1.2.0-macos-arm64.dmg Moa-1.2.0-macos-x86_64.dmg Build: 123</content>
          </entry>
        </feed>
        """
        let update = try MoaUpdateController.releaseInfo(fromAtomFeed: feed)
        try expect(update.version == "1.2.0", "Atom feed parser should extract release version")
        try expect(update.build == 123, "Atom feed parser should extract build number")
        try expect(update.releaseURL.absoluteString == "https://github.com/MoarLiu/Moa/releases/tag/v1.2.0", "Atom feed parser should preserve release URL")
        try expect(update.dmgURL.lastPathComponent.hasPrefix("Moa-1.2.0-macos-"), "Atom feed parser should choose a Moa DMG asset")
        try expect(update.checksumURL.lastPathComponent == update.dmgURL.lastPathComponent + ".sha256", "Atom feed parser should pair DMG checksum asset")
    }

    private static func testUpdaterBackupPruning() throws {
        let root = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: root) }

        let backupRoot = root.appendingPathComponent("Update Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let old = backupRoot.appendingPathComponent("Moa-1.1.0-previous-20260101-010101.app", isDirectory: true)
        let middle = backupRoot.appendingPathComponent("Moa-1.1.1-previous-20260102-010101.app", isDirectory: true)
        let newest = backupRoot.appendingPathComponent("Moa-1.1.2-previous-20260103-010101.app", isDirectory: true)
        let invalid = backupRoot.appendingPathComponent("Moa-invalid.app", isDirectory: true)

        for url in [old, middle, newest, invalid] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        try MoaUpdateController.pruneUpdateBackups(in: backupRoot, keeping: 2)
        try expect(!FileManager.default.fileExists(atPath: old.path), "oldest valid update backup should be pruned")
        try expect(FileManager.default.fileExists(atPath: middle.path), "second newest valid update backup should be kept")
        try expect(FileManager.default.fileExists(atPath: newest.path), "newest valid update backup should be kept")
        try expect(FileManager.default.fileExists(atPath: invalid.path), "invalid backup names should be ignored")
    }

    private static func runSQLite(db: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [db.path, sql]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "sqlite3 failed"
            throw TestError.failure(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
