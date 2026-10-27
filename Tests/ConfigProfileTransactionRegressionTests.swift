#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class ConfigProfileTransactionRegressionTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-transaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func controller(in home: URL) -> ConfigProfileController {
        ConfigProfileController(environment: ["HOME": home.path, "CODEX_HOME": home.appendingPathComponent(".codex").path])
    }

    func testFailedLiveEditRestoresProfileAndClientFiles() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = controller(in: home)
        let profile = try controller.addProfile(name: "Before", baseURL: "https://before.example/v1", apiKey: "before")
        try controller.applyProfile(id: profile.id)
        let urls = [controller.databaseURL, controller.moaConfigURL, controller.codexConfigURL, controller.moaAuthURL, controller.codexAuthURL]
        let before = try urls.map { try Data(contentsOf: $0) }

        try FileManager.default.removeItem(at: controller.backupDir)
        try Data("block backup directory".utf8).write(to: controller.backupDir)
        XCTAssertThrowsError(try controller.updateProfileApplyingIfSelected(
            id: profile.id, name: "After", baseURL: "https://after.example/v1", apiKey: "after", applyToCurrent: true
        ))
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, before)
        XCTAssertEqual(try controller.selectedProfile(), profile)
    }

    func testOfficialAccountDeletionReportsInaccessibleCredential() throws {
        guard geteuid() != 0 else { throw XCTSkip("Directory permissions do not restrict root") }
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = controller(in: home)
        let account = try controller.saveNewOfficialAccount(auth: ["tokens": ["access_token": "test-token"]], name: "Saved", activate: false)
        let credential = try controller.officialAuthURL(for: account)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: controller.officialAuthAccountsDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: controller.officialAuthAccountsDir.path) }

        XCTAssertThrowsError(try controller.deleteOfficialAccount(id: account.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: credential.path))
        XCTAssertTrue(try controller.officialAccounts().contains { $0.id == account.id })
    }

    func testOfficialAccountCanBeForgottenWhenCredentialAlreadyMissing() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = controller(in: home)
        let account = try controller.saveNewOfficialAccount(auth: ["tokens": ["access_token": "test-token"]], name: "Saved", activate: false)
        try FileManager.default.removeItem(at: controller.officialAuthURL(for: account))
        _ = try controller.deleteOfficialAccount(id: account.id)
        XCTAssertFalse(try controller.officialAccounts().contains { $0.id == account.id })
    }
}
#endif
