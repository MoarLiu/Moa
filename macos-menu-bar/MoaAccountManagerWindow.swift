import AppKit
import Combine
import SwiftUI

/// Which group the account window opens scrolled to. The window itself is one
/// list grouped by client, never one tab per client.
enum MoaAccountGroup: String, CaseIterable, Identifiable {
    case codexOfficial
    case codexConfig
    case claude
    case claudeCode
    case workbuddy
    case workbuddyCN
    case deepseek
    case antigravity
    case geminiCLI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexOfficial: return MoaL10n.text("Codex Official")
        case .codexConfig: return MoaL10n.text("Codex Configs")
        case .claude: return "Claude Desktop"
        case .claudeCode: return "Claude Code"
        case .workbuddy: return "WorkBuddy AI"
        case .workbuddyCN: return MoaL10n.text("WorkBuddy")
        case .deepseek: return "DeepSeek"
        case .antigravity: return "Antigravity"
        case .geminiCLI: return "Gemini CLI"
        }
    }

    var symbol: String {
        switch self {
        case .codexOfficial: return "person.crop.circle"
        case .codexConfig: return "gearshape"
        case .claude: return "sparkles"
        case .claudeCode: return "terminal"
        case .workbuddy, .workbuddyCN: return "briefcase"
        case .deepseek: return "bolt"
        case .antigravity: return "arrow.up.circle"
        case .geminiCLI: return "terminal.fill"
        }
    }

    var client: MoaAccountClient {
        switch self {
        case .codexOfficial, .codexConfig: return .codex
        case .claude, .claudeCode: return .claude
        case .workbuddy: return .workbuddy
        case .workbuddyCN: return .workbuddyCN
        case .deepseek: return .deepseek
        case .antigravity: return .antigravity
        case .geminiCLI: return .geminiCLI
        }
    }

    /// Login snapshots can only be renamed; API configs also have credentials to edit.
    var supportsEditing: Bool {
        switch self {
        case .codexConfig, .claude, .claudeCode: return true
        case .codexOfficial, .workbuddy, .workbuddyCN, .deepseek, .antigravity, .geminiCLI: return false
        }
    }
}

struct MoaAccountRow: Identifiable, Equatable {
    let group: MoaAccountGroup
    let id: String
    var name: String
    var detail: String
    var active: Bool
    var health: MoaCredentialHealthReport? = nil
}

struct MoaAccountSection: Identifiable, Equatable {
    let group: MoaAccountGroup
    var rows: [MoaAccountRow]
    var canAddCurrentLogin: Bool
    var currentLoginMessage: String? = nil
    var hasUnsavedLiveLogin: Bool = false

    var id: String { group.id }
}

/// Reads every client's saved accounts into one grouped snapshot. A client
/// whose store cannot be read contributes its error instead of failing the rest.
enum MoaAccountCatalog {
    static func load(app: AppDelegate) -> (sections: [MoaAccountSection], failures: [String]) {
        var sections: [MoaAccountSection] = []
        var failures: [String] = []

        func take(_ group: MoaAccountGroup, _ body: () throws -> MoaAccountSection) {
            do {
                sections.append(try body())
            } catch {
                failures.append("\(group.title): \(error.localizedDescription)")
            }
        }

        take(.codexOfficial) {
            let accounts = try app.profileController.officialAccounts()
            let selected = try app.profileController.currentLiveOfficialAccountID()
            let status = try app.profileController.currentOfficialLoginSaveStatus()
            return MoaAccountSection(
                group: .codexOfficial,
                rows: accounts.map { account in
                    let auth = (try? app.profileController.officialAuthURL(for: account))
                        .map { app.profileController.readAuthJSON(from: $0) } ?? [:]
                    let health = MoaCredentialHealthInspector.inspectCodexOfficial(auth: auth)
                    return MoaAccountRow(
                        group: .codexOfficial,
                        id: account.id,
                        name: account.name,
                        detail: account.email ?? "",
                        active: account.id == selected,
                        health: health
                    )
                },
                canAddCurrentLogin: status.hasLogin && status.savedAccountName == nil,
                currentLoginMessage: status.savedAccountName.map { MoaL10n.format("Current Login Saved as %@", $0) }
                    ?? (status.hasLogin ? MoaL10n.text("Unsaved live login detected. Click Save Current Login to preserve it.") : MoaL10n.text("Sign in to Codex, then save the current login here.")),
                hasUnsavedLiveLogin: status.hasLogin && status.savedAccountName == nil
            )
        }

        take(.codexConfig) {
            let profiles = try app.profileController.profiles()
            let selected = try app.profileController.selectedProfileID()
            return MoaAccountSection(
                group: .codexConfig,
                rows: profiles.map {
                    let health = MoaCredentialHealthInspector.inspectProvider(
                        apiKey: $0.apiKey, baseURL: $0.baseURL, isActive: $0.id == selected
                    )
                    return MoaAccountRow(group: .codexConfig, id: $0.id, name: $0.name, detail: $0.baseURL, active: $0.id == selected, health: health)
                },
                canAddCurrentLogin: false
            )
        }

        take(.claude) {
            let profiles = try app.claudeDesktopProfileController.profiles()
            let selected = try app.claudeDesktopProfileController.selectedProfileID()
            return MoaAccountSection(
                group: .claude,
                rows: profiles.map {
                    let health = MoaCredentialHealthInspector.inspectProvider(
                        apiKey: $0.apiKey, baseURL: $0.baseURL, isActive: $0.id == selected
                    )
                    return MoaAccountRow(group: .claude, id: $0.id, name: $0.name, detail: $0.baseURL, active: $0.id == selected, health: health)
                },
                canAddCurrentLogin: false
            )
        }

        take(.claudeCode) {
            let profiles = try app.claudeCodeSettingsController.profiles()
            let selected = try app.claudeCodeSettingsController.selectedProfileID()
            let liveEnv = app.claudeCodeSettingsController.liveManagedEnv()
            let liveBaseURL = liveEnv?["ANTHROPIC_BASE_URL"]
            return MoaAccountSection(
                group: .claudeCode,
                rows: profiles.map {
                    let health = MoaCredentialHealthInspector.inspectProvider(
                        apiKey: $0.apiKey, baseURL: $0.baseURL, isActive: $0.id == selected, liveBaseURL: liveBaseURL
                    )
                    return MoaAccountRow(
                        group: .claudeCode,
                        id: $0.id,
                        name: $0.name,
                        detail: "\($0.baseURL) · \($0.model)",
                        active: $0.id == selected,
                        health: health
                    )
                },
                canAddCurrentLogin: false,
                currentLoginMessage: selected == nil && liveBaseURL != nil
                    ? MoaL10n.format("Custom ANTHROPIC_BASE_URL detected in ~/.claude/settings.json (%@).", MoaDataPackageCrypto.sanitizedURLString(liveBaseURL!))
                    : nil
            )
        }

        func workbuddy(_ edition: WorkBuddyEdition, _ group: MoaAccountGroup, _ coordinator: MoaWorkBuddyCoordinator) throws -> MoaAccountSection {
            let accounts = try coordinator.controller.accounts()
            let current = try coordinator.controller.currentUID()
            let keyFP = MoaCredentialHealthInspector.keyblobFingerprint(at: coordinator.controller.keyURL)
            let unsaved = current != nil && !accounts.contains(where: { $0.uid == current })
            return MoaAccountSection(
                group: group,
                rows: accounts.map {
                    let health = MoaCredentialHealthInspector.inspectWorkBuddy(account: $0, currentKeyFingerprint: keyFP)
                    return MoaAccountRow(group: group, id: $0.id.uuidString, name: $0.name, detail: $0.uid, active: $0.uid == current, health: health)
                },
                canAddCurrentLogin: unsaved,
                currentLoginMessage: unsaved ? MoaL10n.text("Unsaved live login detected. Click Save Current Login to preserve it.") : nil,
                hasUnsavedLiveLogin: unsaved
            )
        }
        take(.workbuddy) { try workbuddy(.international, .workbuddy, app.workbuddyCoordinator) }
        take(.workbuddyCN) { try workbuddy(.china, .workbuddyCN, app.workbuddyCNCoordinator) }

        take(.deepseek) {
            let accounts = try app.deepseekCoordinator.controller.accounts()
            let current = try app.deepseekCoordinator.controller.currentFingerprint()
            let unsaved = current != nil && !accounts.contains(where: { $0.fingerprint == current })
            return MoaAccountSection(
                group: .deepseek,
                rows: accounts.map {
                    let health = MoaCredentialHealthInspector.inspectDeepSeek(account: $0)
                    return MoaAccountRow(group: .deepseek, id: $0.id.uuidString, name: $0.name, detail: "", active: $0.fingerprint == current, health: health)
                },
                canAddCurrentLogin: unsaved,
                currentLoginMessage: unsaved ? MoaL10n.text("Unsaved live login detected. Click Save Current Login to preserve it.") : nil,
                hasUnsavedLiveLogin: unsaved
            )
        }

        let antigravity = app.antigravityCoordinator.overview
        let agFallbackHealth = MoaCredentialHealthInspector.inspectAntigravityFallback(
            fallbackURL: app.antigravityCoordinator.controller.fallbackURL
        )
        sections.append(MoaAccountSection(
            group: .antigravity,
            rows: antigravity.accounts.map {
                let isActive = $0.id == antigravity.currentID
                return MoaAccountRow(
                    group: .antigravity,
                    id: $0.id.uuidString,
                    name: $0.name,
                    detail: $0.email,
                    active: isActive,
                    health: isActive ? agFallbackHealth : nil
                )
            },
            canAddCurrentLogin: false,
            currentLoginMessage: app.antigravityCoordinator.failure ?? antigravity.message
        ))

        take(.geminiCLI) {
            let accounts = try app.geminiCLICoordinator.controller.accounts()
            let live = try app.geminiCLICoordinator.controller.currentLogin()
            let current = live?.identity
            let unsaved = current != nil && !accounts.contains(where: { $0.identity == current })
            return MoaAccountSection(
                group: .geminiCLI,
                rows: accounts.map {
                    let health = MoaCredentialHealthInspector.inspectGeminiCLI(account: $0)
                    return MoaAccountRow(group: .geminiCLI, id: $0.id.uuidString, name: $0.name, detail: $0.email, active: $0.identity == current, health: health)
                },
                canAddCurrentLogin: unsaved,
                currentLoginMessage: unsaved
                    ? MoaL10n.text("Unsaved live login detected. Click Save Current Login to preserve it.")
                    : (live == nil ? MoaL10n.text("Run `gemini` in Terminal to sign in, then save the login here.") : nil),
                hasUnsavedLiveLogin: unsaved
            )
        }
        return (sections, failures)
    }
}

/// One window for every saved account. Switching stays one click in the menu;
/// this window is where renaming, editing and deleting happen without first
/// making an account active.
final class MoaAccountManagerWindowController {
    unowned let app: AppDelegate

    init(app: AppDelegate) { self.app = app }

    func refreshIfVisible() {
        if app.workspaceWindow.isVisible { app.workspaceWindow.reloadAccounts() }
    }

    func show(group: MoaAccountGroup? = nil) {
        app.workspaceWindow.show(group: group ?? .codexOfficial)
    }
}

final class MoaAccountManagerModel: ObservableObject {
    @Published var sections: [MoaAccountSection] = []
    @Published var failures: [String] = []
    @Published var focus: MoaAccountGroup?
    @Published var focusRequest = UUID()
    let operations: MoaAccountOperationState
    private var operationObserver: AnyCancellable?
    private unowned let app: AppDelegate

    var busy: Bool { !operations.active.isEmpty }
    func isBusy(_ group: MoaAccountGroup) -> Bool { operations.active[group.client] != nil }
    func progress(_ group: MoaAccountGroup) -> String? { operations.active[group.client]?.message }

    init(app: AppDelegate) {
        self.app = app
        operations = app.accountOperations
        operationObserver = operations.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func reload() {
        // Client account controllers hold their lock while graceful quit/launch
        // hands work to the main thread. Never synchronously wait on that lock
        // from the UI while a coordinator is switching an account.
        guard !busy, !app.workbuddyCoordinator.isUpdatingAccounts,
              !app.workbuddyCNCoordinator.isUpdatingAccounts,
              !app.deepseekCoordinator.isUpdatingAccounts,
              !app.antigravityCoordinator.isUpdatingAccounts,
              !app.geminiCLICoordinator.isUpdatingAccounts else { return }
        let loaded = MoaAccountCatalog.load(app: app)
        sections = loaded.sections
        failures = loaded.failures
        app.rebuildCodexProviderMenus()
        app.rebuildClaudeProviderMenus()
        app.rebuildWorkBuddyMenus()
        app.deepseekCoordinator.rebuildMenu()
        app.antigravityCoordinator.rebuildMenu()
        app.geminiCLICoordinator.rebuildMenu()
    }

    var healthAttentionSummaries: [MoaClientHealthSummary] {
        var summaries: [MoaClientHealthSummary] = []
        for section in sections {
            let client = MoaWorkspaceClient.client(for: section.group)
            for row in section.rows {
                if let health = row.health, health.needsAttention {
                    summaries.append(MoaClientHealthSummary(
                        client: client,
                        group: section.group,
                        accountName: row.name.isEmpty ? row.detail : row.name,
                        report: health
                    ))
                }
            }
            if section.hasUnsavedLiveLogin {
                summaries.append(MoaClientHealthSummary(
                    client: client,
                    group: section.group,
                    accountName: section.group.title,
                    report: MoaCredentialHealthReport(
                        severity: .warning,
                        badge: MoaL10n.text("Unsaved Login"),
                        detail: MoaL10n.text("Current live login has not been saved in Moa yet."),
                        expiresAt: nil
                    )
                ))
            }
        }
        return summaries
    }

    func add(_ group: MoaAccountGroup) {
        guard !isBusy(group) else { return }
        let refresh: () -> Void = { [weak self] in self?.reload() }
        switch group {
        case .codexOfficial:
            app.profileActionCoordinator.addCodexOfficialAccountAction()
            refresh()
        case .codexConfig:
            app.providerActionCoordinator.addProfileAction()
            refresh()
        case .claude:
            app.profileActionCoordinator.addClaudeDesktopProviderAction()
            refresh()
        case .claudeCode:
            guard let input = MoaRelease1100Panels.showClaudeCodeProvider() else { return }
            run(.claudeCode, MoaL10n.text("Saving…")) {
                _ = try self.app.claudeCodeSettingsController.addProfile(
                    name: input.name, baseURL: input.baseURL, apiKey: input.apiKey,
                    model: input.model, smallFastModel: input.smallFastModel
                )
            }
        case .workbuddy:
            app.workbuddyCoordinator.saveCurrentAccount(onComplete: refresh)
        case .workbuddyCN:
            app.workbuddyCNCoordinator.saveCurrentAccount(onComplete: refresh)
        case .deepseek:
            app.deepseekCoordinator.saveCurrentAccount(onComplete: refresh)
        case .antigravity:
            app.antigravityCoordinator.saveCurrentAccount(onComplete: refresh)
        case .geminiCLI:
            app.geminiCLICoordinator.saveCurrentAccount(onComplete: refresh)
        }
    }

    func addAnotherLogin(_ group: MoaAccountGroup) {
        guard !isBusy(group) else { return }
        let refresh: () -> Void = { [weak self] in self?.reload() }
        switch group {
        case .codexOfficial:
            app.profileActionCoordinator.addAnotherCodexOfficialAccountAction(onComplete: refresh)
        case .workbuddy:
            app.workbuddyCoordinator.addAnotherAccount(onComplete: refresh)
        case .workbuddyCN:
            app.workbuddyCNCoordinator.addAnotherAccount(onComplete: refresh)
        case .deepseek:
            app.deepseekCoordinator.addAnotherAccount(onComplete: refresh)
        case .antigravity:
            app.antigravityCoordinator.addAnotherAccount(onComplete: refresh)
        case .geminiCLI:
            app.geminiCLICoordinator.addAnotherAccount(onComplete: refresh)
        case .codexConfig, .claude, .claudeCode:
            break
        }
    }

    func copyClaudeCodeEnv(_ row: MoaAccountRow) {
        if row.group == .claude,
           let profile = try? app.claudeDesktopProfileController.profiles().first(where: { $0.id == row.id }) {
            app.profileActionCoordinator.copyClaudeCodeConfig(for: profile)
        } else if row.group == .claudeCode,
                  let profile = try? app.claudeCodeSettingsController.profiles().first(where: { $0.id == row.id }) {
            app.copyToPasteboard(ClaudeCodeSettingsController.environmentSnippet(for: profile))
            MoaNonBlockingAlert.present(
                messageText: MoaL10n.text("Claude Code config copied"),
                informativeText: MoaL10n.format("Copied Claude Code environment variables for \"%@\".", profile.name),
                tone: .success
            )
        }
    }

    func restoreClaudeCodeOfficialMode() {
        guard !isBusy(.claudeCode) else { return }
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Restore Claude Code Official Mode?"),
            informativeText: MoaL10n.text("Removes Moa-managed ANTHROPIC_* environment keys from ~/.claude/settings.json while preserving all other settings."),
            primaryButtonTitle: MoaL10n.text("Restore"),
            tone: .warning
        ) else { return }
        run(.claudeCode, MoaL10n.text("Saving…")) {
            try self.app.claudeCodeSettingsController.restoreOfficialMode()
        }
    }

    func restoreOfficialMode(for client: MoaWorkspaceClient) {
        switch client {
        case .codex:
            guard !isBusy(.codexConfig) else { return }
            guard MoaNonBlockingAlert.confirm(
                messageText: MoaL10n.text("Switch to Codex Official Mode?"),
                informativeText: MoaL10n.text("Codex quits and reopens using official endpoints while keeping your saved providers. Finish active tasks first."),
                primaryButtonTitle: MoaL10n.text("Switch"),
                tone: .warning
            ) else { return }
            app.restoreCodexOfficialAction()
        case .claude:
            guard !isBusy(.claude) else { return }
            guard MoaNonBlockingAlert.confirm(
                messageText: MoaL10n.text("Switch to Claude Desktop Official?"),
                informativeText: MoaL10n.text("Claude Desktop quits and reopens without the 3P provider override. Finish active tasks first."),
                primaryButtonTitle: MoaL10n.text("Switch"),
                tone: .warning
            ) else { return }
            app.restoreClaudeDesktopOfficialAction()
        default:
            break
        }
    }

    func applyCodexNoAccountMode() {
        guard !isBusy(.codexOfficial) else { return }
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Use Codex Without an Official Account?"),
            informativeText: MoaL10n.text("Moa saves the current login (if any), switches auth to API key mode, and reopens Codex. Finish active tasks first."),
            primaryButtonTitle: MoaL10n.text("Continue"),
            tone: .warning
        ) else { return }
        app.applyCodexOfficialNoAccountAction()
    }

    func rename(_ row: MoaAccountRow) {
        guard !isBusy(row.group) else { return }
        guard let name = app.showOfficialAccountNamePanel(
            title: MoaL10n.text("Rename"),
            message: MoaL10n.format("Update the display name for \"%@\". This does not switch accounts or reopen anything.", row.name),
            buttonTitle: MoaL10n.text("Save"),
            initialName: row.name
        ) else { return }
        if row.group == .antigravity, let id = UUID(uuidString: row.id) {
            app.antigravityCoordinator.renameSavedAccount(id: id, name: name) { [weak self] in self?.reload() }
            return
        }
        run(row.group, MoaL10n.text("Saving…")) {
            switch row.group {
            case .codexOfficial:
                _ = try self.app.profileController.renameOfficialAccount(id: row.id, name: name)
            case .codexConfig:
                guard let profile = try self.app.profileController.profiles().first(where: { $0.id == row.id }) else { return }
                _ = try self.app.profileController.updateProfile(id: row.id, name: name, baseURL: profile.baseURL, apiKey: profile.apiKey)
            case .claude:
                guard let profile = try self.app.claudeDesktopProfileController.profiles().first(where: { $0.id == row.id }) else { return }
                _ = try self.app.claudeDesktopProfileController.updateProfile(
                    id: row.id, name: name, baseURL: profile.baseURL, apiKey: profile.apiKey,
                    models: profile.models, oneMModels: profile.enabledOneMModels
                )
            case .claudeCode:
                _ = try self.app.claudeCodeSettingsController.renameProfile(id: row.id, name: name)
            case .workbuddy:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCoordinator.controller.rename(id: id, name: name)
            case .workbuddyCN:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCNCoordinator.controller.rename(id: id, name: name)
            case .deepseek:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.deepseekCoordinator.controller.rename(id: id, name: name)
            case .antigravity:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.antigravityCoordinator.controller.rename(id: id, name: name)
            case .geminiCLI:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.geminiCLICoordinator.controller.rename(id: id, name: name)
            }
        }
    }

    func edit(_ row: MoaAccountRow) {
        guard !isBusy(row.group) else { return }
        switch row.group {
        case .codexConfig:
            guard let profile = try? app.profileController.profiles().first(where: { $0.id == row.id }),
                  let input = app.showEditProfilePanel(for: profile) else { return }
            let id = row.id
            let applyToCurrent = (try? app.profileController.selectedProfileID()) == id
            guard !applyToCurrent || confirmLiveEdit(row, MoaL10n.text("Codex quits and reopens, so finish active tasks first.")) else { return }
            run(row.group, MoaL10n.text("Saving…")) {
                try self.app.controller.changeConfiguration(if: applyToCurrent) {
                    _ = try self.app.profileController.updateProfileApplyingIfSelected(
                        id: id, name: input.name, baseURL: input.baseURL, apiKey: input.apiKey, applyToCurrent: applyToCurrent)
                }
            }
        case .claude:
            guard let profile = try? app.claudeDesktopProfileController.profiles().first(where: { $0.id == row.id }),
                  let input = app.showEditClaudeDesktopProviderPanel(for: profile) else { return }
            let id = row.id
            let applyToCurrent = (try? app.claudeDesktopProfileController.selectedProfileID()) == id
            guard !applyToCurrent || confirmLiveEdit(row, MoaL10n.text("Claude Desktop quits and reopens, so finish active tasks first.")) else { return }
            run(row.group, MoaL10n.text("Saving…")) {
                let applied = try self.app.claudeDesktopProfileController.updateProfileApplyingIfSelected(
                    id: id, name: input.name, baseURL: input.baseURL, apiKey: input.apiKey,
                    models: input.models, oneMModels: input.oneMModels, applyToCurrent: applyToCurrent
                )
                if applied { self.app.claudeDesktopProfileController.reopenClaudeDesktop() }
            }
        case .claudeCode:
            guard let profile = try? app.claudeCodeSettingsController.profiles().first(where: { $0.id == row.id }),
                  let input = MoaRelease1100Panels.showClaudeCodeProvider(editing: profile) else { return }
            let id = row.id
            let applyToCurrent = (try? app.claudeCodeSettingsController.selectedProfileID()) == id
            run(row.group, MoaL10n.text("Saving…")) {
                _ = try self.app.claudeCodeSettingsController.updateProfile(
                    id: id, name: input.name, baseURL: input.baseURL, apiKey: input.apiKey,
                    model: input.model, smallFastModel: input.smallFastModel, applyToCurrent: applyToCurrent
                )
            }
        case .codexOfficial, .workbuddy, .workbuddyCN, .deepseek, .antigravity, .geminiCLI:
            break
        }
    }

    func delete(_ row: MoaAccountRow) {
        guard !isBusy(row.group) else { return }
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.format("Delete \"%@\"?", row.name),
            informativeText: deleteExplanation(row),
            primaryButtonTitle: MoaL10n.text("Delete"),
            tone: .danger
        ) else { return }
        if row.group == .antigravity, let id = UUID(uuidString: row.id) {
            app.antigravityCoordinator.forgetSavedAccount(id: id) { [weak self] in self?.reload() }
            return
        }
        run(row.group, MoaL10n.text("Deleting…")) {
            switch row.group {
            case .codexOfficial:
                let switchesLogin = try self.app.profileController.loadOfficialAccountDatabase().accounts.count > 1
                    && self.app.profileController.currentLiveOfficialAccountID() == row.id
                try self.app.controller.changeConfiguration(if: switchesLogin) {
                    _ = try self.app.profileController.deleteOfficialAccount(id: row.id)
                }
            case .codexConfig:
                _ = try self.app.profileController.deleteProfile(id: row.id)
            case .claude:
                _ = try self.app.claudeDesktopProfileController.deleteProfile(id: row.id)
            case .claudeCode:
                _ = try self.app.claudeCodeSettingsController.deleteProfile(id: row.id)
            case .workbuddy:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCoordinator.controller.delete(id: id)
            case .workbuddyCN:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCNCoordinator.controller.delete(id: id)
            case .deepseek:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.deepseekCoordinator.controller.delete(id: id)
            case .antigravity:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.antigravityCoordinator.controller.delete(id: id)
            case .geminiCLI:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.geminiCLICoordinator.controller.delete(id: id)
            }
        }
    }

    func activate(_ row: MoaAccountRow) {
        guard !isBusy(row.group), !row.active else { return }
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.format("Switch to \"%@\"?", row.name),
            informativeText: switchExplanation(row.group),
            primaryButtonTitle: MoaL10n.text("Switch"),
            tone: .warning
        ) else { return }
        let refresh: () -> Void = { [weak self] in self?.reload() }
        switch row.group {
        case .workbuddy:
            guard let id = UUID(uuidString: row.id) else { return }
            app.workbuddyCoordinator.applySavedAccount(id: id, onComplete: refresh)
            return
        case .workbuddyCN:
            guard let id = UUID(uuidString: row.id) else { return }
            app.workbuddyCNCoordinator.applySavedAccount(id: id, onComplete: refresh)
            return
        case .deepseek:
            guard let id = UUID(uuidString: row.id) else { return }
            app.deepseekCoordinator.applySavedAccount(id: id, onComplete: refresh)
            return
        case .antigravity:
            guard let id = UUID(uuidString: row.id) else { return }
            app.antigravityCoordinator.applySavedAccount(id: id, onComplete: refresh)
            return
        case .geminiCLI:
            guard let id = UUID(uuidString: row.id) else { return }
            app.geminiCLICoordinator.applySavedAccount(id: id, onComplete: refresh)
            return
        case .codexOfficial, .codexConfig, .claude, .claudeCode:
            break
        }
        run(row.group, MoaL10n.text("Switching…")) {
            switch row.group {
            case .codexOfficial:
                try self.app.controller.changeConfiguration {
                    _ = try self.app.profileController.applyOfficialAccount(id: row.id)
                }
            case .codexConfig:
                try self.app.controller.changeConfiguration {
                    _ = try self.app.profileController.applyProfile(id: row.id)
                }
            case .claude:
                _ = try self.app.claudeDesktopProfileController.applyProfile(id: row.id)
                self.app.claudeDesktopProfileController.reopenClaudeDesktop()
            case .claudeCode:
                _ = try self.app.claudeCodeSettingsController.applyProfile(id: row.id)
            case .workbuddy, .workbuddyCN, .deepseek, .antigravity, .geminiCLI:
                break
            }
        }
    }

    private func confirmLiveEdit(_ row: MoaAccountRow, _ consequence: String) -> Bool {
        MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.format("\"%@\" is in use", row.name),
            informativeText: MoaL10n.format("Saving applies the change immediately. %@", consequence),
            primaryButtonTitle: MoaL10n.text("Edit"),
            tone: .warning
        )
    }

    private func deleteExplanation(_ row: MoaAccountRow) -> String {
        switch row.group {
        case .codexOfficial where row.active:
            return MoaL10n.text("This is the login Codex is using. Moa removes the saved copy and switches Codex to the next saved account, which quits and reopens Codex. Finish active tasks first.")
        case .codexOfficial:
            return MoaL10n.text("Only Moa's saved copy of this login is deleted. Codex stays signed in as it is.")
        case .codexConfig:
            return MoaL10n.text("Removes this config from Moa. Codex keeps running with whatever it uses now.")
        case .claude where row.active:
            return MoaL10n.text("This provider is active, so Claude Desktop returns to official mode.")
        case .claude:
            return MoaL10n.text("Removes this provider from Moa. Claude Desktop keeps using its current provider.")
        case .claudeCode where row.active:
            return MoaL10n.text("This preset is active, so Moa removes the managed ANTHROPIC_* env keys from ~/.claude/settings.json.")
        case .claudeCode:
            return MoaL10n.text("Removes this preset from Moa. ~/.claude/settings.json is not modified.")
        case .workbuddy, .workbuddyCN, .deepseek, .antigravity, .geminiCLI:
            return MoaL10n.text("Only Moa's saved copy is deleted. The app stays signed in and its local sessions are kept.")
        }
    }

    private func switchExplanation(_ group: MoaAccountGroup) -> String {
        switch group {
        case .codexOfficial, .codexConfig:
            return MoaL10n.text("Codex quits and reopens, so finish active tasks first.")
        case .claude:
            return MoaL10n.text("Claude Desktop quits and reopens, so finish active tasks first.")
        case .claudeCode:
            return MoaL10n.text("Updates only ANTHROPIC_* env fields in ~/.claude/settings.json. New Claude Code sessions will use this provider.")
        case .workbuddy:
            return MoaL10n.text("WorkBuddy AI quits and reopens, so finish active tasks first. Do not use Log Out.")
        case .workbuddyCN:
            return MoaL10n.text("WorkBuddy quits and reopens, so finish active tasks first. Do not use Log Out.")
        case .deepseek:
            return MoaL10n.text("DeepSeek Harness quits and reopens, so finish active tasks and close other DSH instances first. Do not use Log Out.")
        case .antigravity:
            return MoaL10n.text("Antigravity quits and reopens. Finish active tasks and close agy and Antigravity IDE extensions first; they share the active login.")
        case .geminiCLI:
            return MoaL10n.text("Replaces ~/.gemini/oauth_creds.json and google_accounts.json. Finish active Gemini CLI tasks first; Antigravity credentials stay untouched.")
        }
    }

    private func run(_ group: MoaAccountGroup, _ status: String, _ operation: @escaping () throws -> Void) {
        guard let token = operations.begin(group.client, message: status) else { return }
        app.statusItemText.title = AppDelegate.statusTitle(status)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.operations.finish(group.client, id: token)
                self.reload()
                switch result {
                case .success:
                    self.app.statusItemText.title = AppDelegate.statusTitle("Done")
                case .failure(let error):
                    NSSound.beep()
                    self.app.statusItemText.title = AppDelegate.statusTitle("Failed")
                    self.app.showError(error.localizedDescription)
                }
            }
        }
    }
}

struct MoaAccountManagerView: View {
    @ObservedObject var model: MoaAccountManagerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header.id("accounts-header")
                    if !model.failures.isEmpty {
                        Text(model.failures.joined(separator: "\n"))
                            .font(.system(size: 12))
                            .foregroundStyle(MoaTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(model.sections) { section in
                        MoaAccountSectionView(
                            section: section,
                            busy: model.isBusy(section.group),
                            progress: model.progress(section.group),
                            model: model
                        )
                        .id(section.id)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MoaLiquidWindowBackground())
            .moaFeedbackBanner()
            .onAppear {
                proxy.scrollTo(model.focus?.id ?? "accounts-header", anchor: .top)
            }
            .onChange(of: model.focusRequest) { _ in
                withAnimation { proxy.scrollTo(model.focus?.id ?? "accounts-header", anchor: .top) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MoaL10n.text("Accounts"))
                .font(.system(size: 22, weight: .semibold))
            Text(MoaL10n.text("Rename, edit and delete any saved account here. Switching from the menu bar still applies it immediately."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MoaAccountSectionView: View {
    let section: MoaAccountSection
    let busy: Bool
    let progress: String?
    @ObservedObject var model: MoaAccountManagerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: section.group.symbol)
                    .foregroundStyle(MoaTheme.tint)
                Text(section.group.title)
                    .font(.system(size: 15, weight: .semibold))
                // 长耗时操作(切换账号要等客户端正常退出)必须在这一组上可见,
                // 否则用户只能看到按钮变灰, 分不清"在跑"还是"卡死"。
                if let progress {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                    Text(progress)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MoaTheme.tint)
                }
                Spacer()
                Text(MoaL10n.format("%lld saved", section.rows.count))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if section.rows.isEmpty {
                Text(MoaL10n.text(section.group.supportsEditing
                    ? "Add a configuration to save its URL and API key."
                    : "Sign in to the client, then choose Save Current Login."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(section.rows) { row in
                MoaAccountRowView(row: row, busy: busy, model: model)
            }
            addButtons
            if let message = section.currentLoginMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .moaGlassSurface(radius: 18)
    }

    @ViewBuilder private var addButtons: some View {
        HStack(spacing: 8) {
            switch section.group {
            case .codexOfficial:
                addButton(MoaL10n.text("Save Current Login")) { model.add(.codexOfficial) }
                    .disabled(!section.canAddCurrentLogin || busy)
            case .codexConfig:
                addButton(MoaL10n.text("Add Config")) { model.add(.codexConfig) }
            case .claude:
                addButton(MoaL10n.text("Add Provider")) { model.add(.claude) }
            case .claudeCode:
                addButton(MoaL10n.text("Add Provider")) { model.add(.claudeCode) }
            case .workbuddy, .workbuddyCN:
                addButton(MoaL10n.text("Save Current Login")) { model.add(section.group) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(section.group) }
            case .deepseek:
                addButton(MoaL10n.text("Save Current Login")) { model.add(.deepseek) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(.deepseek) }
            case .antigravity:
                addButton(MoaL10n.text("Save Current Login")) { model.add(.antigravity) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(.antigravity) }
            case .geminiCLI:
                addButton(MoaL10n.text("Save Current Login")) { model.add(.geminiCLI) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(.geminiCLI) }
            }
            Spacer()
        }
        .disabled(busy)
        .padding(.top, 4)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private struct MoaAccountRowView: View {
    let row: MoaAccountRow
    let busy: Bool
    @ObservedObject var model: MoaAccountManagerModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name.isEmpty ? row.detail : row.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if row.active {
                        MoaStatusTag(title: MoaL10n.text("In Use"), tint: MoaTheme.tint)
                    }
                }
                if !row.detail.isEmpty && row.detail != row.name {
                    Text(row.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if !row.active {
                Button(MoaL10n.text("Switch")) { model.activate(row) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(MoaL10n.text("Switching quits and reopens the client."))
            }
            Menu {
                Button(MoaL10n.text("Rename")) { model.rename(row) }
                if row.group.supportsEditing {
                    Button(MoaL10n.text("Edit")) { model.edit(row) }
                }
                Divider()
                Button(role: .destructive) { model.delete(row) } label: { Text(MoaL10n.text("Delete")) }
            } label: {
                Label(MoaL10n.text("Account Actions"), systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(MoaL10n.text("Account Actions"))
            .accessibilityLabel(MoaL10n.format("Actions for %@", row.name.isEmpty ? row.detail : row.name))
        }
        .disabled(busy)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MoaTheme.glassFieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

}
