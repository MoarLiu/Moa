import CryptoKit
import Darwin
import Foundation

enum GeminiCLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let key):
            return MoaL10n.text(key)
        }
    }
}

struct GeminiCLIAccount: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var identity: String
    var email: String
    var oauthCredsSnapshot: Data
    var googleAccountsSnapshot: Data?
    var updatedAt: Date
}

struct GeminiCLILogin {
    let oauthCredsData: Data
    let googleAccountsData: Data?
    let identity: String
    let email: String
    let expiresAt: Date?
    let hasRefreshToken: Bool

    init(oauthCredsData: Data, googleAccountsData: Data? = nil) throws {
        guard !oauthCredsData.isEmpty, oauthCredsData.count <= 2 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: oauthCredsData) as? [String: Any] else {
            throw GeminiCLIError.message("Gemini CLI login format is unsupported or invalid. Run `gemini` to sign in and try again.")
        }
        let accessToken = (root["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshToken = (root["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty || !refreshToken.isEmpty else {
            throw GeminiCLIError.message("Gemini CLI is not signed in. Sign in with Gemini CLI first, then save the login.")
        }

        self.oauthCredsData = oauthCredsData
        self.googleAccountsData = googleAccountsData
        self.hasRefreshToken = !refreshToken.isEmpty

        var jwtClaims: [String: Any] = [:]
        if let idToken = root["id_token"] as? String {
            jwtClaims = Self.decodeJWTPayload(idToken) ?? [:]
        }

        var activeEmail = (jwtClaims["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeEmail == nil || activeEmail?.isEmpty == true,
           let accountsData = googleAccountsData,
           let accountsObj = try? JSONSerialization.jsonObject(with: accountsData) as? [String: Any],
           let active = (accountsObj["active"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !active.isEmpty {
            activeEmail = active
        }

        let normalizedEmail = (activeEmail?.contains("@") == true) ? activeEmail!.lowercased() : ""
        let subject = (jwtClaims["sub"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identitySeed: String
        if !subject.isEmpty {
            identitySeed = "gemini-cli:sub:\(subject)"
        } else if !normalizedEmail.isEmpty {
            identitySeed = "gemini-cli:email:\(normalizedEmail)"
        } else if !refreshToken.isEmpty {
            identitySeed = "gemini-cli:refresh:\(refreshToken)"
        } else {
            identitySeed = "gemini-cli:access:\(accessToken)"
        }
        self.identity = SHA256.hash(data: Data(identitySeed.utf8)).map { String(format: "%02x", $0) }.joined()
        self.email = normalizedEmail

        if let expiryMs = (root["expiry_date"] as? NSNumber)?.doubleValue, expiryMs > 0 {
            let seconds = expiryMs > 100_000_000_000 ? expiryMs / 1000.0 : expiryMs
            self.expiresAt = Date(timeIntervalSince1970: seconds)
        } else if let exp = (jwtClaims["exp"] as? NSNumber)?.doubleValue, exp > 0 {
            self.expiresAt = Date(timeIntervalSince1970: exp)
        } else {
            self.expiresAt = nil
        }
    }

    private static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

/// Manages isolated multi-account snapshots for Google Gemini CLI (`~/.gemini/oauth_creds.json`
/// and `~/.gemini/google_accounts.json`). Never touches Antigravity files or Keychain items.
final class GeminiCLIController {
    private struct Database: Codable {
        var version: Int = 1
        var accounts: [GeminiCLIAccount] = []
    }

    let geminiDir: URL
    let oauthCredsURL: URL
    let googleAccountsURL: URL
    let storageURL: URL
    private let fm = FileManager.default
    private let lock = NSRecursiveLock()

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = MoaDataRoot.homeDirectory(environment: environment).resolvingSymlinksInPath()
        geminiDir = home.appendingPathComponent(".gemini", isDirectory: true).standardizedFileURL
        oauthCredsURL = geminiDir.appendingPathComponent("oauth_creds.json")
        googleAccountsURL = geminiDir.appendingPathComponent("google_accounts.json")
        // Deliberately stored outside movable ~/.moa so local OAuth grants stay device-scoped.
        storageURL = home.appendingPathComponent("Library/Application Support/Moa/gemini-cli-accounts/accounts.json")
    }

    func accounts() throws -> [GeminiCLIAccount] {
        try lock.withLock { try load().accounts }
    }

    func currentLogin() throws -> GeminiCLILogin? {
        try lock.withLock { try readLiveLogin() }
    }

    func currentIdentity() throws -> String? {
        try currentLogin()?.identity
    }

    @discardableResult
    func saveCurrent(name: String) throws -> GeminiCLIAccount {
        try operation {
            let validName = try validatedName(name)
            var db = try load()
            guard let live = try readLiveLogin() else {
                throw GeminiCLIError.message("Gemini CLI is not signed in. Sign in with Gemini CLI first, then save the login.")
            }
            let saved = capture(live, name: validName, in: &db)
            try save(db)
            return saved
        }
    }

    @discardableResult
    func apply(id: UUID) throws -> GeminiCLIAccount {
        try operation {
            var db = try load()
            guard let target = db.accounts.first(where: { $0.id == id }) else {
                throw GeminiCLIError.message("Saved Gemini CLI account was not found.")
            }
            let targetLogin = try GeminiCLILogin(
                oauthCredsData: target.oauthCredsSnapshot,
                googleAccountsData: target.googleAccountsSnapshot
            )
            guard targetLogin.identity == target.identity else {
                throw GeminiCLIError.message("Saved Gemini CLI account is corrupt. Save it again.")
            }
            try replaceLive(with: targetLogin, database: &db)
            return target
        }
    }

    func prepareNewLogin() throws {
        try operation {
            var db = try load()
            try replaceLive(with: nil, database: &db)
        }
    }

    func rename(id: UUID, name: String) throws {
        try operation {
            let validName = try validatedName(name)
            var db = try load()
            guard let index = db.accounts.firstIndex(where: { $0.id == id }) else {
                throw GeminiCLIError.message("Saved Gemini CLI account was not found.")
            }
            db.accounts[index].name = validName
            db.accounts[index].updatedAt = Date()
            try save(db)
        }
    }

    func delete(id: UUID) throws {
        try operation {
            var db = try load()
            guard db.accounts.contains(where: { $0.id == id }) else {
                throw GeminiCLIError.message("Saved Gemini CLI account was not found.")
            }
            db.accounts.removeAll { $0.id == id }
            try save(db)
        }
    }

    func openGeminiFolder() {
        try? fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        _ = MoaProcessRunner.run("/usr/bin/open", [geminiDir.path])
    }

    // MARK: - Private Transaction & Storage Helpers

    private func replaceLive(with target: GeminiCLILogin?, database: inout Database) throws {
        try rejectSymlinks(oauthCredsURL)
        try rejectSymlinks(googleAccountsURL)
        let originalOAuth = fm.fileExists(atPath: oauthCredsURL.path) ? try Data(contentsOf: oauthCredsURL) : nil
        let originalAccounts = fm.fileExists(atPath: googleAccountsURL.path) ? try Data(contentsOf: googleAccountsURL) : nil
        var destination = target
        if let current = try? readLiveLogin() {
            let preserved = capture(current, name: nil, in: &database)
            if target?.identity == current.identity {
                destination = try? GeminiCLILogin(
                    oauthCredsData: preserved.oauthCredsSnapshot,
                    googleAccountsData: preserved.googleAccountsSnapshot
                )
            }
        }
        try save(database)
        do {
            try writeLiveFiles(destination)
        } catch let writeError {
            // Roll back live files on partial write failure.
            do {
                try restoreFile(originalOAuth, to: oauthCredsURL)
                try restoreFile(originalAccounts, to: googleAccountsURL)
            } catch {
                throw GeminiCLIError.message("Gemini CLI could not restore the previous login. Saved accounts remain intact; select your previous account again.")
            }
            throw writeError
        }
    }

    private func writeLiveFiles(_ login: GeminiCLILogin?) throws {
        try rejectSymlinks(geminiDir)
        try rejectSymlinks(oauthCredsURL)
        try rejectSymlinks(googleAccountsURL)
        if let login {
            if !fm.fileExists(atPath: geminiDir.path) {
                try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try MoaSecureFile.write(login.oauthCredsData, to: oauthCredsURL)
            if let accountsData = login.googleAccountsData {
                try MoaSecureFile.write(accountsData, to: googleAccountsURL)
            } else if !login.email.isEmpty {
                let fallbackAccounts: [String: Any] = ["active": login.email, "old": []]
                let data = try JSONSerialization.data(withJSONObject: fallbackAccounts, options: [.prettyPrinted, .sortedKeys])
                try MoaSecureFile.write(data, to: googleAccountsURL)
            }
        } else {
            if fm.fileExists(atPath: oauthCredsURL.path) {
                try fm.removeItem(at: oauthCredsURL)
            }
            if fm.fileExists(atPath: googleAccountsURL.path) {
                try fm.removeItem(at: googleAccountsURL)
            }
        }
    }

    private func restoreFile(_ data: Data?, to url: URL) throws {
        if let data {
            try MoaSecureFile.write(data, to: url)
        } else if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private func readLiveLogin() throws -> GeminiCLILogin? {
        try rejectSymlinks(oauthCredsURL)
        guard fm.fileExists(atPath: oauthCredsURL.path) else { return nil }
        let oauthData = try Data(contentsOf: oauthCredsURL)
        var accountsData: Data?
        if fm.fileExists(atPath: googleAccountsURL.path) {
            try rejectSymlinks(googleAccountsURL)
            accountsData = try? Data(contentsOf: googleAccountsURL)
        }
        return try GeminiCLILogin(oauthCredsData: oauthData, googleAccountsData: accountsData)
    }

    private func capture(_ login: GeminiCLILogin, name: String?, in database: inout Database) -> GeminiCLIAccount {
        let existing = database.accounts.first { $0.identity == login.identity }
        let fallbackName = login.email.isEmpty ? MoaL10n.text("Gemini CLI Account") : login.email
        let account = GeminiCLIAccount(
            id: existing?.id ?? UUID(),
            name: name ?? existing?.name ?? fallbackName,
            identity: login.identity,
            email: login.email,
            oauthCredsSnapshot: login.oauthCredsData,
            googleAccountsSnapshot: login.googleAccountsData,
            updatedAt: Date()
        )
        if let index = database.accounts.firstIndex(where: { $0.id == account.id }) {
            database.accounts[index] = account
        } else {
            database.accounts.append(account)
        }
        return account
    }

    private func validatedName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else {
            throw GeminiCLIError.message("Enter an account name of 1 to 200 characters.")
        }
        return trimmed
    }

    private func load() throws -> Database {
        try rejectSymlinks(storageURL)
        guard fm.fileExists(atPath: storageURL.path) else { return Database() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Database.self, from: Data(contentsOf: storageURL))
    }

    private func save(_ database: Database) throws {
        try prepareStorage()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try MoaSecureFile.write(try encoder.encode(database), to: storageURL)
    }

    private func prepareStorage() throws {
        let dir = storageURL.deletingLastPathComponent()
        try rejectSymlinks(dir)
        try MoaSecureFile.ensurePrivateDirectory(dir)
    }

    private func operation<T>(_ body: () throws -> T) throws -> T {
        try lock.withLock {
            try prepareStorage()
            let lockPath = storageURL.deletingLastPathComponent().appendingPathComponent("operation.lock")
            try rejectSymlinks(lockPath)
            let fd = Darwin.open(lockPath.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else {
                throw GeminiCLIError.message("Unable to lock Gemini CLI account storage.")
            }
            defer { _ = Darwin.close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                throw GeminiCLIError.message("Another Moa operation is updating Gemini CLI. Wait for it to finish and try again.")
            }
            defer { _ = flock(fd, LOCK_UN) }
            return try body()
        }
    }

    private func rejectSymlinks(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GeminiCLIError.message("Refusing to access a symbolic link in Gemini CLI credentials.")
        }
    }
}
