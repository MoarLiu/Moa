import Darwin
import Foundation
import Security

struct AntigravityAccount: Codable, Identifiable {
    var id: UUID
    var name: String
    var identity: String
    var email: String
    var updatedAt: Date
}

struct AntigravityAccountOverview {
    var accounts: [AntigravityAccount] = []
    var currentID: UUID?
    var message: String?
}

final class AntigravityController {
    private struct LiveState: Equatable {
        var keychain: Data?
        var fallback: Data?

        init(keychain: Data? = nil, fallback: Data? = nil) {
            self.keychain = keychain
            self.fallback = fallback
        }
        init(_ login: AntigravityLogin?) {
            keychain = login?.data
            fallback = login?.fileData
        }
        func primaryLogin() throws -> AntigravityLogin? {
            try (keychain ?? fallback).map(AntigravityLogin.init)
        }
    }
    private struct Database: Codable {
        var version = 1
        var accounts: [AntigravityAccount] = []
    }
    let storageURL: URL
    let fallbackURL: URL
    private let home: URL
    private let store: AntigravityCredentialStoring
    private let runtime: AntigravityAppManaging
    private let lock = NSRecursiveLock()
    private let fm = FileManager.default

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         store: AntigravityCredentialStoring = AntigravityKeychain(),
         runtime: AntigravityAppManaging = AntigravityAppManager()) {
        home = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath()
        storageURL = home.appendingPathComponent("Library/Application Support/Moa/antigravity-accounts/accounts.json")
        fallbackURL = home.appendingPathComponent(".gemini/jetski-standalone-oauth-token")
        self.store = store
        self.runtime = runtime
    }

    func accounts() throws -> [AntigravityAccount] { try lock.withLock { try load().accounts } }

    /// Called on a background queue. Passive refresh never requests Keychain UI.
    func overview() throws -> AntigravityAccountOverview {
        try lock.withLock {
            let database = try load()
            do {
                let login = try readLive(interaction: false).primaryLogin()
                return AntigravityAccountOverview(accounts: database.accounts,
                    currentID: database.accounts.first { $0.identity == login?.identity }?.id)
            } catch AntigravityError.keychain(let status) where [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
                return AntigravityAccountOverview(accounts: database.accounts,
                    message: MoaL10n.text("Use Save Current Login to allow Moa to read the Antigravity login in Keychain."))
            } catch {
                return AntigravityAccountOverview(accounts: database.accounts, message: error.localizedDescription)
            }
        }
    }

    @discardableResult
    func saveCurrent(name: String) throws -> AntigravityAccount {
        try operation {
            let name = try validatedName(name)
            var database = try load()
            try runtime.validateInstallation()
            try runtime.ensureNoOtherClients()
            let wasRunning = runtime.isRunning
            try runtime.quit()
            do {
                try runtime.ensureStopped()
                let state = try readLive(interaction: true)
                guard let login = try state.primaryLogin() else {
                    throw AntigravityError.message("Sign in to Antigravity with your Google account before saving the current login.")
                }
                try preserveDifferentFallback(state, primary: login, in: &database)
                let account = try capture(login, name: name, in: &database)
                if wasRunning { try runtime.launch() }
                return account
            } catch {
                if wasRunning && !runtime.isRunning { try? runtime.launch() }
                throw error
            }
        }
    }

    @discardableResult
    func apply(id: UUID) throws -> AntigravityAccount {
        try operation {
            var database = try load()
            guard let target = database.accounts.first(where: { $0.id == id }),
                  let data = try store.read(.saved(id), interaction: true) else { throw missingAccount }
            let login = try AntigravityLogin(data)
            guard login.identity == target.identity else { throw missingAccount }
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

    private func changeLogin(to target: AntigravityLogin?, database: inout Database) throws {
        try runtime.validateInstallation()
        try runtime.ensureNoOtherClients()
        let wasRunning = runtime.isRunning
        try runtime.quit()
        var original = LiveState()
        var replaced = false
        do {
            try runtime.ensureStopped()
            original = try readLive(interaction: true)
            let current = try original.primaryLogin()
            try preserveDifferentFallback(original, primary: current, in: &database)
            if let current { _ = try capture(current, name: nil, in: &database) }
            // Selecting the same Google account retains its latest refreshed grant.
            let destination = LiveState(target?.identity == current?.identity ? current : target)
            try replaceLive(with: destination, expected: original)
            replaced = true
            try runtime.launch()
        } catch {
            let failure = error
            if replaced {
                do {
                    try runtime.quit()
                    try runtime.ensureStopped()
                    let latest = try readLive(interaction: true)
                    let primary = try latest.primaryLogin()
                    try preserveDifferentFallback(latest, primary: primary, in: &database)
                    if let primary { _ = try capture(primary, name: nil, in: &database) }
                    try replaceLive(with: original, expected: latest)
                } catch {
                    throw AntigravityError.recoveryRequired
                }
            }
            if case AntigravityError.recoveryRequired = failure { throw failure }
            if wasRunning && !runtime.isRunning { try? runtime.launch() }
            throw failure
        }
    }

    private func replaceLive(with state: LiveState, expected: LiveState) throws {
        try runtime.ensureStopped()
        guard try readLive(interaction: true) == expected else {
            throw AntigravityError.message("Antigravity login changed during the operation. Close all shared clients and try again.")
        }
        // The file can bootstrap sign-in when the keyring is unavailable. Keep
        // both sources on the same login; a Keychain-only enrollment is unsafe.
        try writeFallback(state.fallback)
        do { try store.write(state.keychain, to: .live) }
        catch {
            let failure = error
            do {
                try runtime.ensureStopped()
                guard try readFallback() == state.fallback,
                      try store.read(.live, interaction: true) == expected.keychain else { throw AntigravityError.recoveryRequired }
                try writeFallback(expected.fallback)
            } catch { throw AntigravityError.recoveryRequired }
            throw failure
        }
    }

    private func readLive(interaction: Bool) throws -> LiveState {
        try LiveState(keychain: store.read(.live, interaction: interaction), fallback: readFallback())
    }

    private func preserveDifferentFallback(_ state: LiveState, primary: AntigravityLogin?, in database: inout Database) throws {
        if let data = state.fallback {
            let fallback = try AntigravityLogin(data)
            if fallback.identity != primary?.identity { _ = try capture(fallback, name: nil, in: &database) }
        }
    }

    private func readFallback() throws -> Data? {
        try rejectSymlinks(fallbackURL)
        guard fm.fileExists(atPath: fallbackURL.path) else { return nil }
        let attributes = try fm.attributesOfItem(atPath: fallbackURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else {
            throw AntigravityError.message("The Antigravity fallback login file is unsupported. Close Antigravity and restore its login file before switching accounts.")
        }
        return try Data(contentsOf: fallbackURL)
    }

    private func writeFallback(_ data: Data?) throws {
        try rejectSymlinks(fallbackURL)
        if let data {
            let directory = fallbackURL.deletingLastPathComponent()
            // Existing .gemini permissions belong to the client; do not change them.
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try MoaSecureFile.write(data, to: fallbackURL)
        } else if fm.fileExists(atPath: fallbackURL.path) {
            try fm.removeItem(at: fallbackURL)
        }
    }

    /// Saved credentials live only in Keychain; the local JSON contains labels and
    /// hashed identity metadata. Refreshes of an existing login remain saved
    /// even if writing an updated timestamp or label subsequently fails.
    private func capture(_ login: AntigravityLogin, name: String?, in database: inout Database) throws -> AntigravityAccount {
        let existing = database.accounts.first { $0.identity == login.identity }
        let account = AntigravityAccount(id: existing?.id ?? UUID(),
            name: name ?? existing?.name ?? (login.email.isEmpty ? MoaL10n.text("Antigravity Account") : login.email),
            identity: login.identity, email: login.email, updatedAt: Date())
        try store.write(login.data, to: .saved(account.id))
        var updated = database
        if let index = updated.accounts.firstIndex(where: { $0.id == account.id }) { updated.accounts[index] = account }
        else { updated.accounts.append(account) }
        do { try save(updated) }
        catch {
            if existing == nil { try? store.write(nil, to: .saved(account.id)) }
            throw error
        }
        database = updated
        return account
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
            let previous = try store.read(.saved(id), interaction: true)
            try store.write(nil, to: .saved(id))
            database.accounts.removeAll { $0.id == id }
            do { try save(database) }
            catch {
                do { try store.write(previous, to: .saved(id)) }
                catch { throw AntigravityError.message("The saved Antigravity login could not be restored after a failed delete. Save that account again after unlocking Keychain.") }
                throw error
            }
        }
    }

    func open() throws { try runtime.launch() }
    func reopen() throws {
        try operation {
            try runtime.ensureNoOtherClients()
            try runtime.quit()
            try runtime.launch()
        }
    }

    private var missingAccount: AntigravityError { .message("The saved Antigravity login is missing or does not match its account. Sign in and save it again.") }
    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { throw AntigravityError.message("Enter an account name of 1 to 200 characters.") }
        return trimmed
    }

    private func operation<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            let directory = storageURL.deletingLastPathComponent()
            try rejectSymlinks(directory)
            try MoaSecureFile.ensurePrivateDirectory(directory)
            let path = directory.appendingPathComponent("operation.lock")
            let descriptor = Darwin.open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw AntigravityError.message("Unable to lock the Antigravity account store. Check its local directory permissions.") }
            defer { Darwin.close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw AntigravityError.message("Another Moa instance is updating Antigravity. Wait for it to finish and try again.") }
            defer { flock(descriptor, LOCK_UN) }
            return try body()
        }
    }

    private func rejectSymlinks(_ url: URL) throws {
        var path = url.standardizedFileURL
        let boundary = home.deletingLastPathComponent().path
        while path.path != "/" && path.path != boundary {
            if (try? fm.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw AntigravityError.message("Antigravity account metadata paths must not contain symbolic links.")
            }
            path.deleteLastPathComponent()
        }
    }

    private func load() throws -> Database {
        try rejectSymlinks(storageURL)
        guard fm.fileExists(atPath: storageURL.path) else { return Database() }
        guard let attributes = try? fm.attributesOfItem(atPath: storageURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 5_242_880,
              let data = try? Data(contentsOf: storageURL),
              let database = try? JSONDecoder().decode(Database.self, from: data), database.version == 1,
              Set(database.accounts.map(\.id)).count == database.accounts.count,
              Set(database.accounts.map(\.identity)).count == database.accounts.count,
              database.accounts.allSatisfy({ $0.identity.count == 64 && $0.identity.allSatisfy(\.isHexDigit) && !$0.name.isEmpty }) else {
            throw AntigravityError.message("Antigravity account metadata is invalid. Restore the local metadata before changing accounts; Keychain logins have not been changed.")
        }
        return database
    }

    private func save(_ database: Database) throws {
        try rejectSymlinks(storageURL)
        try MoaSecureFile.write(JSONEncoder().encode(database), to: storageURL)
    }
}
