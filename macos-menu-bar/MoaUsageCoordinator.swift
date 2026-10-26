import AppKit
import Foundation

enum MoaUsageRefreshSchedule {
    static func interval(needsFrequentRefresh: Bool) -> TimeInterval { needsFrequentRefresh ? 60 : 300 }
}

final class MoaUsageCoordinator {
    let codexScanner: CodexUsageScanner
    let claudeScanner: ClaudeUsageScanner
    let zcodeScanner: ZCodeUsageScanner
    let workbuddyScanner: WorkBuddyUsageScanner
    let workbuddyCNScanner: WorkBuddyUsageScanner

    var onCodexSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onClaudeSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onZCodeSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onWorkBuddySummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onWorkBuddyCNSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var needsFrequentRefresh: (MoaUsageSource) -> Bool = { _ in true }

    var codexSummaryItem: NSMenuItem { pipelines[.codex]!.summaryItem }
    var codexRefreshItem: NSMenuItem { pipelines[.codex]!.refreshItem }
    var claudeSummaryItem: NSMenuItem { pipelines[.claude]!.summaryItem }
    var claudeRefreshItem: NSMenuItem { pipelines[.claude]!.refreshItem }
    var zcodeSummaryItem: NSMenuItem { pipelines[.zcode]!.summaryItem }
    var zcodeRefreshItem: NSMenuItem { pipelines[.zcode]!.refreshItem }
    var workbuddySummaryItem: NSMenuItem { pipelines[.workbuddy]!.summaryItem }
    var workbuddyRefreshItem: NSMenuItem { pipelines[.workbuddy]!.refreshItem }
    var workbuddyCNSummaryItem: NSMenuItem { pipelines[.workbuddyCN]!.summaryItem }
    var workbuddyCNRefreshItem: NSMenuItem { pipelines[.workbuddyCN]!.refreshItem }

    private final class Pipeline {
        let summaryItem = NSMenuItem()
        let refreshItem = MoaUsageRefreshMenuItem()
        let summaryView = CodexUsageSummaryMenuView()
        let queue: DispatchQueue
        var load: (Bool) throws -> CodexUsageSummary
        var summary: CodexUsageSummary?
        var inFlight = false
        var pendingForceRefresh = false
        var lastStartedAt = Date.distantPast

        init(source: MoaUsageSource, load: @escaping (Bool) throws -> CodexUsageSummary) {
            queue = DispatchQueue(label: "com.moarliu.moa.\(source.rawValue)-usage", qos: .utility)
            self.load = load
            summaryItem.view = summaryView
            summaryView.apply(.idle)
        }
    }

    private var pipelines: [MoaUsageSource: Pipeline] = [:]
    private let pricingUpdateCoordinator: MoaUsagePricingUpdateCoordinator
    var onPricingUpdated: (() -> Void)?
    var onPricingRefreshStateChanged: ((Bool) -> Void)?
    var isUpdatingPrices: Bool { pricingUpdateCoordinator.isRefreshing }
    var pricingModelCount: Int { pricingUpdateCoordinator.modelCount }

    func updatePrices(completion: @escaping (Result<MoaUsagePricingCatalogUpdate, Error>) -> Void) {
        pricingUpdateCoordinator.refreshNow(completion: completion)
    }
    private var timer: Timer?
    private var running = false
    private var generation = UUID()
    private var dataRootObserver: NSObjectProtocol?

    init(
        codexScanner: CodexUsageScanner = CodexUsageScanner(),
        claudeScanner: ClaudeUsageScanner = ClaudeUsageScanner(),
        zcodeScanner: ZCodeUsageScanner = ZCodeUsageScanner(),
        workbuddyScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(),
        workbuddyCNScanner: WorkBuddyUsageScanner = WorkBuddyUsageScanner(edition: .china),
        pricingUpdateCoordinator: MoaUsagePricingUpdateCoordinator? = nil
    ) {
        self.codexScanner = codexScanner
        self.claudeScanner = claudeScanner
        self.zcodeScanner = zcodeScanner
        self.workbuddyScanner = workbuddyScanner
        self.workbuddyCNScanner = workbuddyCNScanner
        self.pricingUpdateCoordinator = pricingUpdateCoordinator ?? MoaUsagePricingUpdateCoordinator()
        pipelines = [
            .codex: Pipeline(source: .codex) { try codexScanner.loadSummary(forceRefresh: $0) },
            .claude: Pipeline(source: .claude) { try claudeScanner.loadSummary(forceRefresh: $0) },
            .zcode: Pipeline(source: .zcode) { try zcodeScanner.loadSummary(forceRefresh: $0) },
            .workbuddy: Pipeline(source: .workbuddy) { try workbuddyScanner.loadSummary(forceRefresh: $0) },
            .workbuddyCN: Pipeline(source: .workbuddyCN) { try workbuddyCNScanner.loadSummary(forceRefresh: $0) }
        ]
    }

    deinit {
        timer?.invalidate()
        if let dataRootObserver { NotificationCenter.default.removeObserver(dataRootObserver) }
    }

    func start() {
        guard !running else { return }
        running = true
        for source in MoaUsageSource.allCases {
            pipelines[source]?.refreshItem.onRefresh = { [weak self] in self?.refresh(source, forceRefresh: true) }
        }
        pricingUpdateCoordinator.onCatalogUpdated = { [weak self] in
            self?.refreshAll(forceRefresh: true)
            self?.onPricingUpdated?()
        }
        pricingUpdateCoordinator.onRefreshStateChanged = { [weak self] in self?.onPricingRefreshStateChanged?($0) }
        dataRootObserver = NotificationCenter.default.addObserver(forName: MoaDataRoot.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAll(forceRefresh: true)
        }
        pricingUpdateCoordinator.start()
        refreshAll(forceRefresh: false)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshScheduled() }
        timer.tolerance = 5
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        running = false
        generation = UUID()
        timer?.invalidate()
        timer = nil
        pricingUpdateCoordinator.stop()
        if let dataRootObserver { NotificationCenter.default.removeObserver(dataRootObserver) }
        dataRootObserver = nil
        for pipeline in pipelines.values {
            pipeline.refreshItem.onRefresh = nil
            pipeline.pendingForceRefresh = false
            pipeline.refreshItem.setRefreshing(false)
        }
    }

    func refreshCodex(forceRefresh: Bool) { refresh(.codex, forceRefresh: forceRefresh) }
    func refreshClaude(forceRefresh: Bool) { refresh(.claude, forceRefresh: forceRefresh) }
    func refreshZCode(forceRefresh: Bool) { refresh(.zcode, forceRefresh: forceRefresh) }
    func refreshWorkBuddy(forceRefresh: Bool) { refresh(.workbuddy, forceRefresh: forceRefresh) }
    func refreshWorkBuddyCN(forceRefresh: Bool) { refresh(.workbuddyCN, forceRefresh: forceRefresh) }

    func refreshAllUsage() { refreshAll(forceRefresh: true) }

    func refreshForPresentation() {
        refreshAll(forceRefresh: false, minimumInterval: 5)
    }

    func refreshScheduled(now: Date = Date()) {
        guard running else { return }
        for source in MoaUsageSource.allCases {
            let interval = MoaUsageRefreshSchedule.interval(needsFrequentRefresh: needsFrequentRefresh(source))
            if let pipeline = pipelines[source], now.timeIntervalSince(pipeline.lastStartedAt) >= interval {
                refresh(source, forceRefresh: false, now: now)
            }
        }
    }

    private func refreshAll(forceRefresh: Bool, minimumInterval: TimeInterval = 0) {
        for source in MoaUsageSource.allCases {
            if let pipeline = pipelines[source], Date().timeIntervalSince(pipeline.lastStartedAt) >= minimumInterval || forceRefresh {
                refresh(source, forceRefresh: forceRefresh)
            }
        }
    }

    private func refresh(_ source: MoaUsageSource, forceRefresh: Bool, now: Date = Date()) {
        guard running, let pipeline = pipelines[source] else { return }
        guard !pipeline.inFlight else {
            pipeline.pendingForceRefresh = pipeline.pendingForceRefresh || forceRefresh
            return
        }
        pipeline.inFlight = true
        pipeline.lastStartedAt = now
        pipeline.refreshItem.setRefreshing(true)
        pipeline.summaryView.apply(.loading(pipeline.summary))
        let startedAt = Date()
        let refreshGeneration = generation
        let load = pipeline.load
        pipeline.queue.async { [weak self] in
            let result = Result { try load(forceRefresh) }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, (forceRefresh ? 0.6 : 0) - Date().timeIntervalSince(startedAt))) {
                guard let self else { return }
                pipeline.inFlight = false
                guard self.running else { return }
                guard self.generation == refreshGeneration else {
                    self.refresh(source, forceRefresh: true)
                    return
                }
                pipeline.refreshItem.setRefreshing(false)
                switch result {
                case .success(let summary):
                    pipeline.summary = summary
                    pipeline.summaryView.apply(.loaded(summary))
                    self.summaryLoaded(summary, source: source)
                case .failure(let error):
                    pipeline.summaryView.apply(.failed(pipeline.summary, error.localizedDescription))
                }
                if pipeline.pendingForceRefresh {
                    pipeline.pendingForceRefresh = false
                    self.refresh(source, forceRefresh: true)
                }
            }
        }
    }

    private func summaryLoaded(_ summary: CodexUsageSummary, source: MoaUsageSource) {
        switch source {
        case .codex: onCodexSummaryLoaded?(summary)
        case .claude: onClaudeSummaryLoaded?(summary)
        case .zcode: onZCodeSummaryLoaded?(summary)
        case .workbuddy: onWorkBuddySummaryLoaded?(summary)
        case .workbuddyCN: onWorkBuddyCNSummaryLoaded?(summary)
        }
    }

    #if MOA_TESTING || MOA_TEST_SUPPORT
    var testingInFlightCount: Int { pipelines.values.filter(\.inFlight).count }
    func testingSetLoader(_ source: MoaUsageSource, load: @escaping (Bool) throws -> CodexUsageSummary) {
        pipelines[source]?.load = load
    }
    #endif
}
