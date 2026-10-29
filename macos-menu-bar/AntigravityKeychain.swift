import CryptoKit
import AppKit
import Foundation
import Security

enum AntigravityError: LocalizedError {
    case message(String)
    case keychain(OSStatus)
    case recoveryRequired

    var errorDescription: String? {
        switch self {
        case .message(let key): return MoaL10n.text(key)
        case .recoveryRequired:
            return MoaL10n.text("Antigravity could not restore the previous login. Keep Antigravity and agy closed, unlock Keychain, and select the previous saved account again in Moa.")
        case .keychain(let status):
            return MoaL10n.format("Antigravity Keychain access failed (%d). Unlock the login keychain and allow Moa access, then try again.", status)
        }
    }
}

enum AntigravityCredentialItem: Hashable {
    case live
    case saved(UUID)

    var service: String {
        switch self {
        case .live: return "gemini"
        case .saved: return "com.moa.antigravity.accounts"
        }
    }
    var account: String {
        switch self {
        case .live: return "antigravity"
        case .saved(let id): return id.uuidString
        }
    }
}

protocol AntigravityCredentialStoring {
    func read(_ item: AntigravityCredentialItem, interaction: Bool) throws -> Data?
    func write(_ data: Data?, to item: AntigravityCredentialItem) throws
}

/// Uses the login keychain, matching Antigravity's go-keyring backend. Never
/// launches a shell, logs a secret, or puts credential bytes in process arguments.
final class AntigravityKeychain: AntigravityCredentialStoring {
    private func query(_ item: AntigravityCredentialItem) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: item.service,
         kSecAttrAccount as String: item.account]
    }

    func read(_ item: AntigravityCredentialItem, interaction: Bool) throws -> Data? {
        precondition(!Thread.isMainThread)
        var request = query(item)
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecReturnData as String] = true
        request[kSecUseAuthenticationUI as String] = interaction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AntigravityError.keychain(status == errSecSuccess ? errSecDecode : status)
        }
        return data
    }

    func write(_ data: Data?, to item: AntigravityCredentialItem) throws {
        precondition(!Thread.isMainThread)
        let request = query(item)
        guard let data else {
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AntigravityError.keychain(status) }
            return
        }
        // Updating in place retains the existing item's access controls.
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AntigravityError.keychain(status) }
        var addition = request
        addition[kSecValueData as String] = data
        addition[kSecAttrSynchronizable as String] = false
        if item == .live {
            // A restored missing live item must remain readable by the app,
            // its language server, /usr/bin/security, and Moa itself.
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity")
            let paths = [
                Bundle.main.executableURL?.path,
                appURL?.appendingPathComponent("Contents/MacOS/Antigravity").path,
                appURL?.appendingPathComponent("Contents/Resources/bin/language_server").path,
                "/usr/bin/security"
            ].compactMap { $0 }.filter { FileManager.default.isExecutableFile(atPath: $0) }
            var trusted: [SecTrustedApplication] = []
            for path in paths {
                var application: SecTrustedApplication?
                let status = SecTrustedApplicationCreateFromPath(path, &application)
                guard status == errSecSuccess, let application else { throw AntigravityError.keychain(status) }
                trusted.append(application)
            }
            var access: SecAccess?
            let accessStatus = SecAccessCreate("Antigravity" as CFString, trusted as CFArray, &access)
            guard accessStatus == errSecSuccess, let access else { throw AntigravityError.keychain(accessStatus) }
            addition[kSecAttrAccess as String] = access
        }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AntigravityError.keychain(addStatus) }
    }
}

struct AntigravityLogin {
    let data: Data
    let fileData: Data
    let identity: String
    let email: String

    init(_ data: Data) throws {
        func invalid() -> AntigravityError {
            .message("Antigravity login format is unsupported or incomplete. Sign in with a personal Google account and save it again.")
        }
        guard !data.isEmpty, data.count <= 1_048_576 else { throw invalid() }
        var decoded = data
        if let text = String(data: data, encoding: .utf8) {
            if text.hasPrefix("go-keyring-base64:") {
                guard let value = Data(base64Encoded: String(text.dropFirst("go-keyring-base64:".count))) else { throw invalid() }
                decoded = value
            } else if text.hasPrefix("go-keyring-encoded:") {
                let hex = String(text.dropFirst("go-keyring-encoded:".count))
                guard hex.count.isMultiple(of: 2), hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw invalid() }
                var value = Data()
                var index = hex.startIndex
                while index < hex.endIndex {
                    let next = hex.index(index, offsetBy: 2)
                    guard let byte = UInt8(hex[index..<next], radix: 16) else { throw invalid() }
                    value.append(byte)
                    index = next
                }
                decoded = value
            }
        }
        guard let document = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let token = document["token"] as? [String: Any],
              let refresh = token["refresh_token"] as? String, !refresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let access = token["access_token"] as? String, !access.isEmpty,
              (token["token_type"] as? String ?? "Bearer").caseInsensitiveCompare("Bearer") == .orderedSame else { throw invalid() }
        self.data = data // Preserve the exact envelope, including unknown fields.
        fileData = decoded
        var claims: [String: Any] = [:]
        if let jwt = token["id_token"] as? String {
            let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count == 3 {
                var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
                if let payload = Data(base64Encoded: base64),
                   let parsed = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                   let issuer = parsed["iss"] as? String, ["accounts.google.com", "https://accounts.google.com"].contains(issuer) {
                    claims = parsed
                }
            }
        }
        // Claims are local labels, not a substitute for Google's authentication.
        let subject = (claims["sub"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let claimedEmail = ((claims["email"] as? String) ?? (document["id_token_email"] as? String))
            .flatMap { $0.contains("@") ? $0.lowercased() : nil }
        let value = !subject.isEmpty ? "google:\(subject)" : (claimedEmail.map { "google-email:\($0)" } ?? "grant:\(refresh)")
        identity = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        email = claimedEmail ?? ""
    }
}
