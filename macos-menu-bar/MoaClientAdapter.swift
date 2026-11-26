import AppKit
import Foundation

/// Declarative capability flags describing what a registered client adapter supports.
struct MoaClientCapabilities: OptionSet, Hashable {
    let rawValue: Int

    static let accountSnapshot = Self(rawValue: 1 << 0)
    static let providerConfig = Self(rawValue: 1 << 1)
    static let usageScanner = Self(rawValue: 1 << 2)
    static let launchHelper = Self(rawValue: 1 << 3)
    static let credentialHealth = Self(rawValue: 1 << 4)
    static let codexStatusLine = Self(rawValue: 1 << 5)
    static let claudeCodeSettings = Self(rawValue: 1 << 6)
    static let keychainRepair = Self(rawValue: 1 << 7)
    static let zcodeOfficialReset = Self(rawValue: 1 << 8)
    static let cliOnly = Self(rawValue: 1 << 9)
}

/// Declarative metadata for a single AI Agent client managed by Moa.
/// Adding a new client registers one descriptor here rather than scattering
/// capability and identity lookups across workspace, menu, and CLI surfaces.
struct MoaClientAdapterDescriptor: Identifiable, Equatable {
    let client: MoaWorkspaceClient
    let logoName: String
    let bundleID: String
    let cliBinaryNames: [String]
    let groups: [MoaAccountGroup]
    let usageSource: MoaUsageSource?
    let capabilities: MoaClientCapabilities
    let titleProvider: () -> String
    let capabilitySummaryProvider: () -> String

    var id: String { client.rawValue }
    var title: String { titleProvider() }
    var capabilitySummary: String { capabilitySummaryProvider() }
    var operationClient: MoaAccountClient? { groups.first?.client }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.client == rhs.client
    }
}

/// Central adapter registry for all Moa-supported AI Agent clients.
enum MoaClientAdapterRegistry {
    static let descriptors: [MoaClientAdapterDescriptor] = [
        MoaClientAdapterDescriptor(
            client: .codex,
            logoName: "codex",
            bundleID: "com.openai.codex",
            cliBinaryNames: ["codex"],
            groups: [.codexOfficial, .codexConfig],
            usageSource: .codex,
            capabilities: [.accountSnapshot, .providerConfig, .usageScanner, .launchHelper, .credentialHealth, .codexStatusLine],
            titleProvider: { "ChatGPT / Codex" },
            capabilitySummaryProvider: { MoaL10n.text("Accounts and local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .claude,
            logoName: "claude",
            bundleID: "com.anthropic.claudefordesktop",
            cliBinaryNames: ["claude"],
            groups: [.claude, .claudeCode],
            usageSource: .claude,
            capabilities: [.providerConfig, .usageScanner, .launchHelper, .credentialHealth, .claudeCodeSettings],
            titleProvider: { "Claude Desktop & Code" },
            capabilitySummaryProvider: { MoaL10n.text("Desktop & Code providers · Local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .antigravity,
            logoName: "antigravity",
            bundleID: "com.google.antigravity",
            cliBinaryNames: ["agy"],
            groups: [.antigravity],
            usageSource: .antigravity,
            capabilities: [.accountSnapshot, .usageScanner, .launchHelper, .credentialHealth, .keychainRepair],
            titleProvider: { "Antigravity" },
            capabilitySummaryProvider: { MoaL10n.text("Accounts and local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .deepseek,
            logoName: "deepseek",
            bundleID: "com.deepseek.dsh",
            cliBinaryNames: ["dsh"],
            groups: [.deepseek],
            usageSource: .deepseek,
            capabilities: [.accountSnapshot, .usageScanner, .launchHelper, .credentialHealth],
            titleProvider: { "DeepSeek Harness" },
            capabilitySummaryProvider: { MoaL10n.text("Accounts and local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .workbuddyCN,
            logoName: "workbuddy",
            bundleID: WorkBuddyEdition.china.bundleID,
            cliBinaryNames: [],
            groups: [.workbuddyCN],
            usageSource: .workbuddyCN,
            capabilities: [.accountSnapshot, .usageScanner, .launchHelper, .credentialHealth],
            titleProvider: { MoaL10n.text("WorkBuddy Domestic") },
            capabilitySummaryProvider: { MoaL10n.text("Accounts and local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .workbuddy,
            logoName: "workbuddy",
            bundleID: WorkBuddyEdition.international.bundleID,
            cliBinaryNames: [],
            groups: [.workbuddy],
            usageSource: .workbuddy,
            capabilities: [.accountSnapshot, .usageScanner, .launchHelper, .credentialHealth],
            titleProvider: { MoaL10n.text("WorkBuddy AI International") },
            capabilitySummaryProvider: { MoaL10n.text("Accounts and local usage") }
        ),
        MoaClientAdapterDescriptor(
            client: .zcode,
            logoName: "zcode",
            bundleID: "dev.zcode.app",
            cliBinaryNames: ["zcode"],
            groups: [],
            usageSource: .zcode,
            capabilities: [.usageScanner, .launchHelper, .zcodeOfficialReset],
            titleProvider: { "ZCode" },
            capabilitySummaryProvider: { MoaL10n.text("Local usage and launch") }
        ),
        MoaClientAdapterDescriptor(
            client: .geminiCLI,
            logoName: "gemini",
            bundleID: "",
            cliBinaryNames: ["gemini"],
            groups: [.geminiCLI],
            usageSource: nil,
            capabilities: [.accountSnapshot, .credentialHealth, .cliOnly],
            titleProvider: { "Gemini CLI" },
            capabilitySummaryProvider: { MoaL10n.text("CLI account switching") }
        )
    ]

    private static let byClient: [MoaWorkspaceClient: MoaClientAdapterDescriptor] = Dictionary(
        uniqueKeysWithValues: descriptors.map { ($0.client, $0) }
    )

    static func descriptor(for client: MoaWorkspaceClient) -> MoaClientAdapterDescriptor {
        byClient[client]!
    }

    static func client(for group: MoaAccountGroup) -> MoaWorkspaceClient {
        descriptors.first { $0.groups.contains(group) }!.client
    }

    static func client(for source: MoaUsageSource) -> MoaWorkspaceClient? {
        descriptors.first { $0.usageSource == source }?.client
    }

    static var defaultOrder: [MoaWorkspaceClient] {
        descriptors.map(\.client)
    }
}

/// Persistent user customization for sidebar/menu client order and visibility.
enum MoaClientPreferences {
    static let customOrderKey = "Moa.clients.customOrder"
    static let hiddenClientsKey = "Moa.clients.hiddenIDs"
    static let didChangeNotification = Notification.Name("MoaClientPreferencesDidChange")

    static func orderedClients(defaults: UserDefaults = .standard) -> [MoaWorkspaceClient] {
        let raw = defaults.stringArray(forKey: customOrderKey) ?? []
        var result: [MoaWorkspaceClient] = []
        var seen = Set<MoaWorkspaceClient>()
        for id in raw {
            if let client = MoaWorkspaceClient(rawValue: id), seen.insert(client).inserted {
                result.append(client)
            }
        }
        for client in MoaClientAdapterRegistry.defaultOrder where seen.insert(client).inserted {
            result.append(client)
        }
        return result
    }

    static func setCustomOrder(_ clients: [MoaWorkspaceClient], defaults: UserDefaults = .standard) {
        var unique: [String] = []
        var seen = Set<MoaWorkspaceClient>()
        for client in clients where seen.insert(client).inserted {
            unique.append(client.rawValue)
        }
        for client in MoaClientAdapterRegistry.defaultOrder where seen.insert(client).inserted {
            unique.append(client.rawValue)
        }
        defaults.set(unique, forKey: customOrderKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func hasCustomOrder(defaults: UserDefaults = .standard) -> Bool {
        defaults.stringArray(forKey: customOrderKey) != nil
    }

    static func hiddenClients(defaults: UserDefaults = .standard) -> Set<MoaWorkspaceClient> {
        let raw = defaults.stringArray(forKey: hiddenClientsKey) ?? []
        let parsed = Set(raw.compactMap(MoaWorkspaceClient.init(rawValue:)))
        // Never allow hiding every single client.
        if parsed.count >= MoaWorkspaceClient.allCases.count {
            return []
        }
        return parsed
    }

    static func setHidden(_ hidden: Bool, for client: MoaWorkspaceClient, defaults: UserDefaults = .standard) {
        var current = hiddenClients(defaults: defaults)
        if hidden {
            // Keep at least one visible client.
            if current.count + 1 < MoaWorkspaceClient.allCases.count {
                current.insert(client)
            }
        } else {
            current.remove(client)
        }
        defaults.set(current.map(\.rawValue).sorted(), forKey: hiddenClientsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func moveClient(_ client: MoaWorkspaceClient, offset: Int, defaults: UserDefaults = .standard) {
        var order = orderedClients(defaults: defaults)
        guard let index = order.firstIndex(of: client) else { return }
        let target = max(0, min(order.count - 1, index + offset))
        guard target != index else { return }
        order.remove(at: index)
        order.insert(client, at: target)
        setCustomOrder(order, defaults: defaults)
    }

    static func resetDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: customOrderKey)
        defaults.removeObject(forKey: hiddenClientsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Resolves visible clients respecting custom order (if set) or installed-first default order.
    static func resolvedVisibleClients(
        installed: Set<MoaWorkspaceClient>,
        defaults: UserDefaults = .standard
    ) -> [(client: MoaWorkspaceClient, present: Bool)] {
        let hidden = hiddenClients(defaults: defaults)
        let baseOrder = orderedClients(defaults: defaults).filter { !hidden.contains($0) }
        let allVisible = baseOrder.isEmpty ? MoaClientAdapterRegistry.defaultOrder : baseOrder
        if hasCustomOrder(defaults: defaults) {
            let knowsInstalls = !installed.isEmpty && installed.count < MoaWorkspaceClient.allCases.count
            return allVisible.map { ($0, knowsInstalls ? installed.contains($0) : true) }
        }
        guard !installed.isEmpty, installed.count < MoaWorkspaceClient.allCases.count else {
            return allVisible.map { ($0, true) }
        }
        return allVisible.filter(installed.contains).map { ($0, true) }
            + allVisible.filter { !installed.contains($0) }.map { ($0, false) }
    }
}
