import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MoaUsageReportBatch {
    var report: MoaUsageReport?
    var failures: [String]

    static func load(now: Date, sources: [(MoaUsageSource, () throws -> MoaUsageReport)]) -> Self {
        var rows: [MoaUsageDetailRow] = []
        var failures: [String] = []
        var successes = 0
        for (source, read) in sources {
            do {
                rows += try read().rows
                successes += 1
            } catch {
                failures.append("\(source.title): \(error.localizedDescription)")
            }
        }
        return Self(report: successes > 0 ? MoaUsageReport(rows: rows, generatedAt: now) : nil, failures: failures)
    }
}

final class MoaUsageInsightsWindowController {
    typealias UsageAlertThresholdProvider = (DailyUsageAlertKind) -> Double?
    typealias UsageAlertSettingsAction = (DailyUsageAlertKind) -> Void

    private let codexScanner: CodexUsageScanner
    private let claudeScanner: ClaudeUsageScanner
    private let zcodeScanner: ZCodeUsageScanner
    private let workbuddyScanner: WorkBuddyUsageScanner
    private let workbuddyCNScanner: WorkBuddyUsageScanner
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let usageAlertThresholdProvider: UsageAlertThresholdProvider
    private let usageAlertSettingsAction: UsageAlertSettingsAction
    private var window: NSWindow?
    private var model: MoaUsageInsightsViewModel?

    var isVisible: Bool { window?.isVisible == true }

    func refreshAfterPricingUpdate() {
        if isVisible { model?.refresh(forceRefresh: true) }
    }

    init(
        codexScanner: CodexUsageScanner,
        claudeScanner: ClaudeUsageScanner,
        zcodeScanner: ZCodeUsageScanner,
        workbuddyScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(),
        workbuddyCNScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(edition: .china),
        pricingOverrides: MoaUsagePricingOverrideController = MoaUsagePricingOverrideController(),
        usageAlertThresholdProvider: @escaping UsageAlertThresholdProvider = { _ in nil },
        usageAlertSettingsAction: @escaping UsageAlertSettingsAction = { _ in }
    ) {
        self.codexScanner = codexScanner
        self.claudeScanner = claudeScanner
        self.zcodeScanner = zcodeScanner
        self.workbuddyScanner = workbuddyScanner
        self.workbuddyCNScanner = workbuddyCNScanner
        self.pricingOverrides = pricingOverrides
        self.usageAlertThresholdProvider = usageAlertThresholdProvider
        self.usageAlertSettingsAction = usageAlertSettingsAction
    }

    func show(initialSource: MoaUsageSource? = nil) {
        let window = existingOrNewWindow(initialSource: initialSource)
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewWindow(initialSource: MoaUsageSource?) -> NSWindow {
        if let window {
            if let initialSource {
                model?.selectedSource = initialSource
            }
            model?.refresh(forceRefresh: false)
            return window
        }

        let model = MoaUsageInsightsViewModel(
            codexScanner: codexScanner,
            claudeScanner: claudeScanner,
            zcodeScanner: zcodeScanner,
            workbuddyScanner: workbuddyScanner,
            workbuddyCNScanner: workbuddyCNScanner,
            pricingOverrides: pricingOverrides,
            usageAlertThresholdProvider: usageAlertThresholdProvider,
            usageAlertSettingsAction: usageAlertSettingsAction,
            initialSource: initialSource
        )
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = MoaL10n.text("Usage Insights")
        window.minSize = NSSize(width: 1100, height: 600)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        let hostingView = MoaInteractiveHostingView(rootView: MoaUsageInsightsView(model: model))
        // 不让内容高度反向撑大窗口:否则 30d 视图行数多会把窗口顶得很高。
        // 关闭内容驱动尺寸后,窗口固定在创建尺寸(7d/30d 一致),表格内部自行滚动。
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        window.contentView = hostingView
        self.window = window
        return window
    }
}

private final class MoaUsageInsightsViewModel: ObservableObject {
    @Published var report = MoaUsageReport(rows: [], generatedAt: Date())
    @Published var selectedSource: MoaUsageSource?
    @Published var recentDays = 30
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var pendingForceRefresh = false

    private let codexScanner: CodexUsageScanner
    private let claudeScanner: ClaudeUsageScanner
    private let zcodeScanner: ZCodeUsageScanner
    private let workbuddyScanner: WorkBuddyUsageScanner
    private let workbuddyCNScanner: WorkBuddyUsageScanner
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let usageAlertThresholdProvider: MoaUsageInsightsWindowController.UsageAlertThresholdProvider
    private let usageAlertSettingsAction: MoaUsageInsightsWindowController.UsageAlertSettingsAction

    init(
        codexScanner: CodexUsageScanner,
        claudeScanner: ClaudeUsageScanner,
        zcodeScanner: ZCodeUsageScanner,
        workbuddyScanner: WorkBuddyUsageScanner,
        workbuddyCNScanner: WorkBuddyUsageScanner,
        pricingOverrides: MoaUsagePricingOverrideController,
        usageAlertThresholdProvider: @escaping MoaUsageInsightsWindowController.UsageAlertThresholdProvider,
        usageAlertSettingsAction: @escaping MoaUsageInsightsWindowController.UsageAlertSettingsAction,
        initialSource: MoaUsageSource?
    ) {
        self.codexScanner = codexScanner
        self.claudeScanner = claudeScanner
        self.zcodeScanner = zcodeScanner
        self.workbuddyScanner = workbuddyScanner
        self.workbuddyCNScanner = workbuddyCNScanner
        self.pricingOverrides = pricingOverrides
        self.usageAlertThresholdProvider = usageAlertThresholdProvider
        self.usageAlertSettingsAction = usageAlertSettingsAction
        selectedSource = initialSource
        refresh(forceRefresh: false)
    }

    var filteredReport: MoaUsageReport {
        report.filtered(source: selectedSource, recentDays: recentDays)
    }

    var filteredRows: [MoaUsageDetailRow] {
        filteredReport.rows.sorted { lhs, rhs in
            if lhs.dayKey != rhs.dayKey { return lhs.dayKey > rhs.dayKey }
            if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
            return lhs.model < rhs.model
        }
    }

    var fallbackRows: [MoaUsageDetailRow] {
        filteredReport.fallbackRows
    }

    var selectedAlertKind: DailyUsageAlertKind? {
        switch selectedSource {
        case .some(.codex):
            return .codex
        case .some(.claude):
            return .claude
        case .some(.zcode):
            return .zcode
        case .some(.workbuddy):
            return .workbuddy
        case .some(.workbuddyCN):
            return .workbuddyCN
        case .none:
            return nil
        }
    }

    var workBuddyScopeNote: String {
        if let edition = selectedSource?.workBuddyEdition {
            return edition.localized("WorkBuddy AI: all local accounts. API price estimates are not credits or subscription bills. Unpriced models contribute tokens only; set a custom price to include their cost.")
        }
        return MoaL10n.text("WorkBuddy and WorkBuddy AI are separate sources. Reports use USD API reference prices, not credits. Unpriced models contribute tokens only.")
    }

    var usageAlertThreshold: Double? {
        selectedAlertKind.flatMap { usageAlertThresholdProvider($0) }
    }

    var todayCostForSelectedSource: Double {
        let todayKey = MoaUsageReport.dayKey(from: Date())
        return filteredReport.rows
            .filter { $0.dayKey == todayKey }
            .reduce(0) { $0 + $1.costUSD }
    }

    var alertStatusText: String {
        guard let kind = selectedAlertKind else {
            return MoaL10n.text("Choose a source to view its daily usage alert threshold.")
        }
        guard let threshold = usageAlertThreshold else {
            return String(format: MoaL10n.text("%@ daily usage alert is off."), kind.displayName)
        }
        let thresholdText = DailyUsageAlertController.currency(threshold)
        let todayText = DailyUsageAlertController.currency(todayCostForSelectedSource)
        if todayCostForSelectedSource >= threshold {
            return String(format: MoaL10n.text("%@ daily usage alert is set to %@. Today's local estimate is %@ and has reached the threshold."), kind.displayName, thresholdText, todayText)
        }
        return String(format: MoaL10n.text("%@ daily usage alert is set to %@. Today's local estimate is %@."), kind.displayName, thresholdText, todayText)
    }

    func openDailyUsageAlertSettings() {
        guard let kind = selectedAlertKind else {
            selectedSource = .codex
            usageAlertSettingsAction(.codex)
            return
        }
        usageAlertSettingsAction(kind)
        objectWillChange.send()
    }

    func refresh(forceRefresh: Bool) {
        guard !isLoading else {
            pendingForceRefresh = pendingForceRefresh || forceRefresh
            return
        }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .utility).async {
            let now = Date()
            let result = MoaUsageReportBatch.load(now: now, sources: [
                (.codex, { try self.codexScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.claude, { try self.claudeScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.zcode, { try self.zcodeScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.workbuddy, { try self.workbuddyScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.workbuddyCN, { try self.workbuddyCNScanner.loadReport(forceRefresh: forceRefresh, now: now) })
            ])

            DispatchQueue.main.async {
                self.isLoading = false
                if let report = result.report { self.report = report }
                self.errorMessage = result.failures.isEmpty ? nil : result.failures.joined(separator: "\n")
                if self.pendingForceRefresh {
                    self.pendingForceRefresh = false
                    self.refresh(forceRefresh: true)
                }
            }
        }
    }

    func exportCSV() {
        export(ext: "csv", contentType: .commaSeparatedText) {
            MoaUsageReportExporter.csv(report: filteredReport)
        }
    }

    func exportMarkdown() {
        export(ext: "md", contentType: .plainText) {
            MoaUsageReportExporter.markdown(report: filteredReport)
        }
    }

    func setOverride(for row: MoaUsageDetailRow) {
        let existing = pricingOverrides.override(source: row.source, model: row.model)

        var action: CustomPriceFormAction?

        MoaGlassModalHost.runModal(width: 500, fallbackHeight: 450, title: MoaL10n.text("Custom Usage Price")) {
            CustomPriceFormView(
                title: "\(row.source.title) · \(row.model)",
                canRemove: existing != nil,
                initialInput: existing.map { String(format: "%.4f", $0.inputUSDPerMillion) } ?? "",
                initialOutput: existing.map { String(format: "%.4f", $0.outputUSDPerMillion) } ?? "",
                initialCacheRead: existing?.cacheReadUSDPerMillion.map { String(format: "%.4f", $0) } ?? "",
                initialCacheCreation: existing?.cacheCreationUSDPerMillion.map { String(format: "%.4f", $0) } ?? "",
                onSave: { input, output, cacheRead, cacheCreation in
                    action = .save(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
                    NSApp.stopModal(withCode: .OK)
                },
                onRemove: {
                    action = .remove
                    NSApp.stopModal(withCode: .abort)
                },
                onCancel: {
                    NSApp.stopModal(withCode: .cancel)
                }
            )
        }

        guard let action else { return }

        do {
            switch action {
            case .remove:
                try pricingOverrides.remove(source: row.source, model: row.model)
                refresh(forceRefresh: true)
            case let .save(input, output, cacheRead, cacheCreation):
                try pricingOverrides.upsert(
                    source: row.source,
                    model: row.model,
                    inputUSDPerMillion: input,
                    outputUSDPerMillion: output,
                    cacheReadUSDPerMillion: cacheRead,
                    cacheCreationUSDPerMillion: cacheCreation
                )
                refresh(forceRefresh: true)
            }
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func export(ext: String, contentType: UTType, content: () -> String) {
        let panel = NSSavePanel()
        panel.title = MoaL10n.text("Export Usage Report")
        panel.nameFieldStringValue = "Moa-Usage-\(recentDays)d.\(ext)"
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try content().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }
}

private struct MoaUsageInsightsView: View {
    @ObservedObject var model: MoaUsageInsightsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(MoaLiquidWindowBackground())
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: Binding(
                get: { model.selectedSource?.rawValue ?? "all" },
                set: { raw in model.selectedSource = MoaUsageSource(rawValue: raw) }
            )) {
                Text(MoaL10n.text("All Sources")).tag("all")
                ForEach(MoaUsageSource.allCases, id: \.rawValue) { source in
                    Text(source.tabTitle).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 560)

            Picker("", selection: $model.recentDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refresh(forceRefresh: true)
            } label: {
                Label(MoaL10n.text("Refresh"), systemImage: "arrow.clockwise")
            }

            Button {
                model.exportCSV()
            } label: {
                Label("CSV", systemImage: "tablecells")
            }

            Button {
                model.exportMarkdown()
            } label: {
                Label("MD", systemImage: "doc.plaintext")
            }
        }
        .buttonStyle(MoaGlassButtonStyle(tone: .neutral, minWidth: 0, height: 32))
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            if model.selectedSource == nil || model.selectedSource?.workBuddyEdition != nil {
                Text(model.workBuddyScopeNote)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            alertPanel
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.coral)
            }
            table
            fallbackPanel
        }
        .padding(18)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            metric(title: MoaL10n.text("Estimated Cost"), value: MoaUsageReportExporter.currency(model.filteredReport.totalCostUSD))
            metric(title: MoaL10n.text("Tokens"), value: Self.compactTokens(model.filteredReport.totalTokens))
                .help(Self.exactTokens(model.filteredReport.totalTokens))
            metric(title: MoaL10n.text("Cache Hit"), value: Self.percent(model.filteredReport.cacheHitPercent))
            metric(title: MoaL10n.text("Rows"), value: "\(model.filteredRows.count)")
            metric(title: MoaL10n.text("Fallback / Unpriced"), value: "\(model.fallbackRows.count)")
        }
    }

    private var alertPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.usageAlertThreshold == nil ? "bell.slash" : "bell.badge")
                .foregroundStyle(model.usageAlertThreshold == nil ? Color.secondary : MoaTheme.amber)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(MoaL10n.text("Daily Usage Alert"))
                    .font(.system(size: 13, weight: .semibold))
                Text(model.alertStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                model.openDailyUsageAlertSettings()
            } label: {
                Label(MoaL10n.text("Set Alert"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(MoaGlassButtonStyle(tone: .neutral, minWidth: 92, height: 30))
        }
        .padding(12)
        .background(MoaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MoaTheme.subtleBorder, lineWidth: 1))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MoaTheme.subtleBorder, lineWidth: 1))
    }

    private var table: some View {
        Table(model.filteredRows) {
            TableColumn(MoaL10n.text("Date"), value: \.dayKey)
            TableColumn(MoaL10n.text("Source")) { row in
                Text(row.source.title)
            }
            TableColumn(MoaL10n.text("Model")) { row in
                Text(row.model)
                    .lineLimit(1)
            }
            TableColumn(MoaL10n.text("Tokens")) { row in
                Text(Self.compactTokens(row.totalTokens))
                    .monospacedDigit()
                    .help(Self.exactTokens(row.totalTokens))
            }
            TableColumn(MoaL10n.text("Cost")) { row in
                Text(row.pricingModel == "unpriced" ? "—" : MoaUsageReportExporter.currency(row.costUSD))
                    .monospacedDigit()
            }
            TableColumn(MoaL10n.text("Pricing")) { row in
                HStack(spacing: 6) {
                    if row.pricingModel == "unpriced" {
                        MoaStatusTag(title: MoaL10n.text("Unpriced"), tint: MoaTheme.amber)
                            .fixedSize()
                    } else {
                        Text(row.pricingModel)
                        if row.usesFallbackPricing {
                            MoaStatusTag(title: MoaL10n.text("Fallback"), tint: MoaTheme.amber)
                        }
                    }
                    Button {
                        model.setOverride(for: row)
                    } label: {
                        Label(MoaL10n.text("Set Price"), systemImage: "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(MoaL10n.text("Custom Usage Price"))
                }
            }
        }
        .frame(minHeight: 280)
        .background(MoaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fallbackPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MoaL10n.text("Fallback / Unpriced Models"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            if model.fallbackRows.isEmpty {
                Text(MoaL10n.text("No unknown models are using fallback pricing in the current range. Local estimates, fallback pricing, and custom prices do not change official bills."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.fallbackRows) { row in
                    HStack {
                        Text(row.source.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(row.model)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                        Spacer()
                        Text(row.pricingModel == "unpriced" ? MoaL10n.text("Tokens only; cost excluded") : MoaL10n.format("priced as %@", row.pricingModel))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button(MoaL10n.text("Set Price")) {
                            model.setOverride(for: row)
                        }
                        .buttonStyle(MoaGlassButtonStyle(tone: .neutral, minWidth: 0, height: 28))
                    }
                }
                Text(MoaL10n.text("Local estimates, fallback pricing, and custom prices are for Moa reports only and may differ from official bills."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(MoaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MoaTheme.subtleBorder, lineWidth: 1))
    }

    private static func compactTokens(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
        if magnitude >= 10_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        return "\(value)"
    }

    private static func exactTokens(_ value: Int) -> String {
        MoaL10n.format("%@ tokens", "\(value)")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }
}

// 自定义价格弹窗:统一的玻璃风格 SwiftUI 表单(校验改为内联提示)。
enum CustomPriceFormAction {
    case save(input: Double, output: Double, cacheRead: Double?, cacheCreation: Double?)
    case remove
}

private struct CustomPriceFormView: View {
    private enum Field: Hashable {
        case input
        case output
        case cacheRead
        case cacheCreation
    }

    let title: String
    let canRemove: Bool
    let onSave: (Double, Double, Double?, Double?) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    @State private var inputText: String
    @State private var outputText: String
    @State private var cacheReadText: String
    @State private var cacheCreationText: String
    @State private var statusText: String = ""
    @FocusState private var focusedField: Field?

    init(
        title: String,
        canRemove: Bool,
        initialInput: String,
        initialOutput: String,
        initialCacheRead: String,
        initialCacheCreation: String,
        onSave: @escaping (Double, Double, Double?, Double?) -> Void,
        onRemove: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.canRemove = canRemove
        self.onSave = onSave
        self.onRemove = onRemove
        self.onCancel = onCancel
        _inputText = State(initialValue: initialInput)
        _outputText = State(initialValue: initialOutput)
        _cacheReadText = State(initialValue: initialCacheRead)
        _cacheCreationText = State(initialValue: initialCacheCreation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MoaModalHeader(
                icon: "dollarsign.circle.fill",
                title: title,
                message: MoaL10n.text("Custom prices only affect local estimates. They do not change original logs or official billing.")
            )

            TextField(MoaL10n.text("Input USD / 1M tokens"), text: $inputText)
                .moaModalFieldChrome()
                .focused($focusedField, equals: .input)
            TextField(MoaL10n.text("Output USD / 1M tokens"), text: $outputText)
                .moaModalFieldChrome()
                .focused($focusedField, equals: .output)
            TextField(MoaL10n.text("Cache read USD / 1M tokens"), text: $cacheReadText)
                .moaModalFieldChrome()
                .focused($focusedField, equals: .cacheRead)
            TextField(MoaL10n.text("Cache creation USD / 1M tokens"), text: $cacheCreationText)
                .moaModalFieldChrome()
                .focused($focusedField, equals: .cacheCreation)

            Text(statusText.isEmpty ? " " : statusText)
                .font(.system(size: 12))
                .foregroundStyle(MoaTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 16, alignment: .leading)

            HStack(spacing: 10) {
                if canRemove {
                    Button(MoaL10n.text("Remove"), action: requestRemove)
                        .buttonStyle(MoaGlassButtonStyle(tone: .danger, minWidth: 88, height: 34))
                }
                Spacer()
                Button(MoaL10n.text("Cancel"), action: requestCancel)
                    .buttonStyle(MoaGlassButtonStyle(tone: .neutral, minWidth: 78, height: 34))
                    .keyboardShortcut(.cancelAction)
                Button(MoaL10n.text("Save"), action: requestSave)
                    .buttonStyle(MoaGlassButtonStyle(tone: .primary, minWidth: 88, height: 34))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .moaModalFormBody()
        .onSubmit(requestSave)
        .onAppear { focusedField = .input }
    }

    private func requestSave() {
        resignFieldEditor()
        DispatchQueue.main.async {
            save()
        }
    }

    private func requestRemove() {
        resignFieldEditor()
        DispatchQueue.main.async {
            onRemove()
        }
    }

    private func requestCancel() {
        resignFieldEditor()
        DispatchQueue.main.async {
            onCancel()
        }
    }

    private func resignFieldEditor() {
        focusedField = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func save() {
        let input = Double(inputText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let output = Double(outputText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard input > 0 || output > 0 else {
            statusText = MoaL10n.text("Enter a positive input or output price.")
            focusedField = .input
            return
        }
        let cacheRead = Double(cacheReadText.trimmingCharacters(in: .whitespacesAndNewlines))
        let cacheCreation = Double(cacheCreationText.trimmingCharacters(in: .whitespacesAndNewlines))
        onSave(input, output, cacheRead, cacheCreation)
    }
}
