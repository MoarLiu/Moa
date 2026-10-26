import AppKit
import Foundation

final class MoaDeepSeekCoordinator: NSObject {
    unowned let app: AppDelegate
    let controller: DeepSeekController
    let item = NSMenuItem(title: "DeepSeek", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "DeepSeek")
    private var operationInFlight = false

    init(app: AppDelegate, controller: DeepSeekController = DeepSeekController()) {
        self.app = app
        self.controller = controller
        super.init()
    }

    func rebuildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if operationInFlight {
            let busy = NSMenuItem(title: MoaL10n.text("Updating DeepSeek…"), action: nil, keyEquivalent: "")
            busy.isEnabled = false
            menu.addItem(busy)
            return
        }
        do {
            let accounts = try controller.accounts()
            let fingerprint = try controller.currentFingerprint()
            let current = accounts.first { $0.fingerprint == fingerprint }
            item.title = current.map { "DeepSeek · \($0.name)" } ?? "DeepSeek"
            if accounts.isEmpty {
                let empty = NSMenuItem(title: MoaL10n.text("No Saved Accounts"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for account in accounts {
                let entry = accountItem(account, action: #selector(applyAccount(_:)))
                entry.state = account.fingerprint == fingerprint ? .on : .off
                menu.addItem(entry)
            }
        } catch {
            item.title = "DeepSeek · \(MoaL10n.text("Load Failed"))"
            let failure = NSMenuItem(title: MoaL10n.text("Unable to read DeepSeek accounts"), action: nil, keyEquivalent: "")
            failure.toolTip = error.localizedDescription
            failure.isEnabled = false
            menu.addItem(failure)
        }
        menu.addItem(NSMenuItem.separator())
        let manageItem = actionItem("Manage Accounts…", #selector(AppDelegate.showAccountManagerAction(_:)))
        manageItem.target = app
        manageItem.representedObject = MoaAccountGroup.deepseek.rawValue
        menu.addItem(manageItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Open DeepSeek", #selector(openApp)))
        menu.addItem(actionItem("Reopen DeepSeek", #selector(reopenApp)))
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: MoaL10n.text(title), action: action, keyEquivalent: "")
        item.target = self
        return item
    }
    private func accountItem(_ account: DeepSeekAccount, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: account.name, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = account.id.uuidString
        return item
    }
    private func accountID(_ sender: NSMenuItem) -> UUID? {
        (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    }

    @objc private func saveCurrent() { saveCurrentAccount() }

    func saveCurrentAccount(onComplete: (() -> Void)? = nil) {
        guard !operationInFlight, let name = app.showOfficialAccountNamePanel(
            title: MoaL10n.text("Save DeepSeek Account"),
            message: MoaL10n.text("DeepSeek Harness will quit normally, save its current login on this Mac, and reopen. Finish active tasks and close other DSH instances first. Do not use Log Out."),
            buttonTitle: MoaL10n.text("Save"), initialName: MoaL10n.text("DeepSeek Account")
        ) else { return }
        perform(onComplete: onComplete) { _ = try self.controller.saveCurrent(name: name) }
    }
    func addAnotherAccount(onComplete: (() -> Void)? = nil) {
        guard !operationInFlight, MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Add Another DeepSeek Account?"),
            informativeText: MoaL10n.text("Moa saves the current login and reopens DeepSeek Harness without its account login. Choose Sign In, log in with the other account in your browser, then save it in Moa. API keys and local sessions are kept. Finish active tasks and close other DSH instances first; do not use Log Out."),
            primaryButtonTitle: MoaL10n.text("Continue"), tone: .warning
        ) else { return }
        perform(onComplete: onComplete) { try self.controller.prepareNewLogin() }
    }
    @objc private func applyAccount(_ sender: NSMenuItem) {
        guard let id = accountID(sender) else { return }
        perform { _ = try self.controller.apply(id: id) }
    }
    @objc private func openApp() { perform { try self.controller.open() } }
    @objc private func reopenApp() { perform { try self.controller.reopen() } }

    private func perform(onComplete: (() -> Void)? = nil, _ operation: @escaping () throws -> Void) {
        guard !operationInFlight else { return }
        operationInFlight = true
        app.statusItemText.title = AppDelegate.statusTitle("Updating DeepSeek…")
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.operationInFlight = false
                self.rebuildMenu()
                onComplete?()
                switch result {
                case .success: self.app.statusItemText.title = AppDelegate.statusTitle("DeepSeek updated")
                case .failure(let error):
                    self.app.statusItemText.title = AppDelegate.statusTitle("Failed")
                    self.app.showError(error.localizedDescription)
                }
            }
        }
    }
}
