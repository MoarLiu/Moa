import Foundation

struct CodexUsageSummary {
    let todayCostUSD: Double
    let totalCostUSD: Double
    let todayTokens: Int
    let totalTokens: Int
    let cacheHitPercent: Double
    let topModelName: String?
    let topModelTokens: Int
    let topModelPercent: Double
    let updatedAt: Date
}

enum MoaUsageSource: String, Codable, CaseIterable, Hashable {
    case codex
    case claude
    case zcode
    case workbuddy
    case workbuddyCN = "workbuddy-cn"

    var title: String {
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

    var tabTitle: String { title }

    var workBuddyEdition: WorkBuddyEdition? {
        switch self {
        case .workbuddy: return .international
        case .workbuddyCN: return .china
        default: return nil
        }
    }
}

struct MoaUsageDetailRow: Identifiable, Codable, Hashable {
    var source: MoaUsageSource
    var dayKey: String
    var model: String
    var input: Int
    var cachedInput: Int
    var cacheReadInput: Int
    var cacheCreationInput: Int
    var output: Int
    var costUSD: Double
    var pricingModel: String
    var usesFallbackPricing: Bool

    var id: String {
        "\(source.rawValue)|\(dayKey)|\(model)"
    }

    var totalTokens: Int {
        input + cachedInput + cacheReadInput + cacheCreationInput + output
    }

    var cacheTokens: Int {
        cachedInput + cacheReadInput + cacheCreationInput
    }

    var cacheHitTokens: Int {
        cachedInput + cacheReadInput
    }

    mutating func merge(_ row: MoaUsageDetailRow) {
        input += row.input
        cachedInput += row.cachedInput
        cacheReadInput += row.cacheReadInput
        cacheCreationInput += row.cacheCreationInput
        output += row.output
        costUSD += row.costUSD
        usesFallbackPricing = usesFallbackPricing || row.usesFallbackPricing
        if pricingModel.isEmpty {
            pricingModel = row.pricingModel
        }
    }
}

struct MoaUsageReport {
    var rows: [MoaUsageDetailRow]
    var generatedAt: Date

    var totalCostUSD: Double {
        rows.reduce(0) { $0 + $1.costUSD }
    }

    var totalTokens: Int {
        rows.reduce(0) { $0 + $1.totalTokens }
    }

    var cacheHitTokens: Int {
        rows.reduce(0) { $0 + $1.cacheHitTokens }
    }

    var cacheHitPercent: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(cacheHitTokens) / Double(totalTokens) * 100
    }

    var fallbackRows: [MoaUsageDetailRow] {
        var seen = Set<String>()
        return rows
            .filter(\.usesFallbackPricing)
            .sorted { lhs, rhs in
                if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
                return lhs.model < rhs.model
            }
            .filter { row in
                let key = "\(row.source.rawValue)|\(row.model)|\(row.pricingModel)"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    func filtered(source: MoaUsageSource?, recentDays: Int, now: Date = Date()) -> MoaUsageReport {
        let todayKey = Self.dayKey(from: now)
        let since = Calendar.current.date(byAdding: .day, value: -(max(1, recentDays) - 1), to: now) ?? now
        let sinceKey = Self.dayKey(from: since)
        return MoaUsageReport(
            rows: rows.filter { row in
                let sourceMatches = source.map { row.source == $0 } ?? true
                return sourceMatches && row.dayKey >= sinceKey && row.dayKey <= todayKey
            },
            generatedAt: generatedAt
        )
    }

    static func dayKey(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }
}
