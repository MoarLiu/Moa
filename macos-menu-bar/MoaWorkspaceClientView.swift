import AppKit
import SwiftUI

struct MoaWorkspaceClientView: View {
    unowned let app: AppDelegate
    let client: MoaWorkspaceClient
    @ObservedObject var accounts: MoaAccountManagerModel
    @ObservedObject var navigation: MoaWorkspaceNavigation
    @ObservedObject var usage: MoaUsageCoordinator

    private var group: MoaAccountGroup? {
        client.groups.contains(navigation.accountGroup) ? navigation.accountGroup : client.groups.first
    }

    private var section: MoaAccountSection? {
        accounts.sections.first { $0.group == group }
    }

    private var busy: Bool {
        client.operationClient.map { accounts.operations.active[$0] != nil } ?? false
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !accounts.failures.isEmpty {
                        workspaceNotice(accounts.failures.joined(separator: "\n"), tone: MoaTheme.coral)
                    }
                    if let group {
                        if client.groups.count > 1 { tabs }
                        if let message = accounts.progress(group) {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small)
                                Text(message).font(.system(size: 13))
                            }.padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(MoaWorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if let section {
                            currentLogin(section)
                            if geometry.size.width >= 940 {
                                HStack(alignment: .top, spacing: 24) {
                                    accountList(section).frame(maxWidth: .infinity)
                                    guidance(group).frame(width: 280)
                                }
                            } else {
                                accountList(section)
                                guidance(group)
                            }
                        } else if !MoaRuntimeMode.isWorkspacePreview {
                            workspaceNotice(MoaL10n.text("Account data is unavailable. Refresh to try again."), tone: MoaTheme.amber)
                        } else {
                            workspaceNotice(MoaL10n.text("Preview uses no saved accounts or credentials."))
                        }
                    } else {
                        workspaceNotice(MoaL10n.text("This client supports local usage and launch, not account or provider management."))
                        usageAction
                        Button(MoaL10n.text("Open ZCode Folder")) { app.zcodeController.openZCodeFolder() }
                            .buttonStyle(MoaWorkspaceButtonStyle())
                            .disabled(MoaRuntimeMode.suppressesUserInteraction)
                    }
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityIdentifier("workspace.client.content.\(client.rawValue)")
    }

    private var header: some View {
        HStack(spacing: 16) {
            MoaClientLogo(client: client, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(client.title).font(.system(size: 27, weight: .semibold))
                Text(headerDetail).font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
            }
            Spacer(minLength: 12)
            Button(MoaL10n.text("Open Client")) { app.workspaceWindow.open(client) }
                .buttonStyle(MoaWorkspaceButtonStyle())
                .disabled(busy || MoaRuntimeMode.suppressesUserInteraction)
            Menu {
                Button(MoaL10n.text("Reopen Client")) { app.workspaceWindow.open(client, reopen: true) }
                if client == .codex {
                    Button(MoaL10n.text("Open Codex Folder")) { app.openCodexFolderAction() }
                } else if client == .claude {
                    Button(MoaL10n.text("Open Claude Desktop Folder")) { app.openClaudeDesktopFolderAction() }
                    Button(MoaL10n.text("Open Claude Desktop 3P Folder")) { app.openClaudeDesktop3PFolderAction() }
                }
                if client.usageSource != nil {
                    Button(MoaL10n.text("View Usage Analysis")) { navigation.showUsage(client.usageSource) }
                }
            } label: {
                Label(MoaL10n.text("More Actions"), systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(busy || MoaRuntimeMode.suppressesUserInteraction)
        }
    }

    private var tabs: some View {
        let selection = Binding<MoaAccountGroup>(
            get: { group ?? client.groups.first ?? .codexOfficial },
            set: { navigation.accountGroup = $0 })
        return Picker(MoaL10n.text("Client Sections"), selection: selection) {
            ForEach(client.groups) { group in
                Text(MoaL10n.text(tabTitle(group))).tag(group)
            }
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityLabel(MoaL10n.text("Client Sections"))
        .accessibilityIdentifier("workspace.groups.\(client.rawValue)")
        .fixedSize()
    }

    private func currentLogin(_ section: MoaAccountSection) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                let active = section.rows.first(where: \.active)
                Text(active.map { MoaL10n.format("Currently using: %@", $0.name) }
                     ?? MoaL10n.text("No saved active account"))
                    .font(.system(size: 13, weight: .medium))
                if let message = section.currentLoginMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let detail = active?.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if !section.group.supportsEditing {
                Button(MoaL10n.text("Save Current Login")) { accounts.add(section.group) }
                    .buttonStyle(MoaWorkspaceButtonStyle())
                    .disabled(busy || MoaRuntimeMode.suppressesUserInteraction
                              || (section.group == .codexOfficial && !section.canAddCurrentLogin))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func accountList(_ section: MoaAccountSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(MoaL10n.text(section.group.supportsEditing ? "Saved Providers" : "Saved Accounts"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if section.group.supportsEditing {
                    Menu {
                        Button(MoaL10n.text("Import Config")) { transfer(section.group, exporting: false) }
                        Button(MoaL10n.text("Export Config")) { transfer(section.group, exporting: true) }
                    } label: {
                        Label(MoaL10n.text("Transfer"), systemImage: "arrow.up.arrow.down")
                    }.fixedSize()
                    Button(MoaL10n.text("Add Provider")) { accounts.add(section.group) }
                        .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
                } else if section.group != .codexOfficial {
                    Button(MoaL10n.text("Add Another Account")) { accounts.addAnotherLogin(section.group) }
                        .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
                }
            }.padding(.bottom, 16)
            Divider()
            if section.rows.isEmpty {
                emptyAccounts(section.group)
            } else {
                ForEach(section.rows) { row in
                    accountRow(row)
                    Divider()
                }
            }
            if !section.rows.isEmpty {
                Text(MoaL10n.text(section.group.supportsEditing
                    ? "Configurations are applied by the client. Moa does not proxy requests."
                    : "Switching replaces the client's saved login. Histories are not merged."))
                    .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .disabled(busy || MoaRuntimeMode.suppressesUserInteraction)
    }

    private func accountRow(_ row: MoaAccountRow) -> some View {
        HStack(spacing: 14) {
            Group {
                if let image = MoaUIResources.image(row.group.supportsEditing ? "settings" : "account",
                                                    folder: "Navigation", extension: "svg") {
                    Image(nsImage: image).renderingMode(.template).resizable().frame(width: 18, height: 18)
                        .foregroundStyle(MoaWorkspaceTheme.secondary)
                } else {
                    Image(systemName: row.group.supportsEditing ? "gearshape" : "person.crop.circle")
                }
            }
            .frame(width: 30, height: 30)
            .background(MoaWorkspaceTheme.selected, in: Circle())
            Text(row.name.isEmpty ? row.detail : row.name)
                .font(.system(size: 14, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !row.detail.isEmpty && row.name != row.detail {
                Text(row.detail).font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 280, alignment: .trailing)
            }
            if row.active {
                Text(MoaL10n.text("In Use")).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MoaWorkspaceTheme.success).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MoaWorkspaceTheme.successFill, in: RoundedRectangle(cornerRadius: 5))
            } else {
                Button(MoaL10n.text("Switch")) { accounts.activate(row) }
                    .buttonStyle(MoaWorkspaceButtonStyle())
            }
            Menu {
                Button(MoaL10n.text("Rename")) { accounts.rename(row) }
                if row.group.supportsEditing {
                    Button(MoaL10n.text("Edit")) { accounts.edit(row) }
                }
                Divider()
                Button(role: .destructive) { accounts.delete(row) } label: { Text(MoaL10n.text("Delete")) }
            } label: {
                Label(MoaL10n.text("Account Actions"), systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel(MoaL10n.format("Actions for %@", row.name))
        }
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(row.active ? MoaWorkspaceTheme.subtle : Color.clear)
    }

    private func emptyAccounts(_ group: MoaAccountGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MoaClientLogo(client: client, size: 48)
            Text(MoaL10n.text(group.supportsEditing ? "Add your first provider" : "Save your first login"))
                .font(.system(size: 22, weight: .semibold))
            Text(MoaL10n.text(group.supportsEditing
                ? "Add a configuration to save its URL and API key."
                : "Sign in to the client, then choose Save Current Login."))
                .font(.system(size: 13)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(MoaL10n.text("Keep work and personal identities separate."))
                .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func guidance(_ group: MoaAccountGroup) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if group.supportsEditing {
                Text(MoaL10n.text("When saving a provider")).font(.system(size: 15, weight: .medium))
                step("01", title: "Enter the endpoint", detail: "Use the Base URL and API key the client should send requests to.")
                step("02", title: "Apply the configuration", detail: "Moa writes it into the client's own config and keeps other settings.")
                step("03", title: "Check the client", detail: "Restart the client if it keeps an existing connection open.")
            } else {
                Text(MoaL10n.text("When switching accounts")).font(.system(size: 15, weight: .medium))
                step("01", title: "Finish active tasks", detail: "Complete current replies and tasks in the client first.")
                step("02", title: "Restore the selected identity", detail: "Switching uses the existing client adapter and its recovery checks.")
                step("03", title: "Verify the client login", detail: "Check the displayed identity and send a request in the client.")
            }
            usageAction
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func step(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).foregroundStyle(MoaWorkspaceTheme.accent).font(.system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 6) {
                Text(MoaL10n.text(title)).font(.system(size: 12, weight: .medium))
                Text(MoaL10n.text(detail)).font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var usageAction: some View {
        if let source = client.usageSource {
            Button(MoaL10n.text("View Usage Analysis")) { navigation.showUsage(source) }
                .buttonStyle(MoaWorkspaceButtonStyle())
        } else {
            Text(MoaL10n.text("Local usage analysis is not supported for this client."))
                .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Today's local usage for this client, or what the client does when it has none.
    private var headerDetail: String {
        guard let source = client.usageSource, let summary = usage.workspaceSummaries[source] else {
            return client.capability
        }
        return MoaL10n.format("Today: %@ · %@ tokens", DailyUsageAlertController.currency(summary.todayCostUSD),
                              MoaWorkspaceView.tokens(summary.todayTokens))
    }

    private func tabTitle(_ group: MoaAccountGroup) -> String {
        switch group {
        case .codexOfficial: return "Official Accounts"
        case .codexConfig: return "API Providers"
        case .claude: return "Provider Configurations"
        default: return "Saved Accounts"
        }
    }

    private func transfer(_ group: MoaAccountGroup, exporting: Bool) {
        if group == .claude {
            if exporting { app.exportClaudeDesktopProfilesAction() } else { app.importClaudeDesktopProfilesAction() }
        } else {
            if exporting { app.exportCodexProfilesAction() } else { app.importCodexProfilesAction() }
        }
        accounts.reload()
    }
}
