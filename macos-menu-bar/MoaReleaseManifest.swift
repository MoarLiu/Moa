import CryptoKit
import Foundation

/// Signed release manifest verified with an Ed25519 public key before installing updates.
struct MoaSignedReleaseManifest: Codable, Equatable {
    struct AssetDigest: Codable, Equatable {
        var filename: String
        var sha256: String
        var size: Int64
    }

    var schemaVersion: Int
    var version: String
    var build: Int
    var publishedAt: String
    var assets: [String: AssetDigest]
}

enum MoaReleaseManifestVerifier {
    static let publicKeyInfoPlistKey = "MoaReleaseManifestPublicKey"

    static func bundledPublicKeyData(bundle: Bundle = .main) -> Data? {
        guard let raw = bundle.object(forInfoDictionaryKey: publicKeyInfoPlistKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed), data.count == 32 else {
            return nil
        }
        return data
    }

    static func sign(manifestData: Data, privateKeyRaw: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
        return try key.signature(for: manifestData)
    }

    /// Verifies the Ed25519 detached signature over `manifestData`, decodes the manifest,
    /// and validates version, architecture asset entry, and DMG SHA-256 digest.
    static func verify(
        manifestData: Data,
        signatureBase64OrRaw: Data,
        publicKeyRaw: Data,
        expectedVersion: String,
        expectedArchitecture: String,
        expectedDMGFilename: String,
        actualDMGSHA256: String
    ) throws -> MoaSignedReleaseManifest {
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw)
        } catch {
            throw MoaUpdateError.invalidManifestSignature
        }

        let signatureData: Data
        if signatureBase64OrRaw.count == 64 {
            signatureData = signatureBase64OrRaw
        } else if let text = String(data: signatureBase64OrRaw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
                  let decoded = Data(base64Encoded: text),
                  decoded.count == 64 {
            signatureData = decoded
        } else {
            throw MoaUpdateError.invalidManifestSignature
        }

        guard publicKey.isValidSignature(signatureData, for: manifestData) else {
            throw MoaUpdateError.invalidManifestSignature
        }

        let manifest: MoaSignedReleaseManifest
        do {
            manifest = try JSONDecoder().decode(MoaSignedReleaseManifest.self, from: manifestData)
        } catch {
            throw MoaUpdateError.invalidManifestSignature
        }

        guard manifest.schemaVersion == 1,
              manifest.version == expectedVersion,
              let asset = manifest.assets[expectedArchitecture],
              asset.filename == expectedDMGFilename,
              asset.sha256.lowercased() == actualDMGSHA256.lowercased() else {
            throw MoaUpdateError.manifestDigestMismatch
        }
        return manifest
    }
}
