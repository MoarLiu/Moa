import Foundation

/// Client identity and device-local state are scoped by edition; credentials never cross it.
enum WorkBuddyEdition: String, Codable, CaseIterable {
    case international = "ai"
    case china = "cn"

    var title: String { self == .china ? MoaL10n.text("WorkBuddy") : "WorkBuddy AI" }
    var bundleID: String { self == .china ? "com.tencent.workbuddy.mac" : "com.workbuddy.workbuddy-ai" }
    var authFileName: String { self == .china ? "workbuddy-desktop.info" : "workbuddy-desktop-ai.info" }
    var dataDirectoryName: String { self == .china ? ".workbuddy" : ".workbuddy-ai" }
    // Preserve the international edition's existing accounts and operation-lock inode.
    var accountDirectoryName: String { self == .china ? "workbuddy-cn-accounts" : "workbuddy-accounts" }
    var usageSource: MoaUsageSource { self == .china ? .workbuddyCN : .workbuddy }
    var alertKind: DailyUsageAlertKind { self == .china ? .workbuddyCN : .workbuddy }

    func localized(_ internationalKey: String) -> String {
        let text = MoaL10n.text(internationalKey)
        return self == .china ? text.replacingOccurrences(of: "WorkBuddy AI", with: title) : text
    }

    func acceptsAuthDomain(_ domain: String?) -> Bool {
        guard let domain else { return true }
        let host = URL(string: domain.contains("://") ? domain : "https://" + domain)?.host?.lowercased() ?? ""
        if ["workbuddy.ai", "codebuddy.ai"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return self == .international
        }
        if ["workbuddy.cn", "codebuddy.cn"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return self == .china
        }
        return true // Leave enterprise/self-hosted domains intact.
    }
}
