#if !MOA_TESTING
import Darwin
import Foundation
import XCTest
@testable import Moa

final class MoaMaintenance162RegressionTests: XCTestCase {
    private let fm = FileManager.default

    private func withHome(_ body: (URL, ConfigProfileController) throws -> Void) throws {
        let home = fm.temporaryDirectory.appendingPathComponent("moa-162-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try body(home, ConfigProfileController(environment: ["HOME": home.path]))
    }

    private func mode(_ url: URL) throws -> Int {
        try XCTUnwrap(fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue & 0o7777
    }

    private func client(running: Bool = true) -> CodexAppController {
        let client = CodexAppController()
        client.testingIsRunning = { running }
        client.testingQuit = {}
        client.testingOpen = { XCTFail("Unexpected client launch") }
        return client
    }

    func testFailedTransactionReopensOnlyAfterRestoringClientFiles() throws {
        try withHome { home, store in
            let file = home.appendingPathComponent("fixture.json")
            try Data("before".utf8).write(to: file)
            let client = client()
            var reopened = false
            client.testingOpen = {
                XCTAssertEqual(try Data(contentsOf: file), Data("before".utf8))
                reopened = true
            }
            XCTAssertThrowsError(try client.changeConfiguration {
                try store.withCodexStateTransaction(files: [file]) {
                    try MoaSecureFile.write(Data("partial".utf8), to: file)
                    throw CocoaError(.fileWriteOutOfSpace)
                }
            }) { error in
                XCTAssertTrue(error.localizedDescription.contains("reopened with its previous configuration"))
            }
            XCTAssertTrue(reopened)
        }
    }

    func testFailedRollbackLeavesClientClosedAndReportsRecoveryFailure() throws {
        try withHome { home, store in
            let file = home.appendingPathComponent("fixture.json")
            try Data("before".utf8).write(to: file)
            let client = client()
            XCTAssertThrowsError(try client.changeConfiguration {
                try store.withCodexStateTransaction(files: [file]) {
                    try fm.removeItem(at: file)
                    try fm.createDirectory(at: file, withIntermediateDirectories: true)
                    throw CocoaError(.fileWriteOutOfSpace)
                }
            }) { error in
                XCTAssertTrue(error.localizedDescription.contains("not reopened"))
                XCTAssertTrue(error.localizedDescription.contains("rollback also failed"))
            }
        }
    }

    func testUnknownMutationFailureDoesNotReopenUnverifiedConfiguration() {
        let client = client()
        XCTAssertThrowsError(try client.changeConfiguration { throw CocoaError(.fileWriteNoPermission) }) {
            XCTAssertTrue($0.localizedDescription.contains("not reopened"))
        }
    }

    func testOuterDatabaseRollbackCannotHideInnerClientRollbackFailure() throws {
        try withHome { home, store in
            let file = home.appendingPathComponent("client.json")
            try Data("before".utf8).write(to: file)
            let client = client()
            XCTAssertThrowsError(try client.changeConfiguration {
                try store.withCodexStateTransaction(files: [store.databaseURL]) {
                    try store.withCodexStateTransaction(files: [file]) {
                        try fm.removeItem(at: file)
                        try fm.createDirectory(at: file, withIntermediateDirectories: true)
                        throw CocoaError(.fileWriteOutOfSpace)
                    }
                }
            }) { error in
                XCTAssertTrue(error.localizedDescription.contains("not reopened"))
                XCTAssertTrue(error.localizedDescription.contains("rollback also failed"))
            }
        }
    }

    func testRestoredFailureDoesNotOpenPreviouslyClosedClient() {
        let client = client(running: false)
        XCTAssertThrowsError(try client.changeConfiguration {
            throw CodexStateTransactionError.restored(CocoaError(.fileWriteNoPermission))
        })
    }

    func testBusyStoreRestartsPreviouslyRunningClientWithoutReportingSuccess() {
        let client = client()
        var reopened = false
        client.testingOpen = { reopened = true }
        XCTAssertThrowsError(try client.changeConfiguration { throw MoaDataAccessError.busy })
        XCTAssertTrue(reopened)
    }

    func testRecoveryLaunchFailureRetainsBothErrors() {
        let client = client()
        client.testingOpen = { throw NSError(domain: "Fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "launch-fixture"]) }
        XCTAssertThrowsError(try client.changeConfiguration {
            throw CodexStateTransactionError.restored(NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "write-fixture"]))
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("write-fixture"))
            XCTAssertTrue(error.localizedDescription.contains("launch-fixture"))
        }
    }

    func testSecureWritesSupportDirectoryLinksWithoutChangingSharedPermissions() throws {
        try withHome { home, _ in
            let directory = home.appendingPathComponent("shared")
            let link = home.appendingPathComponent("linked")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o750])
            try fm.createSymbolicLink(at: link, withDestinationURL: directory)
            try MoaSecureFile.write(Data("private".utf8), to: link.appendingPathComponent("profiles.json"))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("profiles.json")), Data("private".utf8))
            XCTAssertEqual(try mode(directory), 0o750)
            XCTAssertEqual(try mode(directory.appendingPathComponent("profiles.json")), 0o600)
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), directory.path)
        }
    }

    func testReplacingParentLinkAfterOpenCannotRedirectSensitiveWrite() throws {
        try withHome { home, _ in
            let original = home.appendingPathComponent("original")
            let other = home.appendingPathComponent("other")
            let link = home.appendingPathComponent("link")
            for directory in [original, other] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
            try Data("unchanged".utf8).write(to: other.appendingPathComponent("auth.json"))
            try fm.createSymbolicLink(at: link, withDestinationURL: original)
            MoaSecureFile.testingAfterOpeningDirectory = {
                try self.fm.removeItem(at: link)
                try self.fm.createSymbolicLink(at: link, withDestinationURL: other)
            }
            defer { MoaSecureFile.testingAfterOpeningDirectory = nil }
            try MoaSecureFile.write(Data("private".utf8), to: link.appendingPathComponent("auth.json"))
            XCTAssertEqual(try String(contentsOf: original.appendingPathComponent("auth.json")), "private")
            XCTAssertEqual(try String(contentsOf: other.appendingPathComponent("auth.json")), "unchanged")
            XCTAssertFalse(try fm.contentsOfDirectory(atPath: original.path).contains { $0.hasPrefix(".moa-private-") })
        }
    }

    func testSwitchAndRollbackWorkWithLinkedMoaAndCodexDirectories() throws {
        try withHome { home, _ in
            for name in [".moa", ".codex"] {
                let url = home.appendingPathComponent(name)
                let real = home.appendingPathComponent("real-\(name)")
                try fm.moveItem(at: url, to: real)
                try fm.createSymbolicLink(at: url, withDestinationURL: real)
            }
            let store = ConfigProfileController(environment: ["HOME": home.path])
            let profile = try store.addProfile(name: "Fixture", baseURL: "https://fixture.invalid/v1", apiKey: "synthetic")
            try store.applyProfile(id: profile.id)
            let urls = [store.codexConfigURL, store.codexAuthURL, store.databaseURL]
            let before = try urls.map { try Data(contentsOf: $0) }
            ConfigProfileController.testingProfileDatabaseSaveFailuresRemaining = 1
            defer { ConfigProfileController.testingProfileDatabaseSaveFailuresRemaining = 0 }
            XCTAssertThrowsError(try store.applyProfile(id: profile.id)) { error in
                guard case CodexStateTransactionError.restored = error else { return XCTFail("Expected successful rollback: \(error)") }
            }
            XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, before)
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".moa").path), home.appendingPathComponent("real-.moa").path)
        }
    }

    private func auth(_ token: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": [
            "account_id": "fixture-account", "email": "fixture@example.invalid", "refresh_token": token
        ]])
    }

    func testSavingNewAndExistingCurrentLoginNeverRewritesRefreshedClientAuth() throws {
        try withHome { _, store in
            let original = try auth("synthetic-original")
            let rotated = try auth("synthetic-rotated")
            try original.write(to: store.codexAuthURL)
            store.testingAfterCurrentOfficialAuthRead = { try rotated.write(to: store.codexAuthURL) }
            let account = try store.addOfficialAccountFromCurrentLogin(name: "Fixture")
            XCTAssertEqual(try Data(contentsOf: store.codexAuthURL), rotated)
            XCTAssertEqual(try store.selectedOfficialAccountID(), account.id)

            let next = try auth("synthetic-next")
            store.testingAfterCurrentOfficialAuthRead = { try next.write(to: store.codexAuthURL) }
            XCTAssertEqual(try store.saveCurrentOfficialLoginAsSelectedAccount().id, account.id)
            XCTAssertEqual(try Data(contentsOf: store.codexAuthURL), next)
        }
    }

    func testFailedSnapshotSaveDoesNotRollBackConcurrentClientRefresh() throws {
        try withHome { _, store in
            try auth("synthetic-original").write(to: store.codexAuthURL)
            let rotated = try auth("synthetic-rotated")
            store.testingBeforeOfficialAccountDatabaseSave = { try rotated.write(to: store.codexAuthURL) }
            ConfigProfileController.testingOfficialAccountDatabaseSaveFailuresRemaining = 1
            defer { ConfigProfileController.testingOfficialAccountDatabaseSaveFailuresRemaining = 0 }
            XCTAssertThrowsError(try store.addOfficialAccountFromCurrentLogin(name: "Fixture"))
            XCTAssertEqual(try Data(contentsOf: store.codexAuthURL), rotated)
            XCTAssertTrue(try store.loadOfficialAccountDatabase().accounts.isEmpty)
        }
    }

    func testCRLFAtExactLimitAndAcrossChunkBoundaryIsNotTruncated() throws {
        try withHome { home, _ in
            for limit in [4, 64 * 1024 - 1, 64 * 1024] {
                let url = home.appendingPathComponent("lines.jsonl")
                let full = Data(repeating: 120, count: limit)
                var data = full
                data.append(Data("\r\nnext\n".utf8))
                try data.write(to: url)
                var lines: [(Data, Bool)] = []
                try MoaJSONLReader.scan(fileURL: url, maximumLineBytes: limit) { lines.append(($0, $1)) }
                XCTAssertEqual(lines.map(\.0), [full, Data("next".utf8)])
                XCTAssertEqual(lines.map(\.1), [false, false])
            }
        }
    }

    func testRecoveryPruningContinuesPastAnImmutableOldPackage() throws {
        try withHome { _, store in
            let recovery = MoaDataPackageController(environment: store.environment)
            try MoaSecureFile.ensurePrivateDirectory(recovery.recoveryDirectory)
            var packages: [URL] = []
            for index in 0..<15 {
                let url = recovery.recoveryDirectory.appendingPathComponent("Moa-Data-Rollback-fixture-\(index).zip")
                try Data("fixture".utf8).write(to: url)
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: url.path)
                packages.append(url)
            }
            let immutable = packages[0]
            guard chflags(immutable.path, UInt32(UF_IMMUTABLE)) == 0 else { throw XCTSkip("Filesystem does not support user immutable flags") }
            defer { _ = chflags(immutable.path, 0) }
            XCTAssertThrowsError(try recovery.pruneRecoveryPackages())
            XCTAssertTrue(fm.fileExists(atPath: immutable.path))
            XCTAssertFalse(fm.fileExists(atPath: packages[1].path))
            XCTAssertFalse(fm.fileExists(atPath: packages[2].path))
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: recovery.recoveryDirectory.path).count, 13)
        }
    }
}
#endif
