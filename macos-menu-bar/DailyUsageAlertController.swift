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
}

// 每日用量提醒弹窗:统一的玻璃风格 SwiftUI 表单(原生复选框 -> SwiftUI Toggle)。
struct DailyUsageAlertFormView: View {
    let title: String
    let onSave: (Double?) -> Void
    let onCancel: () -> Void

    @State private var enabled: Bool
    @State private var thresholdText: String
    @State private var statusText: String = ""
    @FocusState private var thresholdFocused: Bool

    init(
        title: String,
        initialEnabled: Bool,
        initialThresholdText: String,
        onSave: @escaping (Double?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        _enabled = State(initialValue: initialEnabled)
        _thresholdText = State(initialValue: initialThresholdText)
    }

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "bell.badge.fill",
                title: title,
                message: MoaL10n.text("Moa alerts you when today's local estimated cost reaches the threshold. This is only a local estimate, not an official bill.")
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
            onSave(nil)
            return
        }
        let raw = thresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(raw), value > 0 else {
            statusText = MoaL10n.text("Enter an alert threshold greater than 0.")
            thresholdFocused = true
            return
        }
        onSave(value)
    }
}

enum DailyUsageAlertController {
    private static let thresholdPrefix = "Moa.dailyUsageAlert.threshold."
    private static let alertPrefix = "Moa.dailyUsageAlert.lastAlert."

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
        }
    }

    static func menuTitle(for kind: DailyUsageAlertKind) -> String {
        guard let threshold = threshold(for: kind) else {
            return MoaL10n.text("Daily Usage Alert")
        }
        return "\(MoaL10n.text("Daily Usage Alert")) · \(currency(threshold))"
    }

    static func shouldAlert(kind: DailyUsageAlertKind, summary: CodexUsageSummary, defaults: UserDefaults = .standard) -> Bool {
        guard let threshold = threshold(for: kind, defaults: defaults), summary.todayCostUSD >= threshold else {
            defaults.removeObject(forKey: alertPrefix + kind.rawValue)
            return false
        }

        let signature = "\(dayKey(from: summary.updatedAt))|\(String(format: "%.2f", threshold))"
        let key = alertPrefix + kind.rawValue
        guard defaults.string(forKey: key) != signature else {
            return false
        }

        defaults.set(signature, forKey: key)
        return true
    }

    static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func dayKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
