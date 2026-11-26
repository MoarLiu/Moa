import AppKit
import Combine
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let accountOperations = MoaAccountOperationState()
    let controller = CodexAppController()
    let profileController = ConfigProfileController()
    let claudeDesktopProfileController = ClaudeDesktopProfileController()
    let claudeCodeSettingsController = ClaudeCodeSettingsController()
    let zcodeController = ZCodeController()
    lazy var usageCoordinator = MoaUsageCoordinator()
    @MainActor lazy var codexEnhancements = CodexEnhancementCoordinator(controller: controller, operations: accountOperations)
    lazy var workbuddyCoordinator = MoaWorkBuddyCoordinator(app: self, edition: .international)
    lazy var workbuddyCNCoordinator = MoaWorkBuddyCoordinator(app: self, edition: .china)
    lazy var deepseekCoordinator = MoaDeepSeekCoordinator(app: self)
    lazy var antigravityCoordinator = MoaAntigravityCoordinator(app: self)
    lazy var geminiCLICoordinator = MoaGeminiCLICoordinator(app: self)
    let dataPackageController = MoaDataPackageController()
    lazy var backupManager = MoaBackupManager(dataPackages: dataPackageController)
    let updateController = MoaUpdateController()
    lazy var updateCoordinator = MoaUpdateCoordinator(controller: updateController)
    lazy var notificationManager = MoaNotificationManager()
    lazy var launchAtLoginController = MoaLaunchAtLoginController()
    lazy var hotkeyManager = MoaGlobalHotkeyManager()
    lazy var quickSwitcher = MoaQuickSwitcherPanelController(app: self)
    lazy var mainMenuCoordinator = MoaMainMenuCoordinator(app: self)
    lazy var providerActionCoordinator = MoaProviderActionCoordinator(app: self)
    lazy var profileActionCoordinator = MoaProfileActionCoordinator(app: self)
    lazy var accountManagerWindow = MoaAccountManagerWindowController(app: self)
    lazy var workspaceWindow = MoaWorkspaceWindowController(app: self)
    private var appObservers = Set<AnyCancellable>()
    lazy var usageInsightsWindow = MoaUsageInsightsWindowController(
        codexScanner: usageCoordinator.codexScanner,
        claudeScanner: usageCoordinator.claudeScanner,
        zcodeScanner: usageCoordinator.zcodeScanner,
        workbuddyScanner: usageCoordinator.workbuddyScanner,
        workbuddyCNScanner: usageCoordinator.workbuddyCNScanner,
        antigravityScanner: usageCoordinator.antigravityScanner,
        deepseekScanner: usageCoordinator.deepseekScanner,
        usageAlertThresholdProvider: { kind in
            DailyUsageAlertController.threshold(for: kind)
        },
        usageAlertSettingsAction: { [weak self] kind in
            self?.showWorkspaceUsageAlertSettings(kind: kind)
        },
        combinedBudgetSettingsAction: { [weak self] in
            self?.showCombinedUsageBudgetPanel()
        }
    )

    func showWorkspaceUsageAlertSettings(kind: DailyUsageAlertKind) {
        showDailyUsageAlertPanel(kind: kind)
        rebuildProfileMenu()
        rebuildClaudeDesktopProfilesMenu()
        rebuildZCodeMenu()
        rebuildWorkBuddyMenus()
        antigravityCoordinator.rebuildMenu()
        deepseekCoordinator.rebuildMenu()
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let statusItemText = NSMenuItem(title: MoaL10n.format("Status: %@", MoaL10n.text("Ready")), action: nil, keyEquivalent: "")
    var lastMenuRefreshAt = Date.distantPast
    let menuRefreshInterval: TimeInterval = 0.75

    let codexProfilesItem = NSMenuItem(title: "Codex", action: nil, keyEquivalent: "")
    let codexProfilesMenu = NSMenu()
    let claudeDesktopProfilesItem = NSMenuItem(title: "Claude Desktop", action: nil, keyEquivalent: "")
    let claudeDesktopProfilesMenu = NSMenu()
    let zcodeItem = NSMenuItem(title: MoaL10n.text("ZCode"), action: nil, keyEquivalent: "")
    let zcodeMenu = NSMenu(title: MoaL10n.text("ZCode"))
    var workbuddyItem: NSMenuItem { workbuddyCoordinator.item }
    var workbuddyMenu: NSMenu { workbuddyCoordinator.menu }
    var workbuddyCNItem: NSMenuItem { workbuddyCNCoordinator.item }
    var workbuddyCNMenu: NSMenu { workbuddyCNCoordinator.menu }

    let codexDailyUsageAlertItem = NSMenuItem(title: MoaL10n.text("Daily Usage Alert"), action: #selector(showCodexDailyUsageAlertAction), keyEquivalent: "")
    let claudeDailyUsageAlertItem = NSMenuItem(title: MoaL10n.text("Daily Usage Alert"), action: #selector(showClaudeDailyUsageAlertAction), keyEquivalent: "")
    let zcodeDailyUsageAlertItem = NSMenuItem(title: MoaL10n.text("Daily Usage Alert"), action: #selector(showZCodeDailyUsageAlertAction), keyEquivalent: "")
    let codexUsageDetailsItem = NSMenuItem(title: MoaL10n.text("Usage Details"), action: #selector(showCodexUsageDetailsAction), keyEquivalent: "")
    let claudeUsageDetailsItem = NSMenuItem(title: MoaL10n.text("Usage Details"), action: #selector(showClaudeUsageDetailsAction), keyEquivalent: "")
    let zcodeUsageDetailsItem = NSMenuItem(title: MoaL10n.text("Usage Details"), action: #selector(showZCodeUsageDetailsAction), keyEquivalent: "")
    let codexOfficialItem = NSMenuItem(title: MoaL10n.text("Codex Official"), action: nil, keyEquivalent: "")
    let codexOfficialMenu = NSMenu(title: MoaL10n.text("Codex Official"))
    let editProfileItem = NSMenuItem(title: MoaL10n.text("Edit Selected Config"), action: #selector(editProfileAction(_:)), keyEquivalent: "")
    let deleteProfileItem = NSMenuItem(title: MoaL10n.text("Delete Selected Config"), action: #selector(deleteProfileAction(_:)), keyEquivalent: "")
    let importProfilesItem = NSMenuItem(title: MoaL10n.text("Import Config"), action: #selector(importCodexProfilesAction), keyEquivalent: "")
    let exportProfilesItem = NSMenuItem(title: MoaL10n.text("Export Config"), action: #selector(exportCodexProfilesAction), keyEquivalent: "")
    let editClaudeDesktopProviderItem = NSMenuItem(title: MoaL10n.text("Edit Selected Provider"), action: #selector(editClaudeDesktopProviderAction(_:)), keyEquivalent: "")
    let deleteClaudeDesktopProviderItem = NSMenuItem(title: MoaL10n.text("Delete Selected Provider"), action: #selector(deleteClaudeDesktopProviderAction(_:)), keyEquivalent: "")
    let importClaudeDesktopProviderItem = NSMenuItem(title: MoaL10n.text("Import Provider"), action: #selector(importClaudeDesktopProfilesAction), keyEquivalent: "")
    let exportClaudeDesktopProviderItem = NSMenuItem(title: MoaL10n.text("Export Provider"), action: #selector(exportClaudeDesktopProfilesAction), keyEquivalent: "")

    let moaDataItem = NSMenuItem(title: MoaL10n.text("Moa Data"), action: nil, keyEquivalent: "")
    let moaDataMenu = NSMenu(title: MoaL10n.text("Moa Data"))
    let exportDataPackageItem = NSMenuItem(title: MoaL10n.text("Export Data Package"), action: #selector(exportDataPackageAction), keyEquivalent: "")
    let importDataPackageItem = NSMenuItem(title: MoaL10n.text("Import Data Package"), action: #selector(importDataPackageAction), keyEquivalent: "")
    let exportDiagnosticPackageItem = NSMenuItem(title: MoaL10n.text("Export Diagnostic Package"), action: #selector(exportDiagnosticPackageAction), keyEquivalent: "")
    let toggleICloudStorageItem = NSMenuItem(title: MoaL10n.text("Store Data in iCloud"), action: #selector(toggleICloudStorageAction), keyEquivalent: "")
    let openMoaDataFolderItem = NSMenuItem(title: MoaL10n.text("Open Moa Data Folder"), action: #selector(openMoaDataFolderAction), keyEquivalent: "")
    let openICloudDataFolderItem = NSMenuItem(title: MoaL10n.text("Open iCloud Data Folder"), action: #selector(openICloudDataFolderAction), keyEquivalent: "")
    let versionItem = NSMenuItem(title: "Moa", action: nil, keyEquivalent: "")
    let updatePricesItem = NSMenuItem(title: MoaL10n.text("Update Prices"), action: #selector(updatePricesAction), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if MoaRuntimeMode.isWorkspacePreview {
            configureApplicationMenu()
            workspaceWindow.show(.overview)
            return
        }
        repairLegacyICloudDataSplitIfNeeded()
        configureApplicationMenu()
        configureStatusItem()
        configureMenu()
        refreshStatus()
        usageInsightsWindow.presentInWorkspace = { [weak self] source in
            guard let self else { return }
            self.workspaceWindow.navigation.showUsage(source)
            self.workspaceWindow.show()
        }
        usageInsightsWindow.workspaceVisibility = { [weak self] in
            self?.workspaceWindow.isVisible == true && self?.workspaceWindow.navigation.destination == .usage
        }
        usageInsightsWindow.workspacePricingChanged = { [weak self] in
            self?.workspaceWindow.navigation.refreshRequest = UUID()
        }
        configureUsageAlertCallbacks()
        configureNotificationCallbacks()
        configureStatusBarObservers()
        configureHotkeys()
        usageCoordinator.start()
        codexEnhancements.start()
        updateCoordinator.start()
        hotkeyManager.start()
    }

    private func configureHotkeys() {
        hotkeyManager.onTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .quickSwitcher:
                self.quickSwitcher.toggle()
            case .openWorkspace:
                self.workspaceWindow.show(.overview)
            case .openUsage:
                self.workspaceWindow.navigation.showUsage()
                self.workspaceWindow.show()
            }
        }
    }

    private func configureNotificationCallbacks() {
        notificationManager.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .openUsage(let source):
                self.workspaceWindow.navigation.showUsage(source)
                self.workspaceWindow.show()
            case .openSettingsAbout:
                self.workspaceWindow.navigation.showSettings(.about)
                self.workspaceWindow.show()
            }
        }
        updateCoordinator.onBackgroundUpdateDiscovered = { [weak self] update in
            guard let self else { return }
            let buildText = update.build.map { " (\($0))" } ?? ""
            let title = MoaL10n.text("Moa Update Available")
            let body = MoaL10n.format("Moa %@ is available. Open Settings → About to review and install.", "\(update.version)\(buildText)")
            self.notificationManager.post(
                identifier: "moa.update.\(MoaUpdateCoordinator.releaseSignature(for: update))",
                title: title,
                body: body,
                action: .openSettingsAbout,
                allowsAuthorizationPrompt: false,
                fallbackOnDenied: false
            )
            self.mainMenuCoordinator.refreshUpdateIndicator()
        }
    }

    private func configureStatusBarObservers() {
        appObservers.removeAll()
        usageCoordinator.$workspaceSummaries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemDisplay() }
            .store(in: &appObservers)
        updateCoordinator.$availableUpdate
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.mainMenuCoordinator.refreshUpdateIndicator() }
            .store(in: &appObservers)
        NotificationCenter.default.publisher(for: MoaMenuBarDisplayPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemDisplay() }
            .store(in: &appObservers)
        NotificationCenter.default.publisher(for: MoaClientPreferences.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.mainMenuCoordinator.arrangeClientItems()
            }
            .store(in: &appObservers)
        NotificationCenter.default.publisher(for: MoaAppLanguage.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.configureApplicationMenu()
                self.configureMenu()
                self.refreshStatus()
                self.workspaceWindow.navigation.refreshRequest = UUID()
            }
            .store(in: &appObservers)
    }

    func updateStatusItemDisplay() {
        guard let button = statusItem.button else { return }
        let showTodayCost = MoaMenuBarDisplayPreferences.showsTodayCost()
        let title = MoaMenuBarDisplayPreferences.statusItemTitle(
            summaries: usageCoordinator.workspaceSummaries,
            showTodayCost: showTodayCost
        )
        if showTodayCost {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        workspaceWindow.show()
        return false
    }

    private func configureUsageAlertCallbacks() {
        usageCoordinator.onPricingUpdated = { [weak self] in self?.usageInsightsWindow.refreshAfterPricingUpdate() }
        usageCoordinator.onPricingRefreshStateChanged = { [weak self] updating in
            self?.updatePricesItem.title = MoaL10n.text(updating ? "Updating Prices…" : "Update Prices")
            self?.updatePricesItem.isEnabled = !updating
            self?.mainMenuCoordinator.updateVisibleStatus()
        }
        usageCoordinator.needsFrequentRefresh = { [weak self] source in
            let alertEnabled = DailyUsageAlertKind(rawValue: source.rawValue).flatMap { DailyUsageAlertController.threshold(for: $0) } != nil
            return alertEnabled
                || DailyUsageAlertController.hasAnyCombinedBudget()
                || self?.usageInsightsWindow.isVisible == true
        }
        usageCoordinator.onCodexSummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .codex, summary: summary)
        }
        usageCoordinator.onClaudeSummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .claude, summary: summary)
        }
        usageCoordinator.onZCodeSummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .zcode, summary: summary)
        }
        usageCoordinator.onWorkBuddySummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .workbuddy, summary: summary)
        }
        usageCoordinator.onWorkBuddyCNSummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .workbuddyCN, summary: summary)
        }
        usageCoordinator.onAntigravitySummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .antigravity, summary: summary)
        }
        usageCoordinator.onDeepSeekSummaryLoaded = { [weak self] summary in
            self?.maybeShowDailyUsageAlert(kind: .deepseek, summary: summary)
        }
        usageCoordinator.onCombinedUsageUpdated = { [weak self] summaries in
            self?.maybeShowCombinedUsageBudgetAlerts(summaries: summaries)
        }
    }

    private func repairLegacyICloudDataSplitIfNeeded() {
        do {
            if try dataPackageController.repairLegacyICloudDataSplitIfNeeded() {
                NSLog("Moa repaired missing files from legacy iCloud data root")
            }
        } catch {
            NSLog("Moa legacy iCloud data repair failed: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !MoaRuntimeMode.isWorkspacePreview else { return }
        hotkeyManager.stop()
        updateCoordinator.stop()
        codexEnhancements.stop()
        usageCoordinator.stop()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: MoaL10n.text("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let quick = NSMenuItem(title: MoaL10n.text("Quick Switcher…"), action: #selector(showQuickSwitcherAction), keyEquivalent: "k")
        quick.target = self
        appMenu.addItem(quick)
        let overview = NSMenuItem(title: MoaL10n.text("Overview"), action: #selector(showWorkspaceAction), keyEquivalent: "0")
        overview.target = self
        appMenu.addItem(overview)
        let accounts = NSMenuItem(title: MoaL10n.text("Accounts…"), action: #selector(showAllAccountsAction), keyEquivalent: "a")
        accounts.keyEquivalentModifierMask = [.command, .shift]
        accounts.target = self
        appMenu.addItem(accounts)
        let usage = NSMenuItem(title: MoaL10n.text("Usage Overview…"), action: #selector(showUsageOverviewAction), keyEquivalent: "u")
        usage.target = self
        appMenu.addItem(usage)
        let refresh = NSMenuItem(title: MoaL10n.text("Refresh"), action: #selector(refreshUsageAction), keyEquivalent: "r")
        refresh.target = self
        appMenu.addItem(refresh)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: MoaL10n.text("Quit Moa"), action: #selector(quitAction), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: MoaL10n.text("Edit"))
        editMenu.addItem(NSMenuItem(title: MoaL10n.text("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: MoaL10n.text("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: MoaL10n.text("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: MoaL10n.text("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = MoaL10n.text("Moa - Codex, Claude, ZCode, WorkBuddy, WorkBuddy AI, DeepSeek, Antigravity")
        }
        updateStatusItemDisplay()
        statusItem.menu = menu
    }

    static func versionTitle() -> String {
        let version = MoaUpdateController.currentVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let version, !version.isEmpty else {
            return "Moa"
        }

        if let build, !build.isEmpty {
            return "Moa \(version) (\(build))"
        }

        return "Moa \(version)"
    }

    static func statusTitle(_ key: String, _ arguments: CVarArg...) -> String {
        let message = String(format: MoaL10n.text(key), arguments: arguments)
        return MoaL10n.format("Status: %@", message)
    }

    static func tomlEscaped(_ value: String) -> String {
        MoaTomlEditor.escapedStringContent(value)
    }

    static func shellEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    static func identifierSlug(_ value: String) -> String {
        ConfigProfileController.providerIdentifierSlug(value)
    }

    private static func makeMenuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "MoaMenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 19, height: 19)
            image.isTemplate = true
            image.accessibilityDescription = "Moa"
            return image
        }

        let image = NSImage(size: NSSize(width: 19, height: 19))
        image.lockFocus()

        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 1.0, y: 1.0, width: 17.0, height: 17.0))
        ring.lineWidth = 1.6
        ring.stroke()

        NSColor.white.setFill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: 9.9, y: 15.0))
        bolt.line(to: NSPoint(x: 6.8, y: 9.0))
        bolt.line(to: NSPoint(x: 9.2, y: 9.0))
        bolt.line(to: NSPoint(x: 8.0, y: 4.0))
        bolt.line(to: NSPoint(x: 12.7, y: 10.1))
        bolt.line(to: NSPoint(x: 10.2, y: 10.1))
        bolt.line(to: NSPoint(x: 11.1, y: 15.0))
        bolt.close()
        bolt.fill()

        image.unlockFocus()
        image.isTemplate = false
        image.size = NSSize(width: 19, height: 19)
        image.accessibilityDescription = "Moa"
        return image
    }
}
