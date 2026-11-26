import Darwin
import Foundation
import MachO

/// Read-only / controlled CLI Companion built into the Moa binary.
/// Supports: `status`, `usage`, `accounts`, `health`, `backups`, `version`, `help`.
/// Strictly read-only: never prints raw API keys/tokens, never mutates client logins, never launches UI.
enum MoaCLICompanion {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static let supportedCommands: Set<String> = [
        "status", "usage", "accounts", "health", "backups", "version", "--version", "help", "--help", "-h"
    ]

    /// Resolves the enclosing `Moa.app` bundle even when invoked via a symlink (such as Homebrew Cask
    /// `/opt/homebrew/bin/moa` or `~/.local/bin/moa`), where `Bundle.main` otherwise points to the symlink directory.
    static func resolvedAppBundle(
        mainBundle: Bundle = .main,
        executablePathOverride: String? = nil
    ) -> Bundle {
        if isMoaAppBundle(mainBundle) {
            return mainBundle
        }
        if let rawExec = executablePathOverride ?? currentExecutablePath() {
            let resolvedURL = URL(fileURLWithPath: rawExec).resolvingSymlinksInPath().standardizedFileURL
            if let appURL = enclosingAppBundleURL(for: resolvedURL),
               let appBundle = Bundle(url: appURL) {
                return appBundle
            }
        }
        return mainBundle
    }

    static func resolvedVersionInfo(
        mainBundle: Bundle = .main,
        executablePathOverride: String? = nil
    ) -> (version: String, build: String) {
        let bundle = resolvedAppBundle(mainBundle: mainBundle, executablePathOverride: executablePathOverride)
        let version = (bundle.object(forInfoDictionaryKey: "MoaReleaseVersion") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "dev"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        return (version, build)
    }

    private static func isMoaAppBundle(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension == "app"
            && (bundle.object(forInfoDictionaryKey: "MoaReleaseVersion") != nil
                || bundle.bundleIdentifier?.lowercased().contains("moa") == true)
    }

    private static func currentExecutablePath() -> String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return CommandLine.arguments.first }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return CommandLine.arguments.first
        }
        return String(cString: buffer)
    }

    private static func enclosingAppBundleURL(for executableURL: URL) -> URL? {
        var cursor = executableURL.deletingLastPathComponent()
        for _ in 0..<6 {
            if cursor.pathExtension == "app" {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }

    static func runIfMatching(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Output? {
        guard arguments.count >= 2 else { return nil }
        let command = arguments[1]
        guard supportedCommands.contains(command) else { return nil }
        let rest = Array(arguments.dropFirst(2))
        return execute(command: command, args: rest, environment: environment)
    }

    static func execute(
        command: String,
        args: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()
    ) -> Output {
        let jsonMode = args.contains("--json")
        switch command {
        case "help", "--help", "-h":
            return Output(exitCode: 0, stdout: helpText, stderr: "")
        case "version", "--version":
            let info = resolvedVersionInfo()
            if jsonMode {
                return jsonOutput(["version": info.version, "build": info.build])
            }
            return Output(exitCode: 0, stdout: "Moa \(info.version) (\(info.build))\n", stderr: "")
        case "status":
            return runStatus(jsonMode: jsonMode, environment: environment, now: now)
        case "usage":
            return runUsage(args: args, jsonMode: jsonMode, environment: environment, now: now)
        case "accounts":
            return runAccounts(args: args, jsonMode: jsonMode, environment: environment, now: now)
        case "health":
            return runHealth(jsonMode: jsonMode, environment: environment, now: now)
        case "backups":
            return runBackups(jsonMode: jsonMode, environment: environment)
        default:
            return Output(exitCode: 2, stdout: "", stderr: "Unknown command: \(command)\n\(helpText)")
        }
    }

    static var installCommandHint: String {
        let bundle = resolvedAppBundle()
        let execPath = isMoaAppBundle(bundle)
            ? (bundle.executablePath ?? "/Applications/Moa.app/Contents/MacOS/Moa")
            : "/Applications/Moa.app/Contents/MacOS/Moa"
        return "mkdir -p ~/.local/bin && ln -sf \"\(execPath)\" ~/.local/bin/moa"
    }

    private static var helpText: String {
        """
        Moa CLI Companion (read-only)

        Usage:
          moa status [--json]
          moa usage [--today|--7d|--30d|--month] [--source <id>] [--by-model|--by-client] [--json]
          moa accounts [--client <id>] [--json]
          moa health [--json]
          moa backups [--json]
          moa version [--json]
          moa help

        """
    }

    // MARK: - Subcommands

    private static func runStatus(jsonMode: Bool, environment: [String: String], now: Date) -> Output {
        let dataRoot = MoaDataRoot.currentURL(environment: environment).path
        let iCloud = MoaDataRoot.isICloudStorageEnabled(environment: environment)
        let batch = loadAllUsage(environment: environment, now: now)
        let todayKey = MoaUsageReport.dayKey(from: now)
        let todayRows = (batch.report?.rows ?? []).filter { $0.dayKey == todayKey }
        let todayCost = todayRows.reduce(0) { $0 + $1.costUSD }
        let todayTokens = todayRows.reduce(0) { $0 + $1.totalTokens }
        let accounts = collectAccountSummaries(environment: environment, now: now)
        let attentionCount = accounts.filter { $0.healthSeverity == "warning" || $0.healthSeverity == "critical" }.count

        if jsonMode {
            struct Payload: Encodable {
                let dataRoot: String
                let iCloudEnabled: Bool
                let todayCostUSD: Double
                let todayTokens: Int
                let savedAccountCount: Int
                let healthAttentionCount: Int
                let activeByClient: [String: String]
            }
            var activeMap: [String: String] = [:]
            for item in accounts where item.active {
                activeMap[item.client] = item.name
            }
            return encodableJSONOutput(Payload(
                dataRoot: dataRoot,
                iCloudEnabled: iCloud,
                todayCostUSD: todayCost,
                todayTokens: todayTokens,
                savedAccountCount: accounts.count,
                healthAttentionCount: attentionCount,
                activeByClient: activeMap
            ))
        }

        var lines = [
            "Moa Status",
            "  Data Root: \(dataRoot) (\(iCloud ? "iCloud" : "Local"))",
            "  Today's Local Usage: \(MoaUsageReportExporter.currency(todayCost)) (\(todayTokens) tokens)",
            "  Saved Accounts/Providers: \(accounts.count)",
            "  Credential Health Attention: \(attentionCount)"
        ]
        for item in accounts where item.active {
            lines.append("  Active [\(item.client)]: \(item.name)")
        }
        return Output(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", stderr: "")
    }

    private static func runUsage(args: [String], jsonMode: Bool, environment: [String: String], now: Date) -> Output {
        let preset: MoaUsageDateRangePreset
        if args.contains("--today") { preset = .today }
        else if args.contains("--7d") { preset = .last7Days }
        else if args.contains("--month") { preset = .thisMonth }
        else { preset = .last30Days }

        var sourceFilter: MoaUsageSource?
        if let idx = args.firstIndex(of: "--source"), idx + 1 < args.count {
            guard let parsed = MoaUsageSource(rawValue: args[idx + 1]) else {
                return Output(exitCode: 2, stdout: "", stderr: "Unknown usage source: \(args[idx + 1])\n")
            }
            sourceFilter = parsed
        }

        let batch = loadAllUsage(environment: environment, now: now)
        let fullReport = batch.report ?? MoaUsageReport(rows: [], generatedAt: now)
        let bounds = preset.dayKeyBounds(customStart: now, customEnd: now, now: now)
        let filtered = fullReport.filtered(source: sourceFilter, startDayKey: bounds.start, endDayKey: bounds.end)
        let overrides = MoaUsagePricingOverrideController(environment: environment)
        let savings = MoaUsageAnalytics.cacheSavingsUSD(for: filtered, overrides: overrides)

        if jsonMode {
            return Output(
                exitCode: 0,
                stdout: MoaUsageReportExporter.json(report: filtered, cacheSavingsUSD: savings),
                stderr: batch.failures.isEmpty ? "" : batch.failures.joined(separator: "\n") + "\n"
            )
        }

        var lines = [
            "Moa Usage (\(bounds.start) .. \(bounds.end))",
            "  Estimated Cost: \(MoaUsageReportExporter.currency(filtered.totalCostUSD))",
            "  Total Tokens: \(filtered.totalTokens)",
            "  Cache Hit: \(String(format: "%.2f%%", filtered.cacheHitPercent)) (Est. Savings: \(MoaUsageReportExporter.currency(savings)))"
        ]
        if args.contains("--by-model") {
            lines.append("")
            for agg in MoaUsageAnalytics.aggregateByModel(from: filtered, overrides: overrides) {
                lines.append("  \(agg.model): \(MoaUsageReportExporter.currency(agg.costUSD)) · \(agg.totalTokens) tokens")
            }
        } else {
            lines.append("")
            for agg in MoaUsageAnalytics.aggregateByClient(from: filtered, overrides: overrides) {
                lines.append("  \(agg.source.rawValue): \(MoaUsageReportExporter.currency(agg.costUSD)) · \(agg.totalTokens) tokens (\(String(format: "%.1f%%", agg.costSharePercent)))")
            }
        }
        return Output(
            exitCode: 0,
            stdout: lines.joined(separator: "\n") + "\n",
            stderr: batch.failures.isEmpty ? "" : batch.failures.joined(separator: "\n") + "\n"
        )
    }

    private struct CLIAccountSummary: Encodable {
        let client: String
        let group: String
        let name: String
        let detail: String
        let active: Bool
        let healthSeverity: String
        let healthBadge: String
        let healthDetail: String
    }

    private static func runAccounts(args: [String], jsonMode: Bool, environment: [String: String], now: Date) -> Output {
        var clientFilter: String?
        if let idx = args.firstIndex(of: "--client"), idx + 1 < args.count {
            clientFilter = args[idx + 1].lowercased()
        }
        let all = collectAccountSummaries(environment: environment, now: now).filter { item in
            guard let clientFilter else { return true }
            return item.client.lowercased() == clientFilter || item.group.lowercased() == clientFilter
        }
        if jsonMode {
            return encodableJSONOutput(all)
        }
        if all.isEmpty {
            return Output(exitCode: 0, stdout: "No saved accounts or providers found.\n", stderr: "")
        }
        let lines = all.map { item in
            let activeTag = item.active ? " [ACTIVE]" : ""
            let healthTag = item.healthSeverity == "healthy" ? "" : " [\(item.healthBadge)]"
            return "[\(item.client)/\(item.group)] \(item.name)\(activeTag)\(healthTag)"
        }
        return Output(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", stderr: "")
    }

    private static func runHealth(jsonMode: Bool, environment: [String: String], now: Date) -> Output {
        let all = collectAccountSummaries(environment: environment, now: now)
        if jsonMode {
            return encodableJSONOutput(all)
        }
        let issues = all.filter { $0.healthSeverity == "warning" || $0.healthSeverity == "critical" }
        if issues.isEmpty {
            return Output(exitCode: 0, stdout: "All \(all.count) saved accounts/providers passed local read-only health checks.\n", stderr: "")
        }
        let lines = issues.map { "[\($0.healthSeverity.uppercased())] \($0.client) · \($0.name): \($0.healthBadge) — \($0.healthDetail)" }
        return Output(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", stderr: "")
    }

    private static func runBackups(jsonMode: Bool, environment: [String: String]) -> Output {
        let manager = MoaBackupManager(environment: environment)
        let inv = manager.loadInventory()
        if jsonMode {
            struct Payload: Encodable {
                let recoveryPackages: [MoaBackupEntry]
                let codexSnapshots: [MoaBackupEntry]
                let legacyDownloadsBackups: [MoaBackupEntry]
            }
            return encodableJSONOutput(Payload(
                recoveryPackages: inv.recoveryPackages,
                codexSnapshots: inv.codexSnapshots,
                legacyDownloadsBackups: inv.legacyDownloadsBackups
            ))
        }
        var lines = [
            "Recovery Packages: \(inv.recoveryPackages.count)",
            "Codex Snapshots: \(inv.codexSnapshots.count)",
            "Legacy Unencrypted Downloads Backups: \(inv.legacyDownloadsBackups.count)"
        ]
        for entry in inv.recoveryPackages {
            lines.append("  [Recovery] \(entry.name) (\(MoaBackupManager.formattedSize(entry.sizeBytes)))")
        }
        for entry in inv.legacyDownloadsBackups {
            lines.append("  [Legacy Downloads] \(entry.name) (\(MoaBackupManager.formattedSize(entry.sizeBytes)))")
        }
        return Output(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", stderr: "")
    }

    // MARK: - Helpers

    private static func loadAllUsage(environment: [String: String], now: Date) -> MoaUsageReportBatch {
        let codex = CodexUsageScanner(environment: environment)
        let claude = ClaudeUsageScanner(environment: environment)
        let zcode = ZCodeUsageScanner(environment: environment)
        let wb = WorkBuddyUsageScanner(environment: environment, edition: .international)
        let wbCN = WorkBuddyUsageScanner(environment: environment, edition: .china)
        let ag = AntigravityUsageScanner(environment: environment)
        let ds = DeepSeekUsageScanner(environment: environment)
        return MoaUsageReportBatch.load(now: now, sources: [
            (.codex, { try codex.loadReport(forceRefresh: false, now: now, persistCache: false) }),
            (.claude, { try claude.loadReport(forceRefresh: false, now: now, persistCache: false) }),
            (.zcode, { try zcode.loadReport(forceRefresh: false, now: now, persistCache: false) }),
            (.workbuddy, { try wb.loadReport(forceRefresh: false, now: now) }),
            (.workbuddyCN, { try wbCN.loadReport(forceRefresh: false, now: now) }),
            (.antigravity, { try ag.loadReport(forceRefresh: false, now: now) }),
            (.deepseek, { try ds.loadReport(forceRefresh: false, now: now) })
        ])
    }

    private static func collectAccountSummaries(environment: [String: String], now: Date) -> [CLIAccountSummary] {
        var results: [CLIAccountSummary] = []
        let fm = FileManager.default
        let moaHome = MoaDataRoot.currentURL(environment: environment)
        let home = MoaDataRoot.homeDirectory(environment: environment)
        let codexHome: URL = {
            if let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            }
            return home.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
        }()

        // Codex official & providers (strictly read-only; never constructs ConfigProfileController or creates files)
        let officialDBURL = moaHome.appendingPathComponent("codex_official_accounts.json")
        if fm.fileExists(atPath: officialDBURL.path),
           let data = try? Data(contentsOf: officialDBURL),
           let officialDB = try? JSONDecoder().decode(CodexOfficialAccountDatabase.self, from: data) {
            let liveAuth = readJSONObject(at: codexHome.appendingPathComponent("auth.json"))
            let liveRefresh = (liveAuth["tokens"] as? [String: Any])?["refresh_token"] as? String
            let codexAuthRoot = moaHome.appendingPathComponent("codex-auth", isDirectory: true).standardizedFileURL
            let accountsDir = codexAuthRoot.appendingPathComponent("accounts", isDirectory: true).standardizedFileURL
            let dirSafe = (try? codexAuthRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
                && (try? accountsDir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            let accountsPrefix = accountsDir.path.hasSuffix("/") ? accountsDir.path : accountsDir.path + "/"
            for acc in officialDB.accounts {
                let auth: [String: Any]
                if dirSafe,
                   let authURL = readOnlyOfficialAuthURL(
                       for: acc,
                       moaHome: moaHome,
                       accountsDir: accountsDir,
                       accountsPrefix: accountsPrefix
                   ) {
                    auth = readJSONObject(at: authURL)
                } else {
                    auth = [:]
                }
                let accRefresh = (auth["tokens"] as? [String: Any])?["refresh_token"] as? String
                let isActive: Bool
                if let liveRefresh, !liveRefresh.isEmpty, let accRefresh, !accRefresh.isEmpty {
                    isActive = liveRefresh == accRefresh
                } else {
                    isActive = acc.id == officialDB.selectedAccountID
                }
                let health = MoaCredentialHealthInspector.inspectCodexOfficial(auth: auth, now: now)
                results.append(CLIAccountSummary(
                    client: "codex", group: "codexOfficial", name: acc.name, detail: acc.email ?? "",
                    active: isActive, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }
        let codexProfilesURL = moaHome.appendingPathComponent("profiles.json")
        if fm.fileExists(atPath: codexProfilesURL.path),
           let data = try? Data(contentsOf: codexProfilesURL),
           let profileDB = try? JSONDecoder().decode(ProfileDatabase.self, from: data) {
            let selected = profileDB.selectedProfileID
            for p in profileDB.profiles {
                let health = MoaCredentialHealthInspector.inspectProvider(apiKey: p.apiKey, baseURL: p.baseURL, isActive: p.id == selected)
                results.append(CLIAccountSummary(
                    client: "codex", group: "codexConfig", name: p.name,
                    detail: MoaDataPackageCrypto.sanitizedURLString(p.baseURL),
                    active: p.id == selected, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        // Claude Desktop (strictly read-only; never constructs ClaudeDesktopProfileController or creates files)
        let claudeDesktopURL = moaHome.appendingPathComponent("claude_desktop_profiles.json")
        if fm.fileExists(atPath: claudeDesktopURL.path),
           let data = try? Data(contentsOf: claudeDesktopURL),
           let desktopDB = try? JSONDecoder().decode(ReadOnlyClaudeDesktopDB.self, from: data) {
            for p in desktopDB.profiles {
                let health = MoaCredentialHealthInspector.inspectProvider(apiKey: p.apiKey, baseURL: p.baseURL, isActive: p.id == desktopDB.selectedProfileID)
                results.append(CLIAccountSummary(
                    client: "claude", group: "claude", name: p.name,
                    detail: MoaDataPackageCrypto.sanitizedURLString(p.baseURL),
                    active: p.id == desktopDB.selectedProfileID, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        // Claude Code
        let claudeCodeCtrl = ClaudeCodeSettingsController(environment: environment)
        if let profiles = try? claudeCodeCtrl.profiles() {
            let selected = try? claudeCodeCtrl.selectedProfileID()
            let liveBaseURL = claudeCodeCtrl.liveManagedEnv()?["ANTHROPIC_BASE_URL"]
            for p in profiles {
                let health = MoaCredentialHealthInspector.inspectProvider(
                    apiKey: p.apiKey, baseURL: p.baseURL, isActive: p.id == selected, liveBaseURL: liveBaseURL
                )
                results.append(CLIAccountSummary(
                    client: "claude", group: "claudeCode", name: p.name,
                    detail: MoaDataPackageCrypto.sanitizedURLString(p.baseURL),
                    active: p.id == selected, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        // WorkBuddy editions
        for (edition, clientKey, groupKey) in [
            (WorkBuddyEdition.china, "workbuddyCN", "workbuddyCN"),
            (WorkBuddyEdition.international, "workbuddy", "workbuddy")
        ] {
            let ctrl = WorkBuddyController(environment: environment, edition: edition)
            let fp = MoaCredentialHealthInspector.keyblobFingerprint(at: ctrl.keyURL)
            if let accs = try? ctrl.accounts() {
                let current = try? ctrl.currentUID()
                for acc in accs {
                    let health = MoaCredentialHealthInspector.inspectWorkBuddy(account: acc, currentKeyFingerprint: fp)
                    results.append(CLIAccountSummary(
                        client: clientKey, group: groupKey, name: acc.name, detail: acc.uid,
                        active: acc.uid == current, healthSeverity: health.severity.rawValue,
                        healthBadge: health.badge, healthDetail: health.detail
                    ))
                }
            }
        }

        // DeepSeek
        let dsCtrl = DeepSeekController(environment: environment)
        if let accs = try? dsCtrl.accounts() {
            let current = try? dsCtrl.currentFingerprint()
            for acc in accs {
                let health = MoaCredentialHealthInspector.inspectDeepSeek(account: acc, now: now)
                results.append(CLIAccountSummary(
                    client: "deepseek", group: "deepseek", name: acc.name, detail: "",
                    active: acc.fingerprint == current, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        // Antigravity (metadata-only; never prompts Keychain)
        let agCtrl = AntigravityController(environment: environment)
        let agFallbackHealth = MoaCredentialHealthInspector.inspectAntigravityFallback(fallbackURL: agCtrl.fallbackURL, now: now)
        if let accs = try? agCtrl.accounts() {
            for acc in accs {
                let health = agFallbackHealth ?? .healthy()
                results.append(CLIAccountSummary(
                    client: "antigravity", group: "antigravity", name: acc.name, detail: acc.email,
                    active: false, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        // Gemini CLI
        let geminiCtrl = GeminiCLIController(environment: environment)
        if let accs = try? geminiCtrl.accounts() {
            let current = try? geminiCtrl.currentIdentity()
            for acc in accs {
                let health = MoaCredentialHealthInspector.inspectGeminiCLI(account: acc, now: now)
                results.append(CLIAccountSummary(
                    client: "geminiCLI", group: "geminiCLI", name: acc.name, detail: acc.email,
                    active: acc.identity == current, healthSeverity: health.severity.rawValue,
                    healthBadge: health.badge, healthDetail: health.detail
                ))
            }
        }

        return results
    }

    private struct ReadOnlyClaudeDesktopDB: Decodable {
        var selectedProfileID: String?
        var profiles: [ClaudeDesktopProviderProfile]
    }

    private static func readOnlyOfficialAuthURL(
        for account: CodexOfficialAccount,
        moaHome: URL,
        accountsDir: URL,
        accountsPrefix: String
    ) -> URL? {
        let expectedPath = "\(ConfigProfileController.officialAuthAccountsRelativePath)/\(account.id).json"
        guard account.authPath == expectedPath,
              UUID(uuidString: account.id) != nil else {
            return nil
        }
        let candidate = moaHome.appendingPathComponent(account.authPath).standardizedFileURL
        guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              candidate.deletingLastPathComponent() == accountsDir,
              candidate.path.hasPrefix(accountsPrefix) else {
            return nil
        }
        return candidate
    }

    private static func readJSONObject(at url: URL) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func jsonOutput(_ dict: [String: Any]) -> Output {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return Output(exitCode: 1, stdout: "", stderr: "Failed to encode JSON\n")
        }
        return Output(exitCode: 0, stdout: text + "\n", stderr: "")
    }

    private static func encodableJSONOutput<T: Encodable>(_ value: T) -> Output {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return Output(exitCode: 1, stdout: "", stderr: "Failed to encode JSON\n")
        }
        return Output(exitCode: 0, stdout: text + "\n", stderr: "")
    }
}
