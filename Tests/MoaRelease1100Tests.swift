#if !MOA_TESTING
import Carbon.HIToolbox
import CryptoKit
import Foundation
import XCTest
@testable import Moa

final class MoaRelease1100Tests: XCTestCase {
    private func makeTempHome(prefix: String = "moa-1100-test") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeJWT(payload: [String: Any]) throws -> String {
        let headerData = try JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"])
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(b64url(headerData)).\(b64url(payloadData)).signature"
    }

    // MARK: - 1. Adapter Registry & Client Preferences

    func testAdapterRegistryAndClientPreferencesOrderingAndVisibility() {
        let suiteName = "MoaClientPreferencesTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(MoaClientAdapterRegistry.descriptors.count, MoaWorkspaceClient.allCases.count)
        XCTAssertTrue(MoaClientAdapterRegistry.descriptor(for: .geminiCLI).capabilities.contains(.cliOnly))
        XCTAssertTrue(MoaClientAdapterRegistry.descriptor(for: .claude).capabilities.contains(.claudeCodeSettings))
        XCTAssertEqual(MoaClientAdapterRegistry.client(for: .claudeCode), .claude)
        XCTAssertEqual(MoaClientAdapterRegistry.client(for: .geminiCLI), .geminiCLI)
        XCTAssertEqual(MoaClientAdapterRegistry.client(for: .antigravity), .antigravity)
        XCTAssertEqual(MoaClientAdapterRegistry.client(for: .deepseek), .deepseek)

        // Default order matches registry
        XCTAssertEqual(MoaClientPreferences.orderedClients(defaults: defaults), MoaClientAdapterRegistry.defaultOrder)
        XCTAssertFalse(MoaClientPreferences.hasCustomOrder(defaults: defaults))

        // Move geminiCLI up by 1 and hide zcode
        MoaClientPreferences.moveClient(.geminiCLI, offset: -2, defaults: defaults)
        XCTAssertTrue(MoaClientPreferences.hasCustomOrder(defaults: defaults))
        let moved = MoaClientPreferences.orderedClients(defaults: defaults)
        XCTAssertEqual(moved.firstIndex(of: .geminiCLI), MoaWorkspaceClient.allCases.count - 3)

        MoaClientPreferences.setHidden(true, for: .zcode, defaults: defaults)
        XCTAssertTrue(MoaClientPreferences.hiddenClients(defaults: defaults).contains(.zcode))
        let visible = MoaClientPreferences.resolvedVisibleClients(installed: [.codex, .geminiCLI], defaults: defaults)
        XCTAssertFalse(visible.map(\.client).contains(.zcode))

        // Attempting to hide all clients must keep at least one visible
        for client in MoaWorkspaceClient.allCases {
            MoaClientPreferences.setHidden(true, for: client, defaults: defaults)
        }
        XCTAssertLessThan(MoaClientPreferences.hiddenClients(defaults: defaults).count, MoaWorkspaceClient.allCases.count)

        // Reset restores defaults
        MoaClientPreferences.resetDefaults(defaults: defaults)
        XCTAssertFalse(MoaClientPreferences.hasCustomOrder(defaults: defaults))
        XCTAssertTrue(MoaClientPreferences.hiddenClients(defaults: defaults).isEmpty)
    }

    // MARK: - 2. Claude Code Independent Settings Controller

    func testClaudeCodeSettingsFieldLevelEditIsolationAndRollback() throws {
        let home = try makeTempHome(prefix: "moa-cc-settings")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        let initialJSON: [String: Any] = [
            "permissions": ["allow": ["Read", "Bash(git status)"]],
            "hooks": ["PreToolUse": []],
            "env": [
                "CUSTOM_USER_FLAG": "keep-me",
                "ANTHROPIC_BASE_URL": "https://old.example.com"
            ]
        ]
        try JSONSerialization.data(withJSONObject: initialJSON, options: [.prettyPrinted])
            .write(to: settingsURL)

        // Create a Claude Desktop file to verify strict isolation
        let desktopDir = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        try FileManager.default.createDirectory(at: desktopDir, withIntermediateDirectories: true)
        let desktopConfigURL = desktopDir.appendingPathComponent("claude_desktop_config.json")
        let desktopSentinel = Data("{\"mcpServers\":{\"keep\":true}}".utf8)
        try desktopSentinel.write(to: desktopConfigURL)

        let controller = ClaudeCodeSettingsController(environment: env)

        // Reject insecure HTTP non-loopback URL
        XCTAssertThrowsError(try controller.addProfile(
            name: "Insecure",
            baseURL: "http://remote.example.com",
            apiKey: "sk-ant-bad",
            model: "claude-sonnet-4-6"
        ))

        let profile = try controller.addProfile(
            name: "Relay Code",
            baseURL: "https://relay.example.com/v1",
            apiKey: "sk-ant-relay-secret",
            model: "claude-sonnet-4-6",
            smallFastModel: "claude-haiku-4-5"
        )
        _ = try controller.applyProfile(id: profile.id)

        let updatedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertNotNil(updatedObj["permissions"])
        XCTAssertNotNil(updatedObj["hooks"])
        let updatedEnv = try XCTUnwrap(updatedObj["env"] as? [String: Any])
        XCTAssertEqual(updatedEnv["CUSTOM_USER_FLAG"] as? String, "keep-me")
        XCTAssertEqual(updatedEnv["ANTHROPIC_BASE_URL"] as? String, "https://relay.example.com/v1")
        XCTAssertEqual(updatedEnv["ANTHROPIC_AUTH_TOKEN"] as? String, "sk-ant-relay-secret")
        XCTAssertEqual(updatedEnv["ANTHROPIC_MODEL"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(updatedEnv["ANTHROPIC_SMALL_FAST_MODEL"] as? String, "claude-haiku-4-5")

        // Claude Desktop config untouched
        XCTAssertEqual(try Data(contentsOf: desktopConfigURL), desktopSentinel)

        // Restore Official Mode strips only managed ANTHROPIC_* keys
        try controller.restoreOfficialMode()
        XCTAssertNil(try controller.selectedProfileID())
        let restoredObj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        let restoredEnv = try XCTUnwrap(restoredObj["env"] as? [String: Any])
        XCTAssertEqual(restoredEnv["CUSTOM_USER_FLAG"] as? String, "keep-me")
        for key in ClaudeCodeSettingsController.managedEnvKeys {
            XCTAssertNil(restoredEnv[key], "\(key) should be removed on official restore")
        }

        // Malformed settings.json throws without destroying the file
        let brokenContent = Data("{ not valid json".utf8)
        try brokenContent.write(to: settingsURL)
        XCTAssertThrowsError(try controller.applyProfile(id: profile.id))
        XCTAssertEqual(try Data(contentsOf: settingsURL), brokenContent)

        // Symlink rejection
        try FileManager.default.removeItem(at: settingsURL)
        let outsideTarget = home.appendingPathComponent("outside.json")
        try Data("{}".utf8).write(to: outsideTarget)
        try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: outsideTarget)
        XCTAssertThrowsError(try controller.applyProfile(id: profile.id))
    }

    // MARK: - 3. Gemini CLI Account Switching & Antigravity Isolation

    func testGeminiCLISaveSwitchPreserveRefreshedTokenAndAntigravityIsolation() throws {
        let home = try makeTempHome(prefix: "moa-gemini-cli")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)
        let agyDir = geminiDir.appendingPathComponent("antigravity", isDirectory: true)
        try FileManager.default.createDirectory(at: agyDir, withIntermediateDirectories: true)
        let agySentinelURL = agyDir.appendingPathComponent("sentinel.txt")
        try Data("do-not-touch".utf8).write(to: agySentinelURL)

        let oauthURL = geminiDir.appendingPathComponent("oauth_creds.json")
        let accountsURL = geminiDir.appendingPathComponent("google_accounts.json")
        let controller = GeminiCLIController(environment: env)

        // Account A live login
        let jwtA = try makeJWT(payload: ["sub": "sub-a", "email": "alice@example.com", "exp": Date().timeIntervalSince1970 + 7200])
        let oauthA = try JSONSerialization.data(withJSONObject: [
            "access_token": "ya29.alice-v1",
            "refresh_token": "1//refresh-alice",
            "id_token": jwtA,
            "expiry_date": Int((Date().timeIntervalSince1970 + 7200) * 1000)
        ])
        try oauthA.write(to: oauthURL)
        try Data("{\"active\":\"alice@example.com\",\"old\":[]}".utf8).write(to: accountsURL)

        let savedA = try controller.saveCurrent(name: "Alice Work")
        XCTAssertEqual(savedA.email, "alice@example.com")

        // Prepare new login clears oauth_creds.json while preserving Alice in storage
        try controller.prepareNewLogin()
        XCTAssertFalse(FileManager.default.fileExists(atPath: oauthURL.path))
        XCTAssertEqual(try controller.accounts().count, 1)

        // Account B live login
        let jwtB = try makeJWT(payload: ["sub": "sub-b", "email": "bob@example.com", "exp": Date().timeIntervalSince1970 + 7200])
        let oauthB = try JSONSerialization.data(withJSONObject: [
            "access_token": "ya29.bob-v1",
            "refresh_token": "1//refresh-bob",
            "id_token": jwtB,
            "expiry_date": Int((Date().timeIntervalSince1970 + 7200) * 1000)
        ])
        try oauthB.write(to: oauthURL)
        try Data("{\"active\":\"bob@example.com\",\"old\":[]}".utf8).write(to: accountsURL)
        let savedB = try controller.saveCurrent(name: "Bob Personal")

        // Simulate Gemini CLI refreshing Bob's token in place before switching back to Alice
        let oauthBRefreshed = try JSONSerialization.data(withJSONObject: [
            "access_token": "ya29.bob-v2-refreshed",
            "refresh_token": "1//refresh-bob",
            "id_token": jwtB,
            "expiry_date": Int((Date().timeIntervalSince1970 + 14400) * 1000)
        ])
        try oauthBRefreshed.write(to: oauthURL)

        // Switch to Alice -> must auto-preserve Bob's refreshed token snapshot!
        _ = try controller.apply(id: savedA.id)
        XCTAssertEqual(try controller.currentIdentity(), savedA.identity)
        let refreshedB = try XCTUnwrap(try controller.accounts().first { $0.id == savedB.id })
        let refreshedBText = String(data: refreshedB.oauthCredsSnapshot, encoding: .utf8) ?? ""
        XCTAssertTrue(refreshedBText.contains("ya29.bob-v2-refreshed"))

        // Antigravity directory completely untouched
        XCTAssertEqual(try Data(contentsOf: agySentinelURL), Data("do-not-touch".utf8))

        // Rename & delete
        try controller.rename(id: savedB.id, name: "Bob Renamed")
        XCTAssertEqual(try controller.accounts().first { $0.id == savedB.id }?.name, "Bob Renamed")
        try controller.delete(id: savedB.id)
        XCTAssertEqual(try controller.accounts().count, 1)

        // Symlink rejection
        let outside = home.appendingPathComponent("evil.json")
        try oauthA.write(to: outside)
        try FileManager.default.removeItem(at: oauthURL)
        try FileManager.default.createSymbolicLink(at: oauthURL, withDestinationURL: outside)
        XCTAssertThrowsError(try controller.apply(id: savedA.id))
    }

    // MARK: - 4. Antigravity & DeepSeek Local Usage Scanners

    func testAntigravityUsageScannerParsesTranscriptsAndDeduplicatesSteps() throws {
        let home = try makeTempHome(prefix: "moa-agy-usage")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let logsDir = home
            .appendingPathComponent(".gemini/antigravity/brain/conv-1/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let transcript = """
        {"step_index":1,"source":"USER","status":"DONE","created_at":"2026-04-10T10:00:00Z","content":"secret prompt"}
        {"step_index":2,"source":"MODEL","status":"DONE","created_at":"2026-04-10T10:01:00Z","model":"gemini-2.5-pro","input_tokens":10000,"cache_read_tokens":40000,"output_tokens":2000}
        {"step_index":2,"source":"MODEL","status":"DONE","created_at":"2026-04-10T10:01:05Z","model":"gemini-2.5-pro","input_tokens":10000,"cache_read_tokens":40000,"output_tokens":2000}
        {"step_index":3,"source":"MODEL","status":"RUNNING","created_at":"2026-04-10T10:02:00Z","model":"gemini-2.5-pro","input_tokens":99999,"output_tokens":99999}
        {"step_index":4,"source":"MODEL","status":"DONE","created_at":"2026-04-10T10:03:00Z","model":"unknown-experimental-model","input_tokens":5000,"cache_read_tokens":0,"output_tokens":1000}
        """
        try transcript.write(to: logsDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = AntigravityUsageScanner(environment: env, calendarProvider: { utc })
        let report = try scanner.loadReport(forceRefresh: true, now: Date(timeIntervalSince1970: 1775820000))

        XCTAssertEqual(report.rows.count, 2)
        let proRow = try XCTUnwrap(report.rows.first { $0.model == "gemini-2.5-pro" })
        XCTAssertEqual(proRow.source, .antigravity)
        XCTAssertEqual(proRow.dayKey, "2026-04-10")
        // Dedup ensures step_index 2 counted once, RUNNING step 3 ignored
        XCTAssertEqual(proRow.input, 10000)
        XCTAssertEqual(proRow.cacheHitTokens, 40000)
        XCTAssertEqual(proRow.output, 2000)
        XCTAssertGreaterThan(proRow.costUSD, 0)

        let unknownRow = try XCTUnwrap(report.rows.first { $0.model == "unknown-experimental-model" })
        XCTAssertEqual(unknownRow.pricingModel, "unpriced")
        XCTAssertEqual(unknownRow.costUSD, 0, accuracy: 0.000001)

        // Custom pricing override applies immediately
        let overrides = MoaUsagePricingOverrideController(environment: env)
        try overrides.upsert(
            source: .antigravity,
            model: "unknown-experimental-model",
            inputUSDPerMillion: 10,
            outputUSDPerMillion: 20,
            cacheReadUSDPerMillion: nil,
            cacheCreationUSDPerMillion: nil
        )
        let updated = try scanner.loadReport(forceRefresh: true, now: Date(timeIntervalSince1970: 1775820000))
        let pricedUnknown = try XCTUnwrap(updated.rows.first { $0.model == "unknown-experimental-model" })
        XCTAssertEqual(pricedUnknown.pricingModel, MoaL10n.text("Custom"))
        // 5000 * 10/1e6 + 1000 * 20/1e6 = 0.05 + 0.02 = 0.07
        XCTAssertEqual(pricedUnknown.costUSD, 0.07, accuracy: 0.0001)
    }

    func testDeepSeekUsageScannerParsesSessionsAndCacheRates() throws {
        let home = try makeTempHome(prefix: "moa-ds-usage")
        defer { try? FileManager.default.removeItem(at: home) }
        let dshHome = home.appendingPathComponent("custom-dsh", isDirectory: true)
        let sessionsDir = dshHome.appendingPathComponent("storages/session_projcache/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let sessionJSON: [String: Any] = [
            "record": [
                "identity": ["createdAt": 1775820000000.0], // 2026-04-10 UTC
                "rows": [
                    "sessionListMetadata": ["val": ["lastPromptAt": 1775820600000.0]],
                    "modelSelection": ["val": ["lastUsed": ["model": "deepseek-chat"]]],
                    "tokenUsage": [
                        "val": [
                            "totals": [
                                "uncachedInputTokens": 200_000,
                                "cacheReadTokens": 800_000,
                                "cacheWriteTokens": 0,
                                "outputTokens": 50_000
                            ]
                        ]
                    ]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: sessionJSON)
            .write(to: sessionsDir.appendingPathComponent("session-abc.json"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let env = ["HOME": home.path, "DSH_HOME": dshHome.path]
        let scanner = DeepSeekUsageScanner(environment: env, calendarProvider: { utc })
        let report = try scanner.loadReport(forceRefresh: true, now: Date(timeIntervalSince1970: 1775821000))

        XCTAssertEqual(report.rows.count, 1)
        let row = try XCTUnwrap(report.rows.first)
        XCTAssertEqual(row.source, .deepseek)
        XCTAssertEqual(row.model, "deepseek-chat")
        XCTAssertEqual(row.dayKey, "2026-04-10")
        XCTAssertEqual(row.input, 200_000)
        XCTAssertEqual(row.cacheHitTokens, 800_000)
        XCTAssertEqual(row.output, 50_000)
        XCTAssertGreaterThan(row.costUSD, 0)
    }

    // MARK: - 5. Usage Analytics 2.0 & Combined Budgets

    func testUsageAnalyticsDateRangesCacheSavingsAndAggregations() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = utc.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!

        let todayBounds = MoaUsageDateRangePreset.today.dayKeyBounds(customStart: now, customEnd: now, now: now, calendar: utc)
        XCTAssertEqual(todayBounds.start, "2026-04-15")
        XCTAssertEqual(todayBounds.end, "2026-04-15")

        let sevenBounds = MoaUsageDateRangePreset.last7Days.dayKeyBounds(customStart: now, customEnd: now, now: now, calendar: utc)
        XCTAssertEqual(sevenBounds.start, "2026-04-09")
        XCTAssertEqual(sevenBounds.end, "2026-04-15")

        let monthBounds = MoaUsageDateRangePreset.thisMonth.dayKeyBounds(customStart: now, customEnd: now, now: now, calendar: utc)
        XCTAssertEqual(monthBounds.start, "2026-04-01")
        XCTAssertEqual(monthBounds.end, "2026-04-15")

        let rows = [
            MoaUsageDetailRow(
                source: .codex, dayKey: "2026-04-14", model: "gpt-5.4",
                input: 100_000, cachedInput: 900_000, cacheReadInput: 0, cacheCreationInput: 0, output: 10_000,
                costUSD: 2.0, pricingModel: "gpt-5.4", usesFallbackPricing: false
            ),
            MoaUsageDetailRow(
                source: .claude, dayKey: "2026-04-15", model: "claude-sonnet-4-6",
                input: 50_000, cachedInput: 0, cacheReadInput: 500_000, cacheCreationInput: 0, output: 20_000,
                costUSD: 3.0, pricingModel: "claude-sonnet-4-6", usesFallbackPricing: false
            )
        ]
        let report = MoaUsageReport(rows: rows, generatedAt: now)

        // Cache savings must be strictly positive when cache reads are cheaper than uncached input
        let savings = MoaUsageAnalytics.cacheSavingsUSD(for: report)
        XCTAssertGreaterThan(savings, 0)

        let series = MoaUsageAnalytics.dailySeries(from: report, startDayKey: "2026-04-13", endDayKey: "2026-04-15", calendar: utc)
        XCTAssertEqual(series.map(\.dayKey), ["2026-04-13", "2026-04-14", "2026-04-15"])
        XCTAssertEqual(series[0].costUSD, 0, accuracy: 0.0001)
        XCTAssertEqual(series[1].costUSD, 2.0, accuracy: 0.0001)
        XCTAssertEqual(series[2].costUSD, 3.0, accuracy: 0.0001)

        let byModel = MoaUsageAnalytics.aggregateByModel(from: report)
        XCTAssertEqual(byModel.first?.model, "claude-sonnet-4-6")
        XCTAssertEqual(byModel.first?.costSharePercent ?? 0, 60.0, accuracy: 0.01)

        let byClient = MoaUsageAnalytics.aggregateByClient(from: report)
        XCTAssertEqual(byClient.count, 2)
        XCTAssertEqual(byClient.first?.source, .claude)

        let jsonText = MoaUsageReportExporter.json(report: report, cacheSavingsUSD: savings)
        let jsonObj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any])
        XCTAssertEqual(jsonObj["totalCostUSD"] as? Double ?? -1, 5.0, accuracy: 0.001)
        XCTAssertGreaterThan(jsonObj["estimatedCacheSavingsUSD"] as? Double ?? 0, 0)
    }

    func testCombinedDailyAndMonthlyBudgetAlertsAndDeduplication() {
        let suiteName = "MoaCombinedBudgetTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let day1 = Date(timeIntervalSince1970: 1775820000) // 2026-04-10
        let day2 = Date(timeIntervalSince1970: 1775906400) // 2026-04-11 (same month!)

        DailyUsageAlertController.setCombinedThreshold(10.0, for: .daily, defaults: defaults)
        DailyUsageAlertController.setCombinedWarning80Enabled(true, for: .daily, defaults: defaults)
        DailyUsageAlertController.setCombinedThreshold(100.0, for: .monthly, defaults: defaults)
        DailyUsageAlertController.setCombinedWarning80Enabled(true, for: .monthly, defaults: defaults)

        // Daily 80% fires once, then deduplicates
        XCTAssertEqual(DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: 8.5, date: day1, defaults: defaults), .warning80)
        XCTAssertNil(DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: 8.9, date: day1, defaults: defaults))
        // Reaching 100% fires once
        XCTAssertEqual(DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: 10.5, date: day1, defaults: defaults), .reached)
        XCTAssertNil(DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: 11.0, date: day1, defaults: defaults))
        // Next day resets daily bucket
        XCTAssertEqual(DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: 10.2, date: day2, defaults: defaults), .reached)

        // Monthly deduplicates across days in the same month
        XCTAssertEqual(DailyUsageAlertController.pendingCombinedAlertLevel(period: .monthly, costUSD: 85.0, date: day1, defaults: defaults), .warning80)
        XCTAssertNil(DailyUsageAlertController.pendingCombinedAlertLevel(period: .monthly, costUSD: 90.0, date: day2, defaults: defaults))
        XCTAssertEqual(DailyUsageAlertController.pendingCombinedAlertLevel(period: .monthly, costUSD: 105.0, date: day2, defaults: defaults), .reached)
        XCTAssertNil(DailyUsageAlertController.pendingCombinedAlertLevel(period: .monthly, costUSD: 120.0, date: day2, defaults: defaults))
    }

    // MARK: - 6. Schema 3 Encrypted Data Package & Config-Only Layered Export

    func testSchema3EncryptedDataPackageRoundTripAndTamperDistinction() throws {
        let home = try makeTempHome(prefix: "moa-schema3")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let moaHome = home.appendingPathComponent(".moa", isDirectory: true)
        try FileManager.default.createDirectory(at: moaHome, withIntermediateDirectories: true)

        let secretKey = "sk-live-super-secret-value-999"
        let profilesJSON = "{\"profiles\":[{\"name\":\"Relay\",\"apiKey\":\"\(secretKey)\",\"baseURL\":\"https://relay.example.com\"}]}"
        try Data(profilesJSON.utf8).write(to: moaHome.appendingPathComponent("profiles.json"))
        try Data("{\"tokens\":{\"access_token\":\"secret-access-token\"}}".utf8).write(to: moaHome.appendingPathComponent("auth.json"))
        try Data("{\"codex\":{\"my-model\":{\"inputUSDPerMillion\":2.5,\"outputUSDPerMillion\":10.0}}}".utf8)
            .write(to: moaHome.appendingPathComponent("usage-pricing-overrides.json"))

        let controller = MoaDataPackageController(environment: env)
        let encryptedURL = home.appendingPathComponent("backup-schema3.zip")

        // Export encrypted Schema 3 full backup (100k iterations for fast test execution)
        try controller.exportDataPackage(to: encryptedURL, scope: .fullBackup, password: "correct-horse-battery", kdfIterations: 100_000)

        let inspection = try controller.inspectDataPackage(at: encryptedURL)
        XCTAssertEqual(inspection.schemaVersion, 3)
        XCTAssertTrue(inspection.isEncrypted)
        XCTAssertEqual(inspection.scope, .fullBackup)

        // Missing password -> .passwordRequired
        XCTAssertThrowsError(try controller.importDataPackage(from: encryptedURL, password: nil)) { error in
            guard case MoaDataPackageError.passwordRequired = error else {
                XCTFail("Expected passwordRequired, got \(error)")
                return
            }
        }

        // Wrong password -> .wrongPassword
        XCTAssertThrowsError(try controller.importDataPackage(from: encryptedURL, password: "wrong-password")) { error in
            guard case MoaDataPackageError.wrongPassword = error else {
                XCTFail("Expected wrongPassword, got \(error)")
                return
            }
        }

        // Tampered ciphertext -> .corruptedPackage (even with wrong or right password!)
        let cryptoUnit = try MoaDataPackageCrypto.encrypt(
            plaintext: Data("hello-moa".utf8),
            password: "pw",
            scope: .fullBackup,
            iterations: 100_000
        )
        var flipped = cryptoUnit.ciphertext
        flipped[0] ^= 0xFF
        XCTAssertThrowsError(try MoaDataPackageCrypto.decrypt(
            ciphertextAndTag: flipped,
            metadata: cryptoUnit.metadata,
            scope: .fullBackup,
            password: "pw"
        )) { error in
            guard case MoaDataPackageError.corruptedPackage = error else {
                XCTFail("Expected corruptedPackage, got \(error)")
                return
            }
        }

        // Import encrypted Schema 3 into a fresh destination HOME
        let targetHome = try makeTempHome(prefix: "moa-schema3-target")
        defer { try? FileManager.default.removeItem(at: targetHome) }
        let targetController = MoaDataPackageController(environment: ["HOME": targetHome.path])
        _ = try targetController.importDataPackage(from: encryptedURL, password: "correct-horse-battery")
        let restoredProfiles = try String(contentsOf: targetHome.appendingPathComponent(".moa/profiles.json"), encoding: .utf8)
        XCTAssertTrue(restoredProfiles.contains(secretKey))

        // Config-Only layered export strips auth.json and API keys while preserving price overrides
        let configOnlyURL = home.appendingPathComponent("config-only.zip")
        try controller.exportDataPackage(to: configOnlyURL, scope: .configOnly, password: "cfg-password", kdfIterations: 100_000)
        let cfgInspect = try controller.inspectDataPackage(at: configOnlyURL)
        XCTAssertEqual(cfgInspect.scope, .configOnly)

        let cfgHome = try makeTempHome(prefix: "moa-schema3-cfgonly")
        defer { try? FileManager.default.removeItem(at: cfgHome) }
        let cfgController = MoaDataPackageController(environment: ["HOME": cfgHome.path])
        _ = try cfgController.importDataPackage(from: configOnlyURL, password: "cfg-password")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cfgHome.appendingPathComponent(".moa/auth.json").path))
        let sanitizedProfiles = try String(contentsOf: cfgHome.appendingPathComponent(".moa/profiles.json"), encoding: .utf8)
        XCTAssertFalse(sanitizedProfiles.contains(secretKey), "Config-only export must strip API keys")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cfgHome.appendingPathComponent(".moa/usage-pricing-overrides.json").path))
    }

    func testConfigOnlyExportStripsAllActiveInactiveCustomProvidersAndSecrets() throws {
        let home = try makeTempHome(prefix: "moa-cfgonly-audit")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let moaHome = home.appendingPathComponent(".moa", isDirectory: true)
        let codexAuthDir = moaHome.appendingPathComponent("codex-auth/accounts", isDirectory: true)
        let backupsDir = moaHome.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: codexAuthDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let secrets = [
            "sk-active-provider-secret-111",
            "sk-inactive-provider-secret-222",
            "sk-custom-header-secret-333",
            "sk-mcp-env-secret-444",
            "sk-url-query-secret-555",
            "sk-official-refresh-666",
            "sk-backup-snapshot-777",
            "sk-claude-desktop-888",
            "sk-claude-code-999",
            "sk-triple-basic-secret-aaa",
            "sk-triple-literal-secret-bbb",
            "sk-inline-table-secret-ccc"
        ]

        let configTOML = """
        model = "gpt-5.4"
        model_provider = "moa-active"
        model_reasoning_effort = "high"

        [model_providers.moa-active]
        name = "Active Relay"
        base_url = "https://user:pass@relay-a.example.com/v1?token=\(secrets[4])"
        experimental_bearer_token = "\(secrets[0])"
        wire_api = "responses"

        [model_providers.custom-inactive]
        name = "Inactive Custom Provider"
        base_url = \"\"\"
        https://user2:pass2@relay-b.example.com/v1?api_key=\(secrets[9])#frag
        \"\"\"
        fallback_url = '''
        https://relay-c.example.com/v2?token=\(secrets[10])
        '''
        experimental_bearer_token = "\(secrets[1])"
        http_headers = { Authorization = "Bearer \(secrets[2])" }
        extra_auth = { api_key = "\(secrets[11])" }
        wire_api = "responses"

        [mcp_servers.demo.env]
        API_KEY = "\(secrets[3])"
        """
        try configTOML.write(to: moaHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try Data("{\"tokens\":{\"refresh_token\":\"\(secrets[5])\"}}".utf8)
            .write(to: codexAuthDir.appendingPathComponent("acc1.json"))
        try Data("{\"accounts\":[{\"id\":\"1\",\"authPath\":\"accounts/acc1.json\"}]}".utf8)
            .write(to: moaHome.appendingPathComponent("codex_official_accounts.json"))
        try Data("experimental_bearer_token = \"\(secrets[6])\"".utf8)
            .write(to: backupsDir.appendingPathComponent("config.toml.bak"))
        try Data("{\"profiles\":[{\"name\":\"A\",\"apiKey\":\"\(secrets[0])\",\"baseURL\":\"https://a.example.com\"},{\"name\":\"B\",\"apiKey\":\"\(secrets[1])\",\"baseURL\":\"https://b.example.com?key=\(secrets[4])\"}]}".utf8)
            .write(to: moaHome.appendingPathComponent("profiles.json"))
        try Data("{\"profiles\":[{\"name\":\"CD\",\"apiKey\":\"\(secrets[7])\",\"baseURL\":\"https://cd.example.com\"}]}".utf8)
            .write(to: moaHome.appendingPathComponent("claude_desktop_profiles.json"))
        try Data("{\"profiles\":[{\"name\":\"CC\",\"apiKey\":\"\(secrets[8])\",\"baseURL\":\"https://cc.example.com\"}]}".utf8)
            .write(to: moaHome.appendingPathComponent("claude_code_profiles.json"))
        try Data("{\"overrides\":[]}".utf8)
            .write(to: moaHome.appendingPathComponent("usage-pricing-overrides.json"))

        let controller = MoaDataPackageController(environment: env)
        let plaintextConfigOnly = home.appendingPathComponent("config-only-plain.zip")
        try controller.exportDataPackage(to: plaintextConfigOnly, scope: .configOnly, password: nil)

        let importedHome = try makeTempHome(prefix: "moa-cfgonly-imported")
        defer { try? FileManager.default.removeItem(at: importedHome) }
        _ = try MoaDataPackageController(environment: ["HOME": importedHome.path]).importDataPackage(from: plaintextConfigOnly)

        let importedMoa = importedHome.appendingPathComponent(".moa", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedMoa.appendingPathComponent("codex-auth").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedMoa.appendingPathComponent("codex_official_accounts.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedMoa.appendingPathComponent("backups").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedMoa.appendingPathComponent("usage-pricing-overrides.json").path))

        // Walk EVERY file in the imported .moa directory and verify zero secrets remain
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: importedMoa, includingPropertiesForKeys: [.isRegularFileKey]))
        var combinedContent = ""
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                combinedContent += "\n--- \(fileURL.lastPathComponent) ---\n\(text)"
            }
        }
        for secret in secrets {
            XCTAssertFalse(combinedContent.contains(secret), "Config-only export leaked secret: \(secret)")
        }
        XCTAssertTrue(combinedContent.contains("model_reasoning_effort = \"high\""))
        XCTAssertTrue(combinedContent.contains("https://relay-a.example.com/v1"))
        XCTAssertTrue(combinedContent.contains("https://relay-b.example.com/v1"))
        XCTAssertTrue(combinedContent.contains("https://relay-c.example.com/v2"))
        XCTAssertFalse(combinedContent.contains("user2:pass2"))
    }

    // MARK: - 7. Backup & Recovery Manager

    func testBackupManagerInventoryRestoreAndLegacyDownloadsHygiene() throws {
        let home = try makeTempHome(prefix: "moa-backups")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let moaHome = home.appendingPathComponent(".moa", isDirectory: true)
        let codexBackups = moaHome.appendingPathComponent("backups", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: codexBackups, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data("v1-marker".utf8).write(to: moaHome.appendingPathComponent("marker.txt"))
        try Data("snapshot".utf8).write(to: codexBackups.appendingPathComponent("config-2026.toml"))

        let pkgController = MoaDataPackageController(environment: env)
        // Create an unencrypted Schema 2 backup in Downloads (should be flagged)
        let legacyURL = downloads.appendingPathComponent("Moa-Data-20260410-120000.zip")
        try pkgController.exportDataPackage(to: legacyURL, scope: .fullBackup, password: nil)

        // Create an encrypted Schema 3 backup in Downloads (should NOT be flagged as unencrypted legacy!)
        let encryptedDownloadsURL = downloads.appendingPathComponent("Moa-Data-20260411-120000.zip")
        try pkgController.exportDataPackage(to: encryptedDownloadsURL, scope: .fullBackup, password: "safe", kdfIterations: 100_000)

        // Mutate marker then import legacyURL so a rollback recovery package is automatically created
        try Data("v2-marker".utf8).write(to: moaHome.appendingPathComponent("marker.txt"))
        _ = try pkgController.importDataPackage(from: legacyURL)

        let manager = MoaBackupManager(environment: env, dataPackages: pkgController)
        let inventory = manager.loadInventory()

        XCTAssertEqual(inventory.recoveryPackages.count, 1)
        XCTAssertEqual(inventory.recoveryPackages.first?.kind, .recoveryImportRollback)
        XCTAssertEqual(inventory.codexSnapshots.count, 1)
        XCTAssertEqual(inventory.legacyDownloadsBackups.count, 1)
        XCTAssertEqual(inventory.legacyDownloadsBackups.first?.name, legacyURL.lastPathComponent)

        // Restoring the rollback package brings back v2-marker
        let recovery = try XCTUnwrap(inventory.recoveryPackages.first)
        _ = try manager.restoreRecoveryPackage(recovery)
        XCTAssertEqual(try String(contentsOf: moaHome.appendingPathComponent("marker.txt"), encoding: .utf8), "v2-marker")

        // Deleting a Codex snapshot removes it cleanly
        let snapshot = try XCTUnwrap(inventory.codexSnapshots.first)
        try manager.deleteBackup(snapshot)
        XCTAssertTrue(manager.loadInventory().codexSnapshots.isEmpty)
    }

    // MARK: - 8. Credential Health Inspector

    func testCredentialHealthInspectorAcrossClients() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Codex JWT: expired with refresh -> warning; expired without refresh -> critical; expiringSoon -> warning; healthy -> healthy
        let expiredJWT = try makeJWT(payload: ["exp": now.timeIntervalSince1970 - 60])
        let soonJWT = try makeJWT(payload: ["exp": now.timeIntervalSince1970 + 3600])
        let healthyJWT = try makeJWT(payload: ["exp": now.timeIntervalSince1970 + 7 * 86400])

        XCTAssertEqual(
            MoaCredentialHealthInspector.inspectCodexOfficial(auth: ["tokens": ["access_token": expiredJWT, "refresh_token": "rt"]], now: now).severity,
            .warning
        )
        XCTAssertEqual(
            MoaCredentialHealthInspector.inspectCodexOfficial(auth: ["tokens": ["access_token": expiredJWT]], now: now).severity,
            .critical
        )
        XCTAssertEqual(
            MoaCredentialHealthInspector.inspectCodexOfficial(auth: ["tokens": ["access_token": soonJWT]], now: now).severity,
            .warning
        )
        XCTAssertEqual(
            MoaCredentialHealthInspector.inspectCodexOfficial(auth: ["tokens": ["access_token": healthyJWT]], now: now).severity,
            .healthy
        )

        // WorkBuddy keyblob fingerprint check
        let wbAccount = WorkBuddyAccount(
            id: UUID(), uid: "id", name: "WB", updatedAt: now, snapshot: Data(), keyFingerprint: "fp-expected", edition: .international
        )
        XCTAssertEqual(MoaCredentialHealthInspector.inspectWorkBuddy(account: wbAccount, currentKeyFingerprint: nil).severity, .critical)
        XCTAssertEqual(MoaCredentialHealthInspector.inspectWorkBuddy(account: wbAccount, currentKeyFingerprint: "fp-other").severity, .critical)
        XCTAssertEqual(MoaCredentialHealthInspector.inspectWorkBuddy(account: wbAccount, currentKeyFingerprint: "fp-expected").severity, .healthy)

        // Gemini CLI expired with vs without refresh token
        let expiredOAuth = try JSONSerialization.data(withJSONObject: [
            "access_token": "ya29.exp",
            "expiry_date": Int((now.timeIntervalSince1970 - 120) * 1000)
        ])
        let gemNoRefresh = GeminiCLIAccount(
            id: UUID(), name: "Gem", identity: "id", email: "a@b.com",
            oauthCredsSnapshot: expiredOAuth, googleAccountsSnapshot: nil, updatedAt: now
        )
        XCTAssertEqual(MoaCredentialHealthInspector.inspectGeminiCLI(account: gemNoRefresh, now: now).severity, .critical)

        // Provider API key & external drift check
        let drifted = MoaCredentialHealthInspector.inspectProvider(
            apiKey: "sk-ok",
            baseURL: "https://a.example.com",
            isActive: true,
            liveBaseURL: "https://b.example.com"
        )
        XCTAssertEqual(drifted.severity, .warning)
        let emptyKey = MoaCredentialHealthInspector.inspectProvider(
            apiKey: "",
            baseURL: "https://a.example.com",
            isActive: false,
            liveBaseURL: nil
        )
        XCTAssertEqual(emptyKey.severity, .critical)
    }

    // MARK: - 9. Global Hotkeys & Quick Switcher

    func testGlobalHotkeyManagerAndQuickSwitcherFuzzyRanking() {
        let suiteName = "MoaHotkeyTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = MoaGlobalHotkeyManager(defaults: defaults)
        // Disabled by default
        XCTAssertTrue(manager.bindings.isEmpty)

        // Invalid shortcut (no Command/Option/Control modifier) is rejected
        let invalid = MoaHotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0)
        XCTAssertFalse(invalid.isValid)
        manager.setShortcut(invalid, for: .quickSwitcher)
        XCTAssertNil(manager.shortcut(for: .quickSwitcher))

        // Valid shortcut persists & resolves conflicts cleanly
        let combo = MoaHotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey))
        XCTAssertEqual(combo.displayString, "⌥⌘K")
        manager.setShortcut(combo, for: .quickSwitcher)
        XCTAssertEqual(manager.shortcut(for: .quickSwitcher), combo)

        // Assigning same combo to another action clears previous owner
        manager.setShortcut(combo, for: .openUsage)
        XCTAssertNil(manager.shortcut(for: .quickSwitcher))
        XCTAssertEqual(manager.shortcut(for: .openUsage), combo)

        // Persists across reload
        let reloaded = MoaGlobalHotkeyManager(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .openUsage), combo)

        // Quick Switcher fuzzy search & ranking
        let row1 = MoaAccountRow(
            group: .codexOfficial, id: "1", name: "Work OpenAI", detail: "work@company.com",
            active: false, health: nil
        )
        let row2 = MoaAccountRow(
            group: .geminiCLI, id: "2", name: "Gemini Dev", detail: "dev@gmail.com",
            active: true, health: nil
        )
        let sections = [
            MoaAccountSection(group: .codexOfficial, rows: [row1], canAddCurrentLogin: false, currentLoginMessage: nil, hasUnsavedLiveLogin: false),
            MoaAccountSection(group: .geminiCLI, rows: [row2], canAddCurrentLogin: false, currentLoginMessage: nil, hasUnsavedLiveLogin: false)
        ]
        let items = MoaQuickSwitcherEngine.buildItems(sections: sections, visibleClients: [.codex, .geminiCLI])
        let workMatches = MoaQuickSwitcherEngine.filter(items: items, query: "work")
        XCTAssertEqual(workMatches.first?.title, "Work OpenAI")

        let fuzzyMatches = MoaQuickSwitcherEngine.filter(items: items, query: "gmdv")
        XCTAssertTrue(fuzzyMatches.contains { $0.title == "Gemini Dev" })
    }

    // MARK: - 10. Ed25519 Signed Release Manifest

    func testReleaseManifestEd25519Verification() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation

        let manifest = MoaSignedReleaseManifest(
            schemaVersion: 1,
            version: "1.10.0",
            build: 138,
            publishedAt: "2026-04-15T00:00:00Z",
            assets: [
                "arm64": .init(filename: "Moa-1.10.0-arm64.dmg", sha256: "abcdef0123456789", size: 123456)
            ]
        )
        let manifestData = try JSONEncoder().encode(manifest)
        let signature = try MoaReleaseManifestVerifier.sign(manifestData: manifestData, privateKeyRaw: privateKey.rawRepresentation)

        // Valid raw signature passes
        let verified = try MoaReleaseManifestVerifier.verify(
            manifestData: manifestData,
            signatureBase64OrRaw: signature,
            publicKeyRaw: publicKeyData,
            expectedVersion: "1.10.0",
            expectedArchitecture: "arm64",
            expectedDMGFilename: "Moa-1.10.0-arm64.dmg",
            actualDMGSHA256: "ABCDEF0123456789"
        )
        XCTAssertEqual(verified, manifest)

        // Valid base64 signature passes
        let b64Sig = Data(signature.base64EncodedString().utf8)
        _ = try MoaReleaseManifestVerifier.verify(
            manifestData: manifestData,
            signatureBase64OrRaw: b64Sig,
            publicKeyRaw: publicKeyData,
            expectedVersion: "1.10.0",
            expectedArchitecture: "arm64",
            expectedDMGFilename: "Moa-1.10.0-arm64.dmg",
            actualDMGSHA256: "abcdef0123456789"
        )

        // Wrong digest rejected
        XCTAssertThrowsError(try MoaReleaseManifestVerifier.verify(
            manifestData: manifestData,
            signatureBase64OrRaw: signature,
            publicKeyRaw: publicKeyData,
            expectedVersion: "1.10.0",
            expectedArchitecture: "arm64",
            expectedDMGFilename: "Moa-1.10.0-arm64.dmg",
            actualDMGSHA256: "0000000000000000"
        ))

        // Tampered manifest rejected
        var tampered = manifestData
        tampered.append(0x20)
        XCTAssertThrowsError(try MoaReleaseManifestVerifier.verify(
            manifestData: tampered,
            signatureBase64OrRaw: signature,
            publicKeyRaw: publicKeyData,
            expectedVersion: "1.10.0",
            expectedArchitecture: "arm64",
            expectedDMGFilename: "Moa-1.10.0-arm64.dmg",
            actualDMGSHA256: "abcdef0123456789"
        ))
    }

    // MARK: - 11. Read-Only CLI Companion & Zero Secret Leakage

    func testCLICompanionReadOnlyOutputsAndZeroSecretLeakage() throws {
        let home = try makeTempHome(prefix: "moa-cli")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        // Populate Claude Code provider with a secret API key
        let secretAPIKey = "sk-ant-DO-NOT-LEAK-IN-CLI-12345"
        let ccController = ClaudeCodeSettingsController(environment: env)
        let ccProfile = try ccController.addProfile(
            name: "Private Relay",
            baseURL: "https://relay.private.example",
            apiKey: secretAPIKey,
            model: "claude-sonnet-4-6"
        )
        _ = try ccController.applyProfile(id: ccProfile.id)

        // Populate Gemini CLI account with a secret refresh token
        let secretRefresh = "1//DO-NOT-LEAK-GEMINI-REFRESH"
        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        let jwt = try makeJWT(payload: ["sub": "cli-sub", "email": "cli@example.com", "exp": Date().timeIntervalSince1970 + 7200])
        let oauthData = try JSONSerialization.data(withJSONObject: [
            "access_token": "ya29.DO-NOT-LEAK-ACCESS",
            "refresh_token": secretRefresh,
            "id_token": jwt,
            "expiry_date": Int((Date().timeIntervalSince1970 + 7200) * 1000)
        ])
        try oauthData.write(to: geminiDir.appendingPathComponent("oauth_creds.json"))
        _ = try GeminiCLIController(environment: env).saveCurrent(name: "CLI Google")

        let commands: [(String, [String])] = [
            ("status", ["--json"]),
            ("usage", ["--today", "--json"]),
            ("accounts", ["--json"]),
            ("health", ["--json"]),
            ("backups", ["--json"]),
            ("version", ["--json"]),
            ("help", [])
        ]

        for (cmd, args) in commands {
            let output = MoaCLICompanion.execute(command: cmd, args: args, environment: env)
            XCTAssertEqual(output.exitCode, 0, "CLI \(cmd) failed: \(output.stderr)")
            XCTAssertFalse(output.stdout.contains(secretAPIKey), "CLI \(cmd) leaked API key!")
            XCTAssertFalse(output.stdout.contains(secretRefresh), "CLI \(cmd) leaked refresh token!")
            XCTAssertFalse(output.stdout.contains("DO-NOT-LEAK-ACCESS"), "CLI \(cmd) leaked access token!")
            if args.contains("--json") {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(output.stdout.utf8)), "CLI \(cmd) --json must output valid JSON")
            }
        }

        // Verify accounts JSON contains our saved profiles/accounts
        let accountsOut = MoaCLICompanion.execute(command: "accounts", args: ["--json"], environment: env)
        XCTAssertTrue(accountsOut.stdout.contains("Private Relay"))
        XCTAssertTrue(accountsOut.stdout.contains("CLI Google"))
    }

    func testCLICompanionIsStrictlyReadOnlyAndDoesNotMigrateLegacyMoaLite() throws {
        let home = try makeTempHome(prefix: "moa-cli-readonly")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        // Seed a legacy ~/.moa-lite directory AND client log files without creating ~/.moa or App Support/Moa
        let legacyDir = home.appendingPathComponent(".moa-lite", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try Data("legacy-data".utf8).write(to: legacyDir.appendingPathComponent("marker.txt"))

        let codexSessions = home.appendingPathComponent(".codex/sessions/2026/04/15", isDirectory: true)
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        let sessionLine = "{\"timestamp\":\"2026-04-15T10:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":0,\"output_tokens\":20}}}}\n"
        try sessionLine.write(to: codexSessions.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)

        func snapshotTree() -> [String] {
            guard let enumerator = FileManager.default.enumerator(at: home, includingPropertiesForKeys: nil) else { return [] }
            var paths: [String] = []
            for case let url as URL in enumerator {
                paths.append(url.path.replacingOccurrences(of: home.path, with: ""))
            }
            return paths.sorted()
        }

        let before = snapshotTree()
        for (cmd, args) in [
            ("version", ["--json"]),
            ("help", []),
            ("status", ["--json"]),
            ("usage", ["--today", "--json"]),
            ("accounts", ["--json"]),
            ("health", ["--json"]),
            ("backups", ["--json"])
        ] {
            let output = MoaCLICompanion.execute(command: cmd, args: args, environment: env)
            XCTAssertEqual(output.exitCode, 0, "CLI \(cmd) failed: \(output.stderr)")
        }

        let after = snapshotTree()
        XCTAssertEqual(before, after, "Read-only CLI must not create, migrate, or modify any files under HOME")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".moa").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Moa").path))
    }

    func testUpdaterEndToEndSignedManifestVerificationAndFailClosed() async throws {
        final class ManifestURLProtocol: URLProtocol {
            nonisolated(unsafe) static var responses: [URL: Data] = [:]
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url, let data = Self.responses[url] else {
                    let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        #if arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif
        let dmgName = "Moa-1.10.0-macos-\(arch).dmg"
        let validDigest = String(repeating: "a", count: 64)
        let manifest = MoaSignedReleaseManifest(
            schemaVersion: 1,
            version: "1.10.0",
            build: 138,
            publishedAt: "2026-11-26T00:00:00Z",
            assets: [arch: .init(filename: dmgName, sha256: validDigest, size: 1024)]
        )
        let manifestData = try JSONEncoder().encode(manifest)
        let validSig = try MoaReleaseManifestVerifier.sign(manifestData: manifestData, privateKeyRaw: privateKey.rawRepresentation)

        let manifestURL = URL(string: "https://example.invalid/Moa-1.10.0-release-manifest.json")!
        let sigURL = URL(string: "https://example.invalid/Moa-1.10.0-release-manifest.json.sig")!
        let badSigURL = URL(string: "https://example.invalid/bad.sig")!
        ManifestURLProtocol.responses = [
            manifestURL: manifestData,
            sigURL: Data(validSig.base64EncodedString().utf8),
            badSigURL: Data(Data(repeating: 0x42, count: 64).base64EncodedString().utf8)
        ]

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ManifestURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let updater = MoaUpdateController(session: session)
        let workDir = try makeTempHome(prefix: "moa-manifest-work")
        defer { try? FileManager.default.removeItem(at: workDir) }

        let baseRelease = URL(string: "https://example.invalid/release")!
        let dmgURL = URL(string: "https://example.invalid/\(dmgName)")!
        let shaURL = URL(string: "https://example.invalid/\(dmgName).sha256")!

        // 1. Valid signed manifest passes
        let validUpdate = MoaUpdateInfo(
            version: "1.10.0", build: 138, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: manifestURL, manifestSignatureURL: sigURL
        )
        let verified = try await updater.verifySignedManifestIfPresent(
            update: validUpdate, dmgFilename: dmgName, verifiedDigest: validDigest,
            workDirectory: workDir, publicKeyOverride: publicKeyData
        )
        XCTAssertEqual(verified, manifest)

        // 2. Bad signature fails closed
        let badSigUpdate = MoaUpdateInfo(
            version: "1.10.0", build: 138, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: manifestURL, manifestSignatureURL: badSigURL
        )
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: badSigUpdate, dmgFilename: dmgName, verifiedDigest: validDigest,
                workDirectory: workDir, publicKeyOverride: publicKeyData
            )
            XCTFail("Expected invalidManifestSignature")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }

        // 3. Stripped signature (manifest present without .sig) fails closed
        let strippedSigUpdate = MoaUpdateInfo(
            version: "1.10.0", build: 138, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: manifestURL, manifestSignatureURL: nil
        )
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: strippedSigUpdate, dmgFilename: dmgName, verifiedDigest: validDigest,
                workDirectory: workDir, publicKeyOverride: publicKeyData
            )
            XCTFail("Expected invalidManifestSignature when signature is stripped")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }

        // 4. Digest mismatch fails closed
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: validUpdate, dmgFilename: dmgName, verifiedDigest: String(repeating: "b", count: 64),
                workDirectory: workDir, publicKeyOverride: publicKeyData
            )
            XCTFail("Expected manifestDigestMismatch")
        } catch MoaUpdateError.manifestDigestMismatch {
            // Expected
        }

        // 5. Missing BOTH manifest and signature fails closed for >= 1.10.0 (including install entry)
        let missingBothUpdate = MoaUpdateInfo(
            version: "1.10.0", build: 138, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: nil, manifestSignatureURL: nil
        )
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: missingBothUpdate, dmgFilename: dmgName, verifiedDigest: validDigest,
                workDirectory: workDir, publicKeyOverride: publicKeyData
            )
            XCTFail("Expected invalidManifestSignature when both manifest and .sig are missing for 1.10.0")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }
        do {
            try await updater.downloadAndInstall(missingBothUpdate)
            XCTFail("Expected downloadAndInstall to reject >= 1.10.0 update missing both manifest and .sig")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }

        // 6. Legacy (< 1.10.0) releases remain compatible when both manifest and .sig are absent,
        //    but still fail closed on a half-present manifest/signature pair.
        let legacyUpdate = MoaUpdateInfo(
            version: "1.9.9", build: 137, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: nil, manifestSignatureURL: nil
        )
        let legacyVerified = try await updater.verifySignedManifestIfPresent(
            update: legacyUpdate, dmgFilename: "Moa-1.9.9-macos-\(arch).dmg", verifiedDigest: validDigest,
            workDirectory: workDir, publicKeyOverride: publicKeyData
        )
        XCTAssertNil(legacyVerified)

        let legacyStripped = MoaUpdateInfo(
            version: "1.9.9", build: 137, releaseURL: baseRelease, dmgURL: dmgURL, checksumURL: shaURL,
            manifestURL: manifestURL, manifestSignatureURL: nil
        )
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: legacyStripped, dmgFilename: "Moa-1.9.9-macos-\(arch).dmg", verifiedDigest: validDigest,
                workDirectory: workDir, publicKeyOverride: publicKeyData
            )
            XCTFail("Expected invalidManifestSignature for legacy half-present manifest")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }
    }

    func testGitHubAPIPathRequiresSignedManifestWhenBothAssetsMissingFor1100Plus() async throws {
        final class MissingManifestAPIProtocol: URLProtocol {
            nonisolated(unsafe) static var requestedURLs: [URL] = []
            nonisolated(unsafe) static var responseBody = Data()
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                let url = request.url!
                Self.requestedURLs.append(url)
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Self.responseBody)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        // Version threshold checks
        XCTAssertFalse(MoaUpdateController.requiresSignedManifest(forVersion: "0.9.0"))
        XCTAssertFalse(MoaUpdateController.requiresSignedManifest(forVersion: "1.9.9"))
        XCTAssertFalse(MoaUpdateController.requiresSignedManifest(forVersion: "1.9.999"))
        XCTAssertTrue(MoaUpdateController.requiresSignedManifest(forVersion: "1.10.0"))
        XCTAssertTrue(MoaUpdateController.requiresSignedManifest(forVersion: "1.10.0-rc.1"))
        XCTAssertTrue(MoaUpdateController.requiresSignedManifest(forVersion: "1.10.1"))
        XCTAssertTrue(MoaUpdateController.requiresSignedManifest(forVersion: "2.0.0"))
        XCTAssertTrue(MoaUpdateController.requiresSignedManifest(forVersion: "invalid"))

        #if arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif
        let dmgName = "Moa-999.0.0-macos-\(arch).dmg"
        let shaName = "\(dmgName).sha256"
        let apiJSON = """
        {
          "tag_name": "v999.0.0",
          "name": "Moa 999.0.0 (Build 999)",
          "body": "Build 999",
          "html_url": "https://github.com/MoarLiu/Moa/releases/tag/v999.0.0",
          "assets": [
            {"name": "\(dmgName)", "browser_download_url": "https://example.invalid/\(dmgName)"},
            {"name": "\(shaName)", "browser_download_url": "https://example.invalid/\(shaName)"}
          ]
        }
        """
        MissingManifestAPIProtocol.requestedURLs = []
        MissingManifestAPIProtocol.responseBody = Data(apiJSON.utf8)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MissingManifestAPIProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let updater = MoaUpdateController(session: session)

        let checkResult = try await updater.checkForUpdate()
        guard case .updateAvailable(let update) = checkResult else {
            return XCTFail("Expected .updateAvailable from mocked GitHub API")
        }
        XCTAssertEqual(update.version, "999.0.0")
        XCTAssertNil(update.manifestURL)
        XCTAssertNil(update.manifestSignatureURL)
        XCTAssertEqual(MissingManifestAPIProtocol.requestedURLs.count, 1)

        // Install entry must reject before downloading DMG when both manifest and .sig are missing
        do {
            try await updater.downloadAndInstall(update)
            XCTFail("Expected downloadAndInstall to reject GitHub API update missing both manifest and .sig")
        } catch MoaUpdateError.invalidManifestSignature {
            XCTAssertEqual(MissingManifestAPIProtocol.requestedURLs.count, 1, "Must fail before downloading DMG")
        }

        // Direct verification entry must also fail closed
        let workDir = try makeTempHome(prefix: "moa-api-missing-manifest")
        defer { try? FileManager.default.removeItem(at: workDir) }
        let key = Curve25519.Signing.PrivateKey()
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: update, dmgFilename: dmgName,
                verifiedDigest: String(repeating: "a", count: 64),
                workDirectory: workDir, publicKeyOverride: key.publicKey.rawRepresentation
            )
            XCTFail("Expected verifySignedManifestIfPresent to fail closed when both assets are missing")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }
    }

    func testAtomFeedFallbackRetainsSignedManifestAndDetectsStrippedSignature() async throws {
        #if arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif
        let dmg = "Moa-1.10.1-macos-\(arch).dmg"
        let manifestName = "Moa-1.10.1-release-manifest.json"
        let sigName = "\(manifestName).sig"

        // 1. Atom entry listing both manifest and signature preserves both URLs
        let fullFeed = """
        <feed>
          <entry>
            <title>v1.10.1</title>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.10.1"/>
            <content>Assets: \(dmg) \(manifestName) \(sigName)</content>
          </entry>
        </feed>
        """
        let fullUpdate = try MoaUpdateController.releaseInfo(fromAtomFeed: fullFeed)
        XCTAssertEqual(fullUpdate.manifestURL?.lastPathComponent, manifestName)
        XCTAssertEqual(fullUpdate.manifestSignatureURL?.lastPathComponent, sigName)

        // 2. Atom entry with manifest only (stripped .sig) retains manifestURL and nil signature -> fails closed
        let strippedSigFeed = """
        <feed>
          <entry>
            <title>v1.10.1</title>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.10.1"/>
            <content>Assets: \(dmg) \(manifestName)</content>
          </entry>
        </feed>
        """
        let strippedUpdate = try MoaUpdateController.releaseInfo(fromAtomFeed: strippedSigFeed)
        XCTAssertEqual(strippedUpdate.manifestURL?.lastPathComponent, manifestName)
        XCTAssertNil(strippedUpdate.manifestSignatureURL)

        let privateKey = Curve25519.Signing.PrivateKey()
        let updater = MoaUpdateController()
        let workDir = try makeTempHome(prefix: "moa-atom-verify")
        defer { try? FileManager.default.removeItem(at: workDir) }
        do {
            _ = try await updater.verifySignedManifestIfPresent(
                update: strippedUpdate, dmgFilename: dmg,
                verifiedDigest: String(repeating: "a", count: 64),
                workDirectory: workDir, publicKeyOverride: privateKey.publicKey.rawRepresentation
            )
            XCTFail("Stripped .sig on Atom update must fail closed")
        } catch MoaUpdateError.invalidManifestSignature {
            // Expected
        }

        // 3. Atom entry with ONLY .sig does not falsely match .json as substring
        let sigOnlyFeed = """
        <feed>
          <entry>
            <title>v1.10.1</title>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.10.1"/>
            <content>Assets: \(dmg) \(sigName)</content>
          </entry>
        </feed>
        """
        let sigOnlyUpdate = try MoaUpdateController.releaseInfo(fromAtomFeed: sigOnlyFeed)
        XCTAssertNil(sigOnlyUpdate.manifestURL)
        XCTAssertEqual(sigOnlyUpdate.manifestSignatureURL?.lastPathComponent, sigName)

        // 4. Atom entry for >= 1.10.0 omitting manifest filenames still resolves signed manifest pair deterministically
        let minimalNewFeed = """
        <feed>
          <entry>
            <title>v1.11.0</title>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.11.0"/>
            <content>Moa-1.11.0-macos-\(arch).dmg</content>
          </entry>
        </feed>
        """
        let minimalUpdate = try MoaUpdateController.releaseInfo(fromAtomFeed: minimalNewFeed)
        XCTAssertEqual(minimalUpdate.manifestURL?.lastPathComponent, "Moa-1.11.0-release-manifest.json")
        XCTAssertEqual(minimalUpdate.manifestSignatureURL?.lastPathComponent, "Moa-1.11.0-release-manifest.json.sig")

        // 5. Legacy Atom entry (< 1.10.0) omitting manifest filenames keeps both URLs nil for backward compatibility
        let legacyFeed = """
        <feed>
          <entry>
            <title>v1.9.9</title>
            <link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v1.9.9"/>
            <content>Moa-1.9.9-macos-\(arch).dmg</content>
          </entry>
        </feed>
        """
        let legacyUpdate = try MoaUpdateController.releaseInfo(fromAtomFeed: legacyFeed)
        XCTAssertNil(legacyUpdate.manifestURL)
        XCTAssertNil(legacyUpdate.manifestSignatureURL)
    }

    func testCLIRedactsProviderURLSecretsReadsCodexOfficialHealthAndResolvesSymlinkVersion() throws {
        let home = try makeTempHome(prefix: "moa-cli-recheck")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = ["HOME": home.path]

        let moaHome = home.appendingPathComponent(".moa", isDirectory: true)
        let accountsDir = moaHome.appendingPathComponent("codex-auth/accounts", isDirectory: true)
        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        // 1. Valid Codex official account saved under real authPath ("codex-auth/accounts/<uuid>.json")
        let accountID = UUID().uuidString
        let validJWT = try makeJWT(payload: ["email": "healthy@example.com", "exp": Date().timeIntervalSince1970 + 7 * 86400])
        let authJSON = try JSONSerialization.data(withJSONObject: [
            "tokens": [
                "access_token": validJWT,
                "refresh_token": "rt-secret-never-print-codex"
            ]
        ])
        try authJSON.write(to: accountsDir.appendingPathComponent("\(accountID).json"))
        try authJSON.write(to: codexDir.appendingPathComponent("auth.json"))
        let officialDB = CodexOfficialAccountDatabase(
            selectedAccountID: accountID,
            accounts: [
                CodexOfficialAccount(
                    id: accountID,
                    name: "Healthy Official",
                    email: "healthy@example.com",
                    authPath: "codex-auth/accounts/\(accountID).json",
                    createdAt: "2026-04-10T00:00:00Z",
                    lastUsedAt: nil
                )
            ]
        )
        try JSONEncoder().encode(officialDB)
            .write(to: moaHome.appendingPathComponent("codex_official_accounts.json"))

        // 2. Providers with URL credentials in Codex, Claude Desktop, and Claude Code
        let urlSecrets = ["sk-url-codex-111", "sk-url-desktop-222", "sk-url-code-333", "user1:pass1"]
        let codexProfilesJSON: [String: Any] = [
            "selectedProfileID": "p1",
            "profiles": [[
                "id": "p1",
                "name": "Codex Secret URL",
                "baseURL": "https://user1:pass1@codex.example.com/v1?api_key=\(urlSecrets[0])#frag",
                "apiKey": "sk-codex-raw-key",
                "model": "gpt-5.4"
            ]]
        ]
        try JSONSerialization.data(withJSONObject: codexProfilesJSON)
            .write(to: moaHome.appendingPathComponent("profiles.json"))

        let desktopProfilesJSON: [String: Any] = [
            "selectedProfileID": "d1",
            "profiles": [[
                "id": "d1",
                "name": "Desktop Secret URL",
                "baseURL": "https://desktop.example.com/v1?token=\(urlSecrets[1])",
                "apiKey": "sk-desktop-raw-key",
                "models": ["claude-sonnet-4-6"]
            ]]
        ]
        try JSONSerialization.data(withJSONObject: desktopProfilesJSON)
            .write(to: moaHome.appendingPathComponent("claude_desktop_profiles.json"))

        let ccCtrl = ClaudeCodeSettingsController(environment: env)
        _ = try ccCtrl.addProfile(
            name: "Code Secret URL",
            baseURL: "https://code.example.com/v1?key=\(urlSecrets[2])",
            apiKey: "sk-code-raw-key",
            model: "claude-sonnet-4-6"
        )

        let accountsOut = MoaCLICompanion.execute(command: "accounts", args: ["--json"], environment: env)
        let healthOut = MoaCLICompanion.execute(command: "health", args: ["--json"], environment: env)
        XCTAssertEqual(accountsOut.exitCode, 0)
        XCTAssertEqual(healthOut.exitCode, 0)

        for combined in [accountsOut.stdout, healthOut.stdout] {
            for secret in urlSecrets + ["rt-secret-never-print-codex", "sk-codex-raw-key", "sk-desktop-raw-key", "sk-code-raw-key"] {
                XCTAssertFalse(combined.contains(secret), "CLI output leaked secret: \(secret)")
            }
            XCTAssertTrue(combined.contains("https:\\/\\/codex.example.com\\/v1") || combined.contains("https://codex.example.com/v1"))
            XCTAssertTrue(combined.contains("https:\\/\\/desktop.example.com\\/v1") || combined.contains("https://desktop.example.com/v1"))
            XCTAssertTrue(combined.contains("https:\\/\\/code.example.com\\/v1") || combined.contains("https://code.example.com/v1"))
        }

        // Verify Codex official account is reported as healthy + active (NOT Missing Token!)
        let parsedHealth = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(healthOut.stdout.utf8)) as? [[String: Any]])
        let officialEntry = try XCTUnwrap(parsedHealth.first { ($0["group"] as? String) == "codexOfficial" })
        XCTAssertEqual(officialEntry["healthSeverity"] as? String, "healthy")
        XCTAssertEqual(officialEntry["active"] as? Bool, true)

        // 3. Symlinked CLI version resolution finds enclosing .app Info.plist
        let fakeApp = home.appendingPathComponent("Moa.app", isDirectory: true)
        let macOSDir = fakeApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let fakeExec = macOSDir.appendingPathComponent("Moa")
        try Data("#!/bin/sh\n".utf8).write(to: fakeExec)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.moarliu.moa</string>
          <key>CFBundleShortVersionString</key><string>1.10.0</string>
          <key>MoaReleaseVersion</key><string>1.10.0</string>
          <key>CFBundleVersion</key><string>138</string>
        </dict></plist>
        """
        try plist.write(to: fakeApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let symlinkURL = home.appendingPathComponent("bin/moa")
        try FileManager.default.createDirectory(at: symlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: fakeExec)

        let versionInfo = MoaCLICompanion.resolvedVersionInfo(
            mainBundle: Bundle(url: symlinkURL.deletingLastPathComponent()) ?? .main,
            executablePathOverride: symlinkURL.path
        )
        XCTAssertEqual(versionInfo.version, "1.10.0")
        XCTAssertEqual(versionInfo.build, "138")
    }
}
#endif
