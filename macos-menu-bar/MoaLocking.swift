import Foundation

enum MoaDataAccessError: LocalizedError {
    case busy
    var errorDescription: String? {
        MoaL10n.text("Moa is processing data. Try again when it finishes.")
    }
}

/// Serializes store transactions with data snapshots/replacement for one home.
/// Long data operations release the mutex after marking the root busy, so UI
/// actions receive a retryable error instead of waiting for a ZIP or copy.
final class MoaDataAccessCoordinator: @unchecked Sendable {
    /// A long data operation started or finished, so views can stop polling `isBusy`.
    static let busyStateDidChange = Notification.Name("MoaDataAccessBusyStateDidChange")
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: MoaDataAccessCoordinator] = [:]
    private let gate = NSRecursiveLock()
    private let metadata = NSLock()
    private var owner: Thread?
    private var depth = 0
    private var generation: UInt64 = 0

    static func shared(environment: [String: String]) -> MoaDataAccessCoordinator {
        let key = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath().path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[key] { return existing }
        let coordinator = MoaDataAccessCoordinator()
        registry[key] = coordinator
        return coordinator
    }

    var isBusy: Bool {
        metadata.lock(); defer { metadata.unlock() }
        return owner != nil
    }

    var revision: UInt64 {
        metadata.lock(); defer { metadata.unlock() }
        return generation
    }

    func lockForStoreAccess() throws {
        gate.lock()
        metadata.lock()
        let unavailable = owner != nil && owner !== Thread.current
        metadata.unlock()
        if unavailable { gate.unlock(); throw MoaDataAccessError.busy }
    }

    func unlockStoreAccess() { gate.unlock() }

    func withExclusiveOperation<T>(_ operation: () throws -> T) throws -> T {
        gate.lock()
        metadata.lock()
        if owner != nil && owner !== Thread.current {
            metadata.unlock(); gate.unlock()
            throw MoaDataAccessError.busy
        }
        owner = Thread.current
        depth += 1
        let began = depth == 1
        metadata.unlock()
        gate.unlock()
        // Posted on the operation's own thread; UI observers hop to the main queue.
        if began { NotificationCenter.default.post(name: Self.busyStateDidChange, object: self) }
        defer {
            metadata.lock()
            depth -= 1
            let ended = depth == 0
            if ended { owner = nil; generation &+= 1 }
            metadata.unlock()
            if ended { NotificationCenter.default.post(name: Self.busyStateDidChange, object: self) }
        }
        return try operation()
    }
}

final class MoaDataStoreLock {
    private let coordinator: MoaDataAccessCoordinator
    init(environment: [String: String]) { coordinator = .shared(environment: environment) }
    var revision: UInt64 { coordinator.revision }
    var isBusy: Bool { coordinator.isBusy }
    func lock() throws { try coordinator.lockForStoreAccess() }
    func unlock() { coordinator.unlockStoreAccess() }
    func withLock<T>(_ operation: () throws -> T) throws -> T {
        try lock()
        defer { unlock() }
        return try operation()
    }
}

extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
