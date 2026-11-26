import CommonCrypto
import CryptoKit
import Foundation
import Security

enum MoaDataPackageScope: String, Codable, CaseIterable, Identifiable {
    case fullBackup = "full"
    case configOnly = "config-only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBackup: return MoaL10n.text("Full Backup (Settings, Prices & Transferable Credentials)")
        case .configOnly: return MoaL10n.text("Settings & Prices Only (No Credentials)")
        }
    }
}

struct MoaDataPackageEncryptionMetadata: Codable, Equatable {
    var algorithm: String
    var kdf: String
    var iterations: Int
    var saltBase64: String
    var nonceBase64: String
    var keyVerifierBase64: String
    var ciphertextSHA256: String
    var payloadFileName: String
}

struct MoaDataPackageInspection: Equatable {
    let schemaVersion: Int
    let isEncrypted: Bool
    let scope: MoaDataPackageScope
    let exportedAt: String
    let appVersion: String
    let appBuild: String
}

/// Cryptographic primitives for Moa Data Package Schema 3.
/// Uses PBKDF2-HMAC-SHA256 (CommonCrypto) + AES-256-GCM (CryptoKit) with AAD binding
/// and a dedicated key-check HMAC so wrong passwords are cleanly distinguished from corrupted archives.
enum MoaDataPackageCrypto {
    static let algorithm = "AES-256-GCM"
    static let kdf = "PBKDF2-HMAC-SHA256"
    static let defaultIterations = 600_000
    static let minimumIterations = 100_000
    static let maximumIterations = 5_000_000
    static let payloadFileName = "payload.enc"
    private static let keyCheckDomain = "MoaDataPackage-v3-KeyCheck|"

    static func encrypt(
        plaintext: Data,
        password: String,
        scope: MoaDataPackageScope,
        iterations: Int = defaultIterations
    ) throws -> (ciphertext: Data, metadata: MoaDataPackageEncryptionMetadata) {
        guard !password.isEmpty else {
            throw MoaDataPackageError.emptyPassword
        }
        guard (minimumIterations...maximumIterations).contains(iterations) else {
            throw MoaDataPackageError.invalidPackage
        }

        let salt = try randomBytes(count: 32)
        let nonceBytes = try randomBytes(count: 12)
        let derived = try deriveKeys(password: password, salt: salt, iterations: iterations)
        let verifier = computeKeyVerifier(verifierKey: derived.verifierKey, salt: salt, iterations: iterations, scope: scope)
        let aad = authenticatedHeaderData(salt: salt, iterations: iterations, scope: scope)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try AES.GCM.seal(plaintext, using: derived.encryptionKey, nonce: nonce, authenticating: aad)
        // Store ciphertext + 16-byte GCM tag in a fresh 0-indexed Data buffer (nonce lives in manifest metadata).
        var payload = Data(capacity: sealed.ciphertext.count + sealed.tag.count)
        payload.append(sealed.ciphertext)
        payload.append(sealed.tag)
        let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        let metadata = MoaDataPackageEncryptionMetadata(
            algorithm: algorithm,
            kdf: kdf,
            iterations: iterations,
            saltBase64: salt.base64EncodedString(),
            nonceBase64: nonceBytes.base64EncodedString(),
            keyVerifierBase64: verifier.base64EncodedString(),
            ciphertextSHA256: payloadDigest,
            payloadFileName: payloadFileName
        )
        return (payload, metadata)
    }

    static func decrypt(
        ciphertextAndTag: Data,
        metadata: MoaDataPackageEncryptionMetadata,
        scope: MoaDataPackageScope,
        password: String
    ) throws -> Data {
        guard !password.isEmpty else {
            throw MoaDataPackageError.emptyPassword
        }
        guard metadata.algorithm == algorithm,
              metadata.kdf == kdf,
              (minimumIterations...maximumIterations).contains(metadata.iterations),
              let salt = Data(base64Encoded: metadata.saltBase64), salt.count >= 16,
              let nonceBytes = Data(base64Encoded: metadata.nonceBase64), nonceBytes.count == 12,
              let expectedVerifier = Data(base64Encoded: metadata.keyVerifierBase64), expectedVerifier.count == 32,
              ciphertextAndTag.count >= 16 else {
            throw MoaDataPackageError.corruptedPackage
        }

        // Step 1: Verify ciphertext integrity before password check so corrupted files
        // are reported as corrupted rather than misreported as wrong password.
        let actualDigest = SHA256.hash(data: ciphertextAndTag).map { String(format: "%02x", $0) }.joined()
        guard actualDigest == metadata.ciphertextSHA256.lowercased() else {
            throw MoaDataPackageError.corruptedPackage
        }

        // Step 2: Derive keys and verify key-check MAC in constant time.
        let derived = try deriveKeys(password: password, salt: salt, iterations: metadata.iterations)
        let actualVerifier = computeKeyVerifier(
            verifierKey: derived.verifierKey,
            salt: salt,
            iterations: metadata.iterations,
            scope: scope
        )
        guard constantTimeEqual(actualVerifier, expectedVerifier) else {
            throw MoaDataPackageError.wrongPassword
        }

        // Step 3: Decrypt and authenticate with AES-256-GCM + AAD.
        let ciphertextCount = ciphertextAndTag.count - 16
        let ciphertext = ciphertextAndTag.prefix(ciphertextCount)
        let tag = ciphertextAndTag.suffix(16)
        let aad = authenticatedHeaderData(salt: salt, iterations: metadata.iterations, scope: scope)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceBytes)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: derived.encryptionKey, authenticating: aad)
        } catch {
            // Password verified via keyVerifier, so GCM failure indicates corruption/tampering.
            throw MoaDataPackageError.corruptedPackage
        }
    }

    private static func deriveKeys(
        password: String,
        salt: Data,
        iterations: Int
    ) throws -> (encryptionKey: SymmetricKey, verifierKey: SymmetricKey) {
        let passwordData = Data(password.utf8)
        var derivedBytes = [UInt8](repeating: 0, count: 64)
        let status: Int32 = passwordData.withUnsafeBytes { pwdPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwdPtr.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derivedBytes,
                    derivedBytes.count
                )
            }
        }
        guard status == kCCSuccess else {
            throw MoaDataPackageError.commandFailed(MoaL10n.text("Failed to derive encryption key."))
        }
        let encKey = SymmetricKey(data: Data(derivedBytes[0..<32]))
        let verKey = SymmetricKey(data: Data(derivedBytes[32..<64]))
        derivedBytes.resetBytes(in: 0..<derivedBytes.count)
        return (encKey, verKey)
    }

    private static func computeKeyVerifier(
        verifierKey: SymmetricKey,
        salt: Data,
        iterations: Int,
        scope: MoaDataPackageScope
    ) -> Data {
        var message = Data(keyCheckDomain.utf8)
        message.append(Data("\(iterations)|\(scope.rawValue)|".utf8))
        message.append(salt)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: verifierKey)
        return Data(mac)
    }

    private static func authenticatedHeaderData(salt: Data, iterations: Int, scope: MoaDataPackageScope) -> Data {
        var aad = Data("MoaDataPackage|v3|\(algorithm)|\(kdf)|\(iterations)|\(scope.rawValue)|".utf8)
        aad.append(salt)
        return aad
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw MoaDataPackageError.commandFailed(MoaL10n.text("Failed to generate cryptographic random bytes."))
        }
        return Data(bytes)
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            diff |= a ^ b
        }
        return diff == 0
    }

    /// Enforces a strict allowlist and redacts all credentials inside a staged `.moa` directory
    /// for `.configOnly` ("Settings & Prices Only (No Credentials)") layered exports.
    /// Any file not in the allowlist (such as `auth.json`, `codex_official_accounts.json`,
    /// `codex-auth/`, `backups/`, or unknown files) is removed; any allowlisted provider/config
    /// file that cannot be parsed and sanitized fails closed by being removed.
    static func stripCredentialsForConfigOnlyExport(in copiedMoaHome: URL, fileManager: FileManager = .default) throws {
        let pricingFiles: Set<String> = [
            "usage-pricing-overrides.json",
            "usage-pricing-catalog-v1.json"
        ]
        let sanitizedJSONFiles: Set<String> = [
            "profiles.json",
            "claude_desktop_profiles.json",
            "claude_code_profiles.json"
        ]
        let allowlist = pricingFiles.union(sanitizedJSONFiles).union(["config.toml"])

        let topLevelItems = try fileManager.contentsOfDirectory(
            at: copiedMoaHome,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for itemURL in topLevelItems {
            let name = itemURL.lastPathComponent
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if !allowlist.contains(name) || values?.isDirectory == true || values?.isSymbolicLink == true {
                try fileManager.removeItem(at: itemURL)
            }
        }

        // Sanitize allowlisted JSON provider databases while preserving non-secret structure.
        // Fail closed: remove any unparseable file so raw secrets can never leak.
        for jsonFile in sanitizedJSONFiles {
            let url = copiedMoaHome.appendingPathComponent(jsonFile)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                try fileManager.removeItem(at: url)
                continue
            }
            let sanitized = strippingSecretsFromJSON(object)
            if JSONSerialization.isValidJSONObject(sanitized),
               let encoded = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]) {
                try encoded.write(to: url, options: .atomic)
            } else {
                try fileManager.removeItem(at: url)
            }
        }

        // Strip ALL credentials from config.toml across active, inactive, and custom tables.
        // Fail closed: remove if unreadable as UTF-8.
        let configURL = copiedMoaHome.appendingPathComponent("config.toml")
        if fileManager.fileExists(atPath: configURL.path) {
            if let text = try? String(contentsOf: configURL, encoding: .utf8) {
                let sanitized = MoaCodexConfigEditor.strippingAllCredentials(from: text)
                try sanitized.write(to: configURL, atomically: true, encoding: .utf8)
            } else {
                try fileManager.removeItem(at: configURL)
            }
        }
    }

    private static func strippingSecretsFromJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (k, v) in dict {
                if isSensitiveJSONKey(k) {
                    copy[k] = ""
                } else {
                    copy[k] = strippingSecretsFromJSON(v)
                }
            }
            return copy
        }
        if let array = value as? [Any] {
            return array.map { strippingSecretsFromJSON($0) }
        }
        if let string = value as? String {
            return sanitizedConfigOnlyString(string)
        }
        return value
    }

    private static func isSensitiveJSONKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let normalized = lower.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        if ["apikey", "auth", "authorization", "key", "password", "passwd", "cookie", "bearer", "headers", "httpheaders"].contains(normalized) {
            return true
        }
        let fragments = ["token", "secret", "password", "passwd", "apikey", "credential", "privatekey", "accesskey", "authorization", "cookie", "bearer"]
        return fragments.contains { normalized.contains($0) }
    }

    /// Strips userinfo, query parameters, and fragments from a URL string so embedded secrets
    /// cannot leak in config-only exports, CLI JSON output, or health/diagnostic messages.
    static func sanitizedURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if var components = URLComponents(string: trimmed),
           components.scheme != nil, components.host != nil {
            if components.user != nil || components.password != nil || components.query != nil || components.fragment != nil {
                components.user = nil
                components.password = nil
                components.query = nil
                components.fragment = nil
                return components.string ?? ""
            }
            return trimmed
        }
        // Fail closed for malformed URLs that still contain query/fragment/userinfo markers.
        if trimmed.contains("://") && (trimmed.contains("?") || trimmed.contains("#") || trimmed.contains("@")) {
            var candidate = trimmed
            if let qIndex = candidate.firstIndex(of: "?") {
                candidate = String(candidate[..<qIndex])
            }
            if let hIndex = candidate.firstIndex(of: "#") {
                candidate = String(candidate[..<hIndex])
            }
            if let schemeEnd = candidate.range(of: "://")?.upperBound,
               let atIndex = candidate[schemeEnd...].firstIndex(of: "@") {
                let slashAfterScheme = candidate[schemeEnd...].firstIndex(of: "/")
                if slashAfterScheme == nil || atIndex < slashAfterScheme! {
                    candidate.removeSubrange(schemeEnd...atIndex)
                }
            }
            return candidate
        }
        return trimmed
    }

    private static func sanitizedConfigOnlyString(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return ""
        }
        if trimmed.contains("://") {
            return sanitizedURLString(trimmed)
        }
        return string
    }
}
