import AppKit
import Combine
import SwiftUI

struct MoaWorkspaceSettingsView: View {
    unowned let app: AppDelegate
    @State private var tab = 0
    @State private var refresh = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var disabled: Bool {
        MoaRuntimeMode.suppressesUserInteraction || app.dataPackageController.isDataOperationInProgress
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                workspaceHeading("Settings and Data", subtitle: "Quiet tools. Clear data boundaries.")
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
        .onReceive(timer) { refresh = $0 }
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
            workspaceNotice(MoaL10n.text("Local estimates use API reference prices, not subscription bills, credits, or balances."))
            Button(MoaL10n.text(app.usageCoordinator.isUpdatingPrices ? "Updating Prices…" : "Update Prices")) {
                app.updatePricesAction()
            }
            .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
            .disabled(disabled || app.usageCoordinator.isUpdatingPrices)
            Button(MoaL10n.text("Usage Overview…")) { app.workspaceWindow.navigation.showUsage() }
                .buttonStyle(MoaWorkspaceButtonStyle())
            Text(MoaL10n.text("Custom prices and usage alerts remain available in Usage Analysis."))
                .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(AppDelegate.versionTitle()).font(.system(size: 24, weight: .semibold))
            Text(MoaL10n.text("Accounts stay independent. Sessions run in each client."))
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
