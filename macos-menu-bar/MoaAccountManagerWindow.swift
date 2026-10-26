import AppKit
import Combine
import SwiftUI

/// Which group the account window opens scrolled to. The window itself is one
/// list grouped by client, never one tab per client.
enum MoaAccountGroup: String, CaseIterable, Identifiable {
    case codexOfficial
    case codexConfig
    case claude
    case workbuddy
    case workbuddyCN
    case deepseek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexOfficial: return MoaL10n.text("Codex Official")
        case .codexConfig: return MoaL10n.text("Codex Configs")
        case .claude: return "Claude Desktop"
        case .workbuddy: return "WorkBuddy AI"
        case .workbuddyCN: return MoaL10n.text("WorkBuddy")
        case .deepseek: return "DeepSeek"
        }
    }

    var symbol: String {
        switch self {
        case .codexOfficial: return "person.crop.circle"
        case .codexConfig: return "gearshape"
        case .claude: return "sparkles"
        case .workbuddy, .workbuddyCN: return "briefcase"
        case .deepseek: return "bolt"
        }
    }

    var client: MoaAccountClient {
        switch self {
        case .codexOfficial, .codexConfig: return .codex
        case .claude: return .claude
        case .workbuddy: return .workbuddy
        case .workbuddyCN: return .workbuddyCN
        case .deepseek: return .deepseek
        }
    }

    /// Login snapshots can only be renamed; API configs also have credentials to edit.
    var supportsEditing: Bool {
        switch self {
        case .codexConfig, .claude: return true
        case .codexOfficial, .workbuddy, .workbuddyCN, .deepseek: return false
        }
    }
}

struct MoaAccountRow: Identifiable, Equatable {
    let group: MoaAccountGroup
    let id: String
    var name: String
    var detail: String
    var active: Bool
}

struct MoaAccountSection: Identifiable, Equatable {
    let group: MoaAccountGroup
    var rows: [MoaAccountRow]
    var canAddCurrentLogin: Bool
    var currentLoginMessage: String? = nil

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
                rows: accounts.map {
                    MoaAccountRow(group: .codexOfficial, id: $0.id, name: $0.name, detail: $0.email ?? "", active: $0.id == selected)
                },
                canAddCurrentLogin: status.hasLogin && status.savedAccountName == nil,
                currentLoginMessage: status.savedAccountName.map { MoaL10n.format("Current Login Saved as %@", $0) }
                    ?? (status.hasLogin ? nil : MoaL10n.text("Sign in to Codex, then save the current login here."))
            )
        }

        take(.codexConfig) {
            let profiles = try app.profileController.profiles()
            let selected = try app.profileController.selectedProfileID()
            return MoaAccountSection(
                group: .codexConfig,
                rows: profiles.map {
                    MoaAccountRow(group: .codexConfig, id: $0.id, name: $0.name, detail: $0.baseURL, active: $0.id == selected)
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
                    MoaAccountRow(group: .claude, id: $0.id, name: $0.name, detail: $0.baseURL, active: $0.id == selected)
                },
                canAddCurrentLogin: false
            )
        }

        func workbuddy(_ edition: WorkBuddyEdition, _ group: MoaAccountGroup, _ coordinator: MoaWorkBuddyCoordinator) throws -> MoaAccountSection {
            let accounts = try coordinator.controller.accounts()
            let current = try coordinator.controller.currentUID()
            return MoaAccountSection(
                group: group,
                rows: accounts.map {
                    MoaAccountRow(group: group, id: $0.id.uuidString, name: $0.name, detail: $0.uid, active: $0.uid == current)
                },
                canAddCurrentLogin: false
            )
        }
        take(.workbuddy) { try workbuddy(.international, .workbuddy, app.workbuddyCoordinator) }
        take(.workbuddyCN) { try workbuddy(.china, .workbuddyCN, app.workbuddyCNCoordinator) }

        take(.deepseek) {
            let accounts = try app.deepseekCoordinator.controller.accounts()
            let current = try app.deepseekCoordinator.controller.currentFingerprint()
            return MoaAccountSection(
                group: .deepseek,
                rows: accounts.map {
                    MoaAccountRow(group: .deepseek, id: $0.id.uuidString, name: $0.name, detail: "", active: $0.fingerprint == current)
                },
                canAddCurrentLogin: false
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
    private var window: NSWindow?
    private var model: MoaAccountManagerModel?

    init(app: AppDelegate) { self.app = app }

    func refreshIfVisible() {
        if window?.isVisible == true { model?.reload() }
    }

    func show(group: MoaAccountGroup? = nil) {
        let window = existingOrNewWindow()
        model?.focus = group
        model?.focusRequest = UUID()
        model?.reload()
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window { return window }
        let model = MoaAccountManagerModel(app: app)
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = MoaL10n.text("Accounts")
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        let hostingView = MoaInteractiveHostingView(rootView: MoaAccountManagerView(model: model))
        if #available(macOS 13.0, *) { hostingView.sizingOptions = [] }
        window.contentView = hostingView
        self.window = window
        return window
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
              !app.deepseekCoordinator.isUpdatingAccounts else { return }
        let loaded = MoaAccountCatalog.load(app: app)
        sections = loaded.sections
        failures = loaded.failures
        app.rebuildCodexProviderMenus()
        app.rebuildClaudeProviderMenus()
        app.rebuildWorkBuddyMenus()
        app.deepseekCoordinator.rebuildMenu()
    }

    func add(_ group: MoaAccountGroup) {
        guard !isBusy(group) else { return }
        let refresh: () -> Void = { [weak self] in self?.reload() }
        // API configs save synchronously inside their own panel. Login
        // snapshots quit and relaunch an app in the background, so the list
        // waits for that to finish instead of refreshing early.
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
        case .workbuddy:
            app.workbuddyCoordinator.saveCurrentAccount(onComplete: refresh)
        case .workbuddyCN:
            app.workbuddyCNCoordinator.saveCurrentAccount(onComplete: refresh)
        case .deepseek:
            app.deepseekCoordinator.saveCurrentAccount(onComplete: refresh)
        }
    }

    func addAnotherLogin(_ group: MoaAccountGroup) {
        guard !isBusy(group) else { return }
        let refresh: () -> Void = { [weak self] in self?.reload() }
        switch group {
        case .workbuddy:
            app.workbuddyCoordinator.addAnotherAccount(onComplete: refresh)
        case .workbuddyCN:
            app.workbuddyCNCoordinator.addAnotherAccount(onComplete: refresh)
        case .deepseek:
            app.deepseekCoordinator.addAnotherAccount(onComplete: refresh)
        case .codexOfficial, .codexConfig, .claude:
            break
        }
    }

    func rename(_ row: MoaAccountRow) {
        guard !isBusy(row.group) else { return }
        guard let name = app.showOfficialAccountNamePanel(
            title: MoaL10n.text("Rename"),
            message: MoaL10n.format("Update the display name for \"%@\". This does not switch accounts or reopen anything.", row.name),
            buttonTitle: MoaL10n.text("Save"),
            initialName: row.name
        ) else { return }
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
            case .workbuddy:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCoordinator.controller.rename(id: id, name: name)
            case .workbuddyCN:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCNCoordinator.controller.rename(id: id, name: name)
            case .deepseek:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.deepseekCoordinator.controller.rename(id: id, name: name)
            }
        }
    }

    func edit(_ row: MoaAccountRow) {
        guard !isBusy(row.group) else { return }
        switch row.group {
        case .codexConfig:
            guard let profile = try? app.profileController.profiles().first(where: { $0.id == row.id }),
                  let input = app.showEditProfilePanel(for: profile) else { return }
            // The row's active flag is from the last reload, so the menu may
            // have switched configs since. Re-read what is current at save time
            // and only reapply a config the client is still using.
            let id = row.id
            let applyToCurrent = (try? app.profileController.selectedProfileID()) == id
            guard !applyToCurrent || confirmLiveEdit(row, MoaL10n.text("Codex quits and reopens, so finish active tasks first.")) else { return }
            run(row.group, MoaL10n.text("Saving…")) {
                let applied = try self.app.profileController.updateProfileApplyingIfSelected(
                    id: id, name: input.name, baseURL: input.baseURL, apiKey: input.apiKey, applyToCurrent: applyToCurrent)
                if applied { self.app.controller.reopenCodex() }
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
        case .codexOfficial, .workbuddy, .workbuddyCN, .deepseek:
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
        run(row.group, MoaL10n.text("Deleting…")) {
            switch row.group {
            case .codexOfficial:
                let result = try self.app.profileController.deleteOfficialAccount(id: row.id)
                if result.activated != nil { self.app.controller.reopenCodex() }
            case .codexConfig:
                _ = try self.app.profileController.deleteProfile(id: row.id)
            case .claude:
                _ = try self.app.claudeDesktopProfileController.deleteProfile(id: row.id)
            case .workbuddy:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCoordinator.controller.delete(id: id)
            case .workbuddyCN:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.workbuddyCNCoordinator.controller.delete(id: id)
            case .deepseek:
                guard let id = UUID(uuidString: row.id) else { return }
                try self.app.deepseekCoordinator.controller.delete(id: id)
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
        case .codexOfficial, .codexConfig, .claude:
            break
        }
        run(row.group, MoaL10n.text("Switching…")) {
            switch row.group {
            case .codexOfficial:
                _ = try self.app.profileController.applyOfficialAccount(id: row.id)
                self.app.controller.reopenCodex()
            case .codexConfig:
                _ = try self.app.profileController.applyProfile(id: row.id)
                self.app.controller.reopenCodex()
            case .claude:
                _ = try self.app.claudeDesktopProfileController.applyProfile(id: row.id)
                self.app.claudeDesktopProfileController.reopenClaudeDesktop()
            case .workbuddy, .workbuddyCN, .deepseek:
                break // Routed through their shared menu coordinators above.
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
        case .workbuddy, .workbuddyCN, .deepseek:
            return MoaL10n.text("Only Moa's saved copy is deleted. The app stays signed in and its local sessions are kept.")
        }
    }

    private func switchExplanation(_ group: MoaAccountGroup) -> String {
        switch group {
        case .codexOfficial, .codexConfig:
            return MoaL10n.text("Codex quits and reopens, so finish active tasks first.")
        case .claude:
            return MoaL10n.text("Claude Desktop quits and reopens, so finish active tasks first.")
        case .workbuddy:
            return MoaL10n.text("WorkBuddy AI quits and reopens, so finish active tasks first. Do not use Log Out.")
        case .workbuddyCN:
            return MoaL10n.text("WorkBuddy quits and reopens, so finish active tasks first. Do not use Log Out.")
        case .deepseek:
            return MoaL10n.text("DeepSeek Harness quits and reopens, so finish active tasks and close other DSH instances first. Do not use Log Out.")
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
            case .workbuddy, .workbuddyCN:
                addButton(MoaL10n.text("Save Current Login")) { model.add(section.group) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(section.group) }
            case .deepseek:
                addButton(MoaL10n.text("Save Current Login")) { model.add(.deepseek) }
                addButton(MoaL10n.text("Add Another Account")) { model.addAnotherLogin(.deepseek) }
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
