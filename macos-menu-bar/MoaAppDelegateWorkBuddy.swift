import AppKit
import Foundation

final class MoaWorkBuddyCoordinator: NSObject {
    unowned let app: AppDelegate
    let edition: WorkBuddyEdition
    let controller: WorkBuddyController
    let item: NSMenuItem
    let menu: NSMenu
    private var operationInFlight = false

    init(app: AppDelegate, edition: WorkBuddyEdition) {
        self.app = app
        self.edition = edition
        self.controller = WorkBuddyController(edition: edition)
        item = NSMenuItem(title: edition.title, action: nil, keyEquivalent: "")
        menu = NSMenu(title: edition.title)
        super.init()
    }

    private func statusTitle(_ key: String) -> String {
        MoaL10n.format("Status: %@", edition.localized(key))
    }

    private var summaryItem: NSMenuItem {
        edition == .china ? app.usageCoordinator.workbuddyCNSummaryItem : app.usageCoordinator.workbuddySummaryItem
    }
    private var refreshItem: NSMenuItem {
        edition == .china ? app.usageCoordinator.workbuddyCNRefreshItem : app.usageCoordinator.workbuddyRefreshItem
    }

    func rebuildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(summaryItem)
        menu.addItem(refreshItem)
        let note = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 46))
        let label = NSTextField(wrappingLabelWithString: edition.localized("All local accounts · API estimates, not credits. Unpriced models are excluded from cost."))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 16, y: 3, width: 288, height: 40)
        container.addSubview(label)
        note.view = container
        menu.addItem(note)
        menu.addItem(menuItem("Usage Details", #selector(showWorkBuddyUsageAction)))
        let alertItem = menuItem("Daily Usage Alert", #selector(showWorkBuddyUsageAlertAction))
        alertItem.title = DailyUsageAlertController.menuTitle(for: edition.alertKind)
        menu.addItem(alertItem)
        menu.addItem(NSMenuItem.separator())
        if operationInFlight {
            let item = NSMenuItem(title: edition.localized("Updating WorkBuddy AI…"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        var current: WorkBuddyAccount?
        do {
            let accounts = try controller.accounts()
            let uid = try controller.currentUID()
            current = accounts.first { $0.uid == uid }
            item.title = current.map { "\(edition.title) · \($0.name)" } ?? edition.title
            if accounts.isEmpty {
                let item = NSMenuItem(title: edition.localized("No Saved Accounts"), action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            for account in accounts {
                let item = menuItem(account.name, #selector(applyWorkBuddyAccountAction(_:)), localized: false)
                item.representedObject = account.id.uuidString
                item.state = account.uid == uid ? .on : .off
                menu.addItem(item)
            }
        } catch {
            item.title = "\(edition.title) · \(edition.localized("Load Failed"))"
            let item = NSMenuItem(title: edition.localized("Unable to read WorkBuddy AI accounts"), action: nil, keyEquivalent: "")
            item.toolTip = error.localizedDescription
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Save Current WorkBuddy AI Account…", #selector(saveWorkBuddyAccountAction)))
        menu.addItem(menuItem("Add Another WorkBuddy AI Account…", #selector(addWorkBuddyAccountAction)))
        for (title, action) in [
            ("Rename Current Account", #selector(renameWorkBuddyAccountAction(_:))),
            ("Delete Current Account", #selector(deleteWorkBuddyAccountAction(_:)))
        ] {
            let item = menuItem(title, action)
            item.representedObject = current?.id.uuidString
            item.isEnabled = current != nil
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Open WorkBuddy AI", #selector(openWorkBuddyAction)))
        menu.addItem(menuItem("Reopen WorkBuddy AI", #selector(reopenWorkBuddyAction)))
    }

    private func menuItem(_ title: String, _ action: Selector, localized: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: localized ? edition.localized(title) : title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func showWorkBuddyUsageAction() { app.usageInsightsWindow.show(initialSource: edition.usageSource) }
    @objc func showWorkBuddyUsageAlertAction() {
        app.showDailyUsageAlertPanel(kind: edition.alertKind)
        rebuildMenu()
    }

    @objc func saveWorkBuddyAccountAction() {
        guard !operationInFlight,
              let name = app.showOfficialAccountNamePanel(
                title: edition.localized("Save WorkBuddy AI Account"),
                message: edition.localized("WorkBuddy AI will quit normally, save its latest login on this Mac, and reopen. Finish active tasks first. Do not use Log Out."),
                buttonTitle: edition.localized("Save"), initialName: edition.title
              ) else { return }
        performWorkBuddyOperation { _ = try self.controller.saveCurrent(name: name) }
    }

    @objc func addWorkBuddyAccountAction() {
        guard !operationInFlight,
              MoaNonBlockingAlert.confirm(
                messageText: edition.localized("Add Another WorkBuddy AI Account?"),
                informativeText: edition.localized("Moa saves the current login, quits WorkBuddy AI, and opens a fresh login. Sign in with the other account, then choose Save Current WorkBuddy AI Account. Existing sessions stay on this Mac. Finish active tasks first; do not use Log Out."),
                primaryButtonTitle: edition.localized("Continue"), tone: .warning
              ) else { return }
        performWorkBuddyOperation { try self.controller.prepareNewLogin() }
    }

    @objc func applyWorkBuddyAccountAction(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let id = UUID(uuidString: text) else { return }
        performWorkBuddyOperation { _ = try self.controller.apply(id: id) }
    }

    @objc func renameWorkBuddyAccountAction(_ sender: NSMenuItem) {
        guard !operationInFlight, let text = sender.representedObject as? String,
              let id = UUID(uuidString: text),
              let account = try? controller.accounts().first(where: { $0.id == id }),
              let name = app.showOfficialAccountNamePanel(
                title: edition.localized("Rename WorkBuddy AI Account"), message: edition.localized("Update the saved account's display name."),
                buttonTitle: edition.localized("Save"), initialName: account.name
              ) else { return }
        performWorkBuddyOperation { try self.controller.rename(id: id, name: name) }
    }

    @objc func deleteWorkBuddyAccountAction(_ sender: NSMenuItem) {
        guard !operationInFlight, let text = sender.representedObject as? String,
              let id = UUID(uuidString: text), MoaNonBlockingAlert.confirm(
                messageText: edition.localized("Delete Saved WorkBuddy AI Account?"),
                informativeText: edition.localized("Only Moa's saved copy is deleted. WorkBuddy AI stays signed in and its local sessions are kept."),
                primaryButtonTitle: edition.localized("Delete"), tone: .danger
              ) else { return }
        performWorkBuddyOperation { try self.controller.delete(id: id) }
    }

    @objc func openWorkBuddyAction() { performWorkBuddyOperation { try self.controller.open() } }
    @objc func reopenWorkBuddyAction() { performWorkBuddyOperation { try self.controller.reopen() } }

    private func performWorkBuddyOperation(_ operation: @escaping () throws -> Void) {
        guard !operationInFlight else { return }
        operationInFlight = true
        app.statusItemText.title = self.statusTitle("Updating WorkBuddy AI…")
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                self.operationInFlight = false
                self.rebuildMenu()
                if self.edition == .china {
                    self.app.usageCoordinator.refreshWorkBuddyCN(forceRefresh: true)
                } else {
                    self.app.usageCoordinator.refreshWorkBuddy(forceRefresh: true)
                }
                switch result {
                case .success:
                    self.app.statusItemText.title = self.statusTitle("WorkBuddy AI updated")
                case .failure(let error):
                    self.app.statusItemText.title = self.statusTitle("Failed")
                    self.app.showError(error.localizedDescription)
                }
            }
        }
    }
}

extension AppDelegate {
    func rebuildWorkBuddyMenus() {
        workbuddyCoordinator.rebuildMenu()
        workbuddyCNCoordinator.rebuildMenu()
    }
}
