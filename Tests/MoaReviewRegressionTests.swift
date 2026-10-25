import Darwin
import Foundation
import CryptoKit

#if !MOA_TESTING
@testable import Moa
#endif

enum MoaReviewRegressionTests {
    static let tests: [(String, () throws -> Void)] = [
        ("official account sync preserves identities after external login", accountIdentities),
        ("shared workspace accounts retain separate JWT user identities", accountJWTPrincipals),
        ("provider edits preserve commented array tables and their fields", commentedArrayTables),
        ("official restore removes complete quoted and multiline credentials", officialMultilineCredentials),
        ("data imports reject concurrent store writes and allow safe retry", coordinatedImportWrites),
        ("provider switching normalizes quoted and dotted identifiers", quotedProviderIdentifiers),
        ("multiline scalar updates replace complete assignments", multilineScalarAssignments),
        ("diagnostic TOML omits inline and multiline secrets", diagnosticRedaction),
        ("provider updates preserve complete multiline values and arrays", providerMultilineValues),
        ("data imports reject external, chained and cyclic links", packageLinks),
        ("legacy data manifests cannot hide symbolic links", legacyPackageLinks),
        ("bridge failures before headers return valid HTTP", bridgeConnectionFailure),
        ("bridge streams reject premature EOF and preserve finish status", bridgeTermination),
        ("WorkBuddy request replays and timestamp formats aggregate correctly", workBuddyReplays),
        ("custom prices can be updated and removed after pricing a model", customPriceLifecycle),
        ("price caches reload across roots and same-time imports", priceCacheInvalidation),
        ("menu storage reads stay responsive during an active export", storageReadDuringExport)
    ]

    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    private static func withHome(_ run: (URL, [String: String]) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try run(home, ["HOME": home.path, "CODEX_HOME": home.appendingPathComponent(".codex").path])
    }
    private static func login(_ email: String?, accountID: String?, token: String, subject: String? = nil, jwtAccountID: String? = nil) throws -> Data {
        var tokens: [String: String] = ["refresh_token": token, "access_token": "synthetic-access"]
        tokens["email"] = email
        tokens["account_id"] = accountID
        if subject != nil || jwtAccountID != nil {
            var claims: [String: Any] = [:]
            claims["sub"] = subject
            claims["email"] = email
            if let jwtAccountID { claims["https://api.openai.com/auth"] = ["chatgpt_account_id": jwtAccountID] }
            let data = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
            let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            tokens["id_token"] = "header.\(payload).signature"
        }
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": tokens], options: [.sortedKeys])
    }

    private static func accountJWTPrincipals() throws {
        try withHome { home, environment in
            let live = home.appendingPathComponent(".codex/auth.json")
            try FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            try login("a@example.invalid", accountID: "shared-workspace", token: "synthetic-a", subject: "user-a").write(to: live)
            let controller = ConfigProfileController(environment: environment)
            let a = try controller.selectedOfficialAccount()!
            let aURL = try controller.officialAuthURL(for: a)
            let originalA = try Data(contentsOf: aURL)
            // Even an equal email cannot override a known JWT subject mismatch.
            try login("a@example.invalid", accountID: "shared-workspace", token: "synthetic-b", subject: "user-b").write(to: live)
            _ = try controller.officialAccounts()
            try check(try Data(contentsOf: aURL) == originalA, "a shared workspace must not merge different JWT users")
            try check(try controller.currentOfficialLoginSaveStatus().savedAccountName == nil, "a different JWT user must remain available for enrollment")
            let b = try controller.addOfficialAccountFromCurrentLogin(name: "B")
            let bURL = try controller.officialAuthURL(for: b)
            let originalB = try Data(contentsOf: bURL)
            try login("renamed@example.invalid", accountID: "shared-workspace", token: "synthetic-a-new", subject: "user-a").write(to: live)
            _ = try controller.officialAccounts()
            try check(controller.officialAuthRefreshToken(from: controller.readAuthJSON(from: aURL)) == "synthetic-a-new", "the same JWT user must retain rotated credentials")
            try check(try Data(contentsOf: bURL) == originalB, "refreshing one JWT user must not change the other")
            let refreshedA = try Data(contentsOf: aURL)
            try login("a@example.invalid", accountID: nil, token: "synthetic-b-new", subject: "user-b", jwtAccountID: "shared-workspace").write(to: live)
            _ = try controller.officialAccounts()
            try check(controller.officialAuthRefreshToken(from: controller.readAuthJSON(from: bURL)) == "synthetic-b-new", "workspace IDs inside JWT claims must also retain user separation")
            try check(try Data(contentsOf: aURL) == refreshedA, "JWT-only identities must not overwrite a different user")
            try login("renamed@example.invalid", accountID: "other-workspace", token: "synthetic-other", subject: "user-a").write(to: live)
            try check(try controller.currentOfficialLoginSaveStatus().savedAccountName == nil, "the same user in another workspace is a separate login")
        }
    }

    private static func coordinatedImportWrites() throws {
        try withHome { home, environment in
            let sourceHome = home.appendingPathComponent("source-home")
            let sourceEnvironment = ["HOME": sourceHome.path, "CODEX_HOME": sourceHome.appendingPathComponent(".codex").path]
            let source = ConfigProfileController(environment: sourceEnvironment)
            _ = try source.addProfile(name: "Imported", baseURL: "https://imported.example", apiKey: "synthetic")
            let sourcePackages = MoaDataPackageController(environment: sourceEnvironment)
            let archive = home.appendingPathComponent("import.zip")
            let profiles = ConfigProfileController(environment: environment)
            _ = try profiles.addProfile(name: "Before", baseURL: "https://before.example", apiKey: "synthetic")
            // Preserve equal timestamps to ensure imported data cannot be
            // overwritten by an existing controller's stale in-memory database.
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            for url in [source.databaseURL, profiles.databaseURL] {
                try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
            }
            _ = try profiles.profiles()
            try sourcePackages.exportDataPackage(to: archive)
            let claude = ClaudeDesktopProfileController(environment: environment)
            let bridge = ProviderBridgeProfileController(environment: environment)
            let prices = MoaUsagePricingOverrideController(environment: environment)
            let catalog = MoaUsagePricingCatalogStore(environment: environment)
            let sourcePrices = MoaUsagePricingOverrideController(environment: sourceEnvironment)
            try sourcePrices.upsert(source: .codex, model: "gpt-5.5", inputUSDPerMillion: 9, outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            try prices.upsert(source: .codex, model: "gpt-5.5", inputUSDPerMillion: 1, outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            for root in [MoaDataRoot.localURL(environment: sourceEnvironment), MoaDataRoot.localURL(environment: environment)] {
                try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: root.appendingPathComponent("usage-pricing-overrides.json").path)
            }
            _ = prices.overrides()
            try sourcePackages.exportDataPackage(to: archive)
            let packages = MoaDataPackageController(environment: environment)
            let paused = DispatchSemaphore(value: 0)
            let resume = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            let result = ExportResult()
            packages.testingBeforeExportArchive = { paused.signal(); _ = resume.wait(timeout: .now() + 10) }
            DispatchQueue.global().async {
                result.set(Result { try packages.importDataPackage(from: archive) })
                done.signal()
            }
            var completed = false
            defer {
                resume.signal()
                if !completed { _ = done.wait(timeout: .now() + 10) }
            }
            try check(paused.wait(timeout: .now() + 10) == .success, "import must reach its rollback snapshot phase")
            func rejected(_ operation: () throws -> Void) throws {
                do {
                    try operation()
                    throw Failure(description: "a concurrent write must not report success while import is active")
                } catch MoaDataAccessError.busy {}
            }
            try check(packages.isDataOperationInProgress, "data operations must expose a responsive busy state")
            _ = packages.isICloudStorageEnabled()
            try rejected { _ = try profiles.addProfile(name: "Rejected", baseURL: "https://rejected.example", apiKey: "synthetic") }
            try rejected { _ = try ConfigProfileController(environment: environment).addProfile(name: "Second Instance", baseURL: "https://rejected.example", apiKey: "synthetic") }
            try rejected { _ = try claude.addProfile(name: "Rejected", baseURL: "https://claude.example", apiKey: "synthetic", models: ["claude-sonnet-4-6"], oneMModels: []) }
            try rejected { _ = try bridge.updateModels(id: "fixture", models: ["fixture"]) }
            try rejected { try prices.upsert(source: .codex, model: "gpt-5.5", inputUSDPerMillion: 1, outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil) }
            try rejected { _ = try catalog.merge(MoaUsagePricingCatalogSnapshot(sourceURL: "https://prices.example", fetchedAt: Date(), models: [:])) }
            try rejected { _ = try MoaDataPackageController(environment: environment).importDataPackage(from: archive) }
            // Another home must remain independent of the target's operation.
            _ = try source.addProfile(name: "Independent", baseURL: "https://independent.example", apiKey: "synthetic")
            resume.signal()
            try check(done.wait(timeout: .now() + 10) == .success, "import must finish after the snapshot is released")
            completed = true
            let rollback = try result.get()
            try check(!packages.isDataOperationInProgress, "busy state must clear after import")
            try check(try profiles.profiles().map(\.name) == ["Imported"], "cached databases must reload the imported root even when modification times match")
            try check(prices.override(source: .codex, model: "gpt-5.5")?.inputUSDPerMillion == 9, "prices must reload after direct imports without relying on a UI notification")
            let added = try profiles.addProfile(name: "Retried", baseURL: "https://retry.example", apiKey: "synthetic")
            try check(try profiles.profiles().contains { $0.id == added.id }, "writes must succeed on the imported root after a retry")
            try check(try profiles.profiles().contains { $0.name == "Imported" }, "retry must not replay the pre-import database over imported data")
            let extract = home.appendingPathComponent("rollback")
            try run("/usr/bin/ditto", ["-x", "-k", rollback.path, extract.path])
            let old = try JSONDecoder().decode(ProfileDatabase.self, from: Data(contentsOf: extract.appendingPathComponent("MoaDataPackage/.moa/profiles.json")))
            try check(old.profiles.map(\.name) == ["Before"], "rollback data must contain every write acknowledged before import")
            let invalid = home.appendingPathComponent("invalid.zip")
            try Data("synthetic-invalid-archive".utf8).write(to: invalid)
            do { _ = try packages.importDataPackage(from: invalid); throw Failure(description: "invalid archive accepted") }
            catch MoaDataPackageError.commandFailed {}
            try check(!packages.isDataOperationInProgress, "failed imports must also release the write gate")
            _ = try profiles.addProfile(name: "After Failure", baseURL: "https://retry.example", apiKey: "synthetic")
        }
    }

    private static func quotedProviderIdentifiers() throws {
        try withHome { home, environment in
            let controller = ConfigProfileController(environment: environment)
            let profile = ConfigProfile(id: "fixture", name: "New", baseURL: "https://new.example", apiKey: "synthetic-new")
            let fixtures = [
                ("one", "[model_providers.\"one\"]"),
                ("one.dot", "[\"model_providers\".\"one.dot\"]"),
                ("gateway name", "[ model_providers . 'gateway name' ]"),
                ("uni#网关", "[model_providers.\"uni#网关\"] # comment")
            ]
            for (id, header) in fixtures {
                let input = "model_provider = \(MoaTomlEditor.quotedString(id))\n\(header)\nname = \"Old\"\nbase_url = \"https://old.example\"\nexperimental_bearer_token = \"synthetic-old\"\n"
                let updated = controller.generateConfig(input, selecting: profile)
                try check(MoaTomlEditor.stringValue(in: updated, table: "", key: "model_provider") == id, "provider IDs must remain decoded values instead of gaining literal quotes")
                try check(controller.providerTableIDs(in: updated) == [id], "switching must retain exactly one matching provider table")
                try check(!updated.contains("https://old.example") && updated.contains("https://new.example"), "the correct quoted provider must receive the new endpoint")
                let official = MoaCodexConfigEditor.restoringOfficialMode(from: input)
                try check(!official.contains("synthetic-old") && !official.contains("https://old.example"), "quoted provider paths must also be recognized by official restore")
            }
            let live = home.appendingPathComponent(".codex/config.toml")
            let input = "model_provider = \"one.dot\"\n[model_providers.\"one.dot\"]\nbase_url = \"https://old.example\"\n[model_providers.\"one.dot\".http_headers]\nXFixture = \"preserve-nested\"\n"
            try input.write(to: live, atomically: true, encoding: .utf8)
            let saved = try controller.addProfile(name: "New", baseURL: "https://new.example", apiKey: "synthetic-new")
            _ = try controller.applyProfile(id: saved.id)
            let applied = try String(contentsOf: live, encoding: .utf8)
            try check(MoaTomlEditor.stringValue(in: applied, table: "", key: "model_provider") == "one.dot", "the live config must select the literal dotted provider name")
            try check(applied.contains("preserve-nested"), "provider subtables must not be mistaken for separate providers or removed")
            let caseSensitive = "model_provider = \"ONE\"\n[model_providers.one]\nbase_url = \"https://lowercase.example\"\nexperimental_bearer_token = \"preserve-lowercase\"\n[model_providers.ONE]\nbase_url = \"https://uppercase.example\"\nexperimental_bearer_token = \"remove-uppercase\"\n"
            let switched = controller.generateConfig(caseSensitive, selecting: profile)
            try check(MoaTomlEditor.stringValue(in: switched, table: "", key: "model_provider") == "ONE", "provider selection must preserve case-sensitive TOML identity")
            try check(switched.contains("preserve-lowercase"), "switching must not overwrite a provider differing only by case")
            let restored = MoaCodexConfigEditor.restoringOfficialMode(from: caseSensitive)
            try check(restored.contains("preserve-lowercase") && !restored.contains("remove-uppercase"), "official cleanup must distinguish case-sensitive provider names")
        }
    }

    private static func multilineScalarAssignments() throws {
        try withHome { _, environment in
            let controller = ConfigProfileController(environment: environment)
            let profile = ConfigProfile(id: "fixture", name: "New", baseURL: "https://new.example", apiKey: "synthetic-new")
            for value in ["\"\"\"one\"\"\"", "'''one'''", "\"\"\"\none\"\"\" # comment", "\"\"\"o\\\n  ne\"\"\""] {
                let input = "model_provider = \(value)\n[model_providers.one]\nbase_url = \"https://old.example\"\nexperimental_bearer_token = \"synthetic-old\"\n"
                try check(MoaTomlEditor.stringValue(in: input, table: "", key: "model_provider") == "one", "multiline basic and literal strings must decode as the same provider ID")
                let updated = controller.generateConfig(input, selecting: profile)
                try check(updated.components(separatedBy: "model_provider =").count - 1 == 1, "a multiline assignment must be replaced, never duplicated")
                try check(MoaTomlEditor.stringValue(in: updated, table: "", key: "model_provider") == "one", "the rewritten scalar must retain its value")
                try check(!MoaCodexConfigEditor.restoringOfficialMode(from: input).contains("synthetic-old"), "official restore must resolve a multiline root provider selector")
                let windows = input.replacingOccurrences(of: "\n", with: "\r\n")
                let windowsUpdated = controller.generateConfig(windows, selecting: profile)
                try check(windowsUpdated.components(separatedBy: "model_provider =").count - 1 == 1, "CRLF input must also replace the complete scalar without duplication")
                try check(!MoaCodexConfigEditor.restoringOfficialMode(from: windows).contains("synthetic-old"), "CRLF provider settings must retain the same restore behavior")
            }
            let desktop = "[desktop]\ndefault-service-tier = \"\"\"\npriority\"\"\" # comment\nother = \"preserve\"\n"
            let updated = MoaTomlEditor.upsertingString("default", in: desktop, table: "desktop", key: "default-service-tier")
            try check(!updated.contains("priority") && updated.contains("other = \"preserve\""), "multiline replacement must remove its closing delimiter and preserve the next assignment")
            try check(MoaTomlEditor.stringValue(in: updated, table: "desktop", key: "default-service-tier") == "default", "rewritten multiline desktop settings must remain readable")
            let escaped = #"""
            "model\u005fprovider" = """one#literal""" # comment
            """#
            try check(MoaTomlEditor.stringValue(in: escaped, table: "", key: "model_provider") == "one#literal", "quoted Unicode keys and hashes inside multiline values must be decoded correctly")
        }
    }

    private static func commentedArrayTables() throws {
        try withHome { _, environment in
            let controller = ConfigProfileController(environment: environment)
            let profile = ConfigProfile(id: "fixture", name: "New", baseURL: "https://new.example", apiKey: "synthetic")
            for header in ["[[plugins]]", "[[plugins]] # ordinary inline comment", "[[plugins.\"#literal\"]] # another comment"] {
                let array = header + "\nname = \"must-keep-plugin\"\nbase_url = \"https://plugin.example\"\nenabled = true"
                let input = "model_provider = \"one\"\n[model_providers.one]\nname = \"Old\"\nbase_url = \"https://old.example\"\n" + array
                let updated = controller.generateConfig(input, selecting: profile)
                try check(updated.contains(array), "array table content must remain intact, including names shared with provider keys")
            }
            let rootArray = "[[plugins]] # inline comment\nservice_tier = \"priority\""
            try check(MoaTomlEditor.stringValue(in: rootArray, table: "", key: "service_tier") == nil, "array members must never be interpreted as root settings")
        }
    }

    private static func officialMultilineCredentials() throws {
        try withHome { home, environment in
            let preserved = #"""
            instructions = """
            base_url = "keep-as-text"
            experimental_bearer_token = "also-keep-as-text"
            """
            """#
            let providerNote = #"""
            unknown_note = '''
            base_url = "provider-string-content"
            '''
            """#
            let input = #"""
            "model_provider" = "one"
            model = """third-party-model"""
            'base_url' = '''https://root-gateway.example'''
            """# + "\n" + preserved + "\n" + #"""
            [model_providers.one]
            "base_url" = """https://provider-gateway.example"""
            'experimental_bearer_token' = '''
            synthetic-multiline-credential
            '''
            """# + "\n" + providerNote + "\n" + #"""
            [[plugins]] # preserve this boundary
            base_url = "https://plugin.example"
            name = "preserve-plugin"
            [model_providers.other]
            base_url = "https://unselected.example"
            experimental_bearer_token = "preserve-unselected"
            """#
            let restored = MoaCodexConfigEditor.restoringOfficialMode(from: input)
            for marker in ["third-party-model", "root-gateway.example", "provider-gateway.example", "synthetic-multiline-credential"] {
                try check(!restored.contains(marker), "official mode must remove the entire managed value: \(marker)")
            }
            try check(restored.contains(preserved) && restored.contains(providerNote), "unrelated multiline content must remain unchanged")
            try check(restored.contains("https://plugin.example") && restored.contains("preserve-unselected"), "array members and unselected providers must retain their own fields")
            try check(MoaTomlEditor.stringValue(in: restored, table: "", key: "model_provider") == "one", "official restore must retain provider identity for session continuity")
            let managed = input.replacingOccurrences(of: "[model_providers.one]", with: "[model_providers.moa-one]")
            let stripped = MoaCodexConfigEditor.removingExperimentalBearerTokens(from: managed)
            try check(!stripped.contains("synthetic-multiline-credential") && stripped.contains(preserved), "managed credential stripping must remove full values without editing string content")
            let live = home.appendingPathComponent(".codex/config.toml")
            try FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            try input.write(to: live, atomically: true, encoding: .utf8)
            try ConfigProfileController(environment: environment).restoreOfficial()
            let applied = try String(contentsOf: live, encoding: .utf8)
            try check(applied == restored + "\n", "the controller must apply the same safe official config to the live client file")
        }
    }

    private static func accountIdentities() throws {
        try withHome { home, environment in
            let live = home.appendingPathComponent(".codex/auth.json")
            try FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            let aData = try login("a@example.invalid", accountID: "account-a", token: "synthetic-a")
            try aData.write(to: live)
            let controller = ConfigProfileController(environment: environment)
            let a = try controller.selectedOfficialAccount()!
            let aURL = try controller.officialAuthURL(for: a)
            let savedA = try Data(contentsOf: aURL)
            try login("b@example.invalid", accountID: "account-b", token: "synthetic-b").write(to: live)
            _ = try controller.officialAccounts()
            try check(try Data(contentsOf: aURL) == savedA, "opening the menu must not replace A with external login B")
            try check(try controller.currentOfficialLoginSaveStatus().savedAccountName == nil, "a new external login must remain available to save")
            let b = try controller.addOfficialAccountFromCurrentLogin(name: "B")
            try check(try controller.officialAccounts().count == 2, "external login should enroll as a distinct account")
            let bURL = try controller.officialAuthURL(for: b)
            let savedB = try Data(contentsOf: bURL)

            // Same email must not merge two distinct workspace account IDs.
            try login("a@example.invalid", accountID: "account-c", token: "synthetic-c").write(to: live)
            _ = try controller.officialAccounts()
            try check(try Data(contentsOf: aURL) == savedA, "a shared email must not override a known account ID mismatch")
            try check(try Data(contentsOf: bURL) == savedB, "unrelated selected accounts must not be touched")

            try login("a-renamed@example.invalid", accountID: "account-a", token: "synthetic-a-rotated").write(to: live)
            _ = try controller.officialAccounts()
            let refreshed = controller.readAuthJSON(from: aURL)
            try check(controller.officialAuthRefreshToken(from: refreshed) == "synthetic-a-rotated", "known identities must retain rotated tokens even if another account was selected")
            try check(try Data(contentsOf: bURL) == savedB, "refreshing A must preserve B's snapshot")
            let refreshedA = try Data(contentsOf: aURL)
            try login(nil, accountID: nil, token: "synthetic-unknown").write(to: live)
            _ = try controller.officialAccounts()
            try check(try Data(contentsOf: aURL) == refreshedA && Data(contentsOf: bURL) == savedB, "unidentified credentials must not overwrite saved accounts")
        }
    }

    private static func diagnosticRedaction() throws {
        try withHome { home, environment in
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let text = #"""
            # synthetic-comment-secret
            [model_providers.fixture]
            http_headers = { Authorization = "Bearer synthetic-inline-secret", XKey = "synthetic-other-secret" }
            experimental_bearer_token = """
            synthetic-multiline-secret
            """
            unknown_options = [
                "synthetic-array-secret",
                ["synthetic-nested-secret"]
            ]
            request_timeout_ms = 1000
            """#
            try text.write(to: root.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
            try Data("{broken: synthetic-json-secret}".utf8).write(to: root.appendingPathComponent("auth.json"))
            let archive = home.appendingPathComponent("diagnostics.zip")
            try MoaDataPackageController(environment: environment).exportDiagnosticPackage(to: archive)
            let extracted = home.appendingPathComponent("extracted")
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            let redacted = extracted.appendingPathComponent("MoaDiagnostics/redacted")
            for name in ["config.toml", "auth.json"] {
                let output = try String(contentsOf: redacted.appendingPathComponent(name), encoding: .utf8)
                try check(!output.contains("synthetic-"), "diagnostics must never retain secret values in \(name)")
            }
            let output = try String(contentsOf: redacted.appendingPathComponent("config.toml"), encoding: .utf8)
            try check(output.contains("http_headers") && output.contains("request_timeout_ms"), "configuration shape should remain useful for diagnostics")
        }
    }

    private static func providerMultilineValues() throws {
        try withHome { _, environment in
            let controller = ConfigProfileController(environment: environment)
            let extras = #"""
            env_key_instructions = """
            Run the fixture helper.
            name = "this is string content"

            [model_providers.fake]
            """
            literal_note = '''
            base_url = "also string content"
            '''
            unknown_models = [
                "first",
                ["nested", "array"],
                "last"
            ]
            request_timeout_ms = 1000
            """#
            let child = "[model_providers.one.http_headers]\nXFixture = \"preserve-child\""
            let config = "model_provider = \"one\"\n[model_providers.one]\nname = \"Old\"\nbase_url = \"https://old.example\"\n" + extras + "\n" + child
            let profile = ConfigProfile(id: "fixture", name: "Updated", baseURL: "https://new.example", apiKey: "synthetic-key")
            let updated = controller.generateConfig(config, selecting: profile)
            try check(updated.contains(extras), "provider edits must preserve complete multiline strings, arrays and blank lines")
            try check(updated.contains(child), "neighboring provider subtables must remain untouched")
            try check(updated.contains("base_url = \"https://new.example\""), "managed fields should still update")
            try check(!updated.contains("base_url = \"https://old.example\""), "old managed values should be replaced")
        }
    }

    private static func packageLinks() throws {
        for kind in ["absolute", "parent", "chain", "cycle", "safe"] {
            try withHome { home, environment in
                let root = home.appendingPathComponent("fixture-package/MoaDataPackage/.moa")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try Data("keep-original".utf8).write(to: root.appendingPathComponent("profiles.json"))
                let liveRoot = MoaDataRoot.localURL(environment: environment)
                try FileManager.default.createDirectory(at: liveRoot, withIntermediateDirectories: true)
                try Data("keep-original".utf8).write(to: liveRoot.appendingPathComponent("profiles.json"))
                var links: [String: String] = [:]
                func link(_ name: String, _ target: String) throws {
                    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(name).path, withDestinationPath: target)
                    links[name] = target
                }
                switch kind {
                case "absolute": try link("external", home.appendingPathComponent("outside").path)
                case "parent": try link("external", "../outside")
                case "chain": try link("alias", "."); try link("external", "alias/../outside")
                case "cycle": try link("one", "two"); try link("two", "one")
                default:
                    try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
                    try link("nested/alias", "../profiles.json")
                    try link("second", "nested/alias")
                }
                let archive = home.appendingPathComponent("links.zip")
                let controller = MoaDataPackageController(environment: environment)
                func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
                let content = Data("keep-original".utf8)
                var files = [MoaDataPackageManifest.FileEntry(path: "profiles.json", size: Int64(content.count), sha256: hash(content), kind: .file)]
                for (name, destination) in links {
                    let bytes = Data(destination.utf8)
                    files.append(MoaDataPackageManifest.FileEntry(path: name, size: Int64(bytes.count), sha256: hash(bytes), kind: .symbolicLink, symbolicLinkDestination: destination))
                }
                let manifest = MoaDataPackageManifest(schemaVersion: 2, exportedAt: "fixture", appVersion: "fixture", appBuild: "0", dataRootName: ".moa", files: files)
                try JSONEncoder().encode(manifest).write(to: root.deletingLastPathComponent().appendingPathComponent("MoaDataPackageManifest.json"))
                try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", root.deletingLastPathComponent().path, archive.path])
                if kind == "safe" {
                    _ = try controller.importDataPackage(from: archive)
                    try check(try Data(contentsOf: liveRoot.appendingPathComponent("second")) == Data("keep-original".utf8), "contained relative link chains should still round trip")
                } else {
                    do {
                        _ = try controller.importDataPackage(from: archive)
                        throw Failure(description: "unsafe \(kind) link was accepted")
                    } catch MoaDataPackageError.invalidPackage {}
                    try check(try Data(contentsOf: liveRoot.appendingPathComponent("profiles.json")) == Data("keep-original".utf8), "rejected imports must not replace existing user data")
                }
            }
        }
    }

    private static func legacyPackageLinks() throws {
        for target in ["profiles.json", "../missing-outside"] {
        try withHome { home, environment in
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: root.appendingPathComponent("profiles.json"))
            try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path, withDestinationPath: target)
            let controller = MoaDataPackageController(environment: environment)
            let archive = home.appendingPathComponent("schema2.zip")
            try controller.exportDataPackage(to: archive)
            let extract = home.appendingPathComponent("extract")
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, extract.path])
            let package = extract.appendingPathComponent("MoaDataPackage")
            let manifestURL = package.appendingPathComponent("MoaDataPackageManifest.json")
            var manifest = try JSONDecoder().decode(MoaDataPackageManifest.self, from: Data(contentsOf: manifestURL))
            manifest.schemaVersion = 1
            manifest.files.removeAll { $0.resolvedKind == .symbolicLink }
            try JSONEncoder().encode(manifest).write(to: manifestURL)
            let legacy = home.appendingPathComponent("schema1.zip")
            try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", package.path, legacy.path])
            do {
                _ = try controller.importDataPackage(from: legacy)
                throw Failure(description: "schema 1 must not silently omit links from integrity checks")
            } catch MoaDataPackageError.invalidPackage {}
        }
        }
    }

    private static func bridgeConnectionFailure() throws {
        let response = try bridgeResponse(mode: "failure")
        try check(response.hasPrefix("HTTP/1.1 502"), "upstream connection failures require a complete HTTP error response")
        try check(response.contains("Content-Length:") && response.contains("\"status\":\"failed\""), "failure responses must include framing and a structured error")
    }

    private static func bridgeTermination() throws {
        let truncated = try bridgeResponse(mode: "truncated")
        try check(truncated.hasPrefix("HTTP/1.1 200") && truncated.contains("response.failed"), "premature upstream EOF should fail after streaming headers")
        try check(!truncated.contains("response.completed"), "partial streams must never report success")
        let stopped = try bridgeResponse(mode: "stopped")
        try check(stopped.contains("response.completed"), "a valid stop finish_reason may complete without a DONE frame")
        let length = try bridgeResponse(mode: "length")
        try check(length.contains("response.incomplete") && length.contains("max_output_tokens"), "length-limited streams must report incomplete")
        try check(!length.contains("response.completed") && !length.contains("response.function_call_arguments.done"), "truncated tools must not become executable completed calls")
        let filtered = MoaChatSSEToResponsesSSEConverter()
        _ = try filtered.ingest(jsonPayload: #"{"choices":[{"delta":{"content":"partial"},"finish_reason":"content_filter"}]}"#)
        try check(try filtered.finish().joined().contains("response.incomplete"), "content filtering must retain incomplete status")
    }

    private static func bridgeResponse(mode: String) throws -> String {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [ReviewUpstreamProtocol.self]
        let session = URLSession(configuration: settings)
        let server = MoaProviderBridgeServer(urlSession: session, diagnostics: MoaProviderBridgeDiagnostics())
        var config = MoaProviderBridgeServerConfiguration(profile: ConfigProfile(id: "fixture", name: "Fixture", baseURL: "https://upstream.invalid/\(mode)", apiKey: "synthetic"))
        config.bridgeToken = "synthetic"
        config.port = 0
        let port = try server.start(configuration: config)
        defer { server.stop(); session.invalidateAndCancel() }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "socket creation failed") }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try check(result == 0, "local bridge socket should connect")
        let body = #"{"model":"fixture","input":"fixture","stream":true}"#
        let request = "POST /v1/responses HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer synthetic\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body
        let sent = request.withCString { send(fd, $0, request.utf8.count, 0) }
        try check(sent == request.utf8.count, "test request should be sent completely")
        var buffer = [UInt8](repeating: 0, count: 4096)
        var received = Data()
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count == 0 { break }
            try check(count > 0, "bridge must close its response without timing out")
            received.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: received, as: UTF8.self)
    }

    private static func workBuddyReplays() throws {
        for edition in [WorkBuddyEdition.china, .international] {
            try withHome { home, environment in
                let root = home.appendingPathComponent(edition.dataDirectoryName)
                let projects = root.appendingPathComponent("projects")
                let sessions = root.appendingPathComponent("sessions")
                try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
                func event(_ id: String, _ timestamp: Any, _ output: Int) -> [String: Any] {
                    ["id": id, "timestamp": timestamp, "model": "fixture", "usage": ["input_tokens": 100, "output_tokens": output]]
                }
                let first = event("request-a", "2026-10-25T01:02:03.123Z", 10)
                let replay = event("request-a", "2026-10-25T01:02:03.124Z", 10)
                let update = event("request-a", "2026-10-25T01:02:03.125Z", 20)
                let distinct = event("request-b", "2026-10-25T01:02:03Z", 10)
                let numeric = event("request-c", 1_790_000_000_000, 10)
                try writeEvents([first, distinct, numeric], to: projects.appendingPathComponent("a.jsonl"))
                try writeEvents([replay, update, first], to: sessions.appendingPathComponent("b.jsonl"))
                let scanner = WorkBuddyUsageScanner(environment: environment, edition: edition)
                let report = try scanner.loadReport()
                try check(report.totalTokens == 340, "requests must deduplicate by ID, retain the complete update and parse all timestamp formats")
                try check(report.rows.allSatisfy { $0.source == edition.usageSource }, "deduplication must remain edition scoped")
                try check(try scanner.loadReport().totalTokens == 340, "cached logs must use the same deduplication rules")
            }
        }
    }

    private static func customPriceLifecycle() throws {
        try withHome { home, environment in
            let file = home.appendingPathComponent(".workbuddy-ai/projects/fixture.jsonl")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeEvents([["id": "one", "timestamp": 1_790_000_000_000, "model": "fixture", "usage": ["input_tokens": 1000000, "output_tokens": 0]]], to: file)
            let scanner = WorkBuddyUsageScanner(environment: environment)
            let prices = MoaUsagePricingOverrideController(environment: environment)
            try check(try scanner.loadReport().fallbackRows.count == 1, "unknown models start unpriced")
            try prices.upsert(source: .workbuddy, model: "fixture", inputUSDPerMillion: 2, outputUSDPerMillion: 0, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            try check(try scanner.loadReport().totalCostUSD == 2, "the first custom price should apply")
            try prices.upsert(source: .workbuddy, model: "fixture", inputUSDPerMillion: 3, outputUSDPerMillion: 0, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            try check(try scanner.loadReport().totalCostUSD == 3, "an already priced row should accept another edit")
            try prices.remove(source: .workbuddy, model: "fixture")
            try check(try scanner.loadReport().fallbackRows.count == 1, "removing a custom price must restore unpriced behavior")
        }
    }

    private static func priceCacheInvalidation() throws {
        try withHome { _, environment in
            let prices = MoaUsagePricingOverrideController(environment: environment)
            try prices.upsert(source: .codex, model: "gpt-5.5", inputUSDPerMillion: 1, outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            let local = MoaDataRoot.localURL(environment: environment).appendingPathComponent("usage-pricing-overrides.json")
            let cloud = MoaDataRoot.iCloudURL(environment: environment).appendingPathComponent("usage-pricing-overrides.json")
            try FileManager.default.createDirectory(at: cloud.deletingLastPathComponent(), withIntermediateDirectories: true)
            var payload = try JSONSerialization.jsonObject(with: Data(contentsOf: local)) as! [String: Any]
            var rows = payload["overrides"] as! [[String: Any]]
            rows[0]["inputUSDPerMillion"] = 9
            payload["overrides"] = rows
            try JSONSerialization.data(withJSONObject: payload).write(to: cloud)
            let modified = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: local.path)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: cloud.path)
            _ = prices.overrides()
            let flag = MoaDataRoot.iCloudStorageStateURL(environment: environment)
            try FileManager.default.createDirectory(at: flag.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: flag)
            try check(prices.override(source: .codex, model: "gpt-5.5")?.inputUSDPerMillion == 9, "switching roots must invalidate a same-mtime cache")
            rows[0]["inputUSDPerMillion"] = 7
            payload["overrides"] = rows
            try JSONSerialization.data(withJSONObject: payload).write(to: cloud, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: cloud.path)
            NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
            try check(prices.override(source: .codex, model: "gpt-5.5")?.inputUSDPerMillion == 7, "imports must invalidate a same-path, same-mtime cache")
        }
    }

    private final class ExportResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<URL, Error>?
        func set(_ result: Result<URL, Error>) { lock.lock(); value = result; lock.unlock() }
        @discardableResult func get() throws -> URL {
            lock.lock(); defer { lock.unlock() }
            guard let value else { throw Failure(description: "missing asynchronous operation result") }
            return try value.get()
        }
    }

    private static func storageReadDuringExport() throws {
        try withHome { home, environment in
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: root.appendingPathComponent("fixture"))
            let controller = MoaDataPackageController(environment: environment)
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let exported = DispatchSemaphore(value: 0)
            let read = DispatchSemaphore(value: 0)
            let result = ExportResult()
            controller.testingBeforeExportArchive = { entered.signal(); _ = release.wait(timeout: .now() + 5) }
            DispatchQueue.global().async {
                result.set(Result { try controller.exportDataPackage(to: home.appendingPathComponent("data.zip")) })
                exported.signal()
            }
            defer { release.signal(); _ = exported.wait(timeout: .now() + 5) }
            try check(entered.wait(timeout: .now() + 5) == .success, "export must reach the archive phase")
            DispatchQueue.global().async { _ = controller.isICloudStorageEnabled(); read.signal() }
            try check(read.wait(timeout: .now() + 1) == .success, "menu reads must finish while export is deliberately paused")
            release.signal()
            try check(exported.wait(timeout: .now() + 5) == .success, "export must finish after being released")
            exported.signal()
            try result.get()
        }
    }

    private static func writeEvents(_ events: [[String: Any]], to url: URL) throws {
        var data = Data()
        for event in events { data.append(try JSONSerialization.data(withJSONObject: event)); data.append(10) }
        try data.write(to: url)
    }
    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "fixture archive command failed")
    }
}

private final class ReviewUpstreamProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        if request.url!.path.contains("failure") {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let payload: String
        if request.url!.path.contains("length") {
            payload = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"fixture-call","function":{"name":"fixture","arguments":"{\"partial\":"}}]},"finish_reason":"length"}]}"# + "\n\ndata: [DONE]"
        } else if request.url!.path.contains("stopped") {
            payload = #"{"choices":[{"delta":{"content":"done"},"finish_reason":"stop"}]}"#
        } else {
            payload = #"{"choices":[{"delta":{"content":"partial"}}]}"#
        }
        client?.urlProtocol(self, didLoad: Data("data: \(payload)\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
