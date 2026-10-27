#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class CodexMigrationSafetyTests: XCTestCase {
    private enum InjectedFailure: Error { case stopped }

    private func fixture() throws -> (URL, URL, ConfigProfileController) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moa-migration-\(UUID().uuidString)'s")
        let home = root.appendingPathComponent(".codex")
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("a.jsonl")
        try Data("{\"payload\":{\"model_provider\":\"old\"}}\n".utf8).write(to: file)
        return (root, file, ConfigProfileController(environment: ["HOME": root.path, "CODEX_HOME": home.path]))
    }

    func testRollbackKeepsSessionsCreatedAfterBackup() throws {
        let (root, file, controller) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: file)
        let newSession = file.deletingLastPathComponent().appendingPathComponent("new.jsonl")
        var checks = 0
        XCTAssertThrowsError(try controller.migrateCodexSessionModelProvider(to: "new") {
            checks += 1
            if checks == 3 {
                try Data("new session".utf8).write(to: newSession)
                throw InjectedFailure.stopped
            }
        })
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try Data(contentsOf: newSession), Data("new session".utf8))
    }

    func testRollbackDoesNotOverwriteConcurrentChanges() throws {
        let (root, file, controller) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let concurrent = Data("newly written data".utf8)
        var checks = 0
        XCTAssertThrowsError(try controller.migrateCodexSessionModelProvider(to: "new") {
            checks += 1
            if checks == 3 {
                try concurrent.write(to: file)
                throw InjectedFailure.stopped
            }
        }) { error in
            guard let migrationError = error as? CodexSessionProviderMigrationError,
                  case .migrationFailedRollbackFailed = migrationError else {
                return XCTFail("Expected rollback conflict, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), concurrent)
    }

    func testKnownCodexProcessesAreDetected() {
        XCTAssertTrue(CodexAppController.isCodexProcessCommand("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        XCTAssertTrue(CodexAppController.isCodexProcessCommand("/opt/bin/codex-aarch64-apple-darwin"))
        XCTAssertFalse(CodexAppController.isCodexProcessCommand("/usr/bin/sqlite3"))
    }

    func testSQLiteFailureRollsBackBothDatabasesAndSessionFiles() throws {
        let (root, file, controller) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = file.deletingLastPathComponent().deletingLastPathComponent()
        let main = home.appendingPathComponent("state_5.sqlite")
        let nested = home.appendingPathComponent("sqlite/state_5.sqlite")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sqlite(main, "CREATE TABLE threads(model_provider TEXT); INSERT INTO threads VALUES('old');")
        try sqlite(nested, "CREATE TABLE threads(model_provider TEXT); INSERT INTO threads VALUES('old'); CREATE TRIGGER fail_update BEFORE UPDATE ON threads BEGIN SELECT RAISE(ABORT, 'injected'); END;")
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try controller.migrateCodexSessionModelProvider(to: "new"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try sqlite(main, "SELECT model_provider FROM threads;"), "old")
        XCTAssertEqual(try sqlite(nested, "SELECT model_provider FROM threads;"), "old")
    }

    @discardableResult
    private func sqlite(_ url: URL, _ sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-bail", url.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InjectedFailure.stopped }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
