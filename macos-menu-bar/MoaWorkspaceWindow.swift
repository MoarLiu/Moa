import AppKit
import Combine
import SwiftUI

final class MoaWorkspaceWindowController: NSObject, NSWindowDelegate {
    unowned let app: AppDelegate
    let navigation = MoaWorkspaceNavigation()
    lazy var accounts = MoaAccountManagerModel(app: app)
    private(set) var window: NSWindow?

    init(app: AppDelegate) { self.app = app }

    var isVisible: Bool { window?.isVisible == true }
    var isKey: Bool { window?.isKeyWindow == true }

    func show(_ destination: MoaWorkspaceDestination? = nil, group: MoaAccountGroup? = nil) {
        if let group { navigation.showAccount(group) }
        else if let destination { navigation.destination = destination }
        if window == nil {
            let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 1000)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: min(1280, screen.width - 80),
                                    height: min(860, screen.height - 80)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = MoaRuntimeMode.isWorkspacePreview ? "Moa — 1.8.0 Preview" : "Moa"
            window.minSize = NSSize(width: 720, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            if MoaRuntimeMode.isWorkspacePreview {
                if CommandLine.arguments.contains("--preview-compact") {
                    window.setContentSize(NSSize(width: 960, height: 640))
                }
                window.appearance = NSAppearance(named: CommandLine.arguments.contains("--preview-dark") ? .darkAqua : .aqua)
            } else {
                window.setFrameAutosaveName("MoaWorkspaceWindow")
            }
            let host = MoaInteractiveHostingView(rootView: MoaWorkspaceView(
                app: app, navigation: navigation, accounts: accounts, usage: app.usageCoordinator))
            if #available(macOS 13.0, *) { host.sizingOptions = [] }
            window.contentView = host
            self.window = window
        }
        reloadAccounts()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func reloadAccounts() {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        navigation.refreshInstalledClients()
        accounts.reload()
    }

    func refresh() {
        reloadAccounts()
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        app.usageCoordinator.refreshAllUsage()
        navigation.refreshRequest = UUID()
    }

    func windowDidBecomeKey(_ notification: Notification) { reloadAccounts() }

    func open(_ client: MoaWorkspaceClient, reopen: Bool = false) {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        switch client {
        case .codex:
            if reopen { app.reopenCodexAction() } else { app.openCodexAction() }
        case .claude:
            if reopen { app.reopenClaudeDesktopAction() } else { app.openClaudeDesktopAction() }
        case .antigravity: app.antigravityCoordinator.openFromWorkspace(reopen: reopen)
        case .deepseek: app.deepseekCoordinator.openFromWorkspace(reopen: reopen)
        case .workbuddyCN:
            if reopen { app.workbuddyCNCoordinator.reopenWorkBuddyAction() }
            else { app.workbuddyCNCoordinator.openWorkBuddyAction() }
        case .workbuddy:
            if reopen { app.workbuddyCoordinator.reopenWorkBuddyAction() }
            else { app.workbuddyCoordinator.openWorkBuddyAction() }
        case .zcode:
            if reopen { app.zcodeController.reopenZCode() } else { app.zcodeController.openZCode() }
        }
    }
}

struct MoaWorkspaceView: View {
    unowned let app: AppDelegate
    @ObservedObject var navigation: MoaWorkspaceNavigation
    @ObservedObject var accounts: MoaAccountManagerModel
    @ObservedObject var usage: MoaUsageCoordinator

    private var clients: [(client: MoaWorkspaceClient, present: Bool)] {
        MoaClientInstallation.orderedClients(navigation.installedClients)
    }

    var body: some View {
        GeometryReader { geometry in
            // Below this width the sidebar becomes an icon rail so content keeps its room.
            let rail = geometry.size.width < 860
            let sidebarWidth: CGFloat = rail ? 68 : (geometry.size.width < 1100 ? 196 : 220)
            HStack(spacing: 0) {
                sidebar(rail: rail).frame(width: sidebarWidth)
                Rectangle().fill(MoaWorkspaceTheme.border).frame(width: 1)
                Group {
                    switch navigation.destination {
                    case .overview: overview(compact: geometry.size.width - sidebarWidth < 900)
                    case .client(let client):
                        MoaWorkspaceClientView(app: app, client: client, accounts: accounts,
                                               navigation: navigation, usage: usage)
                    case .usage:
                        MoaWorkspaceUsageView(app: app, navigation: navigation)
                    case .settings:
                        MoaWorkspaceSettingsView(app: app)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .foregroundStyle(MoaWorkspaceTheme.text)
            .background(MoaWorkspaceTheme.canvas)
            .accentColor(MoaWorkspaceTheme.accent)
            .moaFeedbackBanner()
        }
    }

    /// A native list, so arrow keys, type-select and VoiceOver work as in any
    /// macOS sidebar instead of on a column of unrelated buttons.
    private func sidebar(rail: Bool) -> some View {
        let selection = Binding<MoaWorkspaceDestination?>(
            get: { navigation.destination },
            set: { destination in
                guard let destination else { return }
                switch destination {
                case .usage: navigation.showUsage()
                case .client(let client):
                    if !client.groups.contains(navigation.accountGroup) {
                        navigation.accountGroup = client.groups.first ?? .codexOfficial
                    }
                    navigation.destination = destination
                default: navigation.destination = destination
                }
            })
        let present = clients.filter(\.present).map(\.client)
        let missing = clients.filter { !$0.present }.map(\.client)
        return VStack(alignment: .leading, spacing: 0) {
            if !rail {
                Text("Moa").font(.system(size: 22, weight: .semibold))
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
            }
            List(selection: selection) {
                Section {
                    navigationRow("Overview", destination: .overview, icon: "overview", rail: rail)
                    navigationRow("Usage Analysis", destination: .usage, icon: "usage", rail: rail)
                }
                Section(header: sectionHeader("Clients", rail: rail)) {
                    ForEach(present) { clientRow($0, present: true, rail: rail) }
                }
                if !missing.isEmpty {
                    Section(header: sectionHeader("Not Installed", rail: rail)) {
                        ForEach(missing) { clientRow($0, present: false, rail: rail) }
                    }
                }
                Section {
                    navigationRow("Settings and Data", destination: .settings, icon: "settings", rail: rail)
                }
            }
            .listStyle(.sidebar)
            if !rail && MoaRuntimeMode.isWorkspacePreview {
                Text(MoaL10n.text("Preview · no account access"))
                    .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(MoaWorkspaceTheme.sidebar)
    }

    @ViewBuilder private func sectionHeader(_ title: String, rail: Bool) -> some View {
        if rail { EmptyView() } else { Text(MoaL10n.text(title)) }
    }

    private func clientRow(_ client: MoaWorkspaceClient, present: Bool, rail: Bool) -> some View {
        HStack(spacing: 10) {
            MoaClientLogo(client: client, size: 20)
            if !rail {
                Text(client.title).font(.system(size: 13)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: rail ? .center : .leading)
        .frame(height: 26)
        .opacity(present ? 1 : 0.5)
        .foregroundStyle(rowTint(.client(client)))
        .listRowBackground(rowBackground(.client(client)))
        .tag(MoaWorkspaceDestination.client(client))
        .help(present ? client.title : MoaL10n.format("%@ · Not installed", client.title))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(present ? client.title : MoaL10n.format("%@ · Not installed", client.title))
        .accessibilityIdentifier("workspace.client.\(client.rawValue)")
    }

    private func navigationRow(_ title: String, destination: MoaWorkspaceDestination, icon: String, rail: Bool) -> some View {
        HStack(spacing: 10) {
            if let image = MoaUIResources.image(icon, folder: "Navigation", extension: "svg") {
                Image(nsImage: image).renderingMode(.template).resizable().frame(width: 18, height: 18)
                    .frame(width: 20)
            }
            if !rail {
                Text(MoaL10n.text(title)).font(.system(size: 13)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: rail ? .center : .leading)
        .frame(height: 26)
        .foregroundStyle(rowTint(destination))
        .listRowBackground(rowBackground(destination))
        .tag(destination)
        .help(MoaL10n.text(title))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MoaL10n.text(title))
        .accessibilityIdentifier("workspace.\(icon)")
    }

    // The list supplies keyboard selection; the highlight uses the workspace
    // palette so it stays legible in both appearances and in inactive windows.
    private func rowTint(_ destination: MoaWorkspaceDestination) -> Color {
        navigation.destination == destination ? MoaWorkspaceTheme.accent : MoaWorkspaceTheme.text
    }

    private func rowBackground(_ destination: MoaWorkspaceDestination) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(navigation.destination == destination ? MoaWorkspaceTheme.selected : Color.clear)
            .padding(.horizontal, 8)
    }

    private var hasSavedAccounts: Bool {
        accounts.sections.contains { !$0.rows.isEmpty }
    }

    private func overview(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    workspaceHeading("Overview", subtitle: "Accounts, configurations, and usage together.")
                    Spacer()
                    Button(MoaL10n.text("Refresh")) { app.workspaceWindow.refresh() }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                }
                if !accounts.failures.isEmpty {
                    workspaceNotice(accounts.failures.joined(separator: "\n"), tone: MoaTheme.coral)
                }
                // Until something is saved there is nothing to resume; say how to begin.
                if !hasSavedAccounts && accounts.failures.isEmpty { gettingStarted }
                if compact {
                    todayPanel
                    clientList
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        clientList.frame(maxWidth: .infinity)
                        todayPanel.frame(width: 264)
                    }
                }
            }.padding(compact ? 24 : 32).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("workspace.overview.content")
    }

    private var gettingStarted: some View {
        let detected = clients.filter(\.present).map(\.client)
        let knowsInstalls = detected.count < MoaWorkspaceClient.allCases.count
        return VStack(alignment: .leading, spacing: 16) {
            Text(MoaL10n.text("Get started")).font(.system(size: 18, weight: .semibold))
            if knowsInstalls {
                HStack(spacing: 8) {
                    ForEach(detected) { MoaClientLogo(client: $0, size: 22) }
                    Text(MoaL10n.format("%lld supported clients found on this Mac", detected.count))
                        .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                startStep("1", title: "Sign in inside the client", detail: "Moa never asks for your password. Use each client's own sign-in.")
                startStep("2", title: "Save it in Moa", detail: "Open a client on the left, then save its current login or add a provider.")
                startStep("3", title: "Switch from the menu bar", detail: "Saved accounts appear in Moa's menu for one-click switching.")
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.selected, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("workspace.overview.getting-started")
    }

    private func startStep(_ number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(.system(size: 12, weight: .semibold)).foregroundStyle(MoaWorkspaceTheme.onAccent)
                .frame(width: 22, height: 22).background(MoaWorkspaceTheme.accent, in: Circle())
            Text(MoaL10n.text(title)).font(.system(size: 13, weight: .medium))
            Text(MoaL10n.text(detail)).font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clientList: some View {
        let ordered = clients
        let installedCount = ordered.filter(\.present).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(MoaL10n.text("My Clients")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(installedCount < ordered.count
                     ? MoaL10n.format("%lld of %lld installed", installedCount, ordered.count)
                     : MoaL10n.format("%lld supported clients", ordered.count))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
            }.padding(.bottom, 14)
            Divider()
            ForEach(ordered, id: \.client) { entry in
                clientListRow(entry.client, present: entry.present)
                Divider()
            }
        }
    }

    private func clientListRow(_ client: MoaWorkspaceClient, present: Bool) -> some View {
        Button {
            if !client.groups.contains(navigation.accountGroup) {
                navigation.accountGroup = client.groups.first ?? .codexOfficial
            }
            navigation.destination = .client(client)
        } label: {
            HStack(spacing: 12) {
                MoaClientLogo(client: client, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(present ? status(client) : MoaL10n.text("Not installed"))
                        .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if client.usageSource != nil {
                    let summary = client.usageSource.flatMap { usage.workspaceSummaries[$0] }
                    let failed = client.usageSource.flatMap { usage.workspaceFailures[$0] } != nil
                    // No usage yet is a dash, not a repeated sentence on every row.
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(summary.map { DailyUsageAlertController.currency($0.todayCostUSD) } ?? "—")
                            .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        if let summary, summary.todayCostUSD > 0 || summary.todayTokens > 0 {
                            Text(MoaL10n.format("%@ tokens today", Self.tokens(summary.todayTokens)))
                                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        } else if failed {
                            Text(MoaL10n.text("Not loaded"))
                                .font(.system(size: 11)).foregroundStyle(MoaTheme.amber)
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
            }
            .frame(minHeight: 54).contentShape(Rectangle())
            .opacity(present ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace.manage.\(client.rawValue)")
    }

    private var todayPanel: some View {
        let total = MoaWorkspaceUsageTotal.make(usage.workspaceSummaries)
        return VStack(alignment: .leading, spacing: 14) {
            Text(MoaL10n.text("Today's Local Usage")).font(.system(size: 14, weight: .medium))
            Text(total.map { DailyUsageAlertController.currency($0.costUSD) } ?? "—")
                .font(.system(size: 34, weight: .semibold)).monospacedDigit()
            Text(MoaL10n.text("API reference cost · USD"))
                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
            Divider()
            metric("Total Tokens", value: total.map { Self.tokens($0.tokens) } ?? "—")
            metric("Loaded Sources", value: "\(total?.loadedSources ?? 0) / \(MoaUsageSource.allCases.count)")
            if !usage.workspaceFailures.isEmpty {
                Text(MoaL10n.text("Some sources could not refresh. Values may include earlier local records."))
                    .font(.system(size: 11)).foregroundStyle(MoaTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(MoaL10n.text("View Usage Analysis")) { navigation.showUsage() }
                .buttonStyle(MoaWorkspaceButtonStyle())
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ label: String, value: String) -> some View {
        HStack {
            Text(MoaL10n.text(label)).foregroundStyle(MoaWorkspaceTheme.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.system(size: 12))
    }

    /// What a client row says under its name: who is active, else how many are
    /// saved, else what Moa can do for it. Never the same empty phrase seven times.
    private func status(_ client: MoaWorkspaceClient) -> String {
        let sections = accounts.sections.filter { client.groups.contains($0.group) }
        for group in client.groups.reversed() {
            if let row = sections.first(where: { $0.group == group })?.rows.first(where: \.active) {
                return row.name.isEmpty ? MoaL10n.text("In Use") : MoaL10n.format("Currently using: %@", row.name)
            }
        }
        let saved = sections.reduce(0) { $0 + $1.rows.count }
        return saved > 0 ? MoaL10n.format("%lld saved", saved) : client.capability
    }

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2f M", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1f K", Double(value) / 1_000) }
        return String(value)
    }
}

func workspaceHeading(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(MoaL10n.text(title)).font(.system(size: 28, weight: .semibold))
        Text(MoaL10n.text(subtitle)).font(.system(size: 13))
            .foregroundStyle(MoaWorkspaceTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func workspaceNotice(_ text: String, tone: Color = MoaWorkspaceTheme.secondary) -> some View {
    Text(text).font(.system(size: 12)).foregroundStyle(tone)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
}
