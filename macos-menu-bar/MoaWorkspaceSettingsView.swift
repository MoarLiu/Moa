import AppKit
import Combine
import SwiftUI

struct MoaWorkspaceSettingsView: View {
    private enum PriceCatalogFilter: String, CaseIterable, Identifiable {
        case all
        case customOnly
        case unpricedOrFallback

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return MoaL10n.text("All Models")
            case .customOnly: return MoaL10n.text("Custom Overrides")
            case .unpricedOrFallback: return MoaL10n.text("Fallback / Unpriced")
            }
        }
    }

    unowned let app: AppDelegate
    @ObservedObject var navigation: MoaWorkspaceNavigation
    @ObservedObject var usage: MoaUsageCoordinator
    @ObservedObject var updates: MoaUpdateCoordinator
    @ObservedObject var launchAtLogin: MoaLaunchAtLoginController
    @ObservedObject var notifications: MoaNotificationManager
    @ObservedObject var hotkeys: MoaGlobalHotkeyManager
    @State private var refresh = Date()
    @State private var showTodayCostInMenuBar: Bool
    @State private var selectedLanguage: MoaAppLanguage
    @State private var clientOrder: [MoaWorkspaceClient]
    @State private var hiddenClients: Set<MoaWorkspaceClient>
    @State private var backupInventory = MoaBackupInventory()
    @State private var priceSearchQuery = ""
    @State private var priceFilter: PriceCatalogFilter = .all
    @State private var priceSourceFilter: MoaUsageSource?
    @State private var catalogEntries: [MoaUsagePricing.CatalogPriceItem] = []
    @State private var fallbackRows: [MoaUsageDetailRow] = []
    @State private var recordingAction: MoaHotKeyAction?
    @State private var keyMonitor: Any?
    @State private var copiedCLICommand = false
    let languageChanged: Bool

    private let pricingOverrides = MoaUsagePricingOverrideController()

    private let stateChanges = NotificationCenter.default.publisher(for: MoaDataAccessCoordinator.busyStateDidChange)
        .merge(with: NotificationCenter.default.publisher(for: MoaDataRoot.didChangeNotification))
        .receive(on: RunLoop.main)

    init(app: AppDelegate, navigation: MoaWorkspaceNavigation, languageChanged: Bool = false) {
        self.app = app
        self.navigation = navigation
        self.languageChanged = languageChanged
        self.usage = app.usageCoordinator
        self.updates = app.updateCoordinator
        self.launchAtLogin = app.launchAtLoginController
        self.notifications = app.notificationManager
        self.hotkeys = app.hotkeyManager
        _showTodayCostInMenuBar = State(initialValue: MoaMenuBarDisplayPreferences.showsTodayCost())
        _selectedLanguage = State(initialValue: MoaAppLanguage.current())
        _clientOrder = State(initialValue: MoaClientPreferences.orderedClients())
        _hiddenClients = State(initialValue: MoaClientPreferences.hiddenClients())
    }

    init(app: AppDelegate, initialTab: MoaWorkspaceSettingsTab = .general) {
        let nav = MoaWorkspaceNavigation()
        nav.settingsTab = initialTab
        self.init(app: app, navigation: nav)
    }

    private var disabled: Bool {
        _ = refresh
        return MoaRuntimeMode.suppressesUserInteraction || app.dataPackageController.isDataOperationInProgress
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                workspaceHeading("Settings and Data", subtitle: "Preferences, shortcuts, storage, backups, prices, and updates.")
                Picker(MoaL10n.text("Settings and Data"), selection: $navigation.settingsTab) {
                    Text(MoaL10n.text("General")).tag(MoaWorkspaceSettingsTab.general)
                    Text(MoaL10n.text("Data and Storage")).tag(MoaWorkspaceSettingsTab.data)
                    Text(MoaL10n.text("Model Prices")).tag(MoaWorkspaceSettingsTab.prices)
                    Text(MoaL10n.text("About")).tag(MoaWorkspaceSettingsTab.about)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(MoaL10n.text("Settings and Data"))
                .frame(maxWidth: 560)

                switch navigation.settingsTab {
                case .general: generalSettings
                case .data: dataSettings
                case .prices: priceSettings
                case .about: about
                }
            }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            launchAtLogin.refresh()
            notifications.refreshAuthorizationState()
            reloadBackups()
            reloadPriceCatalog()
        }
        .onDisappear {
            stopRecordingShortcut()
        }
        .onReceive(stateChanges) { _ in
            refresh = Date()
            reloadBackups()
            reloadPriceCatalog()
        }
        .onReceive(NotificationCenter.default.publisher(for: MoaClientPreferences.didChangeNotification).receive(on: RunLoop.main)) { _ in
            clientOrder = MoaClientPreferences.orderedClients()
            hiddenClients = MoaClientPreferences.hiddenClients()
        }
        .accessibilityIdentifier("workspace.settings.content")
    }

    // MARK: - General

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            desktopPreferencesCard
            notificationsAndUpdatesCard
            globalHotkeysCard
            clientVisibilityCard
        }
        .disabled(MoaRuntimeMode.suppressesUserInteraction)
    }

    private var desktopPreferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MoaL10n.text("Desktop & Menu Bar")).font(.system(size: 16, weight: .medium))

            if launchAtLogin.status == .unsupportedOS {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoaL10n.text("Launch Moa at Login")).font(.system(size: 13, weight: .medium))
                    Text(MoaL10n.text("Automatic Launch at Login requires macOS 13 or later. On macOS 12, add Moa in System Preferences → Users & Groups → Login Items."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Toggle(MoaL10n.text("Launch Moa at Login"), isOn: Binding(
                        get: { !MoaRuntimeMode.isWorkspacePreview && launchAtLogin.status.isEnabled },
                        set: { enabled in _ = launchAtLogin.setEnabled(enabled) }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 13))
                    Spacer()
                    if launchAtLogin.status == .requiresApproval {
                        Button(MoaL10n.text("Open Login Items Settings")) {
                            launchAtLogin.openSystemSettings()
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                    }
                }
                if launchAtLogin.status == .requiresApproval {
                    Text(MoaL10n.text("Approval required in System Settings → General → Login Items."))
                        .font(.system(size: 12)).foregroundStyle(MoaTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.system(size: 12)).foregroundStyle(MoaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(MoaL10n.text("Show Today's Usage in Menu Bar"), isOn: Binding(
                    get: { !MoaRuntimeMode.isWorkspacePreview && showTodayCostInMenuBar },
                    set: { enabled in
                        showTodayCostInMenuBar = enabled
                        MoaMenuBarDisplayPreferences.setShowsTodayCost(enabled)
                    }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 13))
                Text(MoaL10n.text("Display today's aggregated local API estimate next to the menu bar icon."))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoaL10n.text("Language")).font(.system(size: 13, weight: .medium))
                    Text(MoaL10n.text("Choose the display language for Moa menus and workspace."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                }
                Spacer()
                Picker(MoaL10n.text("Language"), selection: Binding(
                    get: { selectedLanguage },
                    set: { next in
                        guard next != selectedLanguage else { return }
                        selectedLanguage = next
                        MoaAppLanguage.set(next)
                    }
                )) {
                    ForEach(MoaAppLanguage.allCases) { language in
                        Text(language.displayTitle).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            if languageChanged {
                HStack(spacing: 12) {
                    Text(MoaL10n.text("Reopen Moa if any system menu or dialog still uses the previous language."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(MoaL10n.text("Reopen Moa")) { app.relaunchMoaAction() }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                }
            }
        }
        .padding(24)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private var notificationsAndUpdatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MoaL10n.text("Notifications & Updates")).font(.system(size: 16, weight: .medium))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoaL10n.text("System Notifications")).font(.system(size: 13, weight: .medium))
                    Text(notificationStatusText)
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if notifications.authorizationState == .notDetermined {
                    Button(MoaL10n.text("Allow Notifications")) {
                        notifications.requestAuthorizationIfNeeded()
                    }
                    .buttonStyle(MoaWorkspaceButtonStyle())
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(MoaL10n.text("Automatically Check for Updates"), isOn: Binding(
                    get: { updates.autoCheckEnabled },
                    set: { updates.autoCheckEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 13))
                Text(MoaL10n.text("Check GitHub Releases once a day in the background and show a subtle indicator when a newer release is ready."))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private var globalHotkeysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(MoaL10n.text("Global Shortcuts")).font(.system(size: 16, weight: .medium))
                Text(MoaL10n.text("Optional system-wide shortcuts (disabled by default; requires no Accessibility permission)."))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(MoaHotKeyAction.allCases) { action in
                let binding = hotkeys.shortcut(for: action)
                let isRecording = recordingAction == action
                HStack(spacing: 12) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if isRecording {
                        Text(MoaL10n.text("Press shortcut…"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MoaWorkspaceTheme.accent)
                        Button(MoaL10n.text("Cancel")) { stopRecordingShortcut() }
                            .buttonStyle(MoaWorkspaceButtonStyle())
                    } else if let binding {
                        Text(binding.displayString)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MoaWorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 6))
                        Button(MoaL10n.text("Record")) { beginRecordingShortcut(for: action) }
                            .buttonStyle(MoaWorkspaceButtonStyle())
                        Button(MoaL10n.text("Clear")) { hotkeys.setShortcut(nil, for: action) }
                            .buttonStyle(MoaWorkspaceButtonStyle())
                    } else {
                        Button(MoaL10n.format("Enable (%@)", action.suggestedShortcut.displayString)) {
                            hotkeys.setShortcut(action.suggestedShortcut, for: action)
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                        Button(MoaL10n.text("Record")) { beginRecordingShortcut(for: action) }
                            .buttonStyle(MoaWorkspaceButtonStyle())
                    }
                }
                if action != MoaHotKeyAction.allCases.last { Divider() }
            }
        }
        .padding(24)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private var clientVisibilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoaL10n.text("Clients Order & Visibility")).font(.system(size: 16, weight: .medium))
                    Text(MoaL10n.text("Customize which AI clients appear in the sidebar and menu bar, and adjust their order."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(MoaL10n.text("Reset Order")) {
                    MoaClientPreferences.resetDefaults()
                }
                .buttonStyle(MoaWorkspaceButtonStyle())
            }

            Divider()

            ForEach(Array(clientOrder.enumerated()), id: \.element.id) { index, client in
                let isVisible = !hiddenClients.contains(client)
                HStack(spacing: 12) {
                    MoaClientLogo(client: client, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.title).font(.system(size: 13, weight: .medium))
                        Text(client.capability).font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    }
                    Spacer()
                    Button {
                        MoaClientPreferences.moveClient(client, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        MoaClientPreferences.moveClient(client, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == clientOrder.count - 1)

                    Toggle("", isOn: Binding(
                        get: { isVisible },
                        set: { show in MoaClientPreferences.setHidden(!show, for: client) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(isVisible && hiddenClients.count + 1 >= MoaWorkspaceClient.allCases.count)
                }
                if index < clientOrder.count - 1 { Divider() }
            }
        }
        .padding(24)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func beginRecordingShortcut(for action: MoaHotKeyAction) {
        stopRecordingShortcut()
        recordingAction = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 { // Escape cancels recording
                stopRecordingShortcut()
                return nil
            }
            let mods = MoaHotKeyShortcut.carbonModifiers(from: event.modifierFlags)
            let shortcut = MoaHotKeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
            if shortcut.isValid {
                hotkeys.setShortcut(shortcut, for: action)
                stopRecordingShortcut()
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private func stopRecordingShortcut() {
        recordingAction = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private var notificationStatusText: String {
        if MoaRuntimeMode.isWorkspacePreview {
            return MoaL10n.text("Used for daily usage alerts and update notifications.")
        }
        switch notifications.authorizationState {
        case .authorized:
            return MoaL10n.text("Enabled. Daily usage alerts appear in Notification Center without stealing focus.")
        case .notDetermined:
            return MoaL10n.text("Not requested yet. Moa asks when you enable a daily usage alert.")
        case .denied:
            return MoaL10n.text("Disabled in macOS System Settings. Moa falls back to menu bar status banners.")
        case .unavailable:
            return MoaL10n.text("System notifications are available when running the bundled Moa.app.")
        }
    }

    // MARK: - Data, Encrypted Export & Backup Recovery Center

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(MoaL10n.text("Data Storage")).font(.system(size: 16, weight: .medium))
                    Spacer()
                    Button(MoaL10n.text("Open Moa Data Folder")) { app.openMoaDataFolderAction() }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                }
                Text(MoaRuntimeMode.isWorkspacePreview
                     ? MoaL10n.text("Preview uses no saved accounts or credentials.")
                     : MoaDataRoot.currentURL().path)
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Toggle(MoaL10n.text("Store Data in iCloud"), isOn: Binding(
                    get: {
                        _ = refresh
                        return !MoaRuntimeMode.isWorkspacePreview && MoaDataRoot.isICloudStorageEnabled()
                    },
                    set: { _ in app.toggleICloudStorageAction() }
                )).toggleStyle(.switch).font(.system(size: 13))
            }
            .padding(24).background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))

            Text(MoaL10n.text("Migration and Maintenance")).font(.system(size: 17, weight: .medium))
            actionRow("Export Moa Data", detail: "Export full or config-only packages with optional AES-256-GCM encryption (Schema 3).",
                      button: "Export Data Package", action: app.exportDataPackageAction)
            Divider()
            actionRow("Import Moa Data", detail: "Supports Schema 1/2 plaintext and Schema 3 encrypted packages with automatic rollback.",
                      button: "Import Data Package", action: app.importDataPackageAction)
            Divider()
            actionRow("Export Diagnostic Package", detail: "Export redacted diagnostic information for troubleshooting.",
                      button: "Export Diagnostic Package", action: app.exportDiagnosticPackageAction)
            Divider()

            backupRecoverySection

            workspaceNotice(MoaL10n.text("Some account credentials are excluded from data packages and iCloud migration. Shared data storage does not synchronize every client login."),
                            tone: MoaTheme.amber)
            if app.dataPackageController.isDataOperationInProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(MoaL10n.text("Updating Moa data…")).font(.system(size: 13))
                }
            }
        }.disabled(disabled)
    }

    private var backupRecoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MoaL10n.text("Backups & Recovery Center")).font(.system(size: 16, weight: .medium))
                    Text(MoaL10n.text("Inspect automatic rollback snapshots, Codex config backups, and legacy unencrypted Downloads archives."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(MoaL10n.text("Refresh")) { reloadBackups() }
                    .buttonStyle(MoaWorkspaceButtonStyle())
            }

            if !backupInventory.legacyDownloadsBackups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MoaL10n.format("Unencrypted Legacy Backups Found in Downloads (%lld)", backupInventory.legacyDownloadsBackups.count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MoaTheme.amber)
                    ForEach(backupInventory.legacyDownloadsBackups) { entry in
                        backupEntryRow(entry, allowRestore: false)
                    }
                }
                .padding(14)
                .background(MoaWorkspaceTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoaTheme.amber.opacity(0.45), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(MoaL10n.format("Automatic Recovery Packages (%lld / 12)", backupInventory.recoveryPackages.count))
                    .font(.system(size: 13, weight: .semibold))
                if backupInventory.recoveryPackages.isEmpty {
                    Text(MoaL10n.text("No recovery packages stored yet. Moa creates one automatically before data imports or iCloud storage moves."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                } else {
                    ForEach(backupInventory.recoveryPackages) { entry in
                        backupEntryRow(entry, allowRestore: true)
                        if entry.id != backupInventory.recoveryPackages.last?.id { Divider() }
                    }
                }
            }

            if !backupInventory.codexSnapshots.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(MoaL10n.format("Codex Configuration Snapshots (%lld)", backupInventory.codexSnapshots.count))
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(backupInventory.codexSnapshots.prefix(12)) { entry in
                        backupEntryRow(entry, allowRestore: false)
                        if entry.id != backupInventory.codexSnapshots.prefix(12).last?.id { Divider() }
                    }
                }
            }
        }
        .padding(22)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func backupEntryRow(_ entry: MoaBackupEntry, allowRestore: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.triggerTitle)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 6) {
                    Text(Self.updatedText(entry.createdAt))
                    Text("·")
                    Text(MoaBackupManager.formattedSize(entry.sizeBytes)).monospacedDigit()
                    if let summary = entry.containsItemsSummary, !summary.isEmpty {
                        Text("·")
                        Text(summary).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(MoaWorkspaceTheme.secondary)
            }
            Spacer()
            if allowRestore {
                Button(MoaL10n.text("Restore")) {
                    app.restoreRecoveryBackup(entry) { reloadBackups() }
                }
                .buttonStyle(MoaWorkspaceButtonStyle())
            }
            Button(MoaL10n.text("Reveal")) {
                app.backupManager.revealInFinder(entry)
            }
            .buttonStyle(MoaWorkspaceButtonStyle())
            Button(MoaL10n.text(entry.kind == .legacyDownloadsBackup ? "Trash" : "Delete")) {
                app.deleteBackupEntry(entry) { reloadBackups() }
            }
            .buttonStyle(MoaWorkspaceButtonStyle())
        }
    }

    private func reloadBackups() {
        guard !MoaRuntimeMode.isWorkspacePreview else { return }
        backupInventory = app.backupManager.loadInventory()
    }

    // MARK: - Model Prices Management Center

    private var filteredCatalogEntries: [MoaUsagePricing.CatalogPriceItem] {
        let query = priceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalogEntries.filter { item in
            if priceFilter == .customOnly && !item.isCustomOverride { return false }
            if let source = priceSourceFilter, item.source != source { return false }
            guard !query.isEmpty else { return true }
            return item.model.lowercased().contains(query) || item.source.title.lowercased().contains(query)
        }
    }

    private var priceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(MoaL10n.text("Reference Price Table")).font(.system(size: 16, weight: .medium))
                    Spacer()
                    if usage.isUpdatingPrices { ProgressView().controlSize(.small) }
                    Button(MoaL10n.text(usage.isUpdatingPrices ? "Updating Prices…" : "Update Prices")) {
                        app.updatePricesAction()
                    }
                    .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
                    .disabled(disabled || usage.isUpdatingPrices)
                }
                priceFact("Last Updated", value: MoaRuntimeMode.isWorkspacePreview ? "—" : Self.updatedText(usage.pricesLastUpdatedAt))
                priceFact("Source", value: usage.pricingSourceHost)
                priceFact("Models with Prices", value: MoaRuntimeMode.isWorkspacePreview ? "—" : "\(usage.pricingModelCount)")
                priceFact("Custom Overrides", value: MoaRuntimeMode.isWorkspacePreview ? "—" : "\(catalogEntries.filter(\.isCustomOverride).count)")
            }
            .padding(24).background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(MoaL10n.text("Price Catalog & Custom Overrides")).font(.system(size: 16, weight: .medium))
                    Spacer()
                    if catalogEntries.contains(where: \.isCustomOverride) {
                        Button(MoaL10n.text("Reset All Custom Prices")) {
                            resetAllCustomPrices()
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                        .disabled(disabled)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker(MoaL10n.text("Price Filter"), selection: $priceFilter) {
                        ForEach(PriceCatalogFilter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    HStack(spacing: 10) {
                        Picker(MoaL10n.text("Usage Source"), selection: Binding(
                            get: { priceSourceFilter?.rawValue ?? "all" },
                            set: { priceSourceFilter = MoaUsageSource(rawValue: $0) }
                        )) {
                            Text(MoaL10n.text("All Sources")).tag("all")
                            ForEach(MoaUsageSource.allCases, id: \.rawValue) { source in
                                Text(source.title).tag(source.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)

                        Spacer()

                        TextField(MoaL10n.text("Search model…"), text: $priceSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                Divider()

                if priceFilter == .unpricedOrFallback {
                    if fallbackRows.isEmpty {
                        Text(MoaL10n.text("No unpriced or fallback models detected in local usage logs."))
                            .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    } else {
                        ForEach(fallbackRows) { row in
                            HStack(spacing: 10) {
                                Text(row.source.title).font(.system(size: 12, weight: .medium))
                                Text(row.model).font(.system(size: 12)).textSelection(.enabled)
                                Spacer()
                                Text(row.pricingModel == "unpriced" ? MoaL10n.text("Unpriced") : MoaL10n.format("priced as %@", row.pricingModel))
                                    .font(.system(size: 11)).foregroundStyle(MoaTheme.amber)
                                Button(MoaL10n.text("Set Price")) {
                                    editPrice(source: row.source, model: row.model)
                                }
                                .buttonStyle(MoaWorkspaceButtonStyle())
                            }
                            Divider()
                        }
                    }
                } else {
                    let entries = filteredCatalogEntries
                    if entries.isEmpty {
                        Text(MoaL10n.text("No models match the current filter."))
                            .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    } else {
                        ForEach(entries.prefix(50)) { entry in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.model).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        if entry.isCustomOverride {
                                            Text(MoaL10n.text("Custom"))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(MoaWorkspaceTheme.accent)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(MoaWorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    Text(entry.source.title)
                                        .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(String(format: "In $%.2f · Out $%.2f", entry.inputUSDPerMillion, entry.outputUSDPerMillion))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                                if let cacheRead = entry.cacheReadUSDPerMillion {
                                    Text(String(format: "Cache $%.3f", cacheRead))
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundStyle(MoaWorkspaceTheme.secondary)
                                }

                                Button(MoaL10n.text(entry.isCustomOverride ? "Edit" : "Override")) {
                                    editPrice(source: entry.source, model: entry.model)
                                }
                                .buttonStyle(MoaWorkspaceButtonStyle())
                                .disabled(disabled)

                                if entry.isCustomOverride {
                                    Button(MoaL10n.text("Reset")) {
                                        try? pricingOverrides.remove(source: entry.source, model: entry.model)
                                        reloadPriceCatalog()
                                        app.usageCoordinator.refreshAllUsage()
                                    }
                                    .buttonStyle(MoaWorkspaceButtonStyle())
                                    .disabled(disabled)
                                }
                            }
                            Divider()
                        }
                        if entries.count > 50 {
                            Text(MoaL10n.format("Showing 50 of %lld models. Narrow with search to view more.", entries.count))
                                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))

            Text(MoaWorkspaceCopy.estimateDisclaimer)
                .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reloadPriceCatalog() {
        guard !MoaRuntimeMode.isWorkspacePreview else { return }
        catalogEntries = MoaUsagePricing.catalogEntries(overrides: pricingOverrides)
        DispatchQueue.global(qos: .utility).async {
            let batch = app.usageCoordinator.loadCombinedReport(forceRefresh: false)
            let rows = batch.report?.fallbackRows ?? []
            DispatchQueue.main.async {
                fallbackRows = rows
            }
        }
    }

    private func editPrice(source: MoaUsageSource, model: String) {
        if MoaCustomPriceModal.present(source: source, model: model, pricingOverrides: pricingOverrides, onError: { app.showError($0.localizedDescription) }) {
            reloadPriceCatalog()
            app.usageCoordinator.refreshAllUsage()
        }
    }

    private func resetAllCustomPrices() {
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Reset All Custom Prices?"),
            informativeText: MoaL10n.text("Removes all custom model price overrides and restores reference catalog pricing."),
            primaryButtonTitle: MoaL10n.text("Reset"),
            tone: .warning
        ) else { return }
        do {
            try pricingOverrides.removeAll()
            reloadPriceCatalog()
            app.usageCoordinator.refreshAllUsage()
        } catch {
            app.showError(error.localizedDescription)
        }
    }

    private func priceFact(_ label: String, value: String) -> some View {
        HStack {
            Text(MoaL10n.text(label)).foregroundStyle(MoaWorkspaceTheme.secondary)
            Spacer()
            Text(value).monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 13))
    }

    private static func updatedText(_ date: Date?, emptyKey: String = "Not updated yet") -> String {
        guard let date else { return MoaL10n.text(emptyKey) }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    // MARK: - About & CLI Companion

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(AppDelegate.versionTitle()).font(.system(size: 24, weight: .semibold))
            Text(MoaWorkspaceCopy.independenceNote)
                .font(.system(size: 13)).foregroundStyle(MoaWorkspaceTheme.secondary)

            if let update = updates.availableUpdate {
                let buildText = update.build.map { " (\($0))" } ?? ""
                VStack(alignment: .leading, spacing: 12) {
                    Text(MoaL10n.format("Update Available: Moa %@", "\(update.version)\(buildText)"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(MoaL10n.text("Moa verifies the release checksum, signed release manifest (when present), and signing identity before replacing the installed app."))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(MoaL10n.text("Download and Install")) {
                            app.installUpdate(update)
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
                        .disabled(disabled)
                        Button(MoaL10n.text("Open GitHub Releases")) {
                            NSWorkspace.shared.open(update.releaseURL)
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoaWorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 12) {
                priceFact("Last Checked", value: MoaRuntimeMode.isWorkspacePreview ? "—" : Self.updatedText(updates.lastCheckedAt, emptyKey: "Not checked yet"))
                HStack(spacing: 12) {
                    Button(MoaL10n.text(updates.isChecking ? "Checking for updates..." : "Check Update")) {
                        app.checkUpdateAction()
                    }
                    .buttonStyle(MoaWorkspaceButtonStyle())
                    .disabled(disabled || updates.isChecking)
                    if updates.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text(MoaL10n.text("Read-Only CLI Companion")).font(.system(size: 16, weight: .medium))
                Text(MoaL10n.text("Query local status, usage, credential health, and backups from Terminal (`moa status`, `moa usage --today --json`, `moa health`, `moa accounts`, `moa backups`). Strictly read-only."))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(MoaCLICompanion.installCommandHint)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MoaWorkspaceTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
                    Button(MoaL10n.text(copiedCLICommand ? "Copied" : "Copy Command")) {
                        app.copyToPasteboard(MoaCLICompanion.installCommandHint)
                        copiedCLICommand = true
                    }
                    .buttonStyle(MoaWorkspaceButtonStyle())
                    .disabled(MoaRuntimeMode.suppressesUserInteraction)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func actionRow(_ title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(MoaL10n.text(title)).font(.system(size: 14, weight: .medium))
                Text(MoaL10n.text(detail)).font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(MoaL10n.text(button), action: action).buttonStyle(MoaWorkspaceButtonStyle())
        }.frame(minHeight: 74)
    }
}
