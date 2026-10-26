import AppKit
import Foundation

final class MoaMainMenuCoordinator {
    unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
    }

    func configureMenu() {
        app.menu.delegate = app
        app.menu.autoenablesItems = false

        app.versionItem.title = AppDelegate.versionTitle()
        app.versionItem.isEnabled = false
        app.menu.addItem(app.versionItem)
        app.statusItemText.isEnabled = false
        app.menu.addItem(app.statusItemText)
        app.menu.addItem(NSMenuItem.separator())

        app.codexProfilesItem.submenu = app.codexProfilesMenu
        app.menu.addItem(app.codexProfilesItem)
        app.claudeDesktopProfilesItem.submenu = app.claudeDesktopProfilesMenu
        app.menu.addItem(app.claudeDesktopProfilesItem)
        app.zcodeItem.submenu = app.zcodeMenu
        app.menu.addItem(app.zcodeItem)
        app.workbuddyCNItem.submenu = app.workbuddyCNMenu
        app.menu.addItem(app.workbuddyCNItem)
        app.workbuddyItem.submenu = app.workbuddyMenu
        app.menu.addItem(app.workbuddyItem)
        app.deepseekCoordinator.item.submenu = app.deepseekCoordinator.menu
        app.menu.addItem(app.deepseekCoordinator.item)
        app.menu.addItem(NSMenuItem.separator())

        app.moaDataItem.submenu = app.moaDataMenu
        configureMoaDataMenu()
        app.menu.addItem(app.moaDataItem)
        app.menu.addItem(NSMenuItem.separator())

        app.updatePricesItem.target = app
        app.menu.addItem(app.updatePricesItem)
        let checkUpdateItem = NSMenuItem(title: MoaL10n.text("Check Update"), action: #selector(AppDelegate.checkUpdateAction), keyEquivalent: "")
        checkUpdateItem.target = app
        app.menu.addItem(checkUpdateItem)
        app.menu.addItem(NSMenuItem.separator())

        app.menu.addItem(NSMenuItem(title: MoaL10n.text("Quit Moa"), action: #selector(AppDelegate.quitAction), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
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
        app.toggleICloudStorageItem.state = iCloudEnabled ? .on : .off
    }

    func refreshStatus() {
        let isFast = app.controller.isFastEnabled()
        app.fastModeItem.state = isFast ? .on : .off
        app.remoteConnectionsItem.state = .off

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
        app.codexOfficialMenu.addItem(useOfficialModeItem)
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

        app.fastModeItem.target = app
        app.fastModeItem.title = MoaL10n.text("Fast Mode")
        app.codexProfilesMenu.addItem(app.fastModeItem)
        app.remoteConnectionsItem.target = app
        app.remoteConnectionsItem.title = MoaL10n.text("Remote Connection Settings…")
        app.codexProfilesMenu.addItem(app.remoteConnectionsItem)
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
