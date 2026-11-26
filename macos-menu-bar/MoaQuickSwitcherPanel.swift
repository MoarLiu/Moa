import AppKit
import SwiftUI

enum MoaQuickSwitcherItemKind: Equatable {
    case destination(MoaWorkspaceDestination, settingsTab: MoaWorkspaceSettingsTab?)
    case client(MoaWorkspaceClient)
    case account(MoaAccountRow)
}

struct MoaQuickSwitcherItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String?
    let logoClient: MoaWorkspaceClient?
    let symbol: String
    let kind: MoaQuickSwitcherItemKind
    let searchTokens: String
}

/// Pure fuzzy search & ranking engine for the Spotlight-style Quick Switcher.
enum MoaQuickSwitcherEngine {
    static func buildItems(
        sections: [MoaAccountSection],
        visibleClients: [MoaWorkspaceClient]
    ) -> [MoaQuickSwitcherItem] {
        var items: [MoaQuickSwitcherItem] = []

        // 1. Saved accounts & providers across visible clients
        let visibleSet = Set(visibleClients)
        for section in sections {
            let client = MoaWorkspaceClient.client(for: section.group)
            guard visibleSet.contains(client) else { continue }
            for row in section.rows {
                let displayName = row.name.isEmpty ? row.detail : row.name
                let subtitle = [client.title, section.group.title, row.detail]
                    .filter { !$0.isEmpty && $0 != displayName }
                    .joined(separator: " · ")
                let badge: String?
                if row.active {
                    badge = MoaL10n.text("In Use")
                } else if let health = row.health, health.needsAttention {
                    badge = health.badge
                } else {
                    badge = nil
                }
                items.append(MoaQuickSwitcherItem(
                    id: "account|\(row.group.rawValue)|\(row.id)",
                    title: displayName,
                    subtitle: subtitle,
                    badge: badge,
                    logoClient: client,
                    symbol: row.group.symbol,
                    kind: .account(row),
                    searchTokens: "\(displayName) \(subtitle) \(client.rawValue) \(row.group.rawValue)".lowercased()
                ))
            }
        }

        // 2. Client pages
        for client in visibleClients {
            items.append(MoaQuickSwitcherItem(
                id: "client|\(client.rawValue)",
                title: client.title,
                subtitle: client.capability,
                badge: nil,
                logoClient: client,
                symbol: "app",
                kind: .client(client),
                searchTokens: "\(client.title) \(client.rawValue) \(client.capability)".lowercased()
            ))
        }

        // 3. Core workspace destinations
        let destinations: [(id: String, title: String, subtitle: String, symbol: String, dest: MoaWorkspaceDestination, tab: MoaWorkspaceSettingsTab?)] = [
            ("dest|overview", MoaL10n.text("Overview"), MoaL10n.text("Accounts, configurations, and usage together."), "square.grid.2x2", .overview, nil),
            ("dest|usage", MoaL10n.text("Usage Analysis"), MoaL10n.text("Trend charts, cache savings, and budgets"), "chart.bar", .usage, nil),
            ("dest|prices", MoaL10n.text("Model Prices"), MoaL10n.text("Search reference prices and manage custom overrides"), "dollarsign.circle", .settings, .prices),
            ("dest|backups", MoaL10n.text("Data and Storage"), MoaL10n.text("Encrypted export, backups, and recovery"), "externaldrive", .settings, .data),
            ("dest|settings", MoaL10n.text("Settings and Data"), MoaL10n.text("Preferences, shortcuts, and client order"), "gearshape", .settings, .general)
        ]
        for entry in destinations {
            items.append(MoaQuickSwitcherItem(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                badge: nil,
                logoClient: nil,
                symbol: entry.symbol,
                kind: .destination(entry.dest, settingsTab: entry.tab),
                searchTokens: "\(entry.title) \(entry.subtitle)".lowercased()
            ))
        }

        return items
    }

    static func filter(items: [MoaQuickSwitcherItem], query: String) -> [MoaQuickSwitcherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        let terms = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.compactMap { item -> (MoaQuickSwitcherItem, Int)? in
            guard let score = matchScore(item: item, fullQuery: trimmed, terms: terms) else { return nil }
            return (item, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.title < rhs.0.title
        }
        .map(\.0)
    }

    private static func matchScore(item: MoaQuickSwitcherItem, fullQuery: String, terms: [String]) -> Int? {
        let title = item.title.lowercased()
        let haystack = item.searchTokens
        var total = 0
        for term in terms {
            if title == term {
                total += 120
            } else if title.hasPrefix(term) {
                total += 80
            } else if title.contains(term) {
                total += 50
            } else if haystack.contains(term) {
                total += 25
            } else if isSubsequence(term, of: haystack) {
                total += 10
            } else {
                return nil
            }
        }
        if title.hasPrefix(fullQuery) { total += 40 }
        if case .account(let row) = item.kind, !row.active { total += 5 }
        return total
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var idx = haystack.startIndex
        for ch in needle {
            guard let found = haystack[idx...].firstIndex(of: ch) else { return false }
            idx = haystack.index(after: found)
        }
        return true
    }
}

private final class MoaQuickSwitcherFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class MoaQuickSwitcherPanelController: NSObject, NSWindowDelegate {
    unowned let app: AppDelegate
    private var panel: NSPanel?
    private let model = MoaQuickSwitcherViewModel()
    private var keyMonitor: Any?

    init(app: AppDelegate) {
        self.app = app
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        reloadItems()
        let panel = ensurePanel()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let x = visible.midX - panel.frame.width / 2
            let y = visible.midY + visible.height * 0.12 - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 40, y)))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func dismiss() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func reloadItems() {
        let loaded = MoaAccountCatalog.load(app: app)
        let visible = MoaClientPreferences.resolvedVisibleClients(installed: MoaClientInstallation.installed()).map(\.client)
        model.query = ""
        model.selectedIndex = 0
        model.allItems = MoaQuickSwitcherEngine.buildItems(sections: loaded.sections, visibleClients: visible)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let contentRect = NSRect(x: 0, y: 0, width: 580, height: 420)
        let panel = MoaQuickSwitcherFloatingPanel(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let view = MoaQuickSwitcherView(
            model: model,
            onExecute: { [weak self] item in self?.execute(item) },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let host = MoaInteractiveHostingView(rootView: view)
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch Int(event.keyCode) {
            case 53: // Escape
                self.dismiss()
                return nil
            case 125: // Down arrow
                self.model.moveSelection(1)
                return nil
            case 126: // Up arrow
                self.model.moveSelection(-1)
                return nil
            case 36, 76: // Return / Enter
                if let item = self.model.selectedItem {
                    self.execute(item)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func execute(_ item: MoaQuickSwitcherItem) {
        dismiss()
        switch item.kind {
        case .destination(let destination, let tab):
            if let tab {
                app.workspaceWindow.navigation.showSettings(tab)
                app.workspaceWindow.show()
            } else if destination == .usage {
                app.workspaceWindow.navigation.showUsage()
                app.workspaceWindow.show()
            } else {
                app.workspaceWindow.show(destination)
            }
        case .client(let client):
            app.workspaceWindow.show(.client(client))
        case .account(let row):
            if row.active {
                app.workspaceWindow.show(group: row.group)
            } else {
                // Reuses the exact same confirmation + active-task protection + operation locks.
                app.workspaceWindow.accounts.activate(row)
            }
        }
    }
}

private final class MoaQuickSwitcherViewModel: ObservableObject {
    @Published var allItems: [MoaQuickSwitcherItem] = []
    @Published var query: String = "" {
        didSet { selectedIndex = 0 }
    }
    @Published var selectedIndex: Int = 0

    var filteredItems: [MoaQuickSwitcherItem] {
        MoaQuickSwitcherEngine.filter(items: allItems, query: query)
    }

    var selectedItem: MoaQuickSwitcherItem? {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return items.first }
        return items[selectedIndex]
    }

    func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = (selectedIndex + delta + count) % count
    }
}

private struct MoaQuickSwitcherView: View {
    @ObservedObject var model: MoaQuickSwitcherViewModel
    let onExecute: (MoaQuickSwitcherItem) -> Void
    let onDismiss: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                TextField(MoaL10n.text("Search clients, accounts, providers, or pages…"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MoaWorkspaceTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            let items = model.filteredItems
            if items.isEmpty {
                VStack(spacing: 8) {
                    Text(MoaL10n.text("No matching accounts or actions"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MoaWorkspaceTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                let isSelected = index == model.selectedIndex
                                Button {
                                    onExecute(item)
                                } label: {
                                    HStack(spacing: 12) {
                                        if let client = item.logoClient {
                                            MoaClientLogo(client: client, size: 22)
                                        } else {
                                            Image(systemName: item.symbol)
                                                .font(.system(size: 15))
                                                .foregroundStyle(MoaWorkspaceTheme.accent)
                                                .frame(width: 22, height: 22)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(1)
                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        if let badge = item.badge {
                                            Text(badge)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(badge == MoaL10n.text("In Use") ? MoaWorkspaceTheme.success : MoaTheme.amber)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(
                                                    (badge == MoaL10n.text("In Use") ? MoaWorkspaceTheme.successFill : MoaWorkspaceTheme.subtle),
                                                    in: RoundedRectangle(cornerRadius: 5)
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? MoaWorkspaceTheme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selectedIndex) { newIndex in
                        if items.indices.contains(newIndex) {
                            proxy.scrollTo(items[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 14) {
                Text(MoaL10n.text("↑↓ Navigate · ↩ Select or Switch · ⎋ Dismiss"))
                    .font(.system(size: 11))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                Spacer()
                Text(MoaL10n.text("Switching asks for confirmation and protects active tasks"))
                    .font(.system(size: 11))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(MoaWorkspaceTheme.subtle)
        }
        .background(MoaWorkspaceTheme.canvas)
        .foregroundStyle(MoaWorkspaceTheme.text)
        .onAppear { searchFocused = true }
    }
}
