import AppKit
import Foundation

final class MoaUsageCoordinator {
    let codexScanner: CodexUsageScanner
    let claudeScanner: ClaudeUsageScanner
    let zcodeScanner: ZCodeUsageScanner
    let workbuddyScanner: WorkBuddyUsageScanner
    let workbuddyCNScanner: WorkBuddyUsageScanner
    let codexSummaryItem = NSMenuItem()
    let codexRefreshItem = NSMenuItem()
    let claudeSummaryItem = NSMenuItem()
    let claudeRefreshItem = NSMenuItem()
    let zcodeSummaryItem = NSMenuItem()
    let workbuddySummaryItem = NSMenuItem()
    let workbuddyCNSummaryItem = NSMenuItem()
    let zcodeRefreshItem = NSMenuItem()
    let workbuddyRefreshItem = NSMenuItem()
    let workbuddyCNRefreshItem = NSMenuItem()

    var onCodexSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onClaudeSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onZCodeSummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onWorkBuddySummaryLoaded: ((CodexUsageSummary) -> Void)?
    var onWorkBuddyCNSummaryLoaded: ((CodexUsageSummary) -> Void)?

    private let codexSummaryView = CodexUsageSummaryMenuView()
    private let codexRefreshView = CodexUsageRefreshMenuView()
    private let claudeSummaryView = CodexUsageSummaryMenuView()
    private let claudeRefreshView = CodexUsageRefreshMenuView()
    private let zcodeSummaryView = CodexUsageSummaryMenuView()
    private let workbuddySummaryView = CodexUsageSummaryMenuView()
    private let workbuddyCNSummaryView = CodexUsageSummaryMenuView()
    private let zcodeRefreshView = CodexUsageRefreshMenuView()
    private let workbuddyRefreshView = CodexUsageRefreshMenuView()
    private let workbuddyCNRefreshView = CodexUsageRefreshMenuView()
    private let codexQueue = DispatchQueue(label: "com.moarliu.moa.codex-usage", qos: .utility)
    private let claudeQueue = DispatchQueue(label: "com.moarliu.moa.claude-usage", qos: .utility)
    private let zcodeQueue = DispatchQueue(label: "com.moarliu.moa.zcode-usage", qos: .utility)
    private let workbuddyQueue = DispatchQueue(label: "com.moarliu.moa.workbuddy-usage", qos: .utility)
    private let workbuddyCNQueue = DispatchQueue(label: "com.moarliu.moa.workbuddy-cn-usage", qos: .utility)
    private let pricingUpdateCoordinator: MoaUsagePricingUpdateCoordinator

    private var codexTimer: Timer?
    private var claudeTimer: Timer?
    private var zcodeTimer: Timer?
    private var workbuddyTimer: Timer?
    private var workbuddyCNTimer: Timer?
    private var codexSummary: CodexUsageSummary?
    private var claudeSummary: CodexUsageSummary?
    private var zcodeSummary: CodexUsageSummary?
    private var workbuddySummary: CodexUsageSummary?
    private var workbuddyCNSummary: CodexUsageSummary?
    private var codexRefreshInFlight = false
    private var claudeRefreshInFlight = false
    private var zcodeRefreshInFlight = false
    private var workbuddyRefreshInFlight = false
    private var workbuddyCNRefreshInFlight = false

    private static let refreshMinimumDisplayDuration: TimeInterval = 0.6

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
    }

    func start() {
        pricingUpdateCoordinator.onCatalogUpdated = { [weak self] in
            self?.refreshCodex(forceRefresh: true)
            self?.refreshClaude(forceRefresh: true)
            self?.refreshZCode(forceRefresh: true)
            self?.refreshWorkBuddy(forceRefresh: true)
            self?.refreshWorkBuddyCN(forceRefresh: true)
        }
        pricingUpdateCoordinator.start()
        startCodex()
        startClaude()
        startZCode()
        startWorkBuddy()
        startWorkBuddyCN()
    }

    func stop() {
        pricingUpdateCoordinator.stop()
        codexTimer?.invalidate()
        codexTimer = nil
        claudeTimer?.invalidate()
        claudeTimer = nil
        zcodeTimer?.invalidate()
        workbuddyTimer?.invalidate()
        workbuddyCNTimer?.invalidate()
        zcodeTimer = nil
        workbuddyTimer = nil
        workbuddyCNTimer = nil
        codexRefreshView.onRefresh = nil
        claudeRefreshView.onRefresh = nil
        zcodeRefreshView.onRefresh = nil
        workbuddyRefreshView.onRefresh = nil
        workbuddyCNRefreshView.onRefresh = nil
    }

    func refreshCodex(forceRefresh: Bool) {
        guard !codexRefreshInFlight else { return }
        let startedAt = Date()
        codexRefreshInFlight = true
        codexRefreshView.setRefreshing(true)
        codexSummaryView.apply(.loading(codexSummary))

        codexQueue.async {
            let result = Result {
                try self.codexScanner.loadSummary(forceRefresh: forceRefresh)
            }

            DispatchQueue.main.async {
                let completeRefresh = {
                    self.codexRefreshInFlight = false
                    self.codexRefreshView.setRefreshing(false)

                    switch result {
                    case .success(let summary):
                        self.codexSummary = summary
                        self.codexSummaryView.apply(.loaded(summary))
                        self.onCodexSummaryLoaded?(summary)
                    case .failure(let error):
                        self.codexSummaryView.apply(.failed(self.codexSummary, error.localizedDescription))
                    }
                }
                let minimumDuration = forceRefresh ? Self.refreshMinimumDisplayDuration : 0
                let delay = max(0, minimumDuration - Date().timeIntervalSince(startedAt))
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completeRefresh()
                    }
                } else {
                    completeRefresh()
                }
            }
        }
    }

    func refreshClaude(forceRefresh: Bool) {
        guard !claudeRefreshInFlight else { return }
        let startedAt = Date()
        claudeRefreshInFlight = true
        claudeRefreshView.setRefreshing(true)
        claudeSummaryView.apply(.loading(claudeSummary))

        claudeQueue.async {
            let result = Result {
                try self.claudeScanner.loadSummary(forceRefresh: forceRefresh)
            }

            DispatchQueue.main.async {
                let completeRefresh = {
                    self.claudeRefreshInFlight = false
                    self.claudeRefreshView.setRefreshing(false)

                    switch result {
                    case .success(let summary):
                        self.claudeSummary = summary
                        self.claudeSummaryView.apply(.loaded(summary))
                        self.onClaudeSummaryLoaded?(summary)
                    case .failure(let error):
                        self.claudeSummaryView.apply(.failed(self.claudeSummary, error.localizedDescription))
                    }
                }
                let minimumDuration = forceRefresh ? Self.refreshMinimumDisplayDuration : 0
                let delay = max(0, minimumDuration - Date().timeIntervalSince(startedAt))
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completeRefresh()
                    }
                } else {
                    completeRefresh()
                }
            }
        }
    }

    func refreshZCode(forceRefresh: Bool) {
        guard !zcodeRefreshInFlight else { return }
        let startedAt = Date()
        zcodeRefreshInFlight = true
        zcodeRefreshView.setRefreshing(true)
        zcodeSummaryView.apply(.loading(zcodeSummary))

        zcodeQueue.async {
            let result = Result {
                try self.zcodeScanner.loadSummary(forceRefresh: forceRefresh)
            }

            DispatchQueue.main.async {
                let completeRefresh = {
                    self.zcodeRefreshInFlight = false
                    self.zcodeRefreshView.setRefreshing(false)

                    switch result {
                    case .success(let summary):
                        self.zcodeSummary = summary
                        self.zcodeSummaryView.apply(.loaded(summary))
                        self.onZCodeSummaryLoaded?(summary)
                    case .failure(let error):
                        self.zcodeSummaryView.apply(.failed(self.zcodeSummary, error.localizedDescription))
                    }
                }
                let minimumDuration = forceRefresh ? Self.refreshMinimumDisplayDuration : 0
                let delay = max(0, minimumDuration - Date().timeIntervalSince(startedAt))
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completeRefresh()
                    }
                } else {
                    completeRefresh()
                }
            }
        }
    }

    func refreshWorkBuddy(forceRefresh: Bool) {
        guard !workbuddyRefreshInFlight else { return }
        let startedAt = Date()
        workbuddyRefreshInFlight = true
        workbuddyRefreshView.setRefreshing(true)
        workbuddySummaryView.apply(.loading(workbuddySummary))

        workbuddyQueue.async {
            let result = Result {
                try self.workbuddyScanner.loadSummary(forceRefresh: forceRefresh)
            }

            DispatchQueue.main.async {
                let completeRefresh = {
                    self.workbuddyRefreshInFlight = false
                    self.workbuddyRefreshView.setRefreshing(false)

                    switch result {
                    case .success(let summary):
                        self.workbuddySummary = summary
                        self.workbuddySummaryView.apply(.loaded(summary))
                        self.onWorkBuddySummaryLoaded?(summary)
                    case .failure(let error):
                        self.workbuddySummaryView.apply(.failed(self.workbuddySummary, error.localizedDescription))
                    }
                }
                let minimumDuration = forceRefresh ? Self.refreshMinimumDisplayDuration : 0
                let delay = max(0, minimumDuration - Date().timeIntervalSince(startedAt))
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completeRefresh()
                    }
                } else {
                    completeRefresh()
                }
            }
        }
    }

    func refreshWorkBuddyCN(forceRefresh: Bool) {
        guard !workbuddyCNRefreshInFlight else { return }
        let startedAt = Date()
        workbuddyCNRefreshInFlight = true
        workbuddyCNRefreshView.setRefreshing(true)
        workbuddyCNSummaryView.apply(.loading(workbuddyCNSummary))

        workbuddyCNQueue.async {
            let result = Result {
                try self.workbuddyCNScanner.loadSummary(forceRefresh: forceRefresh)
            }

            DispatchQueue.main.async {
                let completeRefresh = {
                    self.workbuddyCNRefreshInFlight = false
                    self.workbuddyCNRefreshView.setRefreshing(false)

                    switch result {
                    case .success(let summary):
                        self.workbuddyCNSummary = summary
                        self.workbuddyCNSummaryView.apply(.loaded(summary))
                        self.onWorkBuddyCNSummaryLoaded?(summary)
                    case .failure(let error):
                        self.workbuddyCNSummaryView.apply(.failed(self.workbuddyCNSummary, error.localizedDescription))
                    }
                }
                let minimumDuration = forceRefresh ? Self.refreshMinimumDisplayDuration : 0
                let delay = max(0, minimumDuration - Date().timeIntervalSince(startedAt))
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completeRefresh()
                    }
                } else {
                    completeRefresh()
                }
            }
        }
    }

    private func startCodex() {
        codexSummaryItem.view = codexSummaryView
        codexRefreshItem.view = codexRefreshView
        codexRefreshView.onRefresh = { [weak self] in
            self?.refreshCodex(forceRefresh: true)
        }
        codexSummaryView.apply(.idle)
        refreshCodex(forceRefresh: false)
        codexTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshCodex(forceRefresh: false)
        }
        if let codexTimer {
            RunLoop.main.add(codexTimer, forMode: .common)
        }
    }

    private func startClaude() {
        claudeSummaryItem.view = claudeSummaryView
        claudeRefreshItem.view = claudeRefreshView
        claudeRefreshView.onRefresh = { [weak self] in
            self?.refreshClaude(forceRefresh: true)
        }
        claudeSummaryView.apply(.idle)
        refreshClaude(forceRefresh: false)
        claudeTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshClaude(forceRefresh: false)
        }
        if let claudeTimer {
            RunLoop.main.add(claudeTimer, forMode: .common)
        }
    }

    private func startZCode() {
        zcodeSummaryItem.view = zcodeSummaryView
        zcodeRefreshItem.view = zcodeRefreshView
        zcodeRefreshView.onRefresh = { [weak self] in
            self?.refreshZCode(forceRefresh: true)
        }
        zcodeSummaryView.apply(.idle)
        refreshZCode(forceRefresh: false)
        zcodeTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshZCode(forceRefresh: false)
        }
        if let zcodeTimer {
            RunLoop.main.add(zcodeTimer, forMode: .common)
        }
    }

    private func startWorkBuddy() {
        workbuddySummaryItem.view = workbuddySummaryView
        workbuddyRefreshItem.view = workbuddyRefreshView
        workbuddyRefreshView.onRefresh = { [weak self] in
            self?.refreshWorkBuddy(forceRefresh: true)
        }
        workbuddySummaryView.apply(.idle)
        refreshWorkBuddy(forceRefresh: false)
        workbuddyTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshWorkBuddy(forceRefresh: false)
        }
        if let workbuddyTimer {
            RunLoop.main.add(workbuddyTimer, forMode: .common)
        }
    }
    private func startWorkBuddyCN() {
        workbuddyCNSummaryItem.view = workbuddyCNSummaryView
        workbuddyCNRefreshItem.view = workbuddyCNRefreshView
        workbuddyCNRefreshView.onRefresh = { [weak self] in
            self?.refreshWorkBuddyCN(forceRefresh: true)
        }
        workbuddyCNSummaryView.apply(.idle)
        refreshWorkBuddyCN(forceRefresh: false)
        workbuddyCNTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshWorkBuddyCN(forceRefresh: false)
        }
        if let workbuddyCNTimer {
            RunLoop.main.add(workbuddyCNTimer, forMode: .common)
        }
    }
}
