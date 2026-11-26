#if !MOA_TESTING
import AppKit
import Foundation
import XCTest
@testable import Moa

final class MoaRelease190Tests: XCTestCase {
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.moarliu.moa.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func summary(cost: Double, tokens: Int = 1000, date: Date = Date()) -> CodexUsageSummary {
        CodexUsageSummary(
            todayCostUSD: cost,
            totalCostUSD: cost,
            todayTokens: tokens,
            totalTokens: tokens,
            cacheHitPercent: 25,
            topModelName: nil,
            topModelTokens: 0,
            topModelPercent: 0,
            updatedAt: date
        )
    }

    func testCodexPrepareNewOfficialAccountLoginSavesCurrentAndRestoresOfficialMode() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-190-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let env = ["HOME": home.path]
        let codexDir = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let payload = Data(#"{"sub":"user-190","email":"alpha@example.com","https://api.openai.com/auth":{"chatgpt_account_id":"acct-190"}}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authJSON = """
        {
          "tokens": {
            "id_token": "hdr.\(payload).sig",
            "access_token": "acc-190",
            "refresh_token": "ref-190",
            "account_id": "acct-190"
          },
          "last_refresh": "2026-11-26T00:00:00Z"
        }
        """
        try authJSON.write(to: codexDir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)

        let controller = ConfigProfileController(environment: env)
        try controller.ensureStore()
        let added = try controller.addProfile(name: "Relay", baseURL: "https://relay.example.com/v1", apiKey: "sk-relay")
        _ = try controller.applyProfile(id: added.id)
        XCTAssertEqual(try controller.selectedProfileID(), added.id)

        try controller.prepareNewOfficialAccountLogin()

        let savedAccounts = try controller.officialAccounts()
        XCTAssertEqual(savedAccounts.count, 1)
        XCTAssertEqual(savedAccounts[0].email, "alpha@example.com")
        XCTAssertNil(try controller.selectedOfficialAccountID())
        XCTAssertNil(try controller.selectedProfileID())
        XCTAssertFalse(controller.hasOfficialAuthSession(controller.readAuthJSON(from: codexDir.appendingPathComponent("auth.json"))))

        let liveConfig = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertFalse(liveConfig.contains("https://relay.example.com/v1"))
        XCTAssertFalse(liveConfig.contains("sk-relay"))
    }

    func testClaudeCodeEnvironmentSnippetUsesFirstModelAndEscapesValues() {
        let profile = ClaudeDesktopProviderProfile(
            id: "p1",
            name: "Gateway",
            baseURL: "https://api.example.com/v1",
            apiKey: #"sk-$test"key`1"#,
            models: ["claude-sonnet-4-6", "claude-opus-4-6"],
            oneMModels: []
        )
        let snippet = MoaProfileActionCoordinator.claudeCodeEnvironmentSnippet(for: profile)
        XCTAssertTrue(snippet.contains(#"export ANTHROPIC_BASE_URL="https://api.example.com/v1""#))
        XCTAssertTrue(snippet.contains(#"export ANTHROPIC_AUTH_TOKEN="sk-\$test\"key\`1""#))
        XCTAssertTrue(snippet.contains(#"export ANTHROPIC_MODEL="claude-sonnet-4-6""#))
        XCTAssertTrue(snippet.contains(#"export ANTHROPIC_SMALL_FAST_MODEL="claude-sonnet-4-6""#))

        let emptyModels = ClaudeDesktopProviderProfile(
            id: "p2",
            name: "Default",
            baseURL: "https://api.example.com",
            apiKey: "sk-plain",
            models: [],
            oneMModels: []
        )
        let defaultSnippet = MoaProfileActionCoordinator.claudeCodeEnvironmentSnippet(for: emptyModels)
        XCTAssertTrue(defaultSnippet.contains(#"export ANTHROPIC_MODEL="\#(ProviderConnectionTester.claudeDefaultTestModel)""#))
    }

    func testDailyUsageAlert80PercentWarningAndThresholdDeduplication() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let day1 = Date(timeIntervalSince1970: 1_795_651_200) // 2026-11-26
        let day2 = day1.addingTimeInterval(24 * 60 * 60)

        DailyUsageAlertController.setThreshold(10.0, for: .codex, defaults: defaults)
        XCTAssertFalse(DailyUsageAlertController.warning80Enabled(for: .codex, defaults: defaults))
        XCTAssertNil(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 8.5, date: day1), defaults: defaults))

        DailyUsageAlertController.setWarning80Enabled(true, for: .codex, defaults: defaults)
        XCTAssertNil(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 7.99, date: day1), defaults: defaults))
        XCTAssertEqual(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 8.0, date: day1), defaults: defaults), .warning80)
        XCTAssertNil(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 9.2, date: day1), defaults: defaults), "80% warning should fire once per day/threshold")
        XCTAssertEqual(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 10.0, date: day1), defaults: defaults), .reached)
        XCTAssertNil(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 12.0, date: day1), defaults: defaults), "100% alert should fire once per day/threshold")

        // Jumping straight past 100% suppresses any subsequent 80% warning for that day.
        DailyUsageAlertController.setThreshold(10.0, for: .claude, defaults: defaults)
        DailyUsageAlertController.setWarning80Enabled(true, for: .claude, defaults: defaults)
        XCTAssertEqual(DailyUsageAlertController.pendingAlertLevel(kind: .claude, summary: summary(cost: 10.5, date: day1), defaults: defaults), .reached)
        XCTAssertNil(DailyUsageAlertController.pendingAlertLevel(kind: .claude, summary: summary(cost: 8.5, date: day1), defaults: defaults))

        // Next day resets deduplication.
        XCTAssertEqual(DailyUsageAlertController.pendingAlertLevel(kind: .codex, summary: summary(cost: 8.1, date: day2), defaults: defaults), .warning80)
    }

    func testNotificationManagerDeliversRoutesAndFallsBackSafely() {
        let backend = FakeNotificationBackend()
        var fallbacks: [(String, String)] = []
        let manager = MoaNotificationManager(backend: backend) { title, body in
            fallbacks.append((title, body))
        }

        var routed: [MoaNotificationAction] = []
        manager.onAction = { routed.append($0) }

        backend.state = .authorized
        backend.shouldDeliver = true
        manager.post(identifier: "u1", title: "Reached", body: "$10", action: .openUsage(.codex))
        XCTAssertEqual(backend.delivered.count, 1)
        XCTAssertEqual(backend.delivered[0].action, .openUsage(.codex))
        XCTAssertTrue(fallbacks.isEmpty)

        backend.state = .denied
        backend.shouldDeliver = false
        manager.post(identifier: "u2", title: "Reached", body: "$10", action: .openUsage(.claude), fallbackOnDenied: true)
        XCTAssertEqual(fallbacks.count, 1)
        XCTAssertEqual(fallbacks[0].0, "Reached")

        backend.state = .notDetermined
        manager.post(identifier: "u3", title: "Update", body: "v1.9.0", action: .openSettingsAbout,
                     allowsAuthorizationPrompt: false, fallbackOnDenied: false)
        XCTAssertEqual(backend.authorizationPromptOptions, [true, true, false])
        XCTAssertEqual(fallbacks.count, 1, "Background update alerts should stay silent when notification delivery is unavailable.")

        backend.simulateTap(action: .openUsage(.workbuddyCN))
        backend.simulateTap(action: .openSettingsAbout)
        XCTAssertEqual(routed, [.openUsage(.workbuddyCN), .openSettingsAbout])

        XCTAssertEqual(MoaNotificationAction.parse(userInfo: MoaNotificationAction.openUsage(.zcode).userInfo), .openUsage(.zcode))
        XCTAssertEqual(MoaNotificationAction.parse(userInfo: MoaNotificationAction.openUsage(nil).userInfo), .openUsage(nil))
        XCTAssertEqual(MoaNotificationAction.parse(userInfo: MoaNotificationAction.openSettingsAbout.userInfo), .openSettingsAbout)
    }

    func testAppLanguageBundleResolutionAndMenuBarSummaryFormatter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("assets/Localization")
        let parentBundle = try XCTUnwrap(Bundle(url: root))
        let zhBundle = MoaL10n.bundle(for: .zhHans, in: parentBundle)
        let enBundle = MoaL10n.bundle(for: .english, in: parentBundle)
        XCTAssertEqual(NSLocalizedString("General", bundle: zhBundle, comment: ""), "常规")
        XCTAssertEqual(NSLocalizedString("General", bundle: enBundle, comment: ""), "General")

        XCTAssertEqual(MoaMenuBarDisplayPreferences.statusItemTitle(summaries: [:], showTodayCost: false), "")
        XCTAssertEqual(MoaMenuBarDisplayPreferences.statusItemTitle(summaries: [:], showTodayCost: true), " —")
        let title = MoaMenuBarDisplayPreferences.statusItemTitle(
            summaries: [.codex: summary(cost: 2.5), .claude: summary(cost: 1.25)],
            showTodayCost: true
        )
        XCTAssertEqual(title, " $3.75")
    }

    func testLaunchAtLoginControllerReflectsBackendStatusAndErrors() {
        let backend = FakeLaunchAtLoginBackend()
        let controller = MoaLaunchAtLoginController(backend: backend)
        XCTAssertEqual(controller.status, .disabled)

        XCTAssertTrue(controller.setEnabled(true))
        XCTAssertEqual(controller.status, .enabled)

        backend.nextStatus = .requiresApproval
        controller.refresh()
        XCTAssertEqual(controller.status, .requiresApproval)
        XCTAssertTrue(controller.status.isEnabled)
        controller.openSystemSettings()
        XCTAssertEqual(backend.openedSettingsCount, 1)

        backend.shouldThrow = true
        XCTAssertFalse(controller.setEnabled(false))
        XCTAssertNotNil(controller.lastError)

        backend.nextStatus = .unsupportedOS
        controller.refresh()
        XCTAssertEqual(controller.status, .unsupportedOS)
        XCTAssertFalse(controller.status.isEnabled)
    }

    @MainActor
    func testUpdateCoordinatorSchedulesDailyChecksAndDeduplicatesDiscovery() async throws {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        var clock = Date(timeIntervalSince1970: 1_795_651_200)
        let update190 = MoaUpdateInfo(
            version: "1.9.0",
            build: 137,
            releaseURL: URL(string: "https://github.com/MoarLiu/Moa/releases/tag/v1.9.0")!,
            dmgURL: URL(string: "https://github.com/MoarLiu/Moa/releases/download/v1.9.0/Moa-1.9.0-macos-arm64.dmg")!,
            checksumURL: URL(string: "https://github.com/MoarLiu/Moa/releases/download/v1.9.0/Moa-1.9.0-macos-arm64.dmg.sha256")!
        )
        var nextResult: MoaUpdateCheckResult = .updateAvailable(update190)
        var checks = 0

        let coordinator = MoaUpdateCoordinator(
            defaults: defaults,
            now: { clock },
            checkHandler: {
                checks += 1
                return nextResult
            }
        )
        var discovered: [String] = []
        coordinator.onBackgroundUpdateDiscovered = { discovered.append($0.version) }

        XCTAssertTrue(coordinator.isBackgroundCheckDue())
        _ = await coordinator.performBackgroundCheckIfDue()
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(coordinator.availableUpdate?.version, "1.9.0")
        XCTAssertEqual(discovered, ["1.9.0"])
        XCTAssertFalse(coordinator.isBackgroundCheckDue())

        // Within 24h, background check is skipped.
        clock = clock.addingTimeInterval(60 * 60)
        _ = await coordinator.performBackgroundCheckIfDue()
        XCTAssertEqual(checks, 1)

        // After 24h, same release does not re-notify.
        clock = clock.addingTimeInterval(24 * 60 * 60)
        XCTAssertTrue(coordinator.isBackgroundCheckDue())
        _ = await coordinator.performBackgroundCheckIfDue()
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(discovered, ["1.9.0"])

        // When up to date, availableUpdate clears.
        nextResult = .upToDate(remoteVersion: "1.9.0", remoteBuild: 137)
        _ = try await coordinator.checkNow(userInitiated: true)
        XCTAssertNil(coordinator.availableUpdate)

        // Opting out disables background checks.
        coordinator.autoCheckEnabled = false
        clock = clock.addingTimeInterval(48 * 60 * 60)
        XCTAssertFalse(coordinator.isBackgroundCheckDue())
    }

    @MainActor
    func testWorkspaceParityNavigationStatusLabelsAndEnhancementState() {
        _ = NSApplication.shared
        MoaRuntimeMode.suppressesUserInteraction = true

        let navigation = MoaWorkspaceNavigation()
        navigation.showSettings(.about)
        XCTAssertEqual(navigation.destination, .settings)
        XCTAssertEqual(navigation.settingsTab, .about)

        let claudeOfficial = MoaAccountSection(group: .claude, rows: [], canAddCurrentLogin: false)
        XCTAssertTrue(MoaWorkspaceClientView.activeStatusTitle(for: claudeOfficial).contains("Claude Desktop Official"))

        let codexOfficialMode = MoaAccountSection(group: .codexConfig, rows: [], canAddCurrentLogin: false)
        XCTAssertTrue(MoaWorkspaceClientView.activeStatusTitle(for: codexOfficialMode).contains("Codex Official Mode"))

        let activeProvider = MoaAccountSection(
            group: .claude,
            rows: [MoaAccountRow(group: .claude, id: "1", name: "Relay", detail: "https://relay.example.com", active: true)],
            canAddCurrentLogin: false
        )
        XCTAssertTrue(MoaWorkspaceClientView.activeStatusTitle(for: activeProvider).contains("Relay"))

        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = CodexEnhancementCoordinator(
            controller: CodexAppController(),
            operations: MoaAccountOperationState(),
            defaults: defaults
        )
        XCTAssertFalse(coordinator.settings.enabled)
        coordinator.setEnabled(true)
        coordinator.setShowContext(true)
        coordinator.setShowCache(true)
        coordinator.setBelowComposer(true)
        XCTAssertTrue(coordinator.settings.enabled)
        XCTAssertTrue(coordinator.settings.showContext)
        XCTAssertTrue(coordinator.settings.showCache)
        XCTAssertTrue(coordinator.settings.belowComposer)
        XCTAssertEqual(CodexStatusLineSettings(defaults: defaults), coordinator.settings)
    }

    @MainActor
    func testMenuBarRebuildPreservesClaudeEnvCopyAndUpdateIndicator() {
        _ = NSApplication.shared
        MoaRuntimeMode.suppressesUserInteraction = true
        let app = AppDelegate()
        app.mainMenuCoordinator.configureMenu()
        app.mainMenuCoordinator.configureMenu()
        app.mainMenuCoordinator.rebuildClaudeDesktopProfilesMenu()

        let hasCopyClaudeEnv = app.claudeDesktopProfilesMenu.items.contains {
            $0.action == #selector(AppDelegate.copyClaudeCodeConfigAction)
        }
        XCTAssertTrue(hasCopyClaudeEnv, "Claude Desktop menu must expose Copy Claude Code Env.")
        let updateItems = app.menu.items.flatMap { $0.submenu?.items ?? [] }.filter {
            $0.action == #selector(AppDelegate.openSettingsAboutAction)
        }
        XCTAssertEqual(updateItems.count, 1)
    }
}

private final class FakeNotificationBackend: MoaUserNotificationDelivering {
    var onAction: ((MoaNotificationAction) -> Void)?
    var state: MoaNotificationAuthorizationState = .notDetermined
    var shouldDeliver = true
    var delivered: [(identifier: String, title: String, body: String, action: MoaNotificationAction)] = []
    var authorizationPromptOptions: [Bool] = []

    func authorizationState(completion: @escaping (MoaNotificationAuthorizationState) -> Void) {
        completion(state)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        state = shouldDeliver ? .authorized : .denied
        completion(shouldDeliver)
    }

    func deliver(
        identifier: String,
        title: String,
        body: String,
        action: MoaNotificationAction,
        allowsAuthorizationPrompt: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        authorizationPromptOptions.append(allowsAuthorizationPrompt)
        if shouldDeliver {
            delivered.append((identifier, title, body, action))
        }
        completion(shouldDeliver)
    }

    func simulateTap(action: MoaNotificationAction) {
        onAction?(action)
    }
}

private final class FakeLaunchAtLoginBackend: MoaLaunchAtLoginManaging {
    var nextStatus: MoaLaunchAtLoginStatus = .disabled
    var shouldThrow = false
    var openedSettingsCount = 0

    func status() -> MoaLaunchAtLoginStatus { nextStatus }

    func setEnabled(_ enabled: Bool) throws {
        if shouldThrow {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        }
        nextStatus = enabled ? .enabled : .disabled
    }

    func openSystemSettings() {
        openedSettingsCount += 1
    }
}
#endif
