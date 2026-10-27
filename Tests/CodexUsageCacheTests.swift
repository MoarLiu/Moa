#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class CodexUsageCacheTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-codex-cache-\(UUID().uuidString)")
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("session.jsonl")
        let line = #"{"timestamp":"2026-01-01T00:30:00Z","type":"token_usage_record","payload":{"model":"gpt-5.5","response_id":"one","usage":{"input_tokens":100,"output_tokens":10}}}"#
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
        return (home, file)
    }

    func testTimezoneChangeInvalidatesPersistedDays() throws {
        let (home, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let scanner = CodexUsageScanner(environment: ["HOME": home.path], calendarProvider: { calendar })
        XCTAssertEqual(try scanner.loadReport().rows.first?.dayKey, "2026-01-01")
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(try scanner.loadReport().rows.first?.dayKey, "2025-12-31")
        let reloaded = CodexUsageScanner(environment: ["HOME": home.path], calendarProvider: { calendar })
        XCTAssertEqual(try reloaded.loadReport().rows.first?.dayKey, "2025-12-31")
    }

    func testReadFailureDoesNotCacheIncompleteUsage() throws {
        let (home, file) = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = CodexUsageScanner(environment: ["HOME": home.path])
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        XCTAssertThrowsError(try scanner.loadReport())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertEqual(try scanner.loadReport().totalTokens, 110)
    }
}
#endif
