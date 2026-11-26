#!/usr/bin/env swift
import CryptoKit
import Foundation

/// Release manifest generator & Ed25519 signer/verifier for Moa GitHub Releases.
///
/// Usage:
///   swift scripts/sign-release-manifest.swift keygen
///   swift scripts/sign-release-manifest.swift pubkey [--private-key <base64> | --keychain]
///   swift scripts/sign-release-manifest.swift sign \
///     --version 1.10.0 --build 138 \
///     --arm64 dist/Moa-1.10.0-macos-arm64.dmg \
///     --x86_64 dist/Moa-1.10.0-macos-x86_64.dmg \
///     [--private-key <base64> | --keychain] \
///     --out dist/Moa-1.10.0-release-manifest.json
///   swift scripts/sign-release-manifest.swift verify \
///     --manifest dist/Moa-1.10.0-release-manifest.json \
///     --sig dist/Moa-1.10.0-release-manifest.json.sig \
///     --public-key <base64-ed25519-public-key>

struct AssetDigest: Codable {
    let filename: String
    let sha256: String
    let size: Int64
}

struct ReleaseManifest: Codable {
    let schemaVersion: Int
    let version: String
    let build: Int
    let publishedAt: String
    let assets: [String: AssetDigest]
}

let keychainService = "com.moarliu.moa.release-manifest-signing"
let keychainAccount = "ed25519-private-key"

func fail(_ message: String) -> Never {
    fputs("sign-release-manifest: \(message)\n", stderr)
    exit(1)
}

func sha256File(_ path: String) throws -> (String, Int64) {
    let url = URL(fileURLWithPath: path)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    var total: Int64 = 0
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
        total += Int64(chunk.count)
    }
    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return (hex, total)
}

func optionValue(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

func readPrivateKeyFromKeychain() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    do {
        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    } catch {
        return nil
    }
}

func resolvePrivateKey(from args: [String]) -> Curve25519.Signing.PrivateKey {
    let rawKeyBase64: String?
    if args.contains("--keychain") {
        rawKeyBase64 = readPrivateKeyFromKeychain()
    } else {
        rawKeyBase64 = optionValue("--private-key", in: args)
            ?? ProcessInfo.processInfo.environment["MOA_MANIFEST_PRIVATE_KEY"]
    }
    guard let rawKeyBase64,
          let rawKey = Data(base64Encoded: rawKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawKey) else {
        fail("Missing or invalid --private-key / --keychain / MOA_MANIFEST_PRIVATE_KEY (base64 Ed25519 raw key)")
    }
    return key
}

let args = Array(CommandLine.arguments.dropFirst())
guard let subcommand = args.first else {
    fail("Expected subcommand: keygen | pubkey | sign | verify")
}

switch subcommand {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE_KEY_BASE64=\(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC_KEY_BASE64=\(key.publicKey.rawRepresentation.base64EncodedString())")

case "pubkey":
    let key = resolvePrivateKey(from: args)
    print("PUBLIC_KEY_BASE64=\(key.publicKey.rawRepresentation.base64EncodedString())")

case "sign":
    guard let version = optionValue("--version", in: args),
          let buildStr = optionValue("--build", in: args),
          let build = Int(buildStr),
          let outPath = optionValue("--out", in: args) else {
        fail("sign requires --version, --build, and --out")
    }
    let privateKey = resolvePrivateKey(from: args)
    var assets: [String: AssetDigest] = [:]
    for arch in ["arm64", "x86_64"] {
        if let dmgPath = optionValue("--\(arch)", in: args) {
            let (digest, size) = try sha256File(dmgPath)
            let name = URL(fileURLWithPath: dmgPath).lastPathComponent
            assets[arch] = AssetDigest(filename: name, sha256: digest, size: size)
        }
    }
    guard !assets.isEmpty else {
        fail("Provide at least one asset with --arm64 and/or --x86_64")
    }
    let manifest = ReleaseManifest(
        schemaVersion: 1,
        version: version,
        build: build,
        publishedAt: ISO8601DateFormatter().string(from: Date()),
        assets: assets
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestData = try encoder.encode(manifest)
    let signature = try privateKey.signature(for: manifestData)

    let outURL = URL(fileURLWithPath: outPath)
    let sigURL = URL(fileURLWithPath: outPath + ".sig")
    try manifestData.write(to: outURL, options: .atomic)
    try (signature.base64EncodedString() + "\n").write(to: sigURL, atomically: true, encoding: .utf8)
    print("Signed manifest: \(outURL.path)")
    print("Signature file:  \(sigURL.path)")
    print("Public key:      \(privateKey.publicKey.rawRepresentation.base64EncodedString())")

case "verify":
    guard let manifestPath = optionValue("--manifest", in: args),
          let sigPath = optionValue("--sig", in: args),
          let pubKeyBase64 = optionValue("--public-key", in: args),
          let pubKeyRaw = Data(base64Encoded: pubKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fail("verify requires --manifest, --sig, and --public-key")
    }
    let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let sigText = try String(contentsOf: URL(fileURLWithPath: sigPath), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let sigData = Data(base64Encoded: sigText) else {
        fail("Invalid base64 signature")
    }
    let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyRaw)
    guard pubKey.isValidSignature(sigData, for: manifestData) else {
        fail("Signature verification FAILED")
    }
    let decoded = try JSONDecoder().decode(ReleaseManifest.self, from: manifestData)
    if let expectedVersion = optionValue("--version", in: args), decoded.version != expectedVersion {
        fail("Manifest version mismatch: expected \(expectedVersion), got \(decoded.version)")
    }
    for arch in ["arm64", "x86_64"] {
        if let dmgPath = optionValue("--\(arch)", in: args) {
            guard let asset = decoded.assets[arch] else {
                fail("Manifest missing expected asset for architecture \(arch)")
            }
            let (digest, size) = try sha256File(dmgPath)
            let name = URL(fileURLWithPath: dmgPath).lastPathComponent
            guard asset.filename == name,
                  asset.sha256.lowercased() == digest.lowercased(),
                  asset.size == size else {
                fail("Manifest asset mismatch for \(arch): \(name)")
            }
        }
    }
    print("VERIFIED: Moa \(decoded.version) (build \(decoded.build)) with \(decoded.assets.count) asset(s)")

default:
    fail("Unknown subcommand: \(subcommand)")
}
