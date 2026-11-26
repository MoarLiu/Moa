import AppKit
import SwiftUI

enum MoaTrendChartMetric: String, CaseIterable, Identifiable {
    case cost
    case tokens
    case cacheHit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cost: return MoaL10n.text("Cost")
        case .tokens: return MoaL10n.text("Tokens")
        case .cacheHit: return MoaL10n.text("Cache Hit")
        }
    }
}

enum MoaDistributionDimension: String, CaseIterable, Identifiable {
    case client
    case model

    var id: String { rawValue }

    var title: String {
        switch self {
        case .client: return MoaL10n.text("By Client")
        case .model: return MoaL10n.text("By Model")
        }
    }
}

/// Pure SwiftUI Canvas trend chart compatible with macOS 12.0+ in both light and dark appearances.
struct MoaDailyTrendChartCard: View {
    let points: [MoaUsageDailyPoint]
    @State private var metric: MoaTrendChartMetric = .cost
    @State private var hoveredIndex: Int?

    private var maxValue: Double {
        switch metric {
        case .cost:
            return max(0.10, points.map(\.costUSD).max() ?? 0)
        case .tokens:
            return max(10, Double(points.map(\.totalTokens).max() ?? 0))
        case .cacheHit:
            return 100
        }
    }

    private func metricValue(_ point: MoaUsageDailyPoint) -> Double {
        switch metric {
        case .cost: return point.costUSD
        case .tokens: return Double(point.totalTokens)
        case .cacheHit: return point.cacheHitPercent
        }
    }

    private func formatMetric(_ value: Double) -> String {
        switch metric {
        case .cost:
            return MoaUsageReportExporter.currency(value)
        case .tokens:
            return MoaWorkspaceView.tokens(Int(value.rounded()))
        case .cacheHit:
            return String(format: "%.1f%%", value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MoaL10n.text("Daily Trend"))
                        .font(.system(size: 15, weight: .semibold))
                    if let idx = hoveredIndex, points.indices.contains(idx) {
                        let p = points[idx]
                        Text("\(p.dayKey) · \(MoaUsageReportExporter.currency(p.costUSD)) · \(MoaWorkspaceView.tokens(p.totalTokens)) · \(String(format: "%.1f%%", p.cacheHitPercent))")
                            .font(.system(size: 11))
                            .foregroundStyle(MoaWorkspaceTheme.accent)
                            .monospacedDigit()
                    } else {
                        Text(MoaL10n.text("Hover over any day to inspect cost, tokens, and cache hit rate."))
                            .font(.system(size: 11))
                            .foregroundStyle(MoaWorkspaceTheme.secondary)
                    }
                }
                Spacer(minLength: 8)
                Picker(MoaL10n.text("Chart Metric"), selection: $metric) {
                    ForEach(MoaTrendChartMetric.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            if points.isEmpty {
                Text(MoaL10n.text("No usage records in the selected range."))
                    .font(.system(size: 12))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 168, alignment: .center)
            } else {
                chartBody
                    .frame(height: 176)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private var chartBody: some View {
        GeometryReader { geo in
            let leftAxisWidth: CGFloat = 52
            let bottomAxisHeight: CGFloat = 20
            let plotWidth = max(40, geo.size.width - leftAxisWidth - 8)
            let plotHeight = max(40, geo.size.height - bottomAxisHeight - 8)
            let topPadding: CGFloat = 6

            ZStack(alignment: .topLeading) {
                // Y-axis labels
                VStack {
                    Text(formatMetric(maxValue))
                    Spacer()
                    Text(formatMetric(maxValue * 0.5))
                    Spacer()
                    Text(formatMetric(0))
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(MoaWorkspaceTheme.secondary)
                .frame(width: leftAxisWidth - 6, height: plotHeight, alignment: .trailing)
                .offset(y: topPadding)

                // Plot Canvas
                Canvas { context, size in
                    let gridColor = MoaWorkspaceTheme.border
                    let accent = MoaWorkspaceTheme.accent
                    let success = MoaWorkspaceTheme.success

                    // 3 horizontal gridlines
                    for step in 0...2 {
                        let y = topPadding + plotHeight * CGFloat(step) / 2.0
                        var line = Path()
                        line.move(to: CGPoint(x: leftAxisWidth, y: y))
                        line.addLine(to: CGPoint(x: leftAxisWidth + plotWidth, y: y))
                        context.stroke(line, with: .color(gridColor), lineWidth: 0.75)
                    }

                    let count = points.count
                    guard count > 0 else { return }
                    let slotWidth = plotWidth / CGFloat(count)

                    if metric == .cacheHit {
                        var linePath = Path()
                        var areaPath = Path()
                        var coords: [CGPoint] = []
                        for (index, point) in points.enumerated() {
                            let x = leftAxisWidth + (CGFloat(index) + 0.5) * slotWidth
                            let normalized = min(1, max(0, metricValue(point) / maxValue))
                            let y = topPadding + plotHeight * (1 - CGFloat(normalized))
                            coords.append(CGPoint(x: x, y: y))
                        }
                        if let first = coords.first, let last = coords.last {
                            linePath.move(to: first)
                            areaPath.move(to: CGPoint(x: first.x, y: topPadding + plotHeight))
                            areaPath.addLine(to: first)
                            for pt in coords.dropFirst() {
                                linePath.addLine(to: pt)
                                areaPath.addLine(to: pt)
                            }
                            areaPath.addLine(to: CGPoint(x: last.x, y: topPadding + plotHeight))
                            areaPath.closeSubpath()
                            context.fill(areaPath, with: .color(success.opacity(0.14)))
                            context.stroke(linePath, with: .color(success), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            for (index, pt) in coords.enumerated() {
                                let radius: CGFloat = hoveredIndex == index ? 4.5 : (count <= 31 ? 2.5 : 1.5)
                                let dot = Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
                                context.fill(dot, with: .color(hoveredIndex == index ? accent : success))
                            }
                        }
                    } else {
                        let barWidth = max(2, min(24, slotWidth * 0.68))
                        for (index, point) in points.enumerated() {
                            let val = metricValue(point)
                            let normalized = min(1, max(0, val / maxValue))
                            let barHeight = max(val > 0 ? 2 : 0, plotHeight * CGFloat(normalized))
                            let x = leftAxisWidth + (CGFloat(index) + 0.5) * slotWidth - barWidth / 2
                            let y = topPadding + plotHeight - barHeight
                            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                            let radius = min(4, barWidth / 2)
                            let path = Path(roundedRect: rect, cornerRadius: radius)
                            let isHovered = hoveredIndex == index
                            context.fill(path, with: .color(isHovered ? accent : accent.opacity(0.75)))
                        }
                    }
                }
                .overlay(
                    HStack(spacing: 0) {
                        ForEach(Array(points.indices), id: \.self) { idx in
                            Color.clear
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering {
                                        hoveredIndex = idx
                                    } else if hoveredIndex == idx {
                                        hoveredIndex = nil
                                    }
                                }
                        }
                    }
                    .frame(width: plotWidth, height: plotHeight)
                    .offset(x: leftAxisWidth, y: topPadding),
                    alignment: .topLeading
                )

                // Sparse X-axis labels
                xAxisLabels(leftAxisWidth: leftAxisWidth, plotWidth: plotWidth)
                    .offset(y: topPadding + plotHeight + 4)
            }
        }
    }

    private func xAxisLabels(leftAxisWidth: CGFloat, plotWidth: CGFloat) -> some View {
        let indices = labelIndices(count: points.count)
        return ZStack(alignment: .leading) {
            ForEach(indices, id: \.self) { index in
                let fraction = points.count == 1 ? 0.5 : (CGFloat(index) + 0.5) / CGFloat(points.count)
                Text(points[index].shortLabel)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                    .position(x: leftAxisWidth + plotWidth * fraction, y: 8)
            }
        }
        .frame(height: 16)
    }

    private func labelIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 6 { return Array(0..<count) }
        let tickCount = 5
        return (0..<tickCount).map { slot in
            Int((Double(slot) * Double(count - 1) / Double(tickCount - 1)).rounded())
        }
    }
}

/// Proportional breakdown chart (stacked bar + ranked legend) for Clients or Models.
struct MoaUsageDistributionCard: View {
    let clientAggregates: [MoaUsageClientAggregate]
    let modelAggregates: [MoaUsageModelAggregate]
    @State private var dimension: MoaDistributionDimension = .client

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let costUSD: Double
        let tokens: Int
        let sharePercent: Double
        let color: Color
    }

    private static let palette: [Color] = [
        Color(red: 0.14, green: 0.36, blue: 0.76),
        Color(red: 0.16, green: 0.56, blue: 0.44),
        Color(red: 0.85, green: 0.52, blue: 0.14),
        Color(red: 0.54, green: 0.32, blue: 0.76),
        Color(red: 0.78, green: 0.28, blue: 0.34),
        Color(red: 0.20, green: 0.58, blue: 0.72),
        Color(red: 0.48, green: 0.54, blue: 0.60)
    ]

    private var slices: [Slice] {
        switch dimension {
        case .client:
            let totalCost = clientAggregates.reduce(0) { $0 + $1.costUSD }
            let totalTokens = clientAggregates.reduce(0) { $0 + $1.totalTokens }
            return clientAggregates.prefix(6).enumerated().map { idx, agg in
                let share = totalCost > 0 ? agg.costSharePercent : (totalTokens > 0 ? agg.tokenSharePercent : 0)
                return Slice(
                    id: agg.id,
                    label: agg.source.title,
                    costUSD: agg.costUSD,
                    tokens: agg.totalTokens,
                    sharePercent: share,
                    color: Self.palette[idx % Self.palette.count]
                )
            }
        case .model:
            let top = Array(modelAggregates.prefix(5))
            let rest = Array(modelAggregates.dropFirst(5))
            let totalCost = modelAggregates.reduce(0) { $0 + $1.costUSD }
            let totalTokens = modelAggregates.reduce(0) { $0 + $1.totalTokens }
            var items = top.enumerated().map { idx, agg in
                let share = totalCost > 0 ? agg.costSharePercent : (totalTokens > 0 ? agg.tokenSharePercent : 0)
                return Slice(
                    id: agg.id,
                    label: agg.model,
                    costUSD: agg.costUSD,
                    tokens: agg.totalTokens,
                    sharePercent: share,
                    color: Self.palette[idx % Self.palette.count]
                )
            }
            if !rest.isEmpty {
                let restCost = rest.reduce(0) { $0 + $1.costUSD }
                let restTokens = rest.reduce(0) { $0 + $1.totalTokens }
                let share = totalCost > 0
                    ? (restCost / totalCost * 100)
                    : (totalTokens > 0 ? Double(restTokens) / Double(totalTokens) * 100 : 0)
                items.append(Slice(
                    id: "__other__",
                    label: MoaL10n.format("Other (%lld models)", rest.count),
                    costUSD: restCost,
                    tokens: restTokens,
                    sharePercent: share,
                    color: Self.palette[6]
                ))
            }
            return items
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(MoaL10n.text("Usage Share"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker(MoaL10n.text("Breakdown Dimension"), selection: $dimension) {
                    ForEach(MoaDistributionDimension.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            if slices.isEmpty {
                Text(MoaL10n.text("No usage records in the selected range."))
                    .font(.system(size: 12))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 168, alignment: .center)
            } else {
                GeometryReader { geo in
                    let totalShare = max(0.001, slices.reduce(0) { $0 + max(0, $1.sharePercent) })
                    HStack(spacing: 2) {
                        ForEach(slices) { slice in
                            let w = max(4, (geo.size.width - CGFloat(max(0, slices.count - 1)) * 2) * CGFloat(max(0, slice.sharePercent) / totalShare))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(slice.color)
                                .frame(width: w, height: 14)
                        }
                    }
                }
                .frame(height: 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(slice.costUSD > 0 ? MoaUsageReportExporter.currency(slice.costUSD) : MoaWorkspaceView.tokens(slice.tokens))
                                .font(.system(size: 12))
                                .monospacedDigit()
                            Text(String(format: "%.1f%%", slice.sharePercent))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(MoaWorkspaceTheme.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }
}
