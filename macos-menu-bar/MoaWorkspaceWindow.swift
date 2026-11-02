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
            window.title = MoaRuntimeMode.isWorkspacePreview ? "Moa — 1.7.0 Preview" : "Moa"
            window.minSize = NSSize(width: 960, height: 640)
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

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar(width: geometry.size.width < 1100 ? 190 : 216)
                Rectangle().fill(MoaWorkspaceTheme.border).frame(width: 1)
                Group {
                    switch navigation.destination {
                    case .overview: overview(compact: geometry.size.width < 1140)
                    case .client(let client):
                        MoaWorkspaceClientView(app: app, client: client, accounts: accounts, navigation: navigation)
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

    private func sidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Moa").font(.system(size: 27, weight: .semibold)).padding(.top, 12)
            Text(MoaL10n.text("Your AI client workspace"))
                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .padding(.bottom, 22)
            navigationRow("Overview", destination: .overview, icon: "overview")
            navigationRow("Usage Analysis", destination: .usage, icon: "usage")
            Text(MoaL10n.text("Clients")).font(.system(size: 11, weight: .medium))
                .foregroundStyle(MoaWorkspaceTheme.secondary).padding(.vertical, 10)
            ForEach(MoaWorkspaceClient.allCases) { client in
                Button {
                    navigation.accountGroup = client.groups.first ?? .codexOfficial
                    navigation.destination = .client(client)
                } label: {
                    HStack(spacing: 10) {
                        MoaClientLogo(client: client, size: 20)
                        Text(client.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected(.client(client)) ? MoaWorkspaceTheme.accent : MoaWorkspaceTheme.secondary)
                .background(isSelected(.client(client)) ? MoaWorkspaceTheme.selected : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .help(client.title)
                .accessibilityIdentifier("workspace.client.\(client.rawValue)")
                .accessibilityAddTraits(isSelected(.client(client)) ? .isSelected : [])
            }
            Spacer(minLength: 12)
            navigationRow("Settings and Data", destination: .settings, icon: "settings")
            Text(MoaL10n.text(MoaRuntimeMode.isWorkspacePreview ? "Preview · no account access" : "Local management · Moa"))
                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .padding(.top, 8)
        }
        .padding(16).frame(width: width).frame(maxHeight: .infinity)
        .background(MoaWorkspaceTheme.sidebar)
    }

    private func navigationRow(_ title: String, destination: MoaWorkspaceDestination, icon: String) -> some View {
        Button {
            if destination == .usage { navigation.showUsage() }
            else { navigation.destination = destination }
        } label: {
            HStack(spacing: 10) {
                if let image = MoaUIResources.image(icon, folder: "Navigation", extension: "svg") {
                    Image(nsImage: image).renderingMode(.template).resizable().frame(width: 18, height: 18)
                }
                Text(MoaL10n.text(title)).font(.system(size: 13, weight: isSelected(destination) ? .medium : .regular))
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected(destination) ? MoaWorkspaceTheme.accent : MoaWorkspaceTheme.secondary)
        .background(isSelected(destination) ? MoaWorkspaceTheme.selected : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("workspace.\(icon)")
        .accessibilityAddTraits(isSelected(destination) ? .isSelected : [])
    }

    private func isSelected(_ destination: MoaWorkspaceDestination) -> Bool {
        navigation.destination == destination
    }

    private func overview(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    workspaceHeading("Overview", subtitle: "Accounts, configurations, and usage together.")
                    Spacer()
                    Button(MoaL10n.text("Refresh")) { app.workspaceWindow.refresh() }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                    Button(MoaL10n.text("Manage Clients")) { navigation.showAccount(.codexOfficial) }
                        .buttonStyle(MoaWorkspaceButtonStyle(prominent: true))
                }
                resumePanel
                if !accounts.failures.isEmpty {
                    workspaceNotice(accounts.failures.joined(separator: "\n"), tone: MoaTheme.coral)
                }
                if compact {
                    clientList
                    todayPanel
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        clientList.frame(maxWidth: .infinity)
                        todayPanel.frame(width: 264)
                    }
                }
                Text(MoaL10n.text("Accounts stay independent. Sessions run in each client."))
                    .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
            }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("workspace.overview.content")
    }

    private var resumePanel: some View {
        HStack(alignment: .top, spacing: 22) {
            MoaClientLogo(client: .codex, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(MoaL10n.text("Ready to continue?")).font(.system(size: 20, weight: .medium))
                Text("ChatGPT / Codex · \(currentName(.codex))").font(.system(size: 13))
                Text(MoaL10n.text("Sessions run in the client. Moa manages accounts and configuration."))
                    .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(MoaL10n.text("Open Client")) { app.workspaceWindow.open(.codex) }
                .buttonStyle(MoaWorkspaceButtonStyle())
                .disabled(MoaRuntimeMode.suppressesUserInteraction || accounts.isBusy(.codexOfficial))
        }
        .foregroundStyle(MoaWorkspaceTheme.heroText)
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.hero, in: RoundedRectangle(cornerRadius: 12))
    }

    private var clientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(MoaL10n.text("My Clients")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(MoaL10n.format("%lld supported clients", MoaWorkspaceClient.allCases.count))
                    .font(.system(size: 12)).foregroundStyle(MoaWorkspaceTheme.secondary)
            }.padding(.bottom, 14)
            Divider()
            ForEach(MoaWorkspaceClient.allCases) { client in
                HStack(spacing: 10) {
                    MoaClientLogo(client: client, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(client.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(currentName(client)).font(.system(size: 11))
                            .foregroundStyle(MoaWorkspaceTheme.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(client.capability).font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                    Button(MoaL10n.text(client == .zcode ? "Usage Details" : client == .claude ? "View Providers" : "View Accounts")) {
                        navigation.accountGroup = client.groups.first ?? .codexOfficial
                        navigation.destination = .client(client)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityIdentifier("workspace.manage.\(client.rawValue)")
                }.frame(minHeight: 57)
                Divider()
            }
        }
    }

    private var todayPanel: some View {
        let total = MoaWorkspaceUsageTotal.make(usage.workspaceSummaries)
        return VStack(alignment: .leading, spacing: 18) {
            Text(MoaL10n.text("Today's Local Usage")).font(.system(size: 14, weight: .medium))
            Text(total.map { DailyUsageAlertController.currency($0.costUSD) } ?? "—")
                .font(.system(size: 38, weight: .semibold)).monospacedDigit()
            Text(MoaL10n.text("API reference cost · USD"))
                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
            Divider()
            metric("Total Tokens", value: total.map { Self.tokens($0.tokens) } ?? "—")
            metric("Loaded Sources", value: "\(total?.loadedSources ?? 0) / \(MoaUsageSource.allCases.count)")
            if !usage.workspaceFailures.isEmpty {
                Text(MoaL10n.text("Some sources could not refresh. Values may include earlier local records."))
                    .font(.system(size: 11)).foregroundStyle(MoaTheme.amber)
            }
            Button(MoaL10n.text("View Usage Analysis")) { navigation.showUsage() }
                .buttonStyle(MoaWorkspaceButtonStyle())
            Divider()
            Text(MoaL10n.text("Local estimates use API reference prices, not subscription bills, credits, or balances."))
                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private func currentName(_ client: MoaWorkspaceClient) -> String {
        if client == .zcode { return MoaL10n.text("Local usage and launch") }
        for group in client.groups.reversed() {
            if let row = accounts.sections.first(where: { $0.group == group })?.rows.first(where: \.active) {
                return row.name.isEmpty ? MoaL10n.text("In Use") : row.name
            }
        }
        return MoaL10n.text("No saved active account")
    }

    private static func tokens(_ value: Int) -> String {
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
