import AppKit
import Combine
import SwiftUI

struct MoaWorkspaceSettingsView: View {
    unowned let app: AppDelegate
    @ObservedObject var usage: MoaUsageCoordinator
    @State private var tab = 0
    @State private var refresh = Date()
    // Storage location and long data operations announce themselves; no polling.
    private let stateChanges = NotificationCenter.default.publisher(for: MoaDataAccessCoordinator.busyStateDidChange)
        .merge(with: NotificationCenter.default.publisher(for: MoaDataRoot.didChangeNotification))
        .receive(on: RunLoop.main)

    init(app: AppDelegate, initialTab: Int = 0) {
        self.app = app
        usage = app.usageCoordinator
        _tab = State(initialValue: initialTab)
    }

    private var disabled: Bool {
        _ = refresh
        return MoaRuntimeMode.suppressesUserInteraction || app.dataPackageController.isDataOperationInProgress
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                workspaceHeading("Settings and Data", subtitle: "Storage, prices, and updates.")
                Picker(MoaL10n.text("Settings and Data"), selection: $tab) {
                    Text(MoaL10n.text("Data and Storage")).tag(0)
                    Text(MoaL10n.text("Model Prices")).tag(1)
                    Text(MoaL10n.text("About")).tag(2)
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityLabel(MoaL10n.text("Settings and Data")).frame(maxWidth: 500)
                if tab == 0 { dataSettings }
                else if tab == 1 { priceSettings }
                else { about }
            }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(stateChanges) { _ in refresh = Date() }
        .accessibilityIdentifier("workspace.settings.content")
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

    private static func updatedText(_ date: Date?) -> String {
        guard let date else { return MoaL10n.text("Not updated yet") }
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
            Button(MoaL10n.text("Check Update")) { app.checkUpdateAction() }
                .buttonStyle(MoaWorkspaceButtonStyle())
                .disabled(disabled)
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
