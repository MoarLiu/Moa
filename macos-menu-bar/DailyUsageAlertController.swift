import Foundation
import SwiftUI

enum DailyUsageAlertKind: String, CaseIterable {
    case codex
    case claude
    case zcode
    case workbuddy
    case workbuddyCN = "workbuddy-cn"
    case antigravity
    case deepseek

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
        case .antigravity:
            return "Antigravity"
        case .deepseek:
            return "DeepSeek Harness"
        }
    }

    var usageSource: MoaUsageSource {
        switch self {
        case .codex: return .codex
        case .claude: return .claude
        case .zcode: return .zcode
        case .workbuddy: return .workbuddy
        case .workbuddyCN: return .workbuddyCN
        case .antigravity: return .antigravity
        case .deepseek: return .deepseek
        }
    }
}

enum MoaCombinedBudgetPeriod: String, CaseIterable, Identifiable {
    case daily
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return MoaL10n.text("Combined Daily Budget")
        case .monthly: return MoaL10n.text("Combined Monthly Budget")
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

    // MARK: - Combined All-Sources Daily & Monthly Budgets

    private static let combinedThresholdPrefix = "Moa.combinedBudget.threshold."
    private static let combinedWarn80Prefix = "Moa.combinedBudget.warn80Enabled."
    private static let combinedLastAlertPrefix = "Moa.combinedBudget.lastAlert."
    private static let combinedLastWarn80Prefix = "Moa.combinedBudget.lastWarn80."

    static func combinedThreshold(for period: MoaCombinedBudgetPeriod, defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: combinedThresholdPrefix + period.rawValue)
        return value > 0 ? value : nil
    }

    static func setCombinedThreshold(_ threshold: Double?, for period: MoaCombinedBudgetPeriod, defaults: UserDefaults = .standard) {
        let key = combinedThresholdPrefix + period.rawValue
        if let threshold, threshold > 0 {
            defaults.set(threshold, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: combinedLastAlertPrefix + period.rawValue)
            defaults.removeObject(forKey: combinedLastWarn80Prefix + period.rawValue)
        }
    }

    static func combinedWarning80Enabled(for period: MoaCombinedBudgetPeriod, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: combinedWarn80Prefix + period.rawValue)
    }

    static func setCombinedWarning80Enabled(_ enabled: Bool, for period: MoaCombinedBudgetPeriod, defaults: UserDefaults = .standard) {
        let key = combinedWarn80Prefix + period.rawValue
        if enabled {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: combinedLastWarn80Prefix + period.rawValue)
        }
    }

    static func hasAnyCombinedBudget(defaults: UserDefaults = .standard) -> Bool {
        combinedThreshold(for: .daily, defaults: defaults) != nil
            || combinedThreshold(for: .monthly, defaults: defaults) != nil
    }

    static func pendingCombinedAlertLevel(
        period: MoaCombinedBudgetPeriod,
        costUSD: Double,
        date: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> DailyUsageAlertLevel? {
        guard let threshold = combinedThreshold(for: period, defaults: defaults) else {
            defaults.removeObject(forKey: combinedLastAlertPrefix + period.rawValue)
            defaults.removeObject(forKey: combinedLastWarn80Prefix + period.rawValue)
            return nil
        }

        let bucketKey = period == .daily ? dayKey(from: date) : MoaUsageReport.monthKey(from: date)
        let signature = "\(bucketKey)|\(String(format: "%.2f", threshold))"
        let reachedKey = combinedLastAlertPrefix + period.rawValue
        let warnKey = combinedLastWarn80Prefix + period.rawValue

        if costUSD >= threshold {
            defaults.set(signature, forKey: warnKey)
            guard defaults.string(forKey: reachedKey) != signature else { return nil }
            defaults.set(signature, forKey: reachedKey)
            return .reached
        }

        defaults.removeObject(forKey: reachedKey)

        if combinedWarning80Enabled(for: period, defaults: defaults),
           costUSD >= threshold * 0.8 {
            guard defaults.string(forKey: warnKey) != signature else { return nil }
            defaults.set(signature, forKey: warnKey)
            return .warning80
        }

        defaults.removeObject(forKey: warnKey)
        return nil
    }

    private static func dayKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}

struct MoaCombinedBudgetFormView: View {
    let onSave: (Double?, Bool, Double?, Bool) -> Void
    let onCancel: () -> Void

    @State private var dailyEnabled: Bool
    @State private var dailyText: String
    @State private var dailyWarn80: Bool
    @State private var monthlyEnabled: Bool
    @State private var monthlyText: String
    @State private var monthlyWarn80: Bool
    @State private var statusText: String = ""

    init(
        initialDailyThreshold: Double?,
        initialDailyWarn80: Bool,
        initialMonthlyThreshold: Double?,
        initialMonthlyWarn80: Bool,
        onSave: @escaping (Double?, Bool, Double?, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        _dailyEnabled = State(initialValue: initialDailyThreshold != nil)
        _dailyText = State(initialValue: initialDailyThreshold.map { String(format: "%.2f", $0) } ?? "")
        _dailyWarn80 = State(initialValue: initialDailyWarn80)
        _monthlyEnabled = State(initialValue: initialMonthlyThreshold != nil)
        _monthlyText = State(initialValue: initialMonthlyThreshold.map { String(format: "%.2f", $0) } ?? "")
        _monthlyWarn80 = State(initialValue: initialMonthlyWarn80)
    }

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "chart.bar.doc.horizontal.fill",
                title: MoaL10n.text("Combined Usage Budgets"),
                message: MoaL10n.text("Set daily and monthly budgets across all local usage sources. Estimates use API reference prices, not official bills.")
            )
        } fields: {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(MoaL10n.text("Enable Combined Daily Budget"), isOn: $dailyEnabled)
                    .toggleStyle(.checkbox).font(.system(size: 13, weight: .medium))
                TextField(MoaL10n.text("Example: 20"), text: $dailyText)
                    .moaModalFieldChrome()
                    .disabled(!dailyEnabled).opacity(dailyEnabled ? 1 : 0.5)
                Toggle(MoaL10n.text("Also notify at 80% of daily budget"), isOn: $dailyWarn80)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    .disabled(!dailyEnabled).opacity(dailyEnabled ? 1 : 0.5)

                Divider()

                Toggle(MoaL10n.text("Enable Combined Monthly Budget"), isOn: $monthlyEnabled)
                    .toggleStyle(.checkbox).font(.system(size: 13, weight: .medium))
                TextField(MoaL10n.text("Example: 200"), text: $monthlyText)
                    .moaModalFieldChrome()
                    .disabled(!monthlyEnabled).opacity(monthlyEnabled ? 1 : 0.5)
                Toggle(MoaL10n.text("Also notify at 80% of monthly budget"), isOn: $monthlyWarn80)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    .disabled(!monthlyEnabled).opacity(monthlyEnabled ? 1 : 0.5)

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
    }

    private func save() {
        var daily: Double?
        if dailyEnabled {
            let trimmed = dailyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Double(trimmed), v.isFinite, v > 0 else {
                statusText = MoaL10n.text("Enter an alert threshold greater than 0.")
                return
            }
            daily = v
        }
        var monthly: Double?
        if monthlyEnabled {
            let trimmed = monthlyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Double(trimmed), v.isFinite, v > 0 else {
                statusText = MoaL10n.text("Enter an alert threshold greater than 0.")
                return
            }
            monthly = v
        }
        onSave(daily, dailyEnabled && dailyWarn80, monthly, monthlyEnabled && monthlyWarn80)
    }
}
