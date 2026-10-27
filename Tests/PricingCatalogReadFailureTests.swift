#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class PricingCatalogReadFailureTests: XCTestCase {
    func testUnreadableCatalogIsRetriedAndNeverOverwrittenByMerge() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-catalog-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let writer = MoaUsagePricingCatalogStore(environment: environment)
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let original = MoaUsageRemotePricing(inputUSDPerMillion: 2, outputUSDPerMillion: 3)
        let added = MoaUsageRemotePricing(inputUSDPerMillion: 4, outputUSDPerMillion: 5)
        _ = try writer.merge(.init(sourceURL: "https://example.invalid", fetchedAt: fetchedAt, models: ["all": ["original": original]]))
        let path = home.appendingPathComponent(".moa/usage-pricing-catalog-v1.json")
        let before = try Data(contentsOf: path)
        let reader = MoaUsagePricingCatalogStore(environment: environment)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path) }
        XCTAssertNil(reader.pricing(source: .codex, model: "original"))
        let update = MoaUsagePricingCatalogSnapshot(sourceURL: "https://example.invalid", fetchedAt: fetchedAt.addingTimeInterval(1), models: ["all": ["added": added]])
        XCTAssertThrowsError(try reader.merge(update))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(reader.pricing(source: .codex, model: "original")?.inputUSDPerMillion, 2)
        _ = try reader.merge(update)
        XCTAssertEqual(reader.pricing(source: .codex, model: "original")?.inputUSDPerMillion, 2)
        XCTAssertEqual(reader.pricing(source: .codex, model: "added")?.inputUSDPerMillion, 4)
    }
}
#endif
