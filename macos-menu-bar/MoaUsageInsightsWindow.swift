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
    typealias CombinedBudgetSettingsAction = () -> Void

    private let codexScanner: CodexUsageScanner
    private let claudeScanner: ClaudeUsageScanner
    private let zcodeScanner: ZCodeUsageScanner
    private let workbuddyScanner: WorkBuddyUsageScanner
    private let workbuddyCNScanner: WorkBuddyUsageScanner
    private let antigravityScanner: AntigravityUsageScanner
    private let deepseekScanner: DeepSeekUsageScanner
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let usageAlertThresholdProvider: UsageAlertThresholdProvider
    private let usageAlertSettingsAction: UsageAlertSettingsAction
    private let combinedBudgetSettingsAction: CombinedBudgetSettingsAction
    private var window: NSWindow?
    private var model: MoaUsageInsightsViewModel?
    var presentInWorkspace: ((MoaUsageSource?) -> Void)?
    var workspaceVisibility: (() -> Bool)?
    var workspacePricingChanged: (() -> Void)?

    var isVisible: Bool { workspaceVisibility?() ?? (window?.isVisible == true) }

    func refreshIfKey() -> Bool {
        guard window?.isKeyWindow == true else { return false }
        model?.refresh(forceRefresh: true)
        return true
    }

    func refreshAfterPricingUpdate() {
        workspacePricingChanged?()
        if isVisible { model?.refresh(forceRefresh: true) }
    }

    init(
        codexScanner: CodexUsageScanner,
        claudeScanner: ClaudeUsageScanner,
        zcodeScanner: ZCodeUsageScanner,
        workbuddyScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(),
        workbuddyCNScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(edition: .china),
        antigravityScanner: AntigravityUsageScanner = AntigravityUsageScanner(),
        deepseekScanner: DeepSeekUsageScanner = DeepSeekUsageScanner(),
        pricingOverrides: MoaUsagePricingOverrideController = MoaUsagePricingOverrideController(),
        usageAlertThresholdProvider: @escaping UsageAlertThresholdProvider = { _ in nil },
        usageAlertSettingsAction: @escaping UsageAlertSettingsAction = { _ in },
        combinedBudgetSettingsAction: @escaping CombinedBudgetSettingsAction = {}
    ) {
        self.codexScanner = codexScanner
        self.claudeScanner = claudeScanner
        self.zcodeScanner = zcodeScanner
        self.workbuddyScanner = workbuddyScanner
        self.workbuddyCNScanner = workbuddyCNScanner
        self.antigravityScanner = antigravityScanner
        self.deepseekScanner = deepseekScanner
        self.pricingOverrides = pricingOverrides
        self.usageAlertThresholdProvider = usageAlertThresholdProvider
        self.usageAlertSettingsAction = usageAlertSettingsAction
        self.combinedBudgetSettingsAction = combinedBudgetSettingsAction
    }

    func show(initialSource: MoaUsageSource? = nil) {
        if let presentInWorkspace {
            presentInWorkspace(initialSource)
            return
        }
        let window = existingOrNewWindow(initialSource: initialSource)
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func existingOrNewWindow(initialSource: MoaUsageSource?) -> NSWindow {
        if let window {
            model?.selectedSource = initialSource
            model?.refresh(forceRefresh: false)
            return window
        }

        let model = MoaUsageInsightsViewModel(
            codexScanner: codexScanner,
            claudeScanner: claudeScanner,
            zcodeScanner: zcodeScanner,
            workbuddyScanner: workbuddyScanner,
            workbuddyCNScanner: workbuddyCNScanner,
            antigravityScanner: antigravityScanner,
            deepseekScanner: deepseekScanner,
            pricingOverrides: pricingOverrides,
            usageAlertThresholdProvider: usageAlertThresholdProvider,
            usageAlertSettingsAction: usageAlertSettingsAction,
            combinedBudgetSettingsAction: combinedBudgetSettingsAction,
            initialSource: initialSource
        )
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: min(1160, (NSScreen.main?.visibleFrame.width ?? 1240) - 64),
                                height: min(760, (NSScreen.main?.visibleFrame.height ?? 860) - 64)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = MoaL10n.text("Usage Insights")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        let hostingView = MoaInteractiveHostingView(rootView: MoaUsageInsightsView(model: model))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        window.contentView = hostingView
        self.window = window
        return window
    }
}

final class MoaUsageInsightsViewModel: ObservableObject {
    @Published var report = MoaUsageReport(rows: [], generatedAt: Date())
    @Published var selectedSource: MoaUsageSource?
    @Published var dateRange: MoaUsageDateRangePreset = .last30Days
    @Published var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @Published var customEndDate: Date = Date()
    @Published var viewMode: MoaUsageViewMode = .details
    @Published var sortOrder: MoaUsageSortOrder = .dateDesc
    @Published var searchQuery: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var pendingForceRefresh = false

    private let codexScanner: CodexUsageScanner
    private let claudeScanner: ClaudeUsageScanner
    private let zcodeScanner: ZCodeUsageScanner
    private let workbuddyScanner: WorkBuddyUsageScanner
    private let workbuddyCNScanner: WorkBuddyUsageScanner
    private let antigravityScanner: AntigravityUsageScanner
    private let deepseekScanner: DeepSeekUsageScanner
    private let pricingOverrides: MoaUsagePricingOverrideController
    private let usageAlertThresholdProvider: MoaUsageInsightsWindowController.UsageAlertThresholdProvider
    private let usageAlertSettingsAction: MoaUsageInsightsWindowController.UsageAlertSettingsAction
    private let combinedBudgetSettingsAction: MoaUsageInsightsWindowController.CombinedBudgetSettingsAction

    init(
        codexScanner: CodexUsageScanner,
        claudeScanner: ClaudeUsageScanner,
        zcodeScanner: ZCodeUsageScanner,
        workbuddyScanner: WorkBuddyUsageScanner,
        workbuddyCNScanner: WorkBuddyUsageScanner,
        antigravityScanner: AntigravityUsageScanner = AntigravityUsageScanner(),
        deepseekScanner: DeepSeekUsageScanner = DeepSeekUsageScanner(),
        pricingOverrides: MoaUsagePricingOverrideController,
        usageAlertThresholdProvider: @escaping MoaUsageInsightsWindowController.UsageAlertThresholdProvider,
        usageAlertSettingsAction: @escaping MoaUsageInsightsWindowController.UsageAlertSettingsAction,
        combinedBudgetSettingsAction: @escaping MoaUsageInsightsWindowController.CombinedBudgetSettingsAction = {},
        initialSource: MoaUsageSource?
    ) {
        self.codexScanner = codexScanner
        self.claudeScanner = claudeScanner
        self.zcodeScanner = zcodeScanner
        self.workbuddyScanner = workbuddyScanner
        self.workbuddyCNScanner = workbuddyCNScanner
        self.antigravityScanner = antigravityScanner
        self.deepseekScanner = deepseekScanner
        self.pricingOverrides = pricingOverrides
        self.usageAlertThresholdProvider = usageAlertThresholdProvider
        self.usageAlertSettingsAction = usageAlertSettingsAction
        self.combinedBudgetSettingsAction = combinedBudgetSettingsAction
        selectedSource = initialSource
        if !MoaRuntimeMode.isWorkspacePreview { refresh(forceRefresh: false) }
    }

    var activeBounds: (start: String, end: String) {
        dateRange.dayKeyBounds(customStart: customStartDate, customEnd: customEndDate)
    }

    var filteredReport: MoaUsageReport {
        let bounds = activeBounds
        return report.filtered(
            source: selectedSource,
            startDayKey: bounds.start,
            endDayKey: bounds.end,
            searchQuery: searchQuery
        )
    }

    var filteredRows: [MoaUsageDetailRow] {
        MoaUsageAnalytics.sortedRows(filteredReport.rows, by: sortOrder)
    }

    var modelAggregates: [MoaUsageModelAggregate] {
        MoaUsageAnalytics.aggregateByModel(from: filteredReport, overrides: pricingOverrides)
    }

    var clientAggregates: [MoaUsageClientAggregate] {
        MoaUsageAnalytics.aggregateByClient(from: filteredReport, overrides: pricingOverrides)
    }

    var dailyPoints: [MoaUsageDailyPoint] {
        let bounds = activeBounds
        return MoaUsageAnalytics.dailySeries(
            from: filteredReport,
            startDayKey: bounds.start,
            endDayKey: bounds.end,
            overrides: pricingOverrides
        )
    }

    var estimatedCacheSavingsUSD: Double {
        MoaUsageAnalytics.cacheSavingsUSD(for: filteredReport, overrides: pricingOverrides)
    }

    var fallbackRows: [MoaUsageDetailRow] {
        filteredReport.fallbackRows
    }

    var selectedAlertKind: DailyUsageAlertKind? {
        selectedSource.flatMap { DailyUsageAlertKind(rawValue: $0.rawValue) }
    }

    var usageAlertThreshold: Double? {
        selectedAlertKind.flatMap { usageAlertThresholdProvider($0) }
    }

    var todayCostForSelectedSource: Double {
        let todayKey = MoaUsageReport.dayKey(from: Date())
        return report.rows
            .filter { row in
                row.dayKey == todayKey && (selectedSource.map { row.source == $0 } ?? true)
            }
            .reduce(0) { $0 + $1.costUSD }
    }

    var todayCombinedCostUSD: Double {
        let todayKey = MoaUsageReport.dayKey(from: Date())
        return report.rows.filter { $0.dayKey == todayKey }.reduce(0) { $0 + $1.costUSD }
    }

    var currentMonthCombinedCostUSD: Double {
        MoaUsageAnalytics.currentMonthCostUSD(in: report)
    }

    var combinedDailyBudget: Double? {
        DailyUsageAlertController.combinedThreshold(for: .daily)
    }

    var combinedMonthlyBudget: Double? {
        DailyUsageAlertController.combinedThreshold(for: .monthly)
    }

    var workBuddyScopeNote: String {
        if let edition = selectedSource?.workBuddyEdition {
            return edition.localized("WorkBuddy AI: all local accounts. API price estimates are not credits or subscription bills. Unpriced models contribute tokens only; set a custom price to include their cost.")
        }
        return MoaL10n.text("WorkBuddy and WorkBuddy AI are separate sources. Reports use USD API reference prices, not credits. Unpriced models contribute tokens only.")
    }

    var alertStatusText: String {
        guard let kind = selectedAlertKind else {
            return MoaL10n.text("Showing all sources. Configure combined daily/monthly budgets or select a specific source for per-source daily alerts.")
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
            openCombinedBudgetSettings()
            return
        }
        usageAlertSettingsAction(kind)
        objectWillChange.send()
    }

    func openCombinedBudgetSettings() {
        combinedBudgetSettingsAction()
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
                (.workbuddyCN, { try self.workbuddyCNScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.antigravity, { try self.antigravityScanner.loadReport(forceRefresh: forceRefresh, now: now) }),
                (.deepseek, { try self.deepseekScanner.loadReport(forceRefresh: forceRefresh, now: now) })
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

    func exportJSON() {
        export(ext: "json", contentType: .json) {
            MoaUsageReportExporter.json(report: filteredReport, cacheSavingsUSD: estimatedCacheSavingsUSD)
        }
    }

    func setOverride(source: MoaUsageSource, model modelName: String) {
        let changed = MoaCustomPriceModal.present(
            source: source,
            model: modelName,
            pricingOverrides: pricingOverrides
        ) { [weak self] error in
            self?.errorMessage = error.localizedDescription
        }
        if changed {
            refresh(forceRefresh: true)
        }
    }

    func setOverride(for row: MoaUsageDetailRow) {
        setOverride(source: row.source, model: row.model)
    }

    private func export(ext: String, contentType: UTType, content: () -> String) {
        let panel = NSSavePanel()
        panel.title = MoaL10n.text("Export Usage Report")
        let bounds = activeBounds
        panel.nameFieldStringValue = "Moa-Usage-\(bounds.start)-to-\(bounds.end).\(ext)"
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

struct MoaWorkspaceUsageView: View {
    @ObservedObject var navigation: MoaWorkspaceNavigation
    @StateObject private var model: MoaUsageInsightsViewModel

    init(app: AppDelegate, navigation: MoaWorkspaceNavigation) {
        self.navigation = navigation
        _model = StateObject(wrappedValue: MoaUsageInsightsViewModel(
            codexScanner: app.usageCoordinator.codexScanner,
            claudeScanner: app.usageCoordinator.claudeScanner,
            zcodeScanner: app.usageCoordinator.zcodeScanner,
            workbuddyScanner: app.usageCoordinator.workbuddyScanner,
            workbuddyCNScanner: app.usageCoordinator.workbuddyCNScanner,
            antigravityScanner: app.usageCoordinator.antigravityScanner,
            deepseekScanner: app.usageCoordinator.deepseekScanner,
            pricingOverrides: MoaUsagePricingOverrideController(),
            usageAlertThresholdProvider: { DailyUsageAlertController.threshold(for: $0) },
            usageAlertSettingsAction: { [weak app] kind in app?.showWorkspaceUsageAlertSettings(kind: kind) },
            combinedBudgetSettingsAction: { [weak app] in app?.showCombinedUsageBudgetPanel() },
            initialSource: navigation.usageSource
        ))
    }

    var body: some View {
        Group {
            if MoaRuntimeMode.isWorkspacePreview {
                previewContent
            } else {
                MoaUsageInsightsView(model: model)
            }
        }
        .onReceive(navigation.$usageRequest.dropFirst()) { _ in
            model.selectedSource = navigation.usageSource
        }
        .onReceive(navigation.$refreshRequest.dropFirst()) { _ in
            if !MoaRuntimeMode.suppressesUserInteraction { model.refresh(forceRefresh: true) }
        }
        .accessibilityIdentifier("workspace.usage.content")
    }

    private var previewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                workspaceHeading("Usage Analysis", subtitle: "Local records, clear estimates.")
                workspaceNotice(MoaL10n.text("Preview does not scan local usage records."))
                MoaDailyTrendChartCard(points: [])
                MoaUsageDistributionCard(clientAggregates: [], modelAggregates: [])
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MoaWorkspaceTheme.canvas)
    }
}

private struct MoaUsageInsightsView: View {
    @ObservedObject var model: MoaUsageInsightsViewModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(compact: geometry.size.width < 940)
                    filterBar(compact: geometry.size.width < 940)
                    kpiStrip(width: geometry.size.width)
                    chartsSection(compact: geometry.size.width < 980)
                    budgetPanel
                    if let error = model.errorMessage {
                        workspaceNotice(error, tone: MoaTheme.coral)
                    }
                    if model.selectedSource == nil || model.selectedSource?.workBuddyEdition != nil {
                        Text(model.workBuddyScopeNote)
                            .font(.system(size: 12))
                            .foregroundStyle(MoaWorkspaceTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    viewModeBar
                    dataSection(width: geometry.size.width)
                    fallbackPanel
                }
                .padding(geometry.size.width < 900 ? 20 : 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MoaWorkspaceTheme.canvas)
            .foregroundStyle(MoaWorkspaceTheme.text)
            .moaFeedbackBanner()
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            workspaceHeading("Usage Analysis", subtitle: "Local records, trend charts, cache savings, and cost budgets.")
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { model.refresh(forceRefresh: true) } label: {
                    Label(MoaL10n.text("Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(MoaWorkspaceButtonStyle())
                .disabled(model.isLoading)

                Menu {
                    Button(MoaL10n.text("Export CSV")) { model.exportCSV() }
                    Button(MoaL10n.text("Export Markdown")) { model.exportMarkdown() }
                    Button(MoaL10n.text("Export JSON")) { model.exportJSON() }
                } label: {
                    Label(MoaL10n.text("Export"), systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isLoading)
            }
        }
    }

    private func filterBar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker(MoaL10n.text("Usage Source"), selection: Binding(
                    get: { model.selectedSource?.rawValue ?? "all" },
                    set: { model.selectedSource = MoaUsageSource(rawValue: $0) }
                )) {
                    Text(MoaL10n.text("All Sources")).tag("all")
                    ForEach(MoaUsageSource.allCases, id: \.rawValue) { source in
                        Text(source.tabTitle).tag(source.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 200)
                .accessibilityLabel(MoaL10n.text("Usage Source"))

                Picker(MoaL10n.text("Date Range"), selection: $model.dateRange) {
                    ForEach(MoaUsageDateRangePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .accessibilityLabel(MoaL10n.text("Date Range"))

                if !compact {
                    Spacer(minLength: 8)
                    searchField.frame(width: 210)
                }
            }

            if model.dateRange == .custom {
                HStack(spacing: 16) {
                    DatePicker(MoaL10n.text("From"), selection: $model.customStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker(MoaL10n.text("To"), selection: $model.customEndDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    Spacer()
                }
                .font(.system(size: 12))
            }

            if compact {
                searchField
            }
        }
        .padding(14)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MoaWorkspaceTheme.secondary)
            TextField(MoaL10n.text("Filter models or sources…"), text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !model.searchQuery.isEmpty {
                Button { model.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MoaWorkspaceTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MoaWorkspaceTheme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private func kpiStrip(width: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: width >= 980 ? 5 : 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            metricCard(
                title: MoaL10n.text("Estimated Cost"),
                value: MoaUsageReportExporter.currency(model.filteredReport.totalCostUSD),
                detail: MoaL10n.format("%lld records", model.filteredRows.count)
            )
            metricCard(
                title: MoaL10n.text("Tokens"),
                value: Self.compactTokens(model.filteredReport.totalTokens),
                detail: Self.exactTokens(model.filteredReport.totalTokens)
            )
            metricCard(
                title: MoaL10n.text("Cache Hit"),
                value: Self.percent(model.filteredReport.cacheHitPercent),
                detail: Self.compactTokens(model.filteredReport.cacheHitTokens)
            )
            metricCard(
                title: MoaL10n.text("Est. Cache Savings"),
                value: MoaUsageReportExporter.currency(model.estimatedCacheSavingsUSD),
                detail: MoaL10n.text("vs. uncached input"),
                tint: MoaWorkspaceTheme.success
            )
            metricCard(
                title: MoaL10n.text("Fallback / Unpriced"),
                value: "\(model.fallbackRows.count)",
                detail: model.fallbackRows.isEmpty ? MoaL10n.text("All priced") : MoaL10n.text("Review below"),
                tint: model.fallbackRows.isEmpty ? MoaWorkspaceTheme.text : MoaTheme.amber
            )
        }
    }

    private func metricCard(title: String, value: String, detail: String, tint: Color = MoaWorkspaceTheme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MoaWorkspaceTheme.secondary)
            Text(value)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(MoaWorkspaceTheme.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func chartsSection(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 14) {
                MoaDailyTrendChartCard(points: model.dailyPoints)
                MoaUsageDistributionCard(clientAggregates: model.clientAggregates, modelAggregates: model.modelAggregates)
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                MoaDailyTrendChartCard(points: model.dailyPoints)
                    .frame(maxWidth: .infinity)
                MoaUsageDistributionCard(clientAggregates: model.clientAggregates, modelAggregates: model.modelAggregates)
                    .frame(width: 340)
            }
        }
    }

    private var budgetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: (model.usageAlertThreshold != nil || model.combinedDailyBudget != nil || model.combinedMonthlyBudget != nil) ? "bell.badge" : "bell.slash")
                    .foregroundStyle((model.usageAlertThreshold != nil || model.combinedDailyBudget != nil || model.combinedMonthlyBudget != nil) ? MoaTheme.amber : MoaWorkspaceTheme.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MoaL10n.text("Budgets & Usage Alerts"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.alertStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(MoaWorkspaceTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.selectedAlertKind != nil {
                    Button(MoaL10n.text("Source Alert")) { model.openDailyUsageAlertSettings() }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                }
                Button(MoaL10n.text("Combined Budgets")) { model.openCombinedBudgetSettings() }
                    .buttonStyle(MoaWorkspaceButtonStyle())
            }

            if model.combinedDailyBudget != nil || model.combinedMonthlyBudget != nil {
                Divider()
                HStack(spacing: 16) {
                    if let daily = model.combinedDailyBudget {
                        budgetProgress(
                            title: MoaL10n.text("Combined Daily Budget"),
                            spent: model.todayCombinedCostUSD,
                            limit: daily
                        )
                    }
                    if let monthly = model.combinedMonthlyBudget {
                        budgetProgress(
                            title: MoaL10n.text("Combined Monthly Budget"),
                            spent: model.currentMonthCombinedCostUSD,
                            limit: monthly
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private func budgetProgress(title: String, spent: Double, limit: Double) -> some View {
        let ratio = limit > 0 ? min(1, max(0, spent / limit)) : 0
        let tint: Color = spent >= limit ? MoaTheme.coral : (spent >= limit * 0.8 ? MoaTheme.amber : MoaWorkspaceTheme.accent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(MoaWorkspaceTheme.secondary)
                Spacer()
                Text("\(DailyUsageAlertController.currency(spent)) / \(DailyUsageAlertController.currency(limit))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(MoaWorkspaceTheme.border)
                    RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: geo.size.width * CGFloat(ratio))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var viewModeBar: some View {
        HStack(spacing: 12) {
            Picker(MoaL10n.text("View Mode"), selection: $model.viewMode) {
                ForEach(MoaUsageViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            if model.viewMode == .details {
                Picker(MoaL10n.text("Sort Order"), selection: $model.sortOrder) {
                    ForEach(MoaUsageSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    @ViewBuilder
    private func dataSection(width: CGFloat) -> some View {
        switch model.viewMode {
        case .details:
            if width < 956 {
                Text(MoaL10n.text("Scroll horizontally for additional columns and price settings."))
                    .font(.caption).foregroundStyle(MoaWorkspaceTheme.secondary)
            }
            ScrollView(.horizontal) {
                detailsTable.frame(width: max(920, width - 64))
            }
        case .byModel:
            byModelSection
        case .byClient:
            byClientSection
        }
    }

    private var detailsTable: some View {
        Table(model.filteredRows) {
            TableColumn(MoaL10n.text("Date"), value: \.dayKey)
            TableColumn(MoaL10n.text("Source")) { row in
                Text(row.source.title)
            }
            TableColumn(MoaL10n.text("Model")) { row in
                Text(row.model).lineLimit(1)
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
        .frame(height: 320)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private var byModelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.modelAggregates.isEmpty {
                workspaceNotice(MoaL10n.text("No usage records in the selected range."))
            } else {
                Divider()
                ForEach(model.modelAggregates) { agg in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(agg.model).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if agg.pricingModel == "unpriced" {
                                    MoaStatusTag(title: MoaL10n.text("Unpriced"), tint: MoaTheme.amber)
                                } else if agg.usesFallbackPricing {
                                    MoaStatusTag(title: MoaL10n.text("Fallback"), tint: MoaTheme.amber)
                                }
                            }
                            Text(agg.sources.map(\.title).joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(MoaWorkspaceTheme.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Self.compactTokens(agg.totalTokens)).font(.system(size: 12)).monospacedDigit()
                            Text(MoaL10n.format("Cache %@", Self.percent(agg.cacheHitPercent)))
                                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        }
                        .frame(width: 110, alignment: .trailing)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(agg.pricingModel == "unpriced" ? "—" : MoaUsageReportExporter.currency(agg.costUSD))
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            if agg.cacheSavingsUSD > 0.005 {
                                Text(MoaL10n.format("Saved %@", MoaUsageReportExporter.currency(agg.cacheSavingsUSD)))
                                    .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.success)
                            }
                        }
                        .frame(width: 110, alignment: .trailing)

                        Button(MoaL10n.text("Set Price")) {
                            model.setOverride(source: agg.primarySource, model: agg.model)
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    Divider()
                }
            }
        }
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private var byClientSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.clientAggregates.isEmpty {
                workspaceNotice(MoaL10n.text("No usage records in the selected range."))
            } else {
                Divider()
                ForEach(model.clientAggregates) { agg in
                    HStack(spacing: 12) {
                        if let client = MoaClientAdapterRegistry.client(for: agg.source) {
                            MoaClientLogo(client: client, size: 24)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agg.source.title).font(.system(size: 13, weight: .medium))
                            Text(MoaL10n.format("%lld models · Cache %@", agg.modelCount, Self.percent(agg.cacheHitPercent)))
                                .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(Self.compactTokens(agg.totalTokens))
                            .font(.system(size: 12)).monospacedDigit()
                            .frame(width: 90, alignment: .trailing)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(MoaUsageReportExporter.currency(agg.costUSD))
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            if agg.cacheSavingsUSD > 0.005 {
                                Text(MoaL10n.format("Saved %@", MoaUsageReportExporter.currency(agg.cacheSavingsUSD)))
                                    .font(.system(size: 11)).foregroundStyle(MoaWorkspaceTheme.success)
                            }
                        }
                        .frame(width: 110, alignment: .trailing)

                        Text(String(format: "%.1f%%", agg.costSharePercent))
                            .font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(MoaWorkspaceTheme.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    Divider()
                }
            }
        }
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
    }

    private var fallbackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MoaL10n.text("Fallback / Unpriced Models"))
                .font(.system(size: 15, weight: .semibold))

            if model.fallbackRows.isEmpty {
                Text(MoaL10n.text("No unknown models are using fallback pricing in the current range. Local estimates, fallback pricing, and custom prices do not change official bills."))
                    .font(.system(size: 12))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
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
                            .foregroundStyle(MoaWorkspaceTheme.secondary)
                        Button(MoaL10n.text("Set Price")) {
                            model.setOverride(for: row)
                        }
                        .buttonStyle(MoaWorkspaceButtonStyle())
                    }
                }
                Text(MoaL10n.text("Local estimates, fallback pricing, and custom prices are for Moa reports only and may differ from official bills."))
                    .font(.system(size: 12))
                    .foregroundStyle(MoaWorkspaceTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoaWorkspaceTheme.subtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaWorkspaceTheme.border, lineWidth: 1))
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

enum CustomPriceFormAction {
    case save(input: Double, output: Double, cacheRead: Double?, cacheCreation: Double?)
    case remove
}

enum MoaCustomPriceModal {
    @discardableResult
    static func present(
        source: MoaUsageSource,
        model: String,
        pricingOverrides: MoaUsagePricingOverrideController,
        onError: ((Error) -> Void)? = nil
    ) -> Bool {
        let existing = pricingOverrides.override(source: source, model: model)
        var action: CustomPriceFormAction?

        MoaGlassModalHost.runModal(width: 500, fallbackHeight: 450, title: MoaL10n.text("Custom Usage Price")) {
            CustomPriceFormView(
                title: "\(source.title) · \(model)",
                canRemove: existing != nil,
                initialInput: existing.map { String($0.inputUSDPerMillion) } ?? "",
                initialOutput: existing.map { String($0.outputUSDPerMillion) } ?? "",
                initialCacheRead: existing?.cacheReadUSDPerMillion.map { String($0) } ?? "",
                initialCacheCreation: existing?.cacheCreationUSDPerMillion.map { String($0) } ?? "",
                onSave: { input, output, cacheRead, cacheCreation in
                    action = .save(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
                    MoaGlassModalHost.finish(.OK)
                },
                onRemove: {
                    action = .remove
                    MoaGlassModalHost.finish(.abort)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }

        guard let action else { return false }

        do {
            switch action {
            case .remove:
                try pricingOverrides.remove(source: source, model: model)
                return true
            case let .save(input, output, cacheRead, cacheCreation):
                try pricingOverrides.upsert(
                    source: source,
                    model: model,
                    inputUSDPerMillion: input,
                    outputUSDPerMillion: output,
                    cacheReadUSDPerMillion: cacheRead,
                    cacheCreationUSDPerMillion: cacheCreation
                )
                return true
            }
        } catch {
            onError?(error)
            NSSound.beep()
            return false
        }
    }
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
        MoaModalForm {
            MoaModalHeader(
                icon: "dollarsign.circle.fill",
                title: title,
                message: MoaL10n.text("Custom prices only affect local estimates. They do not change original logs or official billing.")
            )
        } fields: {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    MoaModalFieldLabel(text: MoaL10n.text("Input USD / 1M tokens"))
                    TextField("0.00", text: $inputText)
                        .moaModalFieldChrome()
                        .focused($focusedField, equals: .input)
                        .accessibilityLabel(MoaL10n.text("Input USD / 1M tokens"))
                }
                VStack(alignment: .leading, spacing: 7) {
                    MoaModalFieldLabel(text: MoaL10n.text("Output USD / 1M tokens"))
                    TextField("0.00", text: $outputText)
                        .moaModalFieldChrome()
                        .focused($focusedField, equals: .output)
                        .accessibilityLabel(MoaL10n.text("Output USD / 1M tokens"))
                }
                VStack(alignment: .leading, spacing: 7) {
                    MoaModalFieldLabel(text: MoaL10n.text("Cache read USD / 1M tokens"))
                    TextField("0.00", text: $cacheReadText)
                        .moaModalFieldChrome()
                        .focused($focusedField, equals: .cacheRead)
                        .accessibilityLabel(MoaL10n.text("Cache read USD / 1M tokens"))
                }
                VStack(alignment: .leading, spacing: 7) {
                    MoaModalFieldLabel(text: MoaL10n.text("Cache creation USD / 1M tokens"))
                    TextField("0.00", text: $cacheCreationText)
                        .moaModalFieldChrome()
                        .focused($focusedField, equals: .cacheCreation)
                        .accessibilityLabel(MoaL10n.text("Cache creation USD / 1M tokens"))
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
                if canRemove {
                    MoaModalButton(title: MoaL10n.text("Remove"), action: requestRemove)
                }
                Spacer()
                MoaModalButton(title: MoaL10n.text("Cancel"), action: requestCancel)
                MoaModalButton(title: MoaL10n.text("Save"), prominence: .prominent, keyEquivalent: "\r", action: requestSave)
            }
        }
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
        do {
            let prices = try MoaCustomPrices.parse(input: inputText, output: outputText, cacheRead: cacheReadText, cacheCreation: cacheCreationText)
            onSave(prices.input, prices.output, prices.cacheRead, prices.cacheCreation)
        } catch MoaCustomPriceError.invalidField(let field) {
            statusText = MoaL10n.text("Enter a nonnegative finite number for each price.")
            switch field {
            case .input: focusedField = .input
            case .output: focusedField = .output
            case .cacheRead: focusedField = .cacheRead
            case .cacheCreation: focusedField = .cacheCreation
            }
        } catch MoaCustomPriceError.noPositivePrice {
            statusText = MoaL10n.text("Enter at least one positive input or output price.")
            focusedField = .input
        } catch {
            statusText = error.localizedDescription
        }
    }
}
