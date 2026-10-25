import Foundation

enum MoaUsageReportExporter {
    static func csv(report: MoaUsageReport) -> String {
        let header = [
            "date", "source", "model", "input_tokens", "cache_tokens", "output_tokens",
            "total_tokens", "cost_usd", "pricing_model", "fallback_pricing"
        ]
        let rows = report.rows.sorted(by: rowSort).map { row in
            [
                row.dayKey,
                row.source.title,
                row.model,
                String(row.input),
                String(row.cacheTokens),
                String(row.output),
                String(row.totalTokens),
                String(format: "%.6f", row.costUSD),
                row.pricingModel,
                row.usesFallbackPricing ? "true" : "false"
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    static func markdown(report: MoaUsageReport) -> String {
        var lines = [
            "# Moa Usage Report",
            "",
            "- Generated: \(ISO8601DateFormatter().string(from: report.generatedAt))",
            "- Total cost: \(currency(report.totalCostUSD))",
            "- Total tokens: \(report.totalTokens)",
            "",
            "| Date | Source | Model | Input | Cache | Output | Total | Cost | Pricing | Fallback |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |"
        ]
        if report.rows.contains(where: { $0.source.workBuddyEdition != nil }) {
            let clients = Set(report.rows.map(\.source).filter { $0.workBuddyEdition != nil })
                .sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")
            lines.insert("\(clients): each source combines only its own local accounts. Costs are USD API estimates, not credit bills; unpriced models are excluded from cost totals.", at: 2)
            lines.insert("", at: 3)
        }
        for row in report.rows.sorted(by: rowSort) {
            lines.append("| \(md(row.dayKey)) | \(md(row.source.title)) | \(md(row.model)) | \(row.input) | \(row.cacheTokens) | \(row.output) | \(row.totalTokens) | \(currency(row.costUSD)) | \(md(row.pricingModel)) | \(row.usesFallbackPricing ? "Yes" : "No") |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func rowSort(_ lhs: MoaUsageDetailRow, _ rhs: MoaUsageDetailRow) -> Bool {
        if lhs.dayKey != rhs.dayKey { return lhs.dayKey > rhs.dayKey }
        if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
        return lhs.model < rhs.model
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func md(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
