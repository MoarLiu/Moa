import AppKit
import Foundation

enum CodexUsageMenuState {
    case idle
    case loading(CodexUsageSummary?)
    case loaded(CodexUsageSummary)
    case failed(CodexUsageSummary?, String)
}

final class CodexUsageSummaryMenuView: NSView {
    private static let menuWidth: CGFloat = 300
    private static let menuHeight: CGFloat = 128
    private static let leftX: CGFloat = 16
    private static let centerX: CGFloat = 104
    private static let rightX: CGFloat = 192
    private static let costRightX: CGFloat = 166
    private static let usageColumnWidth: CGFloat = 84
    private static let costColumnWidth: CGFloat = 118
    private static let fullWidth: CGFloat = 268
    private let todayCaption = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let monthCaption = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let todayValue = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
    private let monthValue = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
    private let monthTokensCaption = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let latestTokensCaption = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let cacheHitCaption = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    private let monthTokensValue = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
    private let latestTokensValue = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
    private let cacheHitValue = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
    private let topModelLine = CodexUsageSummaryMenuView.label(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
    private var currentState: CodexUsageMenuState = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.menuWidth, height: Self.menuHeight)))
        [
            todayCaption,
            monthCaption,
            todayValue,
            monthValue,
            monthTokensCaption,
            latestTokensCaption,
            cacheHitCaption,
            monthTokensValue,
            latestTokensValue,
            cacheHitValue,
            topModelLine
        ].forEach(addSubview)
        todayCaption.stringValue = MoaL10n.text("Today Cost")
        monthCaption.stringValue = MoaL10n.text("Total Cost")
        monthTokensCaption.stringValue = MoaL10n.text("Today Usage")
        latestTokensCaption.stringValue = MoaL10n.text("Total Usage")
        cacheHitCaption.stringValue = MoaL10n.text("Cache Hit")
        apply(.idle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.menuWidth, height: Self.menuHeight)
    }

    override func layout() {
        super.layout()
        topModelLine.frame = NSRect(x: Self.leftX, y: 105, width: Self.fullWidth, height: 17)
        todayCaption.frame = NSRect(x: Self.leftX, y: 78, width: Self.costColumnWidth, height: 18)
        monthCaption.frame = NSRect(x: Self.costRightX, y: 78, width: Self.costColumnWidth, height: 18)
        todayValue.frame = NSRect(x: Self.leftX, y: 55, width: Self.costColumnWidth, height: 23)
        monthValue.frame = NSRect(x: Self.costRightX, y: 55, width: Self.costColumnWidth, height: 23)
        monthTokensCaption.frame = NSRect(x: Self.leftX, y: 28, width: Self.usageColumnWidth, height: 18)
        latestTokensCaption.frame = NSRect(x: Self.centerX, y: 28, width: Self.usageColumnWidth, height: 18)
        cacheHitCaption.frame = NSRect(x: Self.rightX, y: 28, width: Self.usageColumnWidth, height: 18)
        monthTokensValue.frame = NSRect(x: Self.leftX, y: 5, width: Self.usageColumnWidth, height: 23)
        latestTokensValue.frame = NSRect(x: Self.centerX, y: 5, width: Self.usageColumnWidth, height: 23)
        cacheHitValue.frame = NSRect(x: Self.rightX, y: 5, width: Self.usageColumnWidth, height: 23)
    }

    func apply(_ state: CodexUsageMenuState) {
        currentState = state
        switch state {
        case .idle:
            todayValue.stringValue = "—"
            monthValue.stringValue = "—"
            monthTokensValue.stringValue = "—"
            latestTokensValue.stringValue = "—"
            cacheHitValue.stringValue = "—"
            topModelLine.stringValue = "\(MoaL10n.text("Top Model")): —"
        case .loading(let previous):
            if let previous {
                applyLoaded(previous)
            } else {
                todayValue.stringValue = "..."
                monthValue.stringValue = "..."
                monthTokensValue.stringValue = "..."
                latestTokensValue.stringValue = "..."
                cacheHitValue.stringValue = "..."
                topModelLine.stringValue = "\(MoaL10n.text("Top Model")): ..."
            }
        case .loaded(let summary):
            applyLoaded(summary)
        case .failed(let previous, let message):
            if let previous {
                applyLoaded(previous)
            } else {
                todayValue.stringValue = "—"
                monthValue.stringValue = "—"
                monthTokensValue.stringValue = "—"
                latestTokensValue.stringValue = "—"
                cacheHitValue.stringValue = "—"
                topModelLine.stringValue = "\(MoaL10n.text("Top Model")): —"
            }
            toolTip = "\(MoaL10n.text("Usage update failed")): \(message)"
        }
        needsLayout = true
    }

    private func applyLoaded(_ summary: CodexUsageSummary) {
        todayValue.stringValue = Self.currency(summary.todayCostUSD)
        monthValue.stringValue = Self.currency(summary.totalCostUSD)
        monthTokensValue.stringValue = Self.tokens(summary.todayTokens)
        latestTokensValue.stringValue = Self.tokens(summary.totalTokens)
        cacheHitValue.stringValue = Self.percent(summary.cacheHitPercent)
        if let topModel = summary.topModelName {
            let displayModel = Self.displayModelName(topModel)
            let topModelText = "\(MoaL10n.text("Top Model")): \(displayModel) (\(MoaL10n.text("Usage Rate")): \(String(format: "%.1f%%", summary.topModelPercent)))"
            topModelLine.stringValue = topModelText
            toolTip = topModelText
        } else {
            topModelLine.stringValue = "\(MoaL10n.text("Top Model")): —"
            toolTip = nil
        }
    }

    private static func label(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        return label
    }

    private static func displayModelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("claude-") {
            return String(trimmed.dropFirst("claude-".count))
        }
        return trimmed
    }

    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func tokens(_ value: Int) -> String {
        let double = Double(value)
        if value >= 1_000_000_000 {
            return compact(double / 1_000_000_000, suffix: "B", decimals: 1)
        }
        if value >= 1_000_000 {
            let decimals = value < 10_000_000 ? 1 : 0
            return compact(double / 1_000_000, suffix: "M", decimals: decimals)
        }
        if value >= 1_000 {
            return compact(double / 1_000, suffix: "K", decimals: 0)
        }
        return "\(value)"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }

    private static func compact(_ value: Double, suffix: String, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if decimals > 0 {
            while text.last == "0" {
                text.removeLast()
            }
            if text.last == "." {
                text.removeLast()
            }
        }
        return "\(text)\(suffix)"
    }
}

final class CodexUsageRefreshMenuView: NSView {
    private static let menuWidth: CGFloat = 300
    private static let menuHeight: CGFloat = 28
    var onRefresh: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: MoaL10n.text("Refresh Status"))
    private var isRefreshing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.menuWidth, height: Self.menuHeight)))
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.menuWidth, height: Self.menuHeight)
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 22, y: 6, width: max(0, bounds.width - 34), height: 17)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRefreshing else { return }
        onRefresh?()
    }

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        titleLabel.stringValue = refreshing ? MoaL10n.text("Refreshing Status...") : MoaL10n.text("Refresh Status")
        titleLabel.textColor = refreshing ? .secondaryLabelColor : .labelColor
    }
}
