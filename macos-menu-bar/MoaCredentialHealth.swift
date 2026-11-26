import CryptoKit
import Foundation

enum MoaCredentialHealthSeverity: String, Codable, Equatable {
    case healthy
    case info
    case warning
    case critical
}

struct MoaCredentialHealthReport: Codable, Equatable {
    let severity: MoaCredentialHealthSeverity
    let badge: String
    let detail: String
    let expiresAt: Date?

    var needsAttention: Bool {
        severity == .warning || severity == .critical
    }

    static func healthy(_ detail: String = "") -> Self {
        Self(severity: .healthy, badge: MoaL10n.text("Healthy"), detail: detail, expiresAt: nil)
    }
}

struct MoaClientHealthSummary: Identifiable, Equatable {
    let client: MoaWorkspaceClient
    let group: MoaAccountGroup
    let accountName: String
    let report: MoaCredentialHealthReport

    var id: String { "\(client.rawValue)|\(group.rawValue)|\(accountName)|\(report.badge)" }
}

/// Strictly read-only local credential health evaluator.
/// Never sends network requests, never refreshes OAuth tokens, and never triggers Keychain UI.
enum MoaCredentialHealthInspector {
    private static let expiringSoonInterval: TimeInterval = 24 * 60 * 60

    static func inspectCodexOfficial(
        auth: [String: Any],
        now: Date = Date()
    ) -> MoaCredentialHealthReport {
        guard let tokens = auth["tokens"] as? [String: Any] else {
            return MoaCredentialHealthReport(
                severity: .critical,
                badge: MoaL10n.text("Missing Token"),
                detail: MoaL10n.text("Saved Codex login has no token payload. Sign in again and re-save."),
                expiresAt: nil
            )
        }
        let refresh = (tokens["refresh_token"] as? String ?? tokens["refreshToken"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let access = (tokens["access_token"] as? String ?? tokens["accessToken"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let idToken = (tokens["id_token"] as? String ?? tokens["idToken"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let exp = jwtExpiry(from: access) ?? jwtExpiry(from: idToken)
        if let exp {
            if exp <= now {
                if refresh.isEmpty {
                    return MoaCredentialHealthReport(
                        severity: .critical,
                        badge: MoaL10n.text("Expired"),
                        detail: MoaL10n.text("Token expired and no refresh token is present. Sign in again."),
                        expiresAt: exp
                    )
                }
                return MoaCredentialHealthReport(
                    severity: .warning,
                    badge: MoaL10n.text("Token Expired"),
                    detail: MoaL10n.text("Access token expired; Codex will attempt to refresh on next launch or require sign-in."),
                    expiresAt: exp
                )
            }
            if exp.timeIntervalSince(now) <= expiringSoonInterval {
                return MoaCredentialHealthReport(
                    severity: .warning,
                    badge: MoaL10n.text("Expiring Soon"),
                    detail: MoaL10n.format("Access token expires on %@.", formattedDate(exp)),
                    expiresAt: exp
                )
            }
            return MoaCredentialHealthReport(
                severity: .healthy,
                badge: MoaL10n.text("Healthy"),
                detail: MoaL10n.format("Token valid until %@.", formattedDate(exp)),
                expiresAt: exp
            )
        }
        if access.isEmpty && refresh.isEmpty {
            return MoaCredentialHealthReport(
                severity: .critical,
                badge: MoaL10n.text("Missing Token"),
                detail: MoaL10n.text("Saved login contains no usable token."),
                expiresAt: nil
            )
        }
        return .healthy()
    }

    static func inspectWorkBuddy(
        account: WorkBuddyAccount,
        currentKeyFingerprint: String?
    ) -> MoaCredentialHealthReport {
        if let savedFP = account.keyFingerprint {
            guard let currentKeyFingerprint else {
                return MoaCredentialHealthReport(
                    severity: .critical,
                    badge: MoaL10n.text("Key Missing"),
                    detail: MoaL10n.text("Local WorkBuddy keyblob is missing. Sign in again on this Mac."),
                    expiresAt: nil
                )
            }
            if savedFP != currentKeyFingerprint {
                return MoaCredentialHealthReport(
                    severity: .critical,
                    badge: MoaL10n.text("Key Changed"),
                    detail: MoaL10n.text("Local keyblob fingerprint changed. Re-save this account on this Mac."),
                    expiresAt: nil
                )
            }
        }
        return .healthy()
    }

    static func inspectDeepSeek(
        account: DeepSeekAccount,
        now: Date = Date()
    ) -> MoaCredentialHealthReport {
        guard let login = try? DeepSeekCredentialDocument.savedLogin(account.snapshot),
              login.fingerprint == account.fingerprint else {
            return MoaCredentialHealthReport(
                severity: .critical,
                badge: MoaL10n.text("Snapshot Invalid"),
                detail: MoaL10n.text("Saved DeepSeek credential snapshot is invalid. Save the login again."),
                expiresAt: nil
            )
        }
        // If the grant token happens to be JWT-shaped, inspect its `exp` claim passively.
        if let tokenLine = account.snapshot.components(separatedBy: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("token:") }) {
            let raw = tokenLine.split(separator: ":", maxSplits: 1).dropFirst().first.map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } ?? ""
            if let exp = jwtExpiry(from: raw) {
                if exp <= now {
                    return MoaCredentialHealthReport(
                        severity: .critical,
                        badge: MoaL10n.text("Expired"),
                        detail: MoaL10n.text("DeepSeek session token expired. Sign in again and re-save."),
                        expiresAt: exp
                    )
                }
                if exp.timeIntervalSince(now) <= expiringSoonInterval {
                    return MoaCredentialHealthReport(
                        severity: .warning,
                        badge: MoaL10n.text("Expiring Soon"),
                        detail: MoaL10n.format("Token expires on %@.", formattedDate(exp)),
                        expiresAt: exp
                    )
                }
            }
        }
        return .healthy()
    }

    static func inspectGeminiCLI(
        account: GeminiCLIAccount,
        now: Date = Date()
    ) -> MoaCredentialHealthReport {
        guard let login = try? GeminiCLILogin(
            oauthCredsData: account.oauthCredsSnapshot,
            googleAccountsData: account.googleAccountsSnapshot
        ) else {
            return MoaCredentialHealthReport(
                severity: .critical,
                badge: MoaL10n.text("Snapshot Invalid"),
                detail: MoaL10n.text("Saved Gemini CLI OAuth snapshot cannot be parsed."),
                expiresAt: nil
            )
        }
        if let exp = login.expiresAt {
            if exp <= now {
                if !login.hasRefreshToken {
                    return MoaCredentialHealthReport(
                        severity: .critical,
                        badge: MoaL10n.text("Expired"),
                        detail: MoaL10n.text("OAuth token expired with no refresh token. Sign in with `gemini` again."),
                        expiresAt: exp
                    )
                }
                return MoaCredentialHealthReport(
                    severity: .warning,
                    badge: MoaL10n.text("Token Expired"),
                    detail: MoaL10n.text("Access token expired; Gemini CLI will refresh using refresh_token on next run."),
                    expiresAt: exp
                )
            }
            if exp.timeIntervalSince(now) <= expiringSoonInterval {
                return MoaCredentialHealthReport(
                    severity: .warning,
                    badge: MoaL10n.text("Expiring Soon"),
                    detail: MoaL10n.format("Token expires on %@.", formattedDate(exp)),
                    expiresAt: exp
                )
            }
        }
        return .healthy()
    }

    static func inspectProvider(
        apiKey: String,
        baseURL: String,
        isActive: Bool,
        liveBaseURL: String? = nil
    ) -> MoaCredentialHealthReport {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MoaCredentialHealthReport(
                severity: .critical,
                badge: MoaL10n.text("Missing Key"),
                detail: MoaL10n.text("API key is empty. Edit this provider to supply a key."),
                expiresAt: nil
            )
        }
        if (try? MoaProviderBaseURLPolicy.validate(baseURL)) == nil {
            return MoaCredentialHealthReport(
                severity: .warning,
                badge: MoaL10n.text("Invalid URL"),
                detail: MoaL10n.text("Provider Base URL does not satisfy HTTPS / loopback policy."),
                expiresAt: nil
            )
        }
        if isActive, let liveBaseURL {
            let expected = (try? MoaProviderBaseURLPolicy.validate(baseURL).normalizedString) ?? baseURL
            let actual = (try? MoaProviderBaseURLPolicy.validate(liveBaseURL).normalizedString) ?? liveBaseURL
            if !actual.isEmpty && actual != expected {
                return MoaCredentialHealthReport(
                    severity: .warning,
                    badge: MoaL10n.text("Modified Externally"),
                    detail: MoaL10n.text("The client's live configuration differs from this saved provider."),
                    expiresAt: nil
                )
            }
        }
        return .healthy()
    }

    static func inspectAntigravityFallback(
        fallbackURL: URL,
        now: Date = Date()
    ) -> MoaCredentialHealthReport? {
        guard FileManager.default.fileExists(atPath: fallbackURL.path),
              (try? fallbackURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: fallbackURL),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = doc["token"] as? [String: Any] else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        let exp: Date?
        if let rawExpiry = token["expiry"] as? String {
            exp = iso.date(from: rawExpiry)
        } else if let idToken = token["id_token"] as? String {
            exp = jwtExpiry(from: idToken)
        } else {
            exp = nil
        }
        let hasRefresh = !((token["refresh_token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let exp, exp <= now {
            return MoaCredentialHealthReport(
                severity: hasRefresh ? .warning : .critical,
                badge: MoaL10n.text(hasRefresh ? "Token Expired" : "Expired"),
                detail: MoaL10n.text(hasRefresh
                    ? "Access token expired; Antigravity will refresh automatically on launch."
                    : "OAuth grant expired. Sign in to Antigravity again."),
                expiresAt: exp
            )
        }
        return .healthy()
    }

    static func keyblobFingerprint(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func jwtExpiry(from token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = (payload["exp"] as? NSNumber)?.doubleValue,
              exp.isFinite, exp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
