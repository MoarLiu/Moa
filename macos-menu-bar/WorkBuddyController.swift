import AppKit
import CryptoKit
import Darwin
import Foundation

enum WorkBuddyError: LocalizedError {
    case message(String, edition: WorkBuddyEdition = .international)
    var errorDescription: String? {
        switch self { case .message(let key, let edition): return edition.localized(key) }
    }
}

protocol WorkBuddyAppManaging {
    var isRunning: Bool { get }
    func quit() throws
    func launch() throws
}

/// Always address exactly one client, even when both editions are running.
final class WorkBuddyAppManager: WorkBuddyAppManaging {
    let edition: WorkBuddyEdition
    init(edition: WorkBuddyEdition = .international) { self.edition = edition }

    var bundleID: String { edition.bundleID }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func quit() throws {
        precondition(!Thread.isMainThread)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        DispatchQueue.main.sync { for app in apps { _ = app.terminate() } }
        let deadline = Date().addingTimeInterval(20)
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !isRunning else {
            throw clientError("WorkBuddy AI did not quit. Finish active tasks and quit it, then try again.")
        }
    }

    func launch() throws {
        precondition(!Thread.isMainThread)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw clientError("WorkBuddy AI is not installed.")
        }
        let done = DispatchSemaphore(value: 0)
        var launchError: Error?
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                launchError = error
                done.signal()
            }
        }
        guard done.wait(timeout: .now() + 20) == .success, launchError == nil else {
            throw clientError("Unable to open WorkBuddy AI. Open it manually and try again.")
        }
    }
    private func clientError(_ key: String) -> WorkBuddyError { .message(key, edition: edition) }

}

struct WorkBuddyAccount: Codable, Identifiable {
    var id: UUID
    var uid: String
    var name: String
    var updatedAt: Date
    // Preserve the entire file, including encrypted envelopes and unknown fields.
    var snapshot: Data
    var keyFingerprint: String?
    var edition: WorkBuddyEdition? = nil
}

final class WorkBuddyController {
    private struct Database: Codable { var accounts: [WorkBuddyAccount] = [] }
    private struct OperationLock {
        let descriptor: Int32
        func release() {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
    }
    private struct Login {
        var uid: String
        var data: Data
        var keyFingerprint: String?
    }

    let authURL: URL
    let keyURL: URL
    let storageURL: URL
    let edition: WorkBuddyEdition
    private let homeURL: URL
    private let runtime: WorkBuddyAppManaging
    private let fileManager = FileManager.default
    private let lock = NSRecursiveLock()

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        edition: WorkBuddyEdition = .international,
        runtime: WorkBuddyAppManaging? = nil
    ) {
        let home = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath()
        homeURL = home
        self.edition = edition
        authURL = home.appendingPathComponent("Library/Application Support/CodeBuddyExtension/Data/Public/auth/\(edition.authFileName)")
        keyURL = home.appendingPathComponent("\(edition.dataDirectoryName)/keyblob")
        // Deliberately outside the movable/exportable Moa data root. Never copy keyblob.
        storageURL = home.appendingPathComponent("Library/Application Support/Moa/\(edition.accountDirectoryName)/accounts.json")
        self.runtime = runtime ?? WorkBuddyAppManager(edition: edition)
    }

    func accounts() throws -> [WorkBuddyAccount] {
        lock.lock(); defer { lock.unlock() }
        return try load().accounts
    }

    func currentUID() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard fileManager.fileExists(atPath: authURL.path) else { return nil }
        try rejectSymlinks(authURL)
        return try optionalLogin(Data(contentsOf: authURL))?.uid
    }

    @discardableResult
    func saveCurrent(name: String) throws -> WorkBuddyAccount {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        let name = try validatedName(name)
        // Fail on a corrupt database before asking the client to quit.
        var database = try load()
        let wasRunning = runtime.isRunning
        try runtime.quit()
        do {
            let current = try readCurrent()
            try requireStopped()
            let account = capture(current, name: name, in: &database)
            try save(database)
            if wasRunning { try runtime.launch() }
            return account
        } catch {
            if wasRunning && !runtime.isRunning { try? runtime.launch() }
            throw error
        }
    }

    @discardableResult
    func apply(id: UUID) throws -> WorkBuddyAccount {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        var database = try load()
        guard let target = database.accounts.first(where: { $0.id == id }) else {
            throw clientError("Saved WorkBuddy AI account was not found.")
        }
        let targetLogin = try login(target.snapshot)
        guard targetLogin.uid == target.uid, targetLogin.keyFingerprint == target.keyFingerprint else {
            throw clientError("This WorkBuddy AI snapshot does not match this Mac's keyblob. Save the account again on this Mac.")
        }
        let wasRunning = runtime.isRunning
        try runtime.quit()
        var original: Data?
        var replaced = false
        do {
            try rejectSymlinks(authURL)
            original = fileManager.fileExists(atPath: authURL.path) ? try Data(contentsOf: authURL) : nil
            var destination = target
            if let original {
                if let current = try optionalLogin(original) {
                    let saved = capture(current, name: nil, in: &database)
                    // Selecting the current account must retain its freshly rotated tokens.
                    if current.uid == target.uid { destination = saved }
                }
            }
            try save(database)
            try requireStopped()
            try secureWrite(destination.snapshot, to: authURL)
            replaced = true
            try runtime.launch()
            return destination
        } catch {
            if replaced {
                // A launch failure must not leave a silently switched login behind.
                do {
                    if runtime.isRunning { try runtime.quit() }
                    try preserveCurrentLogin(in: &database)
                    if let original { try secureWrite(original, to: authURL) }
                    else { try fileManager.removeItem(at: authURL) }
                } catch {
                    throw clientError("WorkBuddy AI could not restore the previous login. Saved accounts are intact; quit WorkBuddy AI and select the previous account again.")
                }
            }
            if wasRunning && !runtime.isRunning { try? runtime.launch() }
            throw error
        }
    }

    func rename(id: UUID, name: String) throws {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        let name = try validatedName(name)
        var database = try load()
        guard let index = database.accounts.firstIndex(where: { $0.id == id }) else {
            throw clientError("Saved WorkBuddy AI account was not found.")
        }
        database.accounts[index].name = name
        try save(database)
    }

    func prepareNewLogin() throws {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        var database = try load()
        let wasRunning = runtime.isRunning
        try runtime.quit()
        var original: Data?
        var removed = false
        do {
            if fileManager.fileExists(atPath: authURL.path) {
                try rejectSymlinks(authURL)
                let data = try Data(contentsOf: authURL)
                original = data
                if let current = try optionalLogin(data) { _ = capture(current, name: nil, in: &database) }
                try save(database)
                try rejectSymlinks(authURL)
                try requireStopped()
                try fileManager.removeItem(at: authURL)
                removed = true
            }
            try runtime.launch()
        } catch {
            if removed, let original {
                do {
                    if runtime.isRunning { try runtime.quit() }
                    try preserveCurrentLogin(in: &database)
                    try secureWrite(original, to: authURL)
                }
                catch {
                    throw clientError("WorkBuddy AI could not restore the previous login. Saved accounts are intact; quit WorkBuddy AI and select the previous account again.")
                }
            }
            if wasRunning && !runtime.isRunning { try? runtime.launch() }
            throw error
        }
    }

    func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        var database = try load()
        database.accounts.removeAll { $0.id == id }
        // Forget only the saved copy. Do not revoke or delete the live login.
        try save(database)
    }

    func reopen() throws {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        try runtime.quit()
        try runtime.launch()
    }

    func open() throws {
        lock.lock(); defer { lock.unlock() }
        let operation = try acquireOperationLock()
        defer { operation.release() }
        try runtime.launch()
    }

    private func clientError(_ key: String) -> WorkBuddyError { .message(key, edition: edition) }

    private func readCurrent() throws -> Login {
        try rejectSymlinks(authURL)
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw clientError("Log in to WorkBuddy AI first, then save the current account.")
        }
        return try login(Data(contentsOf: authURL))
    }

    private func login(_ data: Data) throws -> Login {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["account"] as? [String: Any],
              let uid = account["uid"] as? String, !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let auth = root["auth"] as? [String: Any],
              validSecret(auth["accessToken"]), validSecret(auth["refreshToken"])
        else {
            throw clientError("WorkBuddy AI login is missing or invalid. Log in again before saving or switching accounts.")
        }
        guard edition.acceptsAuthDomain(auth["domain"] as? String) else {
            throw clientError("This login belongs to a different WorkBuddy client. Log in and save it in the matching client.")
        }
        var fingerprint: String?
        if auth["accessToken"] is [String: Any] || auth["refreshToken"] is [String: Any] {
            guard let key = try? Data(contentsOf: keyURL), !key.isEmpty else {
                throw clientError("WorkBuddy AI keyblob is missing. Log in again on this Mac.")
            }
            fingerprint = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        }
        return Login(uid: uid, data: data, keyFingerprint: fingerprint)
    }

    private func optionalLogin(_ data: Data) throws -> Login? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw clientError("WorkBuddy AI login is missing or invalid. Log in again before saving or switching accounts.")
        }
        let auth = root["auth"] as? [String: Any] ?? [:]
        // The fresh sign-in screen can create an empty auth object. It is safe to replace.
        let empty: (Any?) -> Bool = { value in
            value == nil || value is NSNull || (value as? String)?.isEmpty == true
        }
        if empty(auth["accessToken"]) && empty(auth["refreshToken"]) { return nil }
        return try login(data)
    }

    private func validSecret(_ value: Any?) -> Bool {
        if let text = value as? String { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let envelope = value as? [String: Any],
              (envelope["$wbEncrypted"] as? Int) == 1,
              let text = envelope["envelope"] as? String else { return false }
        return !text.isEmpty
    }

    private func capture(_ login: Login, name: String?, in database: inout Database) -> WorkBuddyAccount {
        let existing = database.accounts.first { $0.uid == login.uid }
        let account = WorkBuddyAccount(
            id: existing?.id ?? UUID(), uid: login.uid,
            name: name ?? existing?.name ?? "\(edition.title) · \(login.uid.prefix(8))",
            updatedAt: Date(), snapshot: login.data, keyFingerprint: login.keyFingerprint, edition: edition
        )
        if let index = database.accounts.firstIndex(where: { $0.uid == login.uid }) {
            database.accounts[index] = account
        } else { database.accounts.append(account) }
        return account
    }

    private func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw clientError("Enter an account name.") }
        return value
    }

    private func requireStopped() throws {
        guard !runtime.isRunning else {
            throw clientError("WorkBuddy AI did not quit. Finish active tasks and quit it, then try again.")
        }
    }

    private func preserveCurrentLogin(in database: inout Database) throws {
        try requireStopped()
        try rejectSymlinks(authURL)
        guard fileManager.fileExists(atPath: authURL.path),
              let current = try optionalLogin(Data(contentsOf: authURL)) else { return }
        _ = capture(current, name: nil, in: &database)
        // Save before restoring the original file: the target may already have
        // rotated its refresh token even though its launch later reported failure.
        try save(database)
    }

    private func acquireOperationLock() throws -> OperationLock {
        try prepareStorageDirectory()
        let url = storageURL.deletingLastPathComponent().appendingPathComponent("operation.lock")
        try rejectSymlinks(url)
        // Keep this inode in place. Replacing/deleting a lock file would let
        // another Moa process lock a different inode during an active switch.
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw clientError("Unable to lock WorkBuddy AI credentials. Check the local account directory permissions.")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            _ = Darwin.close(descriptor)
            throw clientError("Another Moa instance is updating WorkBuddy AI. Wait for it to finish and try again.")
        }
        return OperationLock(descriptor: descriptor)
    }

    private func load() throws -> Database {
        try rejectSymlinks(storageURL)
        guard fileManager.fileExists(atPath: storageURL.path) else { return Database() }
        let database = try JSONDecoder().decode(Database.self, from: Data(contentsOf: storageURL))
        guard database.accounts.allSatisfy({ $0.edition == edition || (edition == .international && $0.edition == nil) }) else {
            throw clientError("Saved accounts belong to a different WorkBuddy client. Save accounts separately in each client.")
        }
        return database
    }

    private func save(_ database: Database) throws {
        try prepareStorageDirectory()
        try secureWrite(JSONEncoder().encode(database), to: storageURL)
    }

    private func prepareStorageDirectory() throws {
        let directory = storageURL.deletingLastPathComponent()
        try rejectSymlinks(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func rejectSymlinks(_ url: URL) throws {
        var path = url.standardizedFileURL
        // macOS exposes /var through a system symlink. Only inspect the credential
        // path inside the trusted home, including the home itself.
        let boundary = homeURL.deletingLastPathComponent().path
        while path.path != "/" && path.path != boundary {
            if (try? fileManager.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw clientError("WorkBuddy AI credential paths must not contain symbolic links.")
            }
            path.deleteLastPathComponent()
        }
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try rejectSymlinks(url)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".moa-workbuddy-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw clientError("Unable to save WorkBuddy AI credentials.")
        }
        defer { try? fileManager.removeItem(at: temporary) }
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw clientError("Unable to save WorkBuddy AI credentials.")
        }
    }
}
