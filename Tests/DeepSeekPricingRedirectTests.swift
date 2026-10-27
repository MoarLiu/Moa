import Foundation
import XCTest
@testable import Moa

final class DeepSeekPricingRedirectTests: XCTestCase {
    func testRetiredIDsUseCurrentFlashPriceWithoutChangingIndependentSKUPrecedence() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-price-redirect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = MoaUsagePricingCatalogStore(environment: ["HOME": home.path])
        let fetchedAt = ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!
        let obsolete = MoaUsageRemotePricing(inputUSDPerMillion: 8, outputUSDPerMillion: 16)
        let flash = MoaUsageRemotePricing(inputUSDPerMillion: 0.45, outputUSDPerMillion: 1.8)
        let grok = MoaUsageRemotePricing(inputUSDPerMillion: 7, outputUSDPerMillion: 21)
        let oldIDs = ["deepseek-v4-flash", "deepseek-v4-flash-vision-exp"]

        _ = try store.merge(.init(sourceURL: "https://example.invalid", fetchedAt: fetchedAt, models: ["all": [
            oldIDs[0]: obsolete, oldIDs[1]: obsolete,
            "deepseek/deepseek-v4-flash": obsolete, "grok-4.7-build": grok
        ]]))
        for model in oldIDs + ["deepseek/deepseek-v4-flash"] {
            XCTAssertEqual(MoaUsagePricing.catalogPricing(source: .workbuddy, model: model, store: store)?.inputUSDPerMillion, 0.30)
        }
        XCTAssertEqual(MoaUsagePricing.catalogPricing(source: .workbuddy, model: "grok-4.7-build", store: store)?.inputUSDPerMillion, 7)

        _ = try store.merge(.init(sourceURL: "https://example.invalid", fetchedAt: fetchedAt.addingTimeInterval(1), models: ["all": ["deepseek-flash": flash]]))
        for model in oldIDs + ["deepseek/deepseek-v4-flash"] {
            XCTAssertEqual(MoaUsagePricing.catalogPricing(source: .workbuddy, model: model, store: store)?.inputUSDPerMillion, 0.45)
        }
    }
}
