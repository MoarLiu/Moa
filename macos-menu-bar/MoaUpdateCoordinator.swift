import Foundation

final class MoaUpdateCoordinator: ObservableObject {
    static let autoCheckKey = "Moa.updates.autoCheckEnabled"
    static let lastCheckedAtKey = "Moa.updates.lastCheckedAt"
    static let notifiedVersionKey = "Moa.updates.notifiedVersion"
    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let startupCheckDelay: TimeInterval = 30

    @Published private(set) var availableUpdate: MoaUpdateInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published var autoCheckEnabled: Bool {
        didSet {
            defaults.set(autoCheckEnabled, forKey: Self.autoCheckKey)
            if autoCheckEnabled {
                scheduleBackgroundChecks()
            } else {
                stopBackgroundTimer()
            }
        }
    }

    var onBackgroundUpdateDiscovered: ((MoaUpdateInfo) -> Void)?

    private let checkHandler: () async throws -> MoaUpdateCheckResult
    private let defaults: UserDefaults
    private let now: () -> Date
    private var timer: Timer?
    private var startupTask: DispatchWorkItem?
    private var running = false

    init(
        controller: MoaUpdateController = MoaUpdateController(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        checkHandler: (() async throws -> MoaUpdateCheckResult)? = nil
    ) {
        self.checkHandler = checkHandler ?? { try await controller.checkForUpdate() }
        self.defaults = defaults
        self.now = now
        if defaults.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckEnabled = true
        } else {
            self.autoCheckEnabled = defaults.bool(forKey: Self.autoCheckKey)
        }
        let timestamp = defaults.double(forKey: Self.lastCheckedAtKey)
        self.lastCheckedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    deinit {
        stop()
    }

    func start() {
        guard !running else { return }
        running = true
        guard !MoaRuntimeMode.suppressesUserInteraction,
              !MoaRuntimeMode.isWorkspacePreview else {
            return
        }
        scheduleBackgroundChecks()
    }

    func stop() {
        running = false
        stopBackgroundTimer()
    }

    func isBackgroundCheckDue(at date: Date? = nil) -> Bool {
        guard autoCheckEnabled else { return false }
        let reference = date ?? now()
        guard let lastCheckedAt else { return true }
        return reference.timeIntervalSince(lastCheckedAt) >= Self.checkInterval
    }

    func checkNow(userInitiated: Bool) async throws -> MoaUpdateCheckResult {
        await MainActor.run { self.isChecking = true }
        defer {
            Task { @MainActor in self.isChecking = false }
        }
        let result = try await checkHandler()
        let checkedAt = now()
        await MainActor.run {
            self.recordCheck(result: result, at: checkedAt, userInitiated: userInitiated)
        }
        return result
    }

    func performBackgroundCheckIfDue() async -> MoaUpdateCheckResult? {
        guard autoCheckEnabled, !isChecking, isBackgroundCheckDue() else { return nil }
        return try? await checkNow(userInitiated: false)
    }

    static func releaseSignature(for update: MoaUpdateInfo) -> String {
        "\(update.version)|\(update.build.map(String.init) ?? "")"
    }

    func shouldNotify(for update: MoaUpdateInfo) -> Bool {
        defaults.string(forKey: Self.notifiedVersionKey) != Self.releaseSignature(for: update)
    }

    func markNotified(for update: MoaUpdateInfo) {
        defaults.set(Self.releaseSignature(for: update), forKey: Self.notifiedVersionKey)
    }

    @MainActor
    private func recordCheck(result: MoaUpdateCheckResult, at date: Date, userInitiated: Bool) {
        lastCheckedAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastCheckedAtKey)
        switch result {
        case .upToDate:
            availableUpdate = nil
        case .updateAvailable(let update):
            availableUpdate = update
            if !userInitiated && shouldNotify(for: update) {
                markNotified(for: update)
                onBackgroundUpdateDiscovered?(update)
            }
        }
    }

    private func scheduleBackgroundChecks() {
        stopBackgroundTimer()
        guard running, autoCheckEnabled,
              !MoaRuntimeMode.suppressesUserInteraction,
              !MoaRuntimeMode.isWorkspacePreview else {
            return
        }
        if isBackgroundCheckDue() {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { _ = await self.performBackgroundCheckIfDue() }
            }
            startupTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupCheckDelay, execute: work)
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { _ = await self.performBackgroundCheckIfDue() }
        }
        timer.tolerance = 300
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBackgroundTimer() {
        startupTask?.cancel()
        startupTask = nil
        timer?.invalidate()
        timer = nil
    }
}
