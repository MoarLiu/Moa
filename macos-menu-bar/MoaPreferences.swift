import AppKit
import Foundation
import ServiceManagement

// MARK: - App Language Preference

enum MoaAppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    static let defaultsKey = "Moa.appLanguageOverride"
    static let didChangeNotification = Notification.Name("MoaAppLanguageDidChange")

    var id: String { rawValue }

    var lprojName: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .english: return "en"
        }
    }

    var displayTitle: String {
        switch self {
        case .system: return MoaL10n.text("Follow System")
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: defaultsKey),
              let language = Self(rawValue: raw) else {
            return .system
        }
        return language
    }

    static func set(_ language: Self, defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(language.rawValue, forKey: defaultsKey)
        }
        MoaL10n.reload(defaults: defaults)
        NotificationCenter.default.post(name: didChangeNotification, object: language)
    }
}

// MARK: - Menu Bar Display Preferences

enum MoaMenuBarDisplayPreferences {
    static let showTodayCostKey = "Moa.menuBar.showTodayCost"
    static let didChangeNotification = Notification.Name("MoaMenuBarDisplayDidChange")

    static func showsTodayCost(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showTodayCostKey)
    }

    static func setShowsTodayCost(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: showTodayCostKey)
        NotificationCenter.default.post(name: didChangeNotification, object: enabled)
    }

    static func statusItemTitle(
        summaries: [MoaUsageSource: CodexUsageSummary],
        showTodayCost: Bool
    ) -> String {
        guard showTodayCost else { return "" }
        guard let total = MoaWorkspaceUsageTotal.make(summaries) else {
            return " —"
        }
        return " \(DailyUsageAlertController.currency(total.costUSD))"
    }
}

// MARK: - Launch at Login

enum MoaLaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unsupportedOS

    var isEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }
}

protocol MoaLaunchAtLoginManaging {
    func status() -> MoaLaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

struct MoaSystemLaunchAtLoginBackend: MoaLaunchAtLoginManaging {
    func status() -> MoaLaunchAtLoginStatus {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return .disabled }
        guard #available(macOS 13.0, *) else { return .unsupportedOS }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .disabled }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        guard #available(macOS 13.0, *) else {
            throw NSError(
                domain: "MoaLaunchAtLogin",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: MoaL10n.text("Automatic Launch at Login requires macOS 13 or later. On macOS 12, add Moa in System Preferences → Users & Groups → Login Items.")]
            )
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw NSError(
                domain: "MoaLaunchAtLogin",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: MoaL10n.text("Launch at Login can only be changed when running Moa.app.")]
            )
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

final class MoaLaunchAtLoginController: ObservableObject {
    @Published private(set) var status: MoaLaunchAtLoginStatus
    @Published private(set) var lastError: String?
    private let backend: MoaLaunchAtLoginManaging

    init(backend: MoaLaunchAtLoginManaging = MoaSystemLaunchAtLoginBackend()) {
        self.backend = backend
        self.status = backend.status()
    }

    func refresh() {
        status = backend.status()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        lastError = nil
        do {
            try backend.setEnabled(enabled)
            status = backend.status()
            return true
        } catch {
            status = backend.status()
            lastError = error.localizedDescription
            return false
        }
    }

    func openSystemSettings() {
        backend.openSystemSettings()
    }
}
