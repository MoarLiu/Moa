#if !MOA_TESTING
import Foundation
import Security
import XCTest
@testable import Moa

final class AntigravityTests: XCTestCase {
    private final class Store: AntigravityCredentialStoring {
        var values: [AntigravityCredentialItem: Data] = [:]
        var reads: [(AntigravityCredentialItem, Bool)] = []
        var writes: [AntigravityCredentialItem] = []
        var onRead: ((AntigravityCredentialItem) throws -> Void)?
        var onWrite: ((AntigravityCredentialItem) throws -> Void)?
        func read(_ item: AntigravityCredentialItem, interaction: Bool) throws -> Data? {
            reads.append((item, interaction))
            try onRead?(item)
            return values[item]
        }
        func write(_ data: Data?, to item: AntigravityCredentialItem) throws {
            try onWrite?(item)
            writes.append(item)
            values[item] = data
        }
    }
    private final class Runtime: AntigravityAppManaging {
        var isRunning = true
        var otherClient = false
        var refuseQuit = false
        var straggler = false
        var events: [String] = []
        var onQuit: (() throws -> Void)?
        var onLaunch: (() throws -> Void)?
        func validateInstallation() throws {}
        func ensureNoOtherClients() throws {
            if otherClient { throw AntigravityError.message("shared-client") }
        }
        func ensureStopped() throws {
            if isRunning || otherClient || straggler { throw AntigravityError.message("still-running") }
        }
        func quit() throws {
            events.append("quit")
            if refuseQuit { throw AntigravityError.message("refused-quit") }
            try onQuit?()
            isRunning = false
        }
        func launch() throws {
            events.append("launch")
            try onLaunch?()
            isRunning = true
        }
    }

    private func fixture(_ body: (URL, AntigravityController, Store, Runtime) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-antigravity-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = Store()
        let runtime = Runtime()
        let controller = AntigravityController(environment: ["HOME": home.path], store: store, runtime: runtime)
        store.values[.live] = try credential("a")
        try body(home, controller, store, runtime)
    }

    private func credential(_ subject: String?, refresh: String = "synthetic-refresh", access: String = "synthetic-access", wrapper: Bool = true) throws -> Data {
        var token: [String: Any] = ["refresh_token": refresh, "access_token": access, "token_type": "Bearer", "expiry": "2026-01-01T00:00:00Z"]
        if let subject {
            let claims = try JSONSerialization.data(withJSONObject: ["iss": "https://accounts.google.com", "sub": subject, "email": "\(subject)@example.invalid"])
            let jwt = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            token["id_token"] = "synthetic.\(jwt).signature"
        }
        let data = try JSONSerialization.data(withJSONObject: ["token": token, "future": ["retain": true]], options: [.sortedKeys])
        return wrapper ? Data(("go-keyring-base64:" + data.base64EncodedString()).utf8) : data
    }

    func testEnvelopePreservesUnknownFieldsAndStableGoogleIdentity() throws {
        let raw = try credential("a")
        let login = try AntigravityLogin(raw)
        XCTAssertEqual(login.data, raw)
        XCTAssertEqual(login.email, "a@example.invalid")
        XCTAssertEqual(login.identity, try AntigravityLogin(credential("a", refresh: "rotated", access: "new")).identity)
        XCTAssertNotEqual(login.identity, try AntigravityLogin(credential("b")).identity)
        let plain = try credential("a", wrapper: false)
        let hex = Data(("go-keyring-encoded:" + plain.map { String(format: "%02x", $0) }.joined()).utf8)
        XCTAssertEqual(try AntigravityLogin(hex).identity, login.identity)
        XCTAssertEqual(try AntigravityLogin(hex).data, hex)
    }

    func testOpaqueAccessTokensUseGrantIdentityInsteadOfWholeBlob() throws {
        let first = try AntigravityLogin(credential(nil, access: "one"))
        XCTAssertEqual(first.identity, try AntigravityLogin(credential(nil, access: "two")).identity)
        XCTAssertNotEqual(first.identity, try AntigravityLogin(credential(nil, refresh: "another-grant")).identity)
        XCTAssertEqual(first.email, "")
    }

    func testFileEmailClaimKeepsIdentityStableWhenRefreshesRotate() throws {
        func file(_ refresh: String) throws -> Data {
            let token: [String: Any] = ["refresh_token": refresh, "access_token": "access", "token_type": "Bearer", "expiry": "2026-01-01T00:00:00Z"]
            return try JSONSerialization.data(withJSONObject: ["token": token, "id_token_email": "Stable@Example.invalid"])
        }
        XCTAssertEqual(try AntigravityLogin(file("one")).identity, try AntigravityLogin(file("two")).identity)
        XCTAssertEqual(try AntigravityLogin(file("one")).email, "stable@example.invalid")
    }

    func testUnsupportedCredentialsFailWithoutDisclosingTokens() throws {
        for data in [Data(), Data("synthetic-secret-never-in-error".utf8), Data("go-keyring-base64:invalid".utf8), Data("go-keyring-encoded:XX".utf8), Data(#"{"token":{"refresh_token":"synthetic-secret-never-in-error"}}"#.utf8)] {
            XCTAssertThrowsError(try AntigravityLogin(data)) { error in
                XCTAssertFalse(error.localizedDescription.contains("synthetic-secret"))
            }
        }
    }

    func testSaveCapturesAfterQuitAndKeepsOnlyMetadataOnDisk() throws {
        try fixture { _, controller, store, runtime in
            let latest = try credential("a", refresh: "latest-refresh")
            runtime.onQuit = { store.values[.live] = latest }
            let saved = try controller.saveCurrent(name: " A ")
            XCTAssertEqual(saved.name, "A")
            XCTAssertEqual(store.values[.saved(saved.id)], latest)
            XCTAssertEqual(runtime.events, ["quit", "launch"])
            let metadata = try Data(contentsOf: controller.storageURL)
            XCTAssertNil(metadata.range(of: Data("latest-refresh".utf8)))
            XCTAssertNil(metadata.range(of: latest))
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: controller.storageURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: controller.storageURL.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            runtime.onQuit = nil
            let again = try controller.saveCurrent(name: "Renamed")
            XCTAssertEqual(again.id, saved.id)
            XCTAssertEqual(try controller.accounts().count, 1)
        }
    }

    func testEnrollmentAndAToBToAPreserveExactCredentials() throws {
        try fixture { _, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            try controller.prepareNewLogin()
            XCTAssertNil(store.values[.live])
            let bBytes = try credential("b", refresh: "refresh-b")
            store.values[.live] = bBytes
            let b = try controller.saveCurrent(name: "B")
            _ = try controller.apply(id: a.id)
            XCTAssertEqual(try controller.overview().currentID, a.id)
            _ = try controller.apply(id: b.id)
            XCTAssertEqual(store.values[.live], bBytes)
            XCTAssertEqual(try controller.accounts().count, 2)
            let latest = try credential("b", refresh: "b-rotated")
            store.values[.live] = latest
            _ = try controller.apply(id: b.id)
            XCTAssertEqual(store.values[.live], latest, "Selecting the current account must not restore its older token")
            XCTAssertEqual(store.values[.saved(b.id)], latest)
        }
    }

    func testUnknownOutgoingAccountIsSavedBeforeSwitch() throws {
        try fixture { _, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            let outgoing = try credential("external", refresh: "external-refresh")
            store.values[.live] = outgoing
            _ = try controller.apply(id: a.id)
            let accounts = try controller.accounts()
            let external = try XCTUnwrap(accounts.first { $0.id != a.id })
            XCTAssertEqual(store.values[.saved(external.id)], outgoing)
        }
    }

    func testLaunchFailureRestoresPreviousLoginAndPreservesRefreshedTarget() throws {
        try fixture { _, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            store.values[.live] = try credential("b")
            let b = try controller.saveCurrent(name: "B")
            _ = try controller.apply(id: a.id)
            let original = store.values[.live]
            let refreshed = try credential("b", refresh: "b-refreshed-during-launch")
            runtime.onLaunch = {
                runtime.onLaunch = nil
                runtime.isRunning = true
                store.values[.live] = refreshed
                throw AntigravityError.message("launch-failed")
            }
            XCTAssertThrowsError(try controller.apply(id: b.id))
            XCTAssertEqual(store.values[.live], original)
            XCTAssertEqual(store.values[.saved(b.id)], refreshed)
            runtime.onLaunch = {
                runtime.onLaunch = nil
                throw AntigravityError.message("launch-failed")
            }
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertEqual(store.values[.live], original)
        }
    }

    func testRollbackFailureKeepsClientClosedAndReportsRecovery() throws {
        try fixture { _, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            store.values[.live] = try credential("b")
            runtime.onLaunch = {
                runtime.onLaunch = nil
                store.onWrite = { if $0 == .live { throw AntigravityError.keychain(errSecAuthFailed) } }
                throw AntigravityError.message("launch-failed")
            }
            XCTAssertThrowsError(try controller.apply(id: a.id)) { error in
                XCTAssertTrue(error.localizedDescription.contains("previous login"))
            }
            XCTAssertFalse(runtime.isRunning)
            XCTAssertNotNil(store.values[.saved(a.id)])
        }
    }

    func testRefusedQuitSharedClientsAndStragglersPreventCredentialWrites() throws {
        try fixture { _, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            let before = store.values
            store.writes = []
            runtime.refuseQuit = true
            XCTAssertThrowsError(try controller.prepareNewLogin())
            runtime.refuseQuit = false
            runtime.otherClient = true
            runtime.events = []
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertTrue(runtime.events.isEmpty)
            runtime.otherClient = false
            runtime.straggler = true
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertTrue(store.writes.isEmpty)
            XCTAssertEqual(store.values, before)
        }
    }

    func testConcurrentCredentialChangeIsNotOverwritten() throws {
        try fixture { _, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            store.values[.live] = try credential("b")
            let external = try credential("c")
            var reads = 0
            store.onRead = { item in
                if item == .live {
                    reads += 1
                    if reads == 2 { store.values[.live] = external }
                }
            }
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertEqual(store.values[.live], external)
        }
    }

    func testPassiveReadsNeverAllowPromptsAndKeychainCancellationLeavesLogin() throws {
        try fixture { _, controller, store, runtime in
            _ = try controller.saveCurrent(name: "A")
            store.reads = []
            store.onRead = { _ in throw AntigravityError.keychain(errSecInteractionNotAllowed) }
            let overview = try controller.overview()
            XCTAssertEqual(overview.accounts.count, 1)
            XCTAssertNil(overview.currentID)
            XCTAssertNotNil(overview.message)
            XCTAssertTrue(store.reads.allSatisfy { !$0.1 })
            store.writes = []
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertTrue(store.writes.isEmpty)
            XCTAssertTrue(runtime.isRunning)
        }
    }

    func testRenameAndForgetOnlyChangeSavedCopy() throws {
        try fixture { _, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            let live = store.values[.live]
            try controller.rename(id: a.id, name: "New name")
            XCTAssertEqual(try controller.accounts().first?.name, "New name")
            try controller.delete(id: a.id)
            XCTAssertTrue(try controller.accounts().isEmpty)
            XCTAssertNil(store.values[.saved(a.id)])
            XCTAssertEqual(store.values[.live], live)
        }
    }

    func testCorruptMetadataAndMismatchedSavedLoginFailBeforeQuit() throws {
        try fixture { _, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            store.values[.saved(a.id)] = try credential("someone-else")
            runtime.events = []
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertTrue(runtime.events.isEmpty)
            try Data("corrupt-metadata".utf8).write(to: controller.storageURL)
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertTrue(runtime.events.isEmpty)
        }
    }

    func testMetadataSymlinksAndOtherMoaInstanceAreRejected() throws {
        try fixture { home, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            let other = AntigravityController(environment: ["HOME": home.path], store: store, runtime: runtime)
            runtime.onQuit = { XCTAssertThrowsError(try other.delete(id: a.id)) }
            _ = try controller.saveCurrent(name: "A")
            runtime.onQuit = nil
            let outside = home.appendingPathComponent("untouched")
            try Data("untouched".utf8).write(to: outside)
            try FileManager.default.removeItem(at: controller.storageURL)
            try FileManager.default.createSymbolicLink(at: controller.storageURL, withDestinationURL: outside)
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertEqual(try String(contentsOf: outside), "untouched")
        }
    }

    func testProcessClassificationIncludesCliAndExtensionBackends() {
        for path in ["/Users/test/.local/bin/agy", "/opt/homebrew/bin/antigravity", "/Applications/Antigravity IDE.app/Contents/MacOS/Electron", "/Users/test/.vscode/extensions/google.antigravity/bin/language_server_macos_arm", "/Users/test/.gemini/bin/language_server"] {
            XCTAssertTrue(AntigravityAppManager.isSharedClient(executable: path), path)
        }
        for path in ["/Applications/Codex.app/Contents/MacOS/Codex", "/usr/bin/security", "/usr/local/bin/gemini", "/Applications/Other.app/Contents/Resources/language_server"] {
            XCTAssertFalse(AntigravityAppManager.isSharedClient(executable: path), path)
        }
    }

    func testMetadataFailurePreventsLiveSwitchAndDeleteRestoresSavedSecret() throws {
        try fixture { _, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            let oldMetadata = try Data(contentsOf: controller.storageURL)
            let oldSecret = store.values[.saved(a.id)]
            store.values[.live] = try credential("b")
            let live = store.values[.live]
            store.onWrite = { item in
                if case .saved = item {
                    try FileManager.default.removeItem(at: controller.storageURL)
                    try FileManager.default.createDirectory(at: controller.storageURL, withIntermediateDirectories: false)
                    store.onWrite = nil
                }
            }
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertEqual(store.values[.live], live)
            try FileManager.default.removeItem(at: controller.storageURL)
            try oldMetadata.write(to: controller.storageURL)
            store.onWrite = { item in
                if item == .saved(a.id) {
                    try FileManager.default.removeItem(at: controller.storageURL)
                    try FileManager.default.createDirectory(at: controller.storageURL, withIntermediateDirectories: false)
                    store.onWrite = nil
                }
            }
            XCTAssertThrowsError(try controller.delete(id: a.id))
            XCTAssertEqual(store.values[.saved(a.id)], oldSecret)
            XCTAssertEqual(store.values[.live], live)
        }
    }

    func testMetadataStaysOutsideDataPackagesDiagnosticsAndICloudMoves() throws {
        try fixture { home, controller, store, runtime in
            _ = try controller.saveCurrent(name: "private-antigravity-name")
            let environment = ["HOME": home.path]
            let packages = MoaDataPackageController(environment: environment)
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: root.appendingPathComponent("profiles.json"))
            let archive = home.appendingPathComponent("data.zip")
            let diagnostics = home.appendingPathComponent("diagnostics.zip")
            _ = try packages.exportDataPackage(to: archive)
            _ = try packages.exportDiagnosticPackage(to: diagnostics)
            for (index, zip) in [archive, diagnostics].enumerated() {
                let destination = home.appendingPathComponent("extracted-\(index)")
                XCTAssertEqual(MoaProcessRunner.run("/usr/bin/ditto", ["-x", "-k", zip.path, destination.path]), 0)
                for case let file as URL in FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil)! {
                    if !file.hasDirectoryPath, let data = try? Data(contentsOf: file) {
                        XCTAssertFalse(file.path.contains("antigravity-accounts"))
                        XCTAssertNil(data.range(of: Data("private-antigravity-name".utf8)))
                    }
                }
            }
            try FileManager.default.createDirectory(at: MoaDataRoot.iCloudDriveRoot(environment: environment), withIntermediateDirectories: true)
            _ = try packages.enableICloudStorage()
            let after = AntigravityController(environment: environment, store: store, runtime: runtime)
            XCTAssertEqual(after.storageURL, controller.storageURL)
            XCTAssertEqual(try after.accounts().count, 1)
            _ = try packages.disableICloudStorage()
        }
    }

    private func writeFallback(_ data: Data, controller: AntigravityController) throws {
        try FileManager.default.createDirectory(at: controller.fallbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: controller.fallbackURL)
    }

    func testFileOnlyLoginIsSavedAndEnrollmentClearsBothSources() throws {
        try fixture { _, controller, store, _ in
            store.values[.live] = nil
            let file = try credential("file-account", wrapper: false)
            try writeFallback(file, controller: controller)
            let account = try controller.saveCurrent(name: "File account")
            XCTAssertEqual(store.values[.saved(account.id)], file)
            XCTAssertNil(store.values[.live], "Saving must not rewrite the live credential")
            try controller.prepareNewLogin()
            XCTAssertNil(store.values[.live])
            XCTAssertFalse(FileManager.default.fileExists(atPath: controller.fallbackURL.path))
            _ = try controller.apply(id: account.id)
            XCTAssertEqual(store.values[.live], file)
            XCTAssertEqual(try Data(contentsOf: controller.fallbackURL), file)
        }
    }

    func testDifferentFallbackIsPreservedAndBothSourcesRollBackExactly() throws {
        try fixture { _, controller, store, runtime in
            let oldFile = try credential("historical", wrapper: false)
            try writeFallback(oldFile, controller: controller)
            let a = try controller.saveCurrent(name: "A")
            let historical = try XCTUnwrap(controller.accounts().first { $0.id != a.id })
            XCTAssertEqual(store.values[.saved(historical.id)], oldFile)
            let oldKeychain = store.values[.live]
            runtime.onLaunch = {
                runtime.onLaunch = nil
                throw AntigravityError.message("launch-failed")
            }
            XCTAssertThrowsError(try controller.apply(id: historical.id))
            XCTAssertEqual(store.values[.live], oldKeychain)
            XCTAssertEqual(try Data(contentsOf: controller.fallbackURL), oldFile)
            _ = try controller.apply(id: historical.id)
            XCTAssertEqual(try AntigravityLogin(Data(contentsOf: controller.fallbackURL)).identity, historical.identity)
        }
    }

    func testFailedKeychainWriteRestoresFallbackBeforeReopening() throws {
        try fixture { _, controller, store, runtime in
            let a = try controller.saveCurrent(name: "A")
            store.values[.live] = try credential("b")
            let file = try credential("b", wrapper: false)
            try writeFallback(file, controller: controller)
            let keychain = store.values[.live]
            store.onWrite = { item in
                if item == .live {
                    store.onWrite = nil
                    throw AntigravityError.keychain(errSecUserCanceled)
                }
            }
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertEqual(store.values[.live], keychain)
            XCTAssertEqual(try Data(contentsOf: controller.fallbackURL), file)
            XCTAssertTrue(runtime.isRunning)
        }
    }

    func testFallbackSymlinksAndConcurrentChangesPreventReplacement() throws {
        try fixture { home, controller, store, _ in
            let a = try controller.saveCurrent(name: "A")
            let file = try credential("b", wrapper: false)
            let external = try credential("c", wrapper: false)
            try writeFallback(file, controller: controller)
            var reads = 0
            store.onRead = { item in
                if item == .live {
                    reads += 1
                    if reads == 2 { try external.write(to: controller.fallbackURL) }
                }
            }
            XCTAssertThrowsError(try controller.apply(id: a.id))
            XCTAssertEqual(try Data(contentsOf: controller.fallbackURL), external)
            store.onRead = nil
            let outside = home.appendingPathComponent("unmodified-token")
            try file.write(to: outside)
            try FileManager.default.removeItem(at: controller.fallbackURL)
            try FileManager.default.createSymbolicLink(at: controller.fallbackURL, withDestinationURL: outside)
            XCTAssertThrowsError(try controller.prepareNewLogin())
            XCTAssertEqual(try Data(contentsOf: outside), file)
        }
    }
}
#endif
