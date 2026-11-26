import AppKit
import Combine
import SwiftUI

struct MoaWorkspaceSettingsView: View {
    unowned let app: AppDelegate
    @ObservedObject var navigation: MoaWorkspaceNavigation
    @ObservedObject var usage: MoaUsageCoordinator
    @ObservedObject var updates: MoaUpdateCoordinator
    @ObservedObject var launchAtLogin: MoaLaunchAtLoginController
    @ObservedObject var notifications: MoaNotificationManager
    @State private var refresh = Date()
    @State private var showTodayCostInMenuBar: Bool
    @State private var selectedLanguage: MoaAppLanguage
    let languageChanged: Bool

    // Storage location and long data operations announce themselves; no polling.
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
        _showTodayCostInMenuBar = State(initialValue: MoaMenuBarDisplayPreferences.showsTodayCost())
        _selectedLanguage = State(initialValue: MoaAppLanguage.current())
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
                workspaceHeading("Settings and Data", subtitle: "Preferences, storage, prices, and updates.")
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
        }
        .onReceive(stateChanges) { _ in refresh = Date() }
        .accessibilityIdentifier("workspace.settings.content")
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        .disabled(MoaRuntimeMode.suppressesUserInteraction)
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
            actionRow("Export Moa Data", detail: "Export transferable Moa configuration and application data.",
                      button: "Export Data Package", action: app.exportDataPackageAction)
            Divider()
            actionRow("Import Moa Data", detail: "Review the existing import confirmation before replacing data.",
                      button: "Import Data Package", action: app.importDataPackageAction)
            Divider()
            actionRow("Export Diagnostic Package", detail: "Export diagnostic information for troubleshooting.",
                      button: "Export Diagnostic Package", action: app.exportDiagnosticPackageAction)
            Divider()
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
            }
            .padding(24).background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
            actionRow("Custom Prices and Alerts",
                      detail: "Set a price for any model row, and daily usage alerts, in Usage Analysis.",
                      button: "View Usage Analysis") { app.workspaceWindow.navigation.showUsage() }
            Text(MoaWorkspaceCopy.estimateDisclaimer)
                .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    Text(MoaL10n.text("Moa verifies the release checksum and signing identity before replacing the installed app."))
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
