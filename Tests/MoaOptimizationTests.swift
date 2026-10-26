import CryptoKit
import Darwin
import Foundation

#if !MOA_TESTING
@testable import Moa
#endif

enum MoaOptimizationTests {
    static let tests: [(String, () throws -> Void)] = [
        ("process output cannot block and timed-out children are reaped", processBoundaries),
        ("failed noisy exports release the shared data operation", failedExport),
        ("schema 2 requires complete valid file and link hashes", manifestHashes),
        ("streaming file hashes preserve digests and propagate read errors", fileHashes),
        ("ZCode query cache avoids work and invalidates on database and WAL changes", zcodeCache),
        ("account menu reads preserve timestamps while refreshed credentials persist", accountReadWrites),
        ("provider edits preserve adjacent comments and multiline values", compatibility),
        ("usage scheduling reduces idle work while preserving alerts and forced reloads", usageScheduling)
    ]

    private struct Failure: Error { let message: String }
    private static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(message: message) }
    }

    private static func withHome(_ body: (URL, [String: String]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moa-optimization-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent(".codex").path])
    }

    private static func wait(_ predicate: () -> Bool, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < end
        return predicate()
    }

    private static func processBoundaries() throws {
        try check(MoaProcessRunner.run("/bin/sh", ["-c", "/bin/dd if=/dev/zero bs=65536 count=32; /bin/dd if=/dev/zero bs=65536 count=32 >&2"], timeout: 5) == 0, "large output must finish")
        try check(MoaProcessRunner.run("/does-not-exist", []) == 127, "launch errors must be reported")
        try check(MoaProcessRunner.run("/bin/sh", ["-c", "exit 7"]) == 7, "exit status must be retained")
        try withHome { root, _ in
            let pidFile = root.appendingPathComponent("child-pid")
            let start = Date()
            let status = MoaProcessRunner.run("/bin/sh", ["-c", "echo $$ > \"$1\"; trap '' TERM; exec /bin/sleep 30", "fixture", pidFile.path], timeout: 0.2)
            try check(status == MoaProcessRunner.timeoutStatus && Date().timeIntervalSince(start) < 4, "ignored TERM must escalate within the timeout boundary")
            let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
            try check(kill(pid, 0) == -1 && errno == ESRCH, "timed-out children must be reaped")
        }
    }

    private static func failedExport() throws {
        try withHome { root, environment in
            let dataRoot = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            for index in 0..<1600 {
                let file = dataRoot.appendingPathComponent("unreadable-\(index)")
                try Data("fixture".utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
            }
            let controller = MoaDataPackageController(environment: environment)
            do {
                _ = try controller.exportDataPackage(to: root.appendingPathComponent("export.zip"))
                throw Failure(message: "unreadable export must fail")
            } catch MoaDataPackageError.commandFailed {}
            try check(!controller.isDataOperationInProgress, "failed export must release its operation")
            _ = try ConfigProfileController(environment: environment).addProfile(name: "Retry", baseURL: "https://fixture.invalid", apiKey: "synthetic")
        }
    }

    private static func manifestHashes() throws {
        try withHome { root, environment in
            let package = root.appendingPathComponent("MoaDataPackage")
            let dataRoot = package.appendingPathComponent(".moa")
            try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            let bytes = Data("original".utf8)
            try bytes.write(to: dataRoot.appendingPathComponent("fixture"))
            let validHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let live = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: live.appendingPathComponent("sentinel"))
            let controller = MoaDataPackageController(environment: environment)
            for hash in [nil, "", "123", String(repeating: "z", count: 64), String(repeating: "0", count: 64), validHash.uppercased()] as [String?] {
                let manifest = MoaDataPackageManifest(schemaVersion: 2, exportedAt: "fixture", appVersion: "fixture", appBuild: "0", dataRootName: ".moa", files: [.init(path: "fixture", size: Int64(bytes.count), sha256: hash, kind: .file)])
                try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("MoaDataPackageManifest.json"))
                let zip = root.appendingPathComponent("fixture.zip")
                try? FileManager.default.removeItem(at: zip)
                try check(MoaProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", package.path, zip.path]) == 0, "fixture archive failed")
                if hash == validHash.uppercased() {
                    _ = try controller.importDataPackage(from: zip)
                } else {
                    do {
                        _ = try controller.importDataPackage(from: zip)
                        throw Failure(message: "invalid schema 2 hash accepted")
                    } catch MoaDataPackageError.invalidPackage {}
                    try check(try Data(contentsOf: live.appendingPathComponent("sentinel")) == Data("keep".utf8), "invalid import replaced live data")
                }
            }
            try FileManager.default.createSymbolicLink(atPath: dataRoot.appendingPathComponent("alias").path, withDestinationPath: "fixture")
            let missingLinkHash = MoaDataPackageManifest(schemaVersion: 2, exportedAt: "fixture", appVersion: "fixture", appBuild: "0", dataRootName: ".moa", files: [
                .init(path: "fixture", size: Int64(bytes.count), sha256: validHash, kind: .file),
                .init(path: "alias", size: 7, sha256: nil, kind: .symbolicLink, symbolicLinkDestination: "fixture")
            ])
            try JSONEncoder().encode(missingLinkHash).write(to: package.appendingPathComponent("MoaDataPackageManifest.json"))
            let linkZip = root.appendingPathComponent("link.zip")
            try check(MoaProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", package.path, linkZip.path]) == 0, "link archive failed")
            do { _ = try controller.importDataPackage(from: linkZip); throw Failure(message: "missing link hash accepted") }
            catch MoaDataPackageError.invalidPackage {}
            try FileManager.default.removeItem(at: dataRoot.appendingPathComponent("alias"))
            let legacy = MoaDataPackageManifest(schemaVersion: 1, exportedAt: "fixture", appVersion: "fixture", appBuild: "0", dataRootName: ".moa", files: [.init(path: "fixture", size: Int64(bytes.count), sha256: nil, kind: .file)])
            try JSONEncoder().encode(legacy).write(to: package.appendingPathComponent("MoaDataPackageManifest.json"))
            let legacyZip = root.appendingPathComponent("legacy.zip")
            try check(MoaProcessRunner.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", package.path, legacyZip.path]) == 0, "legacy archive failed")
            _ = try controller.importDataPackage(from: legacyZip)
        }
    }

    private static func fileHashes() throws {
        try withHome { root, _ in
            let file = root.appendingPathComponent("hash")
            for size in [0, 1, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1, 5 * 1024 * 1024 + 3] {
                let bytes = Data(repeating: 0x5a, count: size)
                try bytes.write(to: file)
                let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                try check(try MoaFileHash.sha256(file) == expected, "chunk boundary changed the hash")
            }
            try FileManager.default.removeItem(at: file)
            do { _ = try MoaFileHash.sha256(file); throw Failure(message: "missing file must not hash as empty") }
            catch is CocoaError {}
        }
    }

    private static func zcodeCache() throws {
        try withHome { root, base in
            let database = root.appendingPathComponent("usage.sqlite")
            var environment = base
            environment["ZCODE_USAGE_DB"] = database.path
            func sql(_ statement: String) throws {
                try check(MoaProcessRunner.run("/usr/bin/sqlite3", [database.path, statement]) == 0, "sqlite fixture failed")
            }
            try sql("CREATE TABLE model_usage (status TEXT, started_at INTEGER, model_id TEXT, input_tokens INTEGER, cache_read_input_tokens INTEGER, cache_creation_input_tokens INTEGER, output_tokens INTEGER); INSERT INTO model_usage VALUES ('completed', 1792886400000, 'fixture', 1000000, 0, 0, 0);")
            let scanner = ZCodeUsageScanner(environment: environment)
            let first = try scanner.loadReport()
            for _ in 0..<5 { try check(try scanner.loadReport().totalTokens == first.totalTokens, "cached query changed usage") }
            try check(scanner.testingQueryCount == 1, "unchanged database should spawn one sqlite query")
            let prices = MoaUsagePricingOverrideController(environment: environment)
            try prices.upsert(source: .zcode, model: "fixture", inputUSDPerMillion: 7, outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            try check(try scanner.loadReport().totalCostUSD == 7 && scanner.testingQueryCount == 1, "cached raw usage must reprice without another query")
            _ = try scanner.loadReport(forceRefresh: true)
            try check(scanner.testingQueryCount == 2, "force refresh must query again")
            let wal = URL(fileURLWithPath: database.path + "-wal")
            try Data().write(to: wal)
            _ = try scanner.loadReport()
            try check(scanner.testingQueryCount == 3, "WAL appearance must invalidate")
            try FileManager.default.removeItem(at: wal)
            _ = try scanner.loadReport()
            try check(scanner.testingQueryCount == 4, "WAL removal must invalidate")
            let stamp = try FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as! Date
            try sql("UPDATE model_usage SET input_tokens = 2000000;")
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: database.path)
            try check(try scanner.loadReport().totalTokens == 2000000 && scanner.testingQueryCount == 5, "ctime must catch writes with restored modification time")
            let replacement = root.appendingPathComponent("replacement")
            try FileManager.default.copyItem(at: database, to: replacement)
            try FileManager.default.removeItem(at: database)
            try FileManager.default.moveItem(at: replacement, to: database)
            _ = try scanner.loadReport()
            try check(scanner.testingQueryCount == 6, "database replacement must invalidate")
            try FileManager.default.removeItem(at: database)
            try check(try scanner.loadReport().totalTokens == 0, "removed database must clear usage")
            let writer = Process()
            let input = Pipe()
            writer.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            writer.arguments = [database.path]
            writer.standardInput = input
            writer.standardOutput = FileHandle.nullDevice
            writer.standardError = FileHandle.nullDevice
            try writer.run()
            defer {
                try? input.fileHandleForWriting.close()
                if writer.isRunning { writer.terminate() }
                writer.waitUntilExit()
            }
            func commit(_ sql: String, marker: String) throws {
                let ready = root.appendingPathComponent(marker)
                let command = sql + "\n.shell /usr/bin/touch '" + ready.path + "'\n"
                try input.fileHandleForWriting.write(contentsOf: Data(command.utf8))
                try check(wait { FileManager.default.fileExists(atPath: ready.path) }, "WAL writer did not commit")
            }
            try commit("PRAGMA journal_mode=WAL; CREATE TABLE model_usage (status TEXT, started_at INTEGER, model_id TEXT, input_tokens INTEGER, cache_read_input_tokens INTEGER, cache_creation_input_tokens INTEGER, output_tokens INTEGER); INSERT INTO model_usage VALUES ('completed', 1792886400000, 'fixture', 1000000, 0, 0, 0);", marker: "ready")
            let walScanner = ZCodeUsageScanner(environment: environment)
            try check(try walScanner.loadReport().totalTokens == 1000000, "initial WAL usage missing")
            let mainDate = try FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as! Date
            try commit("UPDATE model_usage SET input_tokens=3000000;", marker: "updated")
            try check(try FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as? Date == mainDate, "fixture must change only WAL")
            try check(try walScanner.loadReport().totalTokens == 3000000 && walScanner.testingQueryCount == 2, "WAL-only commit must invalidate and read fresh usage")
            try commit("PRAGMA wal_checkpoint(TRUNCATE);", marker: "checkpointed")
            try check(try walScanner.loadReport().totalTokens == 3000000 && walScanner.testingQueryCount == 3, "checkpoint must invalidate without losing usage")
        }
    }

    private static func accountReadWrites() throws {
        try withHome { root, environment in
            let controller = ConfigProfileController(environment: environment)
            let live = root.appendingPathComponent(".codex/auth.json")
            func auth(_ refresh: String) throws -> Data {
                try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["email": "fixture@example.invalid", "refresh_token": refresh]])
            }
            try auth("synthetic-one").write(to: live)
            _ = try controller.saveCurrentOfficialLoginAsSelectedAccount()
            let accountURL = try controller.officialAuthURL(for: controller.selectedOfficialAccount()!)
            let databaseURL = controller.officialAccountsDatabaseURL
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            for file in [accountURL, databaseURL] { try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path) }
            let before = try controller.selectedOfficialAccount()!.lastUsedAt
            for _ in 0..<5 { _ = try controller.officialAccounts() }
            for file in [accountURL, databaseURL] {
                try check(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == stamp, "unchanged menu reads must not rewrite credentials or account database")
            }
            try auth("synthetic-rotated").write(to: live)
            _ = try controller.officialAccounts()
            try check(controller.officialAuthRefreshToken(from: controller.readAuthJSON(from: accountURL)) == "synthetic-rotated", "credential rotation must persist")
            try check(try controller.selectedOfficialAccount()!.lastUsedAt == before, "pure sync must not pretend the account was explicitly applied")
        }
    }

    private static func compatibility() throws {
        try withHome { _, environment in
            let controller = ConfigProfileController(environment: environment)
            let text = "model_provider = \"one\"\n[model_providers.one]\nname = \"old\"\n# name note\nbase_url = \"https://old.invalid\"\n# url note\nexperimental_bearer_token = \"synthetic\"\n# token note\nextra = \"\"\"first\nsecond\"\"\"\n"
            let updated = controller.generateConfig(text, selecting: ConfigProfile(id: "fixture", name: "new", baseURL: "https://new.invalid", apiKey: "synthetic-new"))
            try check(["# name note", "# url note", "# token note", "second"].allSatisfy { updated.contains($0) }, "managed keys must not swallow adjacent comments or unknown multiline values")
        }
    }

    private static func usageScheduling() throws {
        try withHome { _, environment in
            let store = MoaUsagePricingCatalogStore(environment: environment)
            let source = URL(string: "https://fixture.invalid/prices")!
            _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: source.absoluteString, fetchedAt: Date(), models: ["codex": ["fixture": MoaUsageRemotePricing(inputUSDPerMillion: 1, outputUSDPerMillion: 1)]]))
            try store.recordSuccessfulCheck(at: Date())
            let updater = MoaUsagePricingUpdateCoordinator(updater: MoaUsagePricingUpdater(store: store, sourceURL: source))
            let coordinator = MoaUsageCoordinator(codexScanner: CodexUsageScanner(environment: environment), claudeScanner: ClaudeUsageScanner(environment: environment), zcodeScanner: ZCodeUsageScanner(environment: environment), workbuddyScanner: WorkBuddyUsageScanner(environment: environment), workbuddyCNScanner: WorkBuddyUsageScanner(environment: environment, edition: .china), pricingUpdateCoordinator: updater)
            defer { coordinator.stop() }
            let calls = UsageCalls()
            let summary = CodexUsageSummary(todayCostUSD: 0, totalCostUSD: 0, todayTokens: 0, totalTokens: 0, cacheHitPercent: 0, topModelName: nil, topModelTokens: 0, topModelPercent: 0, updatedAt: Date())
            for source in MoaUsageSource.allCases {
                coordinator.testingSetLoader(source) { force in calls.add(source, forced: force); return summary }
            }
            func pump(until predicate: () -> Bool) -> Bool {
                let end = Date().addingTimeInterval(3)
                while !predicate() && Date() < end {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                return predicate()
            }
            coordinator.needsFrequentRefresh = { $0 == .codex }
            coordinator.start()
            try check(pump { coordinator.testingInFlightCount == 0 }, "initial summaries did not finish")
            let start = Date()
            for minute in 1...10 {
                coordinator.refreshScheduled(now: start.addingTimeInterval(Double(minute) * 61))
                try check(pump { coordinator.testingInFlightCount == 0 }, "scheduled summaries did not finish")
            }
            try check(calls.count(.codex) == 11, "enabled alert source must refresh each minute")
            for source in MoaUsageSource.allCases where source != .codex {
                try check(calls.count(source) == 3, "idle sources should refresh every five minutes")
            }
            coordinator.testingSetLoader(.claude) { _ in throw Failure(message: "isolated source failure") }
            coordinator.refreshClaude(forceRefresh: true)
            coordinator.refreshWorkBuddy(forceRefresh: true)
            try check(pump { coordinator.testingInFlightCount == 0 }, "failure must not leave refresh state stuck")
            let blocked = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            coordinator.testingSetLoader(.codex) { force in
                calls.add(.codex, forced: force)
                blocked.signal()
                _ = release.wait(timeout: .now() + 3)
                return summary
            }
            var delivered = 0
            coordinator.onCodexSummaryLoaded = { _ in delivered += 1 }
            coordinator.refreshCodex(forceRefresh: false)
            try check(blocked.wait(timeout: .now() + 2) == .success, "blocked loader did not start")
            coordinator.refreshCodex(forceRefresh: true)
            coordinator.stop()
            release.signal()
            try check(pump { coordinator.testingInFlightCount == 0 }, "stopped loader did not drain")
            try check(delivered == 0, "stop must suppress stale callbacks")
            coordinator.testingSetLoader(.codex) { force in calls.add(.codex, forced: force); return summary }
            coordinator.start()
            try check(pump { coordinator.testingInFlightCount == 0 }, "restart did not load")
            NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
            try check(pump { coordinator.testingInFlightCount == 0 }, "data root refresh did not finish")
            try check(calls.forced(.codex) > 0 && calls.forced(.workbuddyCN) > 0, "root replacement must force all sources independently")
        }
    }

    private final class UsageCalls {
        private let lock = NSLock()
        private var counts: [MoaUsageSource: Int] = [:]
        private var forces: [MoaUsageSource: Int] = [:]
        func add(_ source: MoaUsageSource, forced: Bool) {
            lock.lock(); defer { lock.unlock() }
            counts[source, default: 0] += 1
            if forced { forces[source, default: 0] += 1 }
        }
        func count(_ source: MoaUsageSource) -> Int { lock.lock(); defer { lock.unlock() }; return counts[source, default: 0] }
        func forced(_ source: MoaUsageSource) -> Int { lock.lock(); defer { lock.unlock() }; return forces[source, default: 0] }
    }
}
