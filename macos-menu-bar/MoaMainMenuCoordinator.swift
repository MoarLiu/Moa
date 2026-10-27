import AppKit
import Combine
import Foundation

final class MoaMainMenuCoordinator {
    unowned let app: AppDelegate
    private var observers = Set<AnyCancellable>()

    init(app: AppDelegate) {
        self.app = app
    }

    func configureMenu() {
        app.menu.delegate = app
        app.menu.autoenablesItems = false
        app.menu.removeAllItems()
        app.versionItem.title = AppDelegate.versionTitle()
        app.versionItem.isEnabled = false
        app.menu.addItem(app.versionItem)
        app.menu.addItem(.separator())
        app.statusItemText.isEnabled = false
        app.statusItemText.isHidden = true
        app.menu.addItem(app.statusItemText)

        for (item, submenu) in [
            (app.codexProfilesItem, app.codexProfilesMenu),
            (app.claudeDesktopProfilesItem, app.claudeDesktopProfilesMenu),
            (app.zcodeItem, app.zcodeMenu),
            (app.workbuddyCNItem, app.workbuddyCNMenu),
            (app.workbuddyItem, app.workbuddyMenu),
            (app.deepseekCoordinator.item, app.deepseekCoordinator.menu)
        ] {
            submenu.autoenablesItems = false
            item.submenu = submenu
            app.menu.addItem(item)
        }
        app.menu.addItem(.separator())
        let accountsItem = actionItem("Accounts…", #selector(AppDelegate.showAllAccountsAction), key: "a")
        accountsItem.keyEquivalentModifierMask = [.command, .shift]
        app.menu.addItem(accountsItem)
        app.menu.addItem(actionItem("Usage Overview…", #selector(AppDelegate.showUsageOverviewAction), key: "u"))
        app.menu.addItem(.separator())

        let utilities = NSMenu(title: "Moa")
        utilities.autoenablesItems = false
        app.moaDataItem.submenu = app.moaDataMenu
        configureMoaDataMenu()
        utilities.addItem(app.moaDataItem)
        app.updatePricesItem.target = app
        utilities.addItem(app.updatePricesItem)
        utilities.addItem(actionItem("Check Update", #selector(AppDelegate.checkUpdateAction)))
        let utilitiesItem = NSMenuItem(title: "Moa", action: nil, keyEquivalent: "")
        utilitiesItem.submenu = utilities
        app.menu.addItem(utilitiesItem)
        app.menu.addItem(actionItem("Quit Moa", #selector(AppDelegate.quitAction), key: "q"))

        MoaFeedbackCenter.shared.anchorRect = { [weak app] in
            guard let button = app?.statusItem.button, let window = button.window else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        observers.removeAll()
        app.accountOperations.$active.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.app.lastMenuRefreshAt = .distantPast
                self?.updateVisibleStatus()
            }
        }.store(in: &observers)
        MoaFeedbackCenter.shared.$message.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateVisibleStatus() }
        }.store(in: &observers)
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: MoaL10n.text(title), action: action, keyEquivalent: key)
        item.target = app
        return item
    }

    func updateVisibleStatus() {
        if let operation = app.accountOperations.active.values.first {
            app.statusItemText.title = AppDelegate.statusTitle(operation.message)
            app.statusItemText.isHidden = false
        } else if app.dataPackageController.isDataOperationInProgress {
            app.statusItemText.isHidden = false
        } else if app.usageCoordinator.isUpdatingPrices {
            app.statusItemText.title = AppDelegate.statusTitle("Updating Prices…")
            app.statusItemText.isHidden = false
        } else if let message = MoaFeedbackCenter.shared.message {
            app.statusItemText.title = message.title
            app.statusItemText.isHidden = false
        } else {
            app.statusItemText.isHidden = true
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateVisibleStatus()
        // Keep the existing menus responsive; their write actions are guarded
        // by the shared store coordinator until the data operation finishes.
        guard !app.dataPackageController.isDataOperationInProgress else { return }
        app.usageCoordinator.refreshForPresentation()
        let now = Date()
        guard now.timeIntervalSince(app.lastMenuRefreshAt) >= app.menuRefreshInterval else {
            return
        }
        app.lastMenuRefreshAt = now
        rebuildProfileMenu()
        rebuildClaudeDesktopProfilesMenu()
        rebuildZCodeMenu()
        app.rebuildWorkBuddyMenus()
        app.deepseekCoordinator.rebuildMenu()
        configureMoaDataMenu()
        refreshStatus()
    }

    func configureMoaDataMenu() {
        app.moaDataMenu.removeAllItems()
        for item in [
            app.exportDataPackageItem,
            app.importDataPackageItem,
            NSMenuItem.separator(),
            app.toggleICloudStorageItem,
            app.openMoaDataFolderItem,
            app.openICloudDataFolderItem,
            NSMenuItem.separator(),
            app.exportDiagnosticPackageItem
        ] {
            app.moaDataMenu.addItem(item)
        }

        for item in [
            app.exportDataPackageItem,
            app.importDataPackageItem,
            app.exportDiagnosticPackageItem,
            app.toggleICloudStorageItem,
            app.openMoaDataFolderItem,
            app.openICloudDataFolderItem
        ] {
            item.target = app
        }

        let iCloudEnabled = app.dataPackageController.isICloudStorageEnabled()
        app.toggleICloudStorageItem.title = iCloudEnabled
            ? MoaL10n.text("Move Data Back to This Mac")
            : MoaL10n.text("Store Data in iCloud")
        app.toggleICloudStorageItem.state = .off
        let location = NSMenuItem(title: MoaL10n.text(iCloudEnabled ? "Data Location: iCloud" : "Data Location: This Mac"), action: nil, keyEquivalent: "")
        location.isEnabled = false
        app.moaDataMenu.insertItem(location, at: 0)
        app.moaDataMenu.insertItem(.separator(), at: 1)
    }

    func refreshStatus() {
        if let button = app.statusItem.button {
            button.toolTip = MoaL10n.text("Moa - Codex, Claude, ZCode, WorkBuddy, WorkBuddy AI, DeepSeek")
        }
    }

    func rebuildZCodeMenu() {
        app.zcodeMenu.removeAllItems()
        app.zcodeItem.title = MoaL10n.text("ZCode")
        app.zcodeMenu.title = MoaL10n.text("ZCode")

        app.zcodeMenu.addItem(app.usageCoordinator.zcodeSummaryItem)
        app.zcodeMenu.addItem(app.usageCoordinator.zcodeRefreshItem)
        app.zcodeDailyUsageAlertItem.target = app
        app.zcodeDailyUsageAlertItem.title = DailyUsageAlertController.menuTitle(for: .zcode)
        app.zcodeMenu.addItem(app.zcodeDailyUsageAlertItem)
        app.zcodeUsageDetailsItem.target = app
        app.zcodeMenu.addItem(app.zcodeUsageDetailsItem)
        app.zcodeMenu.addItem(NSMenuItem.separator())

        let zcodeOfficialItem = NSMenuItem(title: MoaL10n.text("ZCode Official Mode"), action: #selector(AppDelegate.applyZCodeOfficialModeAction), keyEquivalent: "")
        zcodeOfficialItem.target = app
        zcodeOfficialItem.state = .on
        let currentMode = NSMenuItem(title: MoaL10n.text("Current Mode: Official"), action: nil, keyEquivalent: "")
        currentMode.isEnabled = false
        app.zcodeMenu.addItem(currentMode)
        zcodeOfficialItem.title = MoaL10n.text("Reapply Official Configuration…")
        zcodeOfficialItem.state = .off
        app.zcodeMenu.addItem(zcodeOfficialItem)
        app.zcodeMenu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: MoaL10n.text("Open ZCode"), action: #selector(AppDelegate.openZCodeAction), keyEquivalent: "")
        openItem.target = app
        app.zcodeMenu.addItem(openItem)

        let reopenItem = NSMenuItem(title: MoaL10n.text("Reopen ZCode"), action: #selector(AppDelegate.reopenZCodeAction), keyEquivalent: "")
        reopenItem.target = app
        app.zcodeMenu.addItem(reopenItem)

        let openFolderItem = NSMenuItem(title: MoaL10n.text("Open ZCode Folder"), action: #selector(AppDelegate.openZCodeFolderAction), keyEquivalent: "")
        openFolderItem.target = app
        app.zcodeMenu.addItem(openFolderItem)
    }

    func rebuildProfileMenu() {
        app.codexProfilesMenu.removeAllItems()
        if let operation = app.accountOperations.active[.codex] {
            let item = NSMenuItem(title: operation.message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            app.codexProfilesMenu.addItem(item)
            app.codexProfilesMenu.addItem(manageAccountsItem(.codexConfig))
            return
        }
        app.codexProfilesMenu.autoenablesItems = false

        let selectedID: String?
        let profiles: [ConfigProfile]
        let officialAccounts: [CodexOfficialAccount]
        let selectedOfficialAccountID: String?
        let currentOfficialLoginSaveStatus: (hasLogin: Bool, savedAccountName: String?)
        do {
            selectedID = try app.profileController.selectedProfileID()
            profiles = try app.profileController.profiles()
            officialAccounts = try app.profileController.officialAccounts()
            selectedOfficialAccountID = try app.profileController.selectedOfficialAccountID()
            currentOfficialLoginSaveStatus = try app.profileController.currentOfficialLoginSaveStatus()
        } catch {
            showDataLoadFailure(error, source: "Codex", in: app.codexProfilesMenu)
            app.codexProfilesItem.title = "Codex · \(MoaL10n.text("Load Failed"))"
            return
        }
        let selectedName = app.currentCodexSelectionName()
        app.codexProfilesItem.title = "Codex · \(selectedName)"
        let isNoOfficialAccountMode = selectedOfficialAccountID == nil

        app.codexProfilesMenu.addItem(app.usageCoordinator.codexSummaryItem)
        app.codexProfilesMenu.addItem(app.usageCoordinator.codexRefreshItem)
        app.codexDailyUsageAlertItem.target = app
        app.codexDailyUsageAlertItem.title = DailyUsageAlertController.menuTitle(for: .codex)
        app.codexProfilesMenu.addItem(app.codexDailyUsageAlertItem)
        app.codexUsageDetailsItem.target = app
        app.codexProfilesMenu.addItem(app.codexUsageDetailsItem)
        app.codexProfilesMenu.addItem(NSMenuItem.separator())

        for item in app.codexEnhancements.menuItems { app.codexProfilesMenu.addItem(item) }
        app.codexProfilesMenu.addItem(NSMenuItem.separator())

        app.codexOfficialMenu.removeAllItems()
        app.codexOfficialMenu.autoenablesItems = false
        app.codexOfficialMenu.title = MoaL10n.text("Codex Official")
        app.codexOfficialItem.title = MoaL10n.text("Codex Official")
        app.codexOfficialItem.target = nil
        app.codexOfficialItem.action = nil
        app.codexOfficialItem.isEnabled = true
        app.codexOfficialItem.state = selectedID == nil ? .on : .off
        app.codexOfficialItem.submenu = app.codexOfficialMenu
        let useOfficialModeItem = NSMenuItem(title: MoaL10n.text("Use Codex Official Mode"), action: #selector(AppDelegate.restoreCodexOfficialAction), keyEquivalent: "")
        useOfficialModeItem.target = app
        useOfficialModeItem.state = selectedID == nil ? .on : .off
        useOfficialModeItem.isEnabled = !isNoOfficialAccountMode
        useOfficialModeItem.toolTip = isNoOfficialAccountMode ? MoaL10n.text("Choose a saved official account, or open Codex to sign in.") : nil
        app.codexOfficialMenu.addItem(useOfficialModeItem)
        if isNoOfficialAccountMode {
            app.codexOfficialMenu.addItem(actionItem("Open Codex to Sign In…", #selector(AppDelegate.openCodexAction)))
        }
        app.codexOfficialMenu.addItem(NSMenuItem.separator())

        let noAccountItem = NSMenuItem(title: MoaL10n.text("Do Not Use Account"), action: #selector(AppDelegate.applyCodexOfficialNoAccountAction), keyEquivalent: "")
        noAccountItem.target = app
        noAccountItem.state = isNoOfficialAccountMode ? .on : .off
        app.codexOfficialMenu.addItem(noAccountItem)

        if officialAccounts.isEmpty {
            let emptyItem = NSMenuItem(title: MoaL10n.text("No Official Accounts"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            app.codexOfficialMenu.addItem(emptyItem)
        } else {
            for account in officialAccounts {
                let item = NSMenuItem(title: account.displayTitle, action: #selector(AppDelegate.applyCodexOfficialAccountAction(_:)), keyEquivalent: "")
                item.target = app
                item.representedObject = account.id
                item.state = account.id == selectedOfficialAccountID ? .on : .off
                app.codexOfficialMenu.addItem(item)
            }
        }
        app.codexOfficialMenu.addItem(NSMenuItem.separator())
        if let savedAccountName = currentOfficialLoginSaveStatus.savedAccountName {
            let savedItem = NSMenuItem(title: MoaL10n.format("Current Login Saved as %@", savedAccountName), action: nil, keyEquivalent: "")
            savedItem.isEnabled = false
            app.codexOfficialMenu.addItem(savedItem)
        } else if !currentOfficialLoginSaveStatus.hasLogin {
            let noneItem = NSMenuItem(title: MoaL10n.text("No Current Official Login"), action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            app.codexOfficialMenu.addItem(noneItem)
        }
        app.codexOfficialMenu.addItem(manageAccountsItem(.codexOfficial))
        app.codexProfilesMenu.addItem(app.codexOfficialItem)

        if profiles.isEmpty {
            let emptyItem = NSMenuItem(title: MoaL10n.text("No Saved Configs"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            app.codexProfilesMenu.addItem(emptyItem)
        } else {
            app.codexProfilesMenu.addItem(NSMenuItem.separator())
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(AppDelegate.applyProfileAction(_:)), keyEquivalent: "")
                item.representedObject = profile.id
                item.state = profile.id == selectedID ? .on : .off
                app.codexProfilesMenu.addItem(item)
            }
        }

        app.codexProfilesMenu.addItem(NSMenuItem.separator())
        app.codexProfilesMenu.addItem(manageAccountsItem(.codexConfig))
        app.codexProfilesMenu.addItem(NSMenuItem.separator())

        app.codexProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open Codex"), action: #selector(AppDelegate.openCodexAction), keyEquivalent: ""))
        app.codexProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Reopen Codex"), action: #selector(AppDelegate.reopenCodexAction), keyEquivalent: ""))
        let migrateHistoryProviderItem = NSMenuItem(title: MoaL10n.text("Migrate History model_provider"), action: #selector(AppDelegate.migrateCodexSessionModelProviderAction), keyEquivalent: "")
        migrateHistoryProviderItem.target = app
        app.codexProfilesMenu.addItem(migrateHistoryProviderItem)
        app.codexProfilesMenu.addItem(NSMenuItem.separator())
        app.codexProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open Moa Folder"), action: #selector(AppDelegate.openMoaFolderAction), keyEquivalent: ""))
        app.codexProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open Codex Folder"), action: #selector(AppDelegate.openCodexFolderAction), keyEquivalent: ""))
    }

    func rebuildClaudeDesktopProfilesMenu() {
        app.claudeDesktopProfilesMenu.removeAllItems()
        if let operation = app.accountOperations.active[.claude] {
            let item = NSMenuItem(title: operation.message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            app.claudeDesktopProfilesMenu.addItem(item)
            app.claudeDesktopProfilesMenu.addItem(manageAccountsItem(.claude))
            return
        }

        let selectedID: String?
        let profiles: [ClaudeDesktopProviderProfile]
        do {
            selectedID = try app.claudeDesktopProfileController.selectedProfileID()
            profiles = try app.claudeDesktopProfileController.profiles()
        } catch {
            showDataLoadFailure(error, source: "Claude Desktop", in: app.claudeDesktopProfilesMenu)
            app.claudeDesktopProfilesItem.title = "Claude Desktop · \(MoaL10n.text("Load Failed"))"
            return
        }
        let selectedName = app.claudeDesktopProfileController.selectedProfileName() ?? MoaL10n.text("Official")
        app.claudeDesktopProfilesItem.title = "Claude Desktop · \(selectedName)"

        app.claudeDesktopProfilesMenu.addItem(app.usageCoordinator.claudeSummaryItem)
        app.claudeDesktopProfilesMenu.addItem(app.usageCoordinator.claudeRefreshItem)
        app.claudeDailyUsageAlertItem.target = app
        app.claudeDailyUsageAlertItem.title = DailyUsageAlertController.menuTitle(for: .claude)
        app.claudeDesktopProfilesMenu.addItem(app.claudeDailyUsageAlertItem)
        app.claudeUsageDetailsItem.target = app
        app.claudeDesktopProfilesMenu.addItem(app.claudeUsageDetailsItem)
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem.separator())

        let officialItem = NSMenuItem(title: MoaL10n.text("Claude Desktop Official"), action: #selector(AppDelegate.restoreClaudeDesktopOfficialAction), keyEquivalent: "")
        officialItem.state = selectedID == nil ? .on : .off
        app.claudeDesktopProfilesMenu.addItem(officialItem)

        if !profiles.isEmpty {
            app.claudeDesktopProfilesMenu.addItem(NSMenuItem.separator())
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(AppDelegate.applyClaudeDesktopProviderAction(_:)), keyEquivalent: "")
                item.representedObject = profile.id
                item.state = profile.id == selectedID ? .on : .off
                app.claudeDesktopProfilesMenu.addItem(item)
            }
        }

        app.claudeDesktopProfilesMenu.addItem(NSMenuItem.separator())
        app.claudeDesktopProfilesMenu.addItem(manageAccountsItem(.claude))
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem.separator())
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open Claude Desktop"), action: #selector(AppDelegate.openClaudeDesktopAction), keyEquivalent: ""))
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Reopen Claude Desktop"), action: #selector(AppDelegate.reopenClaudeDesktopAction), keyEquivalent: ""))
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open Claude Folder"), action: #selector(AppDelegate.openClaudeDesktopFolderAction), keyEquivalent: ""))
        app.claudeDesktopProfilesMenu.addItem(NSMenuItem(title: MoaL10n.text("Open 3P Profile Folder"), action: #selector(AppDelegate.openClaudeDesktop3PFolderAction), keyEquivalent: ""))
    }

    private func manageAccountsItem(_ group: MoaAccountGroup) -> NSMenuItem {
        let item = NSMenuItem(title: MoaL10n.text("Manage Accounts…"), action: #selector(AppDelegate.showAccountManagerAction(_:)), keyEquivalent: "")
        item.target = app
        item.representedObject = group.rawValue
        return item
    }

    private func showDataLoadFailure(_ error: Error, source: String, in menu: NSMenu) {
        let item = NSMenuItem(
            title: MoaL10n.format("Unable to load %@ data: %@", source, error.localizedDescription),
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        menu.addItem(item)
        app.statusItemText.title = AppDelegate.statusTitle("Load Failed")
    }
}
