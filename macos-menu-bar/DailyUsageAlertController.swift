import Foundation
import SwiftUI

enum DailyUsageAlertKind: String {
    case codex
    case claude
    case zcode
    case workbuddy
    case workbuddyCN = "workbuddy-cn"

    var displayName: String {
        switch self {
        case .codex:
            return MoaL10n.text("Codex")
        case .claude:
            return MoaL10n.text("Claude Desktop")
        case .zcode:
            return MoaL10n.text("ZCode")
        case .workbuddy:
            return "WorkBuddy AI"
        case .workbuddyCN:
            return WorkBuddyEdition.china.title
        }
    }

    var usageSource: MoaUsageSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .zcode: return .zcode
        case .workbuddy: return .workbuddy
        case .workbuddyCN: return .workbuddyCN
        }
    }
}

enum DailyUsageAlertLevel: Equatable {
    case warning80
    case reached
}

// 每日用量提醒弹窗:统一的玻璃风格 SwiftUI 表单(原生复选框 -> SwiftUI Toggle)。
struct DailyUsageAlertFormView: View {
    let title: String
    let onSave: (Double?, Bool) -> Void
    let onCancel: () -> Void

    @State private var enabled: Bool
    @State private var thresholdText: String
    @State private var warnAt80: Bool
    @State private var statusText: String = ""
    @FocusState private var thresholdFocused: Bool

    init(
        title: String,
        initialEnabled: Bool,
        initialThresholdText: String,
        initialWarnAt80: Bool = false,
        onSave: @escaping (Double?, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        _enabled = State(initialValue: initialEnabled)
        _thresholdText = State(initialValue: initialThresholdText)
        _warnAt80 = State(initialValue: initialWarnAt80)
    }

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "bell.badge.fill",
                title: title,
                message: MoaL10n.text("Moa sends a notification when today's local estimated cost reaches the threshold. This is only a local estimate, not an official bill.")
            )
        } fields: {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(MoaL10n.text("Enable Daily Usage Alert"), isOn: $enabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 7) {
                    MoaModalFieldLabel(text: MoaL10n.text("Daily Alert Threshold (USD)"))
                    TextField(MoaL10n.text("Example: 10"), text: $thresholdText)
                        .moaModalFieldChrome()
                        .accessibilityLabel(MoaL10n.text("Daily Alert Threshold (USD)"))
                        .focused($thresholdFocused)
                        .disabled(!enabled)
                        .opacity(enabled ? 1 : 0.5)
                        .onSubmit(save)
                }

                Toggle(MoaL10n.text("Also notify at 80% of threshold"), isOn: $warnAt80)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.5)

                Text(statusText.isEmpty ? " " : statusText)
                    .id("moa-form-status")
                    .preference(key: MoaFormStatusPreferenceKey.self, value: statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 16, alignment: .leading)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                MoaModalButton(title: MoaL10n.text("Cancel"), action: onCancel)
                MoaModalButton(title: MoaL10n.text("Save"), prominence: .prominent, keyEquivalent: "\r", action: save)
            }
        }
        .onAppear {
            if enabled {
                thresholdFocused = true
            }
        }
    }

    private func save() {
        guard enabled else {
            onSave(nil, false)
            return
        }
        let raw = thresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(raw), value > 0 else {
            statusText = MoaL10n.text("Enter an alert threshold greater than 0.")
            thresholdFocused = true
            return
        }
        onSave(value, warnAt80)
    }
}

enum DailyUsageAlertController {
    private static let thresholdPrefix = "Moa.dailyUsageAlert.threshold."
    private static let alertPrefix = "Moa.dailyUsageAlert.lastAlert."
    private static let warn80EnabledPrefix = "Moa.dailyUsageAlert.warn80Enabled."
    private static let warn80AlertPrefix = "Moa.dailyUsageAlert.lastWarn80."

    static func threshold(for kind: DailyUsageAlertKind, defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: thresholdPrefix + kind.rawValue)
        return value > 0 ? value : nil
    }

    static func setThreshold(_ threshold: Double?, for kind: DailyUsageAlertKind, defaults: UserDefaults = .standard) {
        let key = thresholdPrefix + kind.rawValue
        if let threshold, threshold > 0 {
            defaults.set(threshold, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: alertPrefix + kind.rawValue)
            defaults.removeObject(forKey: warn80AlertPrefix + kind.rawValue)
        }
    }

    static func warning80Enabled(for kind: DailyUsageAlertKind, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: warn80EnabledPrefix + kind.rawValue)
    }

    static func setWarning80Enabled(_ enabled: Bool, for kind: DailyUsageAlertKind, defaults: UserDefaults = .standard) {
        let key = warn80EnabledPrefix + kind.rawValue
        if enabled {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: warn80AlertPrefix + kind.rawValue)
        }
    }

    static func menuTitle(for kind: DailyUsageAlertKind) -> String {
        guard let threshold = threshold(for: kind) else {
            return MoaL10n.text("Daily Usage Alert")
        }
        return "\(MoaL10n.text("Daily Usage Alert")) · \(currency(threshold))"
    }

    static func shouldAlert(kind: DailyUsageAlertKind, summary: CodexUsageSummary, defaults: UserDefaults = .standard) -> Bool {
        pendingAlertLevel(kind: kind, summary: summary, defaults: defaults) == .reached
    }

    static func pendingAlertLevel(
        kind: DailyUsageAlertKind,
        summary: CodexUsageSummary,
        defaults: UserDefaults = .standard
    ) -> DailyUsageAlertLevel? {
        guard let threshold = threshold(for: kind, defaults: defaults) else {
            defaults.removeObject(forKey: alertPrefix + kind.rawValue)
            defaults.removeObject(forKey: warn80AlertPrefix + kind.rawValue)
            return nil
        }

        let signature = "\(dayKey(from: summary.updatedAt))|\(String(format: "%.2f", threshold))"
        let reachedKey = alertPrefix + kind.rawValue
        let warnKey = warn80AlertPrefix + kind.rawValue

        if summary.todayCostUSD >= threshold {
            // Once the full threshold is reached for this day/threshold, suppress
            // any later 80% warning for the same signature.
            defaults.set(signature, forKey: warnKey)
            guard defaults.string(forKey: reachedKey) != signature else {
                return nil
            }
            defaults.set(signature, forKey: reachedKey)
            return .reached
        }

        defaults.removeObject(forKey: reachedKey)

        if warning80Enabled(for: kind, defaults: defaults),
           summary.todayCostUSD >= threshold * 0.8 {
            guard defaults.string(forKey: warnKey) != signature else {
                return nil
            }
            defaults.set(signature, forKey: warnKey)
            return .warning80
        }

        defaults.removeObject(forKey: warnKey)
        return nil
    }

    static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func dayKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
