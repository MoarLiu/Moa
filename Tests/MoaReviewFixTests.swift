#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class MoaReviewFixTests: XCTestCase {
    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-review-fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    func testBackupsWithinOneSecondKeepTheEarlierLogin() throws {
        try withHome { home in
            let controller = ConfigProfileController(environment: ["HOME": home.path])
            try FileManager.default.createDirectory(at: controller.codexAuthURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var contents: [String] = []
            // Several rounds, so at least two always share a second-resolution stamp.
            for round in 0..<4 {
                let text = #"{"tokens":{"id_token":"login-\#(round)"}}"#
                contents.append(text)
                try Data(text.utf8).write(to: controller.codexAuthURL)
                try controller.backupCodexFiles()
            }
            let backups = try FileManager.default.contentsOfDirectory(at: controller.backupDir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("auth.json.") }
            let saved = Set(try backups.map { try String(contentsOf: $0, encoding: .utf8) })
            XCTAssertEqual(saved, Set(contents))
        }
    }

    func testBlankCacheFieldsOnUnknownModelsUseTheCustomInputPrice() throws {
        try withHome { home in
            let controller = MoaUsagePricingOverrideController(environment: ["HOME": home.path])
            let model = "review-fixture-unknown-model"
            for source in [MoaUsageSource.codex, .claude, .zcode] {
                try controller.upsert(source: source, model: model, inputUSDPerMillion: 0.2,
                                      outputUSDPerMillion: 0.8, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
            }
            // Codex input includes cached tokens: 100k prompt, all at $0.20/M.
            let codex = try XCTUnwrap(controller.codexCostEstimate(model: model, inputTokens: 100_000, cachedInputTokens: 90_000, outputTokens: 0))
            XCTAssertEqual(codex.costUSD, 0.02, accuracy: 1e-12)
            // Claude and ZCode pass cache tokens separately: 10k + 60k + 30k.
            let claude = try XCTUnwrap(controller.claudeCostEstimate(model: model, inputTokens: 10_000, cacheReadInputTokens: 60_000,
                                                                      cacheCreationInputTokens: 30_000, outputTokens: 0))
            XCTAssertEqual(claude.costUSD, 0.02, accuracy: 1e-12)
            let zcode = try XCTUnwrap(controller.zcodeCostEstimate(model: model, inputTokens: 10_000, cacheReadInputTokens: 60_000,
                                                                    cacheCreationInputTokens: 30_000, outputTokens: 0))
            XCTAssertEqual(zcode.costUSD, 0.02, accuracy: 1e-12)
        }
    }

    func testZCodeRowsUseTheReportDayKey() throws {
        try withHome { home in
            let database = home.appendingPathComponent(".zcode/cli/db/db.sqlite")
            try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
            let now = Date()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [database.path, """
            create table model_usage (status text, started_at integer, model_id text, input_tokens integer, cache_read_input_tokens integer, cache_creation_input_tokens integer, output_tokens integer);
            insert into model_usage values ('completed',\(Int64(now.timeIntervalSince1970 * 1000)),'glm-fixture',1000,0,0,100);
            """]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)

            let report = try ZCodeUsageScanner(environment: ["HOME": home.path]).loadReport()
            XCTAssertEqual(report.rows.map(\.dayKey), [MoaUsageReport.dayKey(from: now)])
            XCTAssertEqual(report.filtered(source: nil, recentDays: 1, now: now).rows.count, 1)
        }
    }
}
#endif
