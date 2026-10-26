import AppKit
import CryptoKit
import Darwin
import Foundation

protocol DeepSeekAppManaging {
    var isRunning: Bool { get }
    func quit() throws
    func launch() throws
}

final class DeepSeekAppManager: DeepSeekAppManaging {
    static let bundleID = "com.deepseek.dsh"
    private let dshHome: URL
    init(dshHome: URL) { self.dshHome = dshHome }
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }
    func quit() throws {
        precondition(!Thread.isMainThread)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        DispatchQueue.main.sync { for app in apps { _ = app.terminate() } }
        let deadline = Date().addingTimeInterval(20)
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !isRunning else {
            throw DeepSeekError.message("DeepSeek did not quit. Finish active tasks and quit it, then try again.")
        }
    }
    func launch() throws {
        precondition(!Thread.isMainThread)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw DeepSeekError.message("DeepSeek Harness is not installed.")
        }
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        DispatchQueue.main.async {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.environment = ["DSH_HOME": self.dshHome.path]
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                failure = error
                done.signal()
            }
        }
        guard done.wait(timeout: .now() + 20) == .success, failure == nil else {
            throw DeepSeekError.message("Unable to open DeepSeek. Open DeepSeek Harness manually and try again.")
        }
    }
}

struct DeepSeekAccount: Codable, Identifiable {
    var id: UUID
    var name: String
    var fingerprint: String
    var snapshot: String
    var updatedAt: Date
}

final class DeepSeekController {
    private struct Database: Codable {
        var version = 1
        var credentialPath: String
        var accounts: [DeepSeekAccount] = []
    }
    let authURL: URL
    let storageURL: URL
    private let homeURL: URL
    private let runtime: DeepSeekAppManaging
    private let lock = NSRecursiveLock()
    private let fm = FileManager.default
    private let validHome: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment, runtime: DeepSeekAppManaging? = nil) {
        homeURL = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath()
        let override = environment["DSH_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        validHome = override.isEmpty || override.hasPrefix("/")
        let dshHome = override.isEmpty ? homeURL.appendingPathComponent(".dsh") : URL(fileURLWithPath: override)
        authURL = dshHome.standardizedFileURL.appendingPathComponent(".credentials.yaml")
        storageURL = homeURL.appendingPathComponent("Library/Application Support/Moa/deepseek-accounts/accounts.json")
        self.runtime = runtime ?? DeepSeekAppManager(dshHome: dshHome.standardizedFileURL)
    }

    func accounts() throws -> [DeepSeekAccount] {
        lock.lock(); defer { lock.unlock() }
        return try load().accounts
    }
    func currentFingerprint() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try readDocument().login?.fingerprint
    }

    @discardableResult
    func saveCurrent(name: String) throws -> DeepSeekAccount {
        try operation {
            let name = try validatedName(name)
            var database = try load()
            let wasRunning = runtime.isRunning
            try runtime.quit()
            do {
                let account = try credentialLock {
                    try requireStopped()
                    guard let login = try readDocument().login else {
                        throw DeepSeekError.message("DeepSeek is not signed in. Sign in to DeepSeek Harness before saving an account.")
                    }
                    let account = capture(login, name: name, in: &database)
                    try save(database)
                    return account
                }
                if wasRunning { try runtime.launch() }
                return account
            } catch {
                if wasRunning && !runtime.isRunning { try? runtime.launch() }
                throw error
            }
        }
    }

    @discardableResult
    func apply(id: UUID) throws -> DeepSeekAccount {
        try operation {
            var database = try load()
            guard let target = database.accounts.first(where: { $0.id == id }) else { throw missingAccount }
            let login = try DeepSeekCredentialDocument.savedLogin(target.snapshot)
            try changeLogin(to: login, database: &database)
            return target
        }
    }

    func prepareNewLogin() throws {
        try operation {
            var database = try load()
            try changeLogin(to: nil, database: &database)
        }
    }

    /// Stop first, then edit one record under Harness's own writer-lock protocol.
    /// No logout HTTP request is sent, so local account enrollment does not revoke
    /// saved grants. API keys, browser-session secrets and device identity remain.
    private func changeLogin(to target: DeepSeekLogin?, database: inout Database) throws {
        let wasRunning = runtime.isRunning
        try runtime.quit()
        var previous: DeepSeekLogin?
        var replaced = false
        do {
            try credentialLock {
                try requireStopped()
                let document = try readDocument()
                previous = document.login
                if let previous { _ = capture(previous, name: nil, in: &database) }
                try save(database)
                try writeLogin(target, in: document)
                replaced = true
            }
            try runtime.launch()
        } catch {
            if replaced {
                do {
                    try runtime.quit()
                    try requireStopped()
                    try credentialLock {
                        let document = try readDocument()
                        if let latest = document.login { _ = capture(latest, name: nil, in: &database) }
                        try save(database)
                        // Re-read and replace only the grant: startup may have
                        // legitimately changed other records or provider keys.
                        try writeLogin(previous, in: document)
                    }
                } catch {
                    throw DeepSeekError.message("DeepSeek could not restore the previous login. Saved accounts are intact; quit DeepSeek Harness and select the previous account again.")
                }
            }
            if wasRunning && !runtime.isRunning { try? runtime.launch() }
            throw error
        }
    }

    func rename(id: UUID, name: String) throws {
        try operation {
            let name = try validatedName(name)
            var database = try load()
            guard let index = database.accounts.firstIndex(where: { $0.id == id }) else { throw missingAccount }
            database.accounts[index].name = name
            try save(database)
        }
    }
    func delete(id: UUID) throws {
        try operation {
            var database = try load()
            guard database.accounts.contains(where: { $0.id == id }) else { throw missingAccount }
            database.accounts.removeAll { $0.id == id }
            try save(database)
        }
    }
    func open() throws { try operation { try runtime.launch() } }
    func reopen() throws { try operation { try runtime.quit(); try runtime.launch() } }

    private var missingAccount: DeepSeekError { .message("Saved DeepSeek account was not found.") }
    private func validatedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DeepSeekError.message("Enter an account name.") }
        return name
    }
    private func capture(_ login: DeepSeekLogin, name: String?, in database: inout Database) -> DeepSeekAccount {
        let existing = database.accounts.first { $0.fingerprint == login.fingerprint }
        let account = DeepSeekAccount(id: existing?.id ?? UUID(), name: name ?? existing?.name ?? MoaL10n.text("DeepSeek Account"),
                                      fingerprint: login.fingerprint, snapshot: login.snapshot, updatedAt: Date())
        if let index = database.accounts.firstIndex(where: { $0.id == account.id }) { database.accounts[index] = account }
        else { database.accounts.append(account) }
        return account
    }
    private func requireStopped() throws {
        guard !runtime.isRunning else {
            throw DeepSeekError.message("DeepSeek did not quit. Finish active tasks and quit it, then try again.")
        }
    }
    private func readDocument() throws -> DeepSeekCredentialDocument {
        guard validHome else { throw DeepSeekError.message("DSH_HOME must be an absolute path before using DeepSeek account switching.") }
        try rejectSymlinks(authURL)
        guard fm.fileExists(atPath: authURL.path) else { return try DeepSeekCredentialDocument("version: 1\n") }
        let attributes = try fm.attributesOfItem(atPath: authURL.path)
        guard let permissions = attributes[.posixPermissions] as? Int, permissions & 0o077 == 0,
              attributes[.type] as? FileAttributeType == .typeRegular else {
            throw DeepSeekError.message("DeepSeek credentials must be a private regular file readable only by this user. Check its file permissions before continuing.")
        }
        let data = try Data(contentsOf: authURL)
        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw DeepSeekError.message("DeepSeek credentials use an unsupported or invalid format. Update Moa before saving or switching accounts.")
        }
        return try DeepSeekCredentialDocument(text)
    }
    private func writeLogin(_ login: DeepSeekLogin?, in document: DeepSeekCredentialDocument) throws {
        try requireStopped()
        try secureWrite(Data(document.replacingLogin(with: login).utf8), to: authURL)
    }
    private func load() throws -> Database {
        try rejectSymlinks(storageURL)
        guard fm.fileExists(atPath: storageURL.path) else { return Database(credentialPath: authURL.path) }
        do {
            let database = try JSONDecoder().decode(Database.self, from: Data(contentsOf: storageURL))
            guard database.version == 1, database.credentialPath == authURL.path,
                  Set(database.accounts.map(\.id)).count == database.accounts.count,
                  Set(database.accounts.map(\.fingerprint)).count == database.accounts.count else { throw missingAccount }
            for account in database.accounts {
                guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      try DeepSeekCredentialDocument.savedLogin(account.snapshot).fingerprint == account.fingerprint else { throw missingAccount }
            }
            return database
        } catch {
            throw DeepSeekError.message("Saved DeepSeek accounts are invalid or belong to another credential path. Restore the local account file before continuing.")
        }
    }
    private func save(_ database: Database) throws {
        try prepareStorage()
        try secureWrite(JSONEncoder().encode(database), to: storageURL)
    }
    private func prepareStorage() throws {
        let directory = storageURL.deletingLastPathComponent()
        try rejectSymlinks(directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func operation<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard validHome else { throw DeepSeekError.message("DSH_HOME must be an absolute path before using DeepSeek account switching.") }
        try prepareStorage()
        let path = storageURL.deletingLastPathComponent().appendingPathComponent("operation.lock")
        try rejectSymlinks(path)
        let descriptor = Darwin.open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw DeepSeekError.message("Unable to lock or save DeepSeek credentials. Check the local file permissions.") }
        defer { _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw DeepSeekError.message("Another Moa instance is updating DeepSeek. Wait for it to finish and try again.")
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
    private func credentialLock<T>(_ body: () throws -> T) throws -> T {
        guard validHome else { throw DeepSeekError.message("DSH_HOME must be an absolute path before using DeepSeek account switching.") }
        let directory = authURL.deletingLastPathComponent()
        try rejectSymlinks(directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = authURL.appendingPathExtension("lock")
        try rejectSymlinks(path)
        var descriptor = Darwin.open(path.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if descriptor < 0 && errno == EEXIST, try recoverExitedWriter(at: path) {
            descriptor = Darwin.open(path.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw DeepSeekError.message("DeepSeek credentials are being updated by another process. Wait for it to finish and try again.")
        }
        defer { _ = Darwin.close(descriptor); _ = Darwin.unlink(path.path) }
        let pid = Data("\(getpid())\n".utf8)
        let written = pid.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard written == pid.count else { throw DeepSeekError.message("Unable to lock or save DeepSeek credentials. Check the local file permissions.") }
        return try body()
    }
    /// Match Harness's claim-file protocol; never remove an active or unreadable
    /// writer lock, and recheck the exact record under the shared takeover claim.
    private func recoverExitedWriter(at path: URL) throws -> Bool {
        guard let record = try? Data(contentsOf: path), let text = String(data: record, encoding: .utf8),
              text.hasSuffix("\n"), let pid = Int32(text.dropLast()), pid > 0,
              text == "\(pid)\n",
              Darwin.kill(pid, 0) != 0, errno == ESRCH else { return false }
        let hash = SHA256.hash(data: record).map { String(format: "%02x", $0) }.joined().prefix(16)
        let claim = URL(fileURLWithPath: path.path + ".takeover-" + String(hash))
        try rejectSymlinks(claim)
        let descriptor = Darwin.open(claim.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor); _ = Darwin.unlink(claim.path) }
        let owner = Data("\(getpid())\n".utf8)
        guard owner.withUnsafeBytes({ Darwin.write(descriptor, $0.baseAddress, $0.count) }) == owner.count,
              (try? Data(contentsOf: path)) == record, Darwin.kill(pid, 0) != 0, errno == ESRCH else { return false }
        return Darwin.unlink(path.path) == 0
    }
    private func rejectSymlinks(_ url: URL) throws {
        var path = url.standardizedFileURL
        let boundary = homeURL.deletingLastPathComponent().path
        while path.path != "/" && path.path != boundary {
            if (try? fm.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw DeepSeekError.message("DeepSeek credential paths must not contain symbolic links.")
            }
            path.deleteLastPathComponent()
        }
    }
    private func secureWrite(_ data: Data, to url: URL) throws {
        try rejectSymlinks(url)
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".moa-deepseek-\(UUID().uuidString)")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw DeepSeekError.message("Unable to lock or save DeepSeek credentials. Check the local file permissions.") }
        defer { _ = Darwin.close(descriptor); try? fm.removeItem(at: temporary) }
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(descriptor) == 0, Darwin.rename(temporary.path, url.path) == 0 else {
            throw DeepSeekError.message("Unable to lock or save DeepSeek credentials. Check the local file permissions.")
        }
    }
}
