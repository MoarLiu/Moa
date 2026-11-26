import AppKit
import Foundation

final class MoaGeminiCLICoordinator: NSObject {
    unowned let app: AppDelegate
    let controller: GeminiCLIController
    let item = NSMenuItem(title: "Gemini CLI", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Gemini CLI")
    var isUpdatingAccounts: Bool { app.accountOperations.active[.geminiCLI] != nil }

    init(app: AppDelegate, controller: GeminiCLIController = GeminiCLIController()) {
        self.app = app
        self.controller = controller
        super.init()
    }

    func rebuildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if isUpdatingAccounts {
            let busy = NSMenuItem(title: MoaL10n.text("Updating Gemini CLI…"), action: nil, keyEquivalent: "")
            busy.isEnabled = false
            menu.addItem(busy)
            return
        }
        do {
            let accounts = try controller.accounts()
            let currentID = try controller.currentIdentity()
            let current = accounts.first { $0.identity == currentID }
            item.title = current.map { "Gemini CLI · \($0.name)" } ?? "Gemini CLI"
            if accounts.isEmpty {
                let empty = NSMenuItem(title: MoaL10n.text("No Saved Accounts"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for account in accounts {
                let entry = NSMenuItem(title: account.name, action: #selector(applyAccount(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = account.id.uuidString
                entry.state = account.identity == currentID ? .on : .off
                menu.addItem(entry)
            }
        } catch {
            item.title = "Gemini CLI · \(MoaL10n.text("Load Failed"))"
            let failure = NSMenuItem(title: MoaL10n.text("Unable to read Gemini CLI accounts"), action: nil, keyEquivalent: "")
            failure.toolTip = error.localizedDescription
            failure.isEnabled = false
            menu.addItem(failure)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: MoaL10n.text("Manage Accounts…"), action: #selector(AppDelegate.showAccountManagerAction(_:)), keyEquivalent: "")
        manage.target = app
        manage.representedObject = MoaAccountGroup.geminiCLI.rawValue
        menu.addItem(manage)
        let folder = NSMenuItem(title: MoaL10n.text("Open Gemini Folder"), action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
    }

    func saveCurrentAccount(onComplete: (() -> Void)? = nil) {
        let suggestedName = (try? controller.currentLogin()?.email).flatMap { $0.isEmpty ? nil : $0 }
            ?? MoaL10n.text("Gemini CLI Account")
        guard !isUpdatingAccounts, let name = app.showOfficialAccountNamePanel(
            title: MoaL10n.text("Save Gemini CLI Account"),
            message: MoaL10n.text("Save the current Gemini CLI OAuth login on this Mac. Antigravity credentials are not touched."),
            buttonTitle: MoaL10n.text("Save"),
            initialName: suggestedName
        ) else { return }
        perform(onComplete: onComplete) { _ = try self.controller.saveCurrent(name: name) }
    }

    func addAnotherAccount(onComplete: (() -> Void)? = nil) {
        guard !isUpdatingAccounts, MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Add Another Gemini CLI Account?"),
            informativeText: MoaL10n.text("Moa saves the current Gemini CLI login and clears ~/.gemini/oauth_creds.json. Run `gemini` in your terminal to sign in with the new Google account, then click Save Current Login in Moa."),
            primaryButtonTitle: MoaL10n.text("Continue"),
            tone: .warning
        ) else { return }
        perform(onComplete: onComplete) { try self.controller.prepareNewLogin() }
    }

    @objc private func applyAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        applySavedAccount(id: id)
    }

    func applySavedAccount(id: UUID, onComplete: (() -> Void)? = nil) {
        perform(onComplete: onComplete) { _ = try self.controller.apply(id: id) }
    }

    @objc private func openFolder() {
        controller.openGeminiFolder()
    }

    private func perform(onComplete: (() -> Void)? = nil, _ operation: @escaping () throws -> Void) {
        guard let token = app.accountOperations.begin(.geminiCLI, message: MoaL10n.text("Updating Gemini CLI…")) else { return }
        app.statusItemText.title = AppDelegate.statusTitle("Updating Gemini CLI…")
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.app.accountOperations.finish(.geminiCLI, id: token)
                self.rebuildMenu()
                if let onComplete { onComplete() }
                else { self.app.accountManagerWindow.refreshIfVisible() }
                switch result {
                case .success:
                    self.app.statusItemText.title = AppDelegate.statusTitle("Gemini CLI updated")
                case .failure(let error):
                    self.app.statusItemText.title = AppDelegate.statusTitle("Failed")
                    self.app.showError(error.localizedDescription)
                }
            }
        }
    }
}
