#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class ClaudeUsageCacheRegressionTests: XCTestCase {
    private func fixture() throws -> (URL, URL, [String: String]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moa-claude-cache-\(UUID().uuidString)")
        let projects = root.appendingPathComponent(".claude/projects/project", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let log = projects.appendingPathComponent("session.jsonl")
        let record = #"{"type": "assistant", "timestamp": "2026-10-27T00:30:00Z", "message": {"id": "message-1", "model": "claude-sonnet-4-6", "usage": {"input_tokens": 10, "output_tokens": 5}}}"#
        try (record + "\n").write(to: log, atomically: true, encoding: .utf8)
        return (root, log, ["HOME": root.path])
    }

    func testCachedDaysRecomputeWhenTimeZoneChanges() throws {
        let (root, _, environment) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let scanner = ClaudeUsageScanner(environment: environment, calendarProvider: { calendar })
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-27T00:30:00Z"))

        let first = try scanner.loadReport(now: now)
        XCTAssertEqual(first.rows.map(\.dayKey), ["2026-10-27"])
        XCTAssertEqual(first.totalTokens, 15)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3600))
        let second = try scanner.loadReport(now: now)
        XCTAssertEqual(second.rows.map(\.dayKey), ["2026-10-26"])
        XCTAssertEqual(try scanner.loadSummary(now: now).todayTokens, 15)
    }

    func testReadFailureDoesNotCachePartialResultsAndCanRetry() throws {
        let (root, _, environment) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = ClaudeUsageScanner(environment: environment)
        scanner.testingBeforeScan = { _ in throw CocoaError(.fileReadNoPermission) }
        XCTAssertThrowsError(try scanner.loadReport())
        scanner.testingBeforeScan = nil
        XCTAssertEqual(try scanner.loadReport().totalTokens, 15)
    }
}
#endif
