import Foundation

/// Date range selector for Usage Analysis 2.0.
enum MoaUsageDateRangePreset: String, CaseIterable, Identifiable, Hashable {
    case today
    case last7Days = "7d"
    case last30Days = "30d"
    case thisMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return MoaL10n.text("Today")
        case .last7Days: return "7d"
        case .last30Days: return "30d"
        case .thisMonth: return MoaL10n.text("This Month")
        case .custom: return MoaL10n.text("Custom")
        }
    }

    func dayKeyBounds(customStart: Date, customEnd: Date, now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String) {
        let todayKey = MoaUsageReport.dayKey(from: now, calendar: calendar)
        switch self {
        case .today:
            return (todayKey, todayKey)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
            return (MoaUsageReport.dayKey(from: start, calendar: calendar), todayKey)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
            return (MoaUsageReport.dayKey(from: start, calendar: calendar), todayKey)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps) ?? now
            return (MoaUsageReport.dayKey(from: start, calendar: calendar), todayKey)
        case .custom:
            let low = min(customStart, customEnd)
            let high = max(customStart, customEnd)
            return (
                MoaUsageReport.dayKey(from: low, calendar: calendar),
                MoaUsageReport.dayKey(from: high, calendar: calendar)
            )
        }
    }
}

enum MoaUsageViewMode: String, CaseIterable, Identifiable {
    case details
    case byModel
    case byClient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return MoaL10n.text("Daily Details")
        case .byModel: return MoaL10n.text("By Model")
        case .byClient: return MoaL10n.text("By Client")
        }
    }
}

enum MoaUsageSortOrder: String, CaseIterable, Identifiable {
    case dateDesc
    case costDesc
    case tokensDesc
    case modelAsc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateDesc: return MoaL10n.text("Newest First")
        case .costDesc: return MoaL10n.text("Highest Cost")
        case .tokensDesc: return MoaL10n.text("Most Tokens")
        case .modelAsc: return MoaL10n.text("Model Name")
        }
    }
}

struct MoaUsageDailyPoint: Identifiable, Equatable {
    let dayKey: String
    let costUSD: Double
    let totalTokens: Int
    let cacheHitTokens: Int
    let cacheHitPercent: Double
    let cacheSavingsUSD: Double
    let costBySource: [MoaUsageSource: Double]

    var id: String { dayKey }

    var shortLabel: String {
        if dayKey.count >= 10 {
            return String(dayKey.dropFirst(5))
        }
        return dayKey
    }
}

struct MoaUsageModelAggregate: Identifiable, Equatable {
    let model: String
    let sources: [MoaUsageSource]
    let inputTokens: Int
    let cacheTokens: Int
    let cacheHitTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let costUSD: Double
    let cacheSavingsUSD: Double
    let pricingModel: String
    let usesFallbackPricing: Bool
    let costSharePercent: Double
    let tokenSharePercent: Double

    var id: String { model }

    var cacheHitPercent: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(cacheHitTokens) / Double(totalTokens) * 100
    }

    var primarySource: MoaUsageSource {
        sources.first ?? .codex
    }
}

struct MoaUsageClientAggregate: Identifiable, Equatable {
    let source: MoaUsageSource
    let modelCount: Int
    let inputTokens: Int
    let cacheTokens: Int
    let cacheHitTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let costUSD: Double
    let cacheSavingsUSD: Double
    let costSharePercent: Double
    let tokenSharePercent: Double

    var id: String { source.rawValue }

    var cacheHitPercent: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(cacheHitTokens) / Double(totalTokens) * 100
    }
}

enum MoaUsageAnalytics {
    /// Estimates USD saved from prompt cache reads compared to paying full uncached input rates.
    /// Returns 0 for unpriced models or when cache read rate >= input rate.
    static func cacheSavingsUSD(
        for row: MoaUsageDetailRow,
        overrides: MoaUsagePricingOverrideController? = nil
    ) -> Double {
        guard row.pricingModel != "unpriced", row.cacheHitTokens > 0 else { return 0 }
        guard let rates = MoaUsagePricing.referenceRates(source: row.source, model: row.model, overrides: overrides) else {
            return 0
        }
        let perTokenDelta = max(0, rates.inputUSDPerMillion - rates.cacheReadUSDPerMillion) / 1_000_000
        return Double(row.cacheHitTokens) * perTokenDelta
    }

    static func cacheSavingsUSD(
        for report: MoaUsageReport,
        overrides: MoaUsagePricingOverrideController? = nil
    ) -> Double {
        report.rows.reduce(0) { $0 + cacheSavingsUSD(for: $1, overrides: overrides) }
    }

    static func currentMonthCostUSD(
        in report: MoaUsageReport,
        source: MoaUsageSource? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let prefix = MoaUsageReport.monthKey(from: now, calendar: calendar) + "-"
        return report.rows.reduce(0) { sum, row in
            guard row.dayKey.hasPrefix(prefix) else { return sum }
            if let source, row.source != source { return sum }
            return sum + row.costUSD
        }
    }

    /// Generates a contiguous daily series between `startDayKey` and `endDayKey` (capped at 120 days for rendering clarity).
    static func dailySeries(
        from report: MoaUsageReport,
        startDayKey: String,
        endDayKey: String,
        overrides: MoaUsagePricingOverrideController? = nil,
        calendar: Calendar = .current
    ) -> [MoaUsageDailyPoint] {
        var grouped: [String: (cost: Double, tokens: Int, hit: Int, savings: Double, bySource: [MoaUsageSource: Double])] = [:]
        for row in report.rows {
            var bucket = grouped[row.dayKey] ?? (0, 0, 0, 0, [:])
            bucket.cost += row.costUSD
            bucket.tokens += row.totalTokens
            bucket.hit += row.cacheHitTokens
            bucket.savings += cacheSavingsUSD(for: row, overrides: overrides)
            bucket.bySource[row.source, default: 0] += row.costUSD
            grouped[row.dayKey] = bucket
        }

        let keys = dayKeysBetween(startDayKey: startDayKey, endDayKey: endDayKey, calendar: calendar)
        let effectiveKeys = keys.isEmpty ? grouped.keys.sorted() : keys
        return effectiveKeys.map { key in
            let bucket = grouped[key]
            let tokens = bucket?.tokens ?? 0
            let hit = bucket?.hit ?? 0
            return MoaUsageDailyPoint(
                dayKey: key,
                costUSD: bucket?.cost ?? 0,
                totalTokens: tokens,
                cacheHitTokens: hit,
                cacheHitPercent: tokens > 0 ? Double(hit) / Double(tokens) * 100 : 0,
                cacheSavingsUSD: bucket?.savings ?? 0,
                costBySource: bucket?.bySource ?? [:]
            )
        }
    }

    static func aggregateByModel(
        from report: MoaUsageReport,
        overrides: MoaUsagePricingOverrideController? = nil
    ) -> [MoaUsageModelAggregate] {
        let totalCost = report.totalCostUSD
        let totalTokens = report.totalTokens
        var grouped: [String: [MoaUsageDetailRow]] = [:]
        for row in report.rows {
            grouped[row.model, default: []].append(row)
        }
        return grouped.map { model, rows in
            let input = rows.reduce(0) { $0 + $1.input }
            let cache = rows.reduce(0) { $0 + $1.cacheTokens }
            let hit = rows.reduce(0) { $0 + $1.cacheHitTokens }
            let output = rows.reduce(0) { $0 + $1.output }
            let tokens = rows.reduce(0) { $0 + $1.totalTokens }
            let cost = rows.reduce(0) { $0 + $1.costUSD }
            let savings = rows.reduce(0) { $0 + cacheSavingsUSD(for: $1, overrides: overrides) }
            let sources = Array(Set(rows.map(\.source))).sorted { $0.rawValue < $1.rawValue }
            let fallback = rows.contains(where: \.usesFallbackPricing)
            let pricingLabel = rows.first?.pricingModel ?? ""
            return MoaUsageModelAggregate(
                model: model,
                sources: sources,
                inputTokens: input,
                cacheTokens: cache,
                cacheHitTokens: hit,
                outputTokens: output,
                totalTokens: tokens,
                costUSD: cost,
                cacheSavingsUSD: savings,
                pricingModel: pricingLabel,
                usesFallbackPricing: fallback,
                costSharePercent: totalCost > 0 ? (cost / totalCost * 100) : 0,
                tokenSharePercent: totalTokens > 0 ? (Double(tokens) / Double(totalTokens) * 100) : 0
            )
        }.sorted { lhs, rhs in
            if lhs.costUSD != rhs.costUSD { return lhs.costUSD > rhs.costUSD }
            if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
            return lhs.model < rhs.model
        }
    }

    static func aggregateByClient(
        from report: MoaUsageReport,
        overrides: MoaUsagePricingOverrideController? = nil
    ) -> [MoaUsageClientAggregate] {
        let totalCost = report.totalCostUSD
        let totalTokens = report.totalTokens
        var grouped: [MoaUsageSource: [MoaUsageDetailRow]] = [:]
        for row in report.rows {
            grouped[row.source, default: []].append(row)
        }
        return grouped.map { source, rows in
            let input = rows.reduce(0) { $0 + $1.input }
            let cache = rows.reduce(0) { $0 + $1.cacheTokens }
            let hit = rows.reduce(0) { $0 + $1.cacheHitTokens }
            let output = rows.reduce(0) { $0 + $1.output }
            let tokens = rows.reduce(0) { $0 + $1.totalTokens }
            let cost = rows.reduce(0) { $0 + $1.costUSD }
            let savings = rows.reduce(0) { $0 + cacheSavingsUSD(for: $1, overrides: overrides) }
            let modelCount = Set(rows.map(\.model)).count
            return MoaUsageClientAggregate(
                source: source,
                modelCount: modelCount,
                inputTokens: input,
                cacheTokens: cache,
                cacheHitTokens: hit,
                outputTokens: output,
                totalTokens: tokens,
                costUSD: cost,
                cacheSavingsUSD: savings,
                costSharePercent: totalCost > 0 ? (cost / totalCost * 100) : 0,
                tokenSharePercent: totalTokens > 0 ? (Double(tokens) / Double(totalTokens) * 100) : 0
            )
        }.sorted { lhs, rhs in
            if lhs.costUSD != rhs.costUSD { return lhs.costUSD > rhs.costUSD }
            if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
            return lhs.source.rawValue < rhs.source.rawValue
        }
    }

    static func sortedRows(_ rows: [MoaUsageDetailRow], by order: MoaUsageSortOrder) -> [MoaUsageDetailRow] {
        rows.sorted { lhs, rhs in
            switch order {
            case .dateDesc:
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey > rhs.dayKey }
                if lhs.costUSD != rhs.costUSD { return lhs.costUSD > rhs.costUSD }
                return lhs.model < rhs.model
            case .costDesc:
                if lhs.costUSD != rhs.costUSD { return lhs.costUSD > rhs.costUSD }
                if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
                return lhs.dayKey > rhs.dayKey
            case .tokensDesc:
                if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
                if lhs.costUSD != rhs.costUSD { return lhs.costUSD > rhs.costUSD }
                return lhs.dayKey > rhs.dayKey
            case .modelAsc:
                if lhs.model != rhs.model { return lhs.model < rhs.model }
                return lhs.dayKey > rhs.dayKey
            }
        }
    }

    private static func dayKeysBetween(startDayKey: String, endDayKey: String, calendar: Calendar) -> [String] {
        guard let startDate = parseDayKey(startDayKey, calendar: calendar),
              let endDate = parseDayKey(endDayKey, calendar: calendar),
              startDate <= endDate else {
            return []
        }
        let dayDiff = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        guard dayDiff >= 0, dayDiff <= 120 else { return [] }
        return (0...dayDiff).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate).map {
                MoaUsageReport.dayKey(from: $0, calendar: calendar)
            }
        }
    }

    private static func parseDayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
