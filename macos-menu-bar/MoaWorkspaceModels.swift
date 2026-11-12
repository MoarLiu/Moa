import AppKit
import Foundation
import SwiftUI

enum MoaWorkspaceClient: String, CaseIterable, Identifiable {
    case codex, claude, antigravity, deepseek, workbuddyCN, workbuddy, zcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "ChatGPT / Codex"
        case .claude: return "Claude Desktop"
        case .antigravity: return "Antigravity"
        case .deepseek: return "DeepSeek Harness"
        case .workbuddyCN: return MoaL10n.text("WorkBuddy Domestic")
        case .workbuddy: return MoaL10n.text("WorkBuddy AI International")
        case .zcode: return "ZCode"
        }
    }

    var logoName: String {
        switch self {
        case .workbuddyCN, .workbuddy: return "workbuddy"
        default: return rawValue
        }
    }

    var bundleID: String {
        switch self {
        case .codex: return "com.openai.codex"
        case .claude: return "com.anthropic.claudefordesktop"
        case .antigravity: return "com.google.antigravity"
        case .deepseek: return "com.deepseek.dsh"
        case .workbuddyCN: return WorkBuddyEdition.china.bundleID
        case .workbuddy: return WorkBuddyEdition.international.bundleID
        case .zcode: return "dev.zcode.app"
        }
    }

    var groups: [MoaAccountGroup] {
        switch self {
        case .codex: return [.codexOfficial, .codexConfig]
        case .claude: return [.claude]
        case .antigravity: return [.antigravity]
        case .deepseek: return [.deepseek]
        case .workbuddyCN: return [.workbuddyCN]
        case .workbuddy: return [.workbuddy]
        case .zcode: return []
        }
    }

    var operationClient: MoaAccountClient? {
        groups.first?.client
    }

    var usageSource: MoaUsageSource? {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .workbuddyCN: return .workbuddyCN
        case .workbuddy: return .workbuddy
        case .zcode: return .zcode
        case .antigravity, .deepseek: return nil
        }
    }

    var capability: String {
        switch self {
        case .claude: return MoaL10n.text("Desktop providers · Code usage")
        case .antigravity, .deepseek: return MoaL10n.text("Account switching")
        case .zcode: return MoaL10n.text("Local usage and launch")
        default: return MoaL10n.text("Accounts and local usage")
        }
    }

    static func client(for group: MoaAccountGroup) -> Self {
        // Every supported account group belongs to exactly one workspace client.
        allCases.first { $0.groups.contains(group) }!
    }
}

enum MoaWorkspaceDestination: Hashable {
    case overview, usage, settings
    case client(MoaWorkspaceClient)
}

/// Which clients are installed right now. The workspace dims the rest and the
/// menu bar folds them away, so a client the user does not have stops competing
/// with the ones they do. Detection is advisory: when it finds nothing at all
/// (unusual locations, a test process), every client keeps its normal place.
enum MoaClientInstallation {
    static func installed() -> Set<MoaWorkspaceClient> {
        guard !MoaRuntimeMode.isWorkspacePreview else { return Set(MoaWorkspaceClient.allCases) }
        var found: Set<MoaWorkspaceClient> = []
        for client in MoaWorkspaceClient.allCases where isInstalled(client) {
            found.insert(client)
        }
        return found
    }

    static func isInstalled(_ client: MoaWorkspaceClient) -> Bool {
        if client == .codex {
            let override = ProcessInfo.processInfo.environment["CODEX_APP"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !override.isEmpty {
                return FileManager.default.fileExists(atPath: override)
            }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: client.bundleID) != nil
    }

    /// Installed first in their original order, then the missing ones. The second
    /// element is false for a client this Mac does not have.
    static func orderedClients(_ installed: Set<MoaWorkspaceClient>) -> [(client: MoaWorkspaceClient, present: Bool)] {
        let all = MoaWorkspaceClient.allCases
        guard !installed.isEmpty, installed.count < all.count else {
            return all.map { ($0, true) }
        }
        return all.filter(installed.contains).map { ($0, true) }
            + all.filter { !installed.contains($0) }.map { ($0, false) }
    }
}

final class MoaWorkspaceNavigation: ObservableObject {
    @Published var destination: MoaWorkspaceDestination = .overview
    @Published var accountGroup: MoaAccountGroup = .codexOfficial
    @Published var usageSource: MoaUsageSource?
    @Published private(set) var usageRequest = UUID()
    @Published var refreshRequest = UUID()
    @Published var installedClients = MoaClientInstallation.installed()

    func refreshInstalledClients() {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        let found = MoaClientInstallation.installed()
        if found != installedClients { installedClients = found }
    }

    func showAccount(_ group: MoaAccountGroup) {
        accountGroup = group
        destination = .client(.client(for: group))
    }

    func showUsage(_ source: MoaUsageSource? = nil) {
        usageSource = source
        usageRequest = UUID()
        destination = .usage
    }
}

struct MoaWorkspaceUsageTotal {
    let costUSD: Double
    let tokens: Int
    let loadedSources: Int

    static func make(_ summaries: [MoaUsageSource: CodexUsageSummary]) -> Self? {
        guard !summaries.isEmpty else { return nil }
        return Self(
            costUSD: summaries.values.reduce(0) { $0 + $1.todayCostUSD },
            tokens: summaries.values.reduce(0) { $0 + $1.todayTokens },
            loadedSources: summaries.count
        )
    }
}

enum MoaWorkspaceCopy {
    /// The one place these two disclaimers live, so a surface that already shows
    /// one does not repeat it.
    static var estimateDisclaimer: String {
        MoaL10n.text("Local estimates use API reference prices, not subscription bills, credits, or balances.")
    }

    static var independenceNote: String {
        MoaL10n.text("Accounts stay independent. Sessions run in each client.")
    }
}

enum MoaUIResources {
    static func url(_ name: String, folder: String, extension ext: String) -> URL? {
        var bundles = [Bundle.main]
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        for bundle in bundles {
            guard let root = bundle.resourceURL else { continue }
            for base in [root.appendingPathComponent("UI"), root.appendingPathComponent("Resources/UI")] {
                let candidate = base.appendingPathComponent(folder).appendingPathComponent(name).appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    static func image(_ name: String, folder: String = "Brands", extension ext: String = "png") -> NSImage? {
        url(name, folder: folder, extension: ext).flatMap { NSImage(contentsOf: $0) }
    }
}

enum MoaWorkspaceTheme {
    static let canvas = color(0xFFFFFF, 0x13171B)
    static let sidebar = color(0xF3F5F7, 0x1A2026)
    static let subtle = color(0xF7F9FB, 0x20272E)
    static let selected = color(0xE8EFF8, 0x263D58)
    static let hero = color(0x152B44, 0xE1ECF8)
    static let text = color(0x172B3A, 0xEEF3F7)
    static let secondary = color(0x60717F, 0xA8BAC8)
    static let accent = color(0x245CC3, 0x91B9FF)
    static let border = color(0xE3E8ED, 0x303B46)
    static let success = color(0x28785F, 0x78C7A4)
    static let successFill = color(0xEAF5EF, 0x213C31)
    static let heroText = color(0xFFFFFF, 0x172B3A)
    static let onAccent = color(0xFFFFFF, 0x172B3A)

    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        func resolve(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                    green: Double((hex >> 8) & 255) / 255,
                    blue: Double(hex & 255) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            resolve(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }
}

struct MoaClientLogo: View {
    let client: MoaWorkspaceClient
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = MoaUIResources.image(client.logoName) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed").resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MoaWorkspaceButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(prominent ? MoaWorkspaceTheme.onAccent : MoaWorkspaceTheme.text)
            .background(prominent ? MoaWorkspaceTheme.accent : MoaWorkspaceTheme.canvas,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                prominent ? Color.clear : MoaWorkspaceTheme.border, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}
