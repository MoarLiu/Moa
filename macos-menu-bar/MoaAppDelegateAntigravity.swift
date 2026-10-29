import AppKit
import Foundation

final class MoaAntigravityCoordinator: NSObject {
    unowned let app: AppDelegate
    let controller: AntigravityController
    let item = NSMenuItem(title: "Antigravity", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Antigravity")
    private(set) var overview = AntigravityAccountOverview()
    private(set) var failure: String?
    private var refreshing = false
    private var revision = 0
    private var lastRefresh = Date.distantPast
    var isUpdatingAccounts: Bool { app.accountOperations.active[.antigravity] != nil }

    init(app: AppDelegate, controller: AntigravityController = AntigravityController()) {
        self.app = app
        self.controller = controller
        super.init()
    }

    // Rendering and the shared account catalog only inspect cached metadata.
    // Keychain calls run off the main thread and passive reads cannot prompt.
    func rebuildMenu() {
        renderMenu()
        refreshIfNeeded()
    }

    private func renderMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let current = overview.accounts.first { $0.id == overview.currentID }
        item.title = current.map { "Antigravity · \($0.name)" } ?? "Antigravity"
        if isUpdatingAccounts {
            let busy = NSMenuItem(title: MoaL10n.text("Updating Antigravity…"), action: nil, keyEquivalent: "")
            busy.isEnabled = false
            menu.addItem(busy)
            return
        }
        if overview.accounts.isEmpty {
            let empty = NSMenuItem(title: MoaL10n.text("No Saved Accounts"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for account in overview.accounts {
            let entry = actionItem(account.name, #selector(applyAccount(_:)), localized: false)
            entry.representedObject = account.id.uuidString
            entry.state = account.id == overview.currentID ? .on : .off
            menu.addItem(entry)
        }
        if let message = failure ?? overview.message {
            let status = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(.separator())
        let manage = actionItem("Manage Accounts…", #selector(AppDelegate.showAccountManagerAction(_:)))
        manage.target = app
        manage.representedObject = MoaAccountGroup.antigravity.rawValue
        menu.addItem(manage)
        menu.addItem(.separator())
        menu.addItem(actionItem("Open Antigravity", #selector(openApp)))
        menu.addItem(actionItem("Reopen Antigravity", #selector(reopenApp)))
    }

    private func actionItem(_ title: String, _ action: Selector, localized: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: localized ? MoaL10n.text(title) : title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    private func refreshIfNeeded() {
        guard !MoaRuntimeMode.suppressesUserInteraction,
              !refreshing, !isUpdatingAccounts, Date().timeIntervalSince(lastRefresh) >= 1 else { return }
        refreshing = true
        let generation = revision
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try self.controller.overview() }
            DispatchQueue.main.async {
                self.refreshing = false
                guard generation == self.revision, !self.isUpdatingAccounts else { return }
                self.accept(result)
                self.renderMenu()
                self.app.accountManagerWindow.refreshIfVisible()
            }
        }
    }

    private func accept(_ result: Result<AntigravityAccountOverview, Error>) {
        lastRefresh = Date()
        switch result {
        case .success(let overview): self.overview = overview; failure = nil
        case .failure(let error): overview.currentID = nil; failure = error.localizedDescription
        }
    }

    func saveCurrentAccount(onComplete: (() -> Void)? = nil) {
        guard !isUpdatingAccounts, let name = app.showOfficialAccountNamePanel(
            title: MoaL10n.text("Save Antigravity Account"),
            message: MoaL10n.text("Antigravity will quit normally, save its latest Google login in Keychain, and reopen. Finish active tasks and close agy and Antigravity IDE extensions first."),
            buttonTitle: MoaL10n.text("Save"), initialName: MoaL10n.text("Antigravity Account")
        ) else { return }
        perform(onComplete: onComplete) { _ = try self.controller.saveCurrent(name: name) }
    }

    func addAnotherAccount(onComplete: (() -> Void)? = nil) {
        guard !isUpdatingAccounts, MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Add Another Antigravity Account?"),
            informativeText: MoaL10n.text("Moa saves the current login in Keychain, quits Antigravity, and opens a fresh Google sign-in. Sign in with the other account, then save it in Moa. Finish active tasks and close agy and Antigravity IDE extensions first."),
            primaryButtonTitle: MoaL10n.text("Continue"), tone: .warning
        ) else { return }
        perform(onComplete: onComplete) { try self.controller.prepareNewLogin() }
    }

    @objc private func applyAccount(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        applySavedAccount(id: id)
    }

    func applySavedAccount(id: UUID, onComplete: (() -> Void)? = nil) {
        perform(onComplete: onComplete) { _ = try self.controller.apply(id: id) }
    }
    func renameSavedAccount(id: UUID, name: String, onComplete: (() -> Void)? = nil) {
        perform(onComplete: onComplete) { try self.controller.rename(id: id, name: name) }
    }
    func forgetSavedAccount(id: UUID, onComplete: (() -> Void)? = nil) {
        perform(onComplete: onComplete) { try self.controller.delete(id: id) }
    }
    @objc private func openApp() { perform { try self.controller.open() } }
    @objc private func reopenApp() { perform { try self.controller.reopen() } }

    private func perform(onComplete: (() -> Void)? = nil, _ operation: @escaping () throws -> Void) {
        guard let token = app.accountOperations.begin(.antigravity, message: MoaL10n.text("Updating Antigravity…")) else { return }
        revision += 1
        renderMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            let refreshed = Result { try self.controller.overview() }
            DispatchQueue.main.async {
                self.app.accountOperations.finish(.antigravity, id: token)
                self.accept(refreshed)
                self.renderMenu()
                if let onComplete { onComplete() }
                else { self.app.accountManagerWindow.refreshIfVisible() }
                switch result {
                case .success: self.app.statusItemText.title = AppDelegate.statusTitle("Done")
                case .failure(let error):
                    self.app.statusItemText.title = AppDelegate.statusTitle("Failed")
                    self.app.showError(error.localizedDescription)
                }
            }
        }
    }
}
