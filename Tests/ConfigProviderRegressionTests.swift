#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class ConfigProviderRegressionTests: XCTestCase {
    private func withController(config: String, _ body: (ConfigProfileController) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-provider-regression-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try config.write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try body(ConfigProfileController(environment: ["HOME": home.path]))
    }

    func testDefaultOfficialModeDoesNotImportOrOverwriteStoredProviders() throws {
        let config = """
        model = "gpt-5"
        [model_providers.backup]
        base_url = "https://backup.example"
        experimental_bearer_token = "backup-token"
        [model_providers.moa-custom]
        base_url = "https://other.example"
        """
        try withController(config: config) { controller in
            XCTAssertTrue(try controller.profiles().isEmpty)
            let profile = ConfigProfile(id: "test", name: "New", baseURL: "https://new.example", apiKey: "new-token")
            let updated = controller.generateConfig(config, selecting: profile)
            XCTAssertEqual(controller.rootTomlStringValue(in: updated, key: "model_provider"), "moa-custom-2")
            XCTAssertEqual(controller.tomlStringValue(in: updated, table: "model_providers.backup", key: "base_url"), "https://backup.example")
            XCTAssertEqual(controller.tomlStringValue(in: updated, table: "model_providers.moa-custom", key: "base_url"), "https://other.example")
            XCTAssertEqual(controller.tomlStringValue(in: updated, table: "model_providers.moa-custom-2", key: "base_url"), "https://new.example")
        }
    }

    func testDottedProviderAssignmentsArePreservedWithoutRedefinition() throws {
        let config = """
        model_provider = "foo"
        model_providers.foo.base_url = "https://old.example"
        model_providers.foo.extra = "keep"
        model_providers.moa-custom.base_url = "https://reserved.example"
        """
        try withController(config: config) { controller in
            let profile = ConfigProfile(id: "test", name: "New", baseURL: "https://new.example", apiKey: "new-token")
            let updated = controller.generateConfig(config, selecting: profile)
            XCTAssertEqual(controller.rootTomlStringValue(in: updated, key: "model_provider"), "moa-custom-2")
            XCTAssertTrue(updated.contains("model_providers.foo.extra = \"keep\""))
            XCTAssertFalse(updated.contains("[model_providers.foo]"))
            XCTAssertFalse(updated.contains("[model_providers.moa-custom]"))
            XCTAssertEqual(controller.tomlStringValue(in: updated, table: "model_providers.moa-custom-2", key: "base_url"), "https://new.example")
        }
    }

    func testUnknownSelectedProviderDoesNotBorrowOtherProvidersCredentials() throws {
        let config = """
        model_provider = "missing"
        [model_providers.backup]
        base_url = "https://backup.example"
        experimental_bearer_token = "backup-token"
        """
        try withController(config: config) { controller in
            XCTAssertTrue(try controller.profiles().isEmpty)
        }
    }

    func testInlineProviderRootFailsWithoutChangingLiveConfig() throws {
        let config = "model_providers = { foo = { base_url = \"https://old.example\" } }\n"
        try withController(config: config) { controller in
            let profile = try controller.addProfile(name: "New", baseURL: "https://new.example", apiKey: "new-token")
            XCTAssertThrowsError(try controller.applyProfile(id: profile.id))
            XCTAssertEqual(try String(contentsOf: controller.codexConfigURL, encoding: .utf8), config)
        }
    }

    func testNoAccountModeRejectsInlineProviderRootAndRestoresState() throws {
        let config = "model_providers = { foo = { base_url = \"https://old.example\" } }\n"
        for selectProfile in [false, true] {
            try withController(config: config) { controller in
                let profile = try controller.addProfile(name: "New", baseURL: "https://new.example", apiKey: "new-token")
                if selectProfile {
                    var database = try controller.loadDatabase()
                    database.selectedProfileID = profile.id
                    try controller.saveDatabase(database)
                }
                try Data("{\"OPENAI_API_KEY\":\"synthetic\"}".utf8).write(to: controller.codexAuthURL)
                let originalAuth = try Data(contentsOf: controller.codexAuthURL)
                let originalDatabase = try Data(contentsOf: controller.databaseURL)
                XCTAssertThrowsError(try controller.applyOfficialNoAccountMode())
                XCTAssertEqual(try String(contentsOf: controller.codexConfigURL, encoding: .utf8), config)
                XCTAssertEqual(try Data(contentsOf: controller.codexAuthURL), originalAuth)
                XCTAssertEqual(try Data(contentsOf: controller.databaseURL), originalDatabase)
            }
        }
    }

    func testNoAccountModeWithoutProfilesPreservesInlineProviderRoot() throws {
        let config = "model_providers = { foo = { base_url = \"https://old.example\" } }\n"
        try withController(config: config) { controller in
            _ = try controller.applyOfficialNoAccountMode()
            XCTAssertEqual(try String(contentsOf: controller.codexConfigURL, encoding: .utf8), config)
        }
    }
}
#endif
