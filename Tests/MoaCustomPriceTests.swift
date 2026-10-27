#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class MoaCustomPriceTests: XCTestCase {
    func testPriceInputsPreservePrecisionAndDistinguishBlankFromInvalid() throws {
        let original = 0.000012345678901234
        let prices = try MoaCustomPrices.parse(input: String(original), output: "", cacheRead: "0", cacheCreation: " ")
        XCTAssertEqual(prices.input, original)
        XCTAssertEqual(prices.output, 0)
        XCTAssertEqual(prices.cacheRead, 0)
        XCTAssertNil(prices.cacheCreation)

        for invalid in ["1x", "-1", "nan", "inf"] {
            XCTAssertThrowsError(try MoaCustomPrices.parse(input: "1", output: invalid, cacheRead: "", cacheCreation: "")) {
                XCTAssertEqual($0 as? MoaCustomPriceError, .invalidField(.output))
            }
            XCTAssertThrowsError(try MoaCustomPrices.parse(input: "1", output: "0", cacheRead: invalid, cacheCreation: "")) {
                XCTAssertEqual($0 as? MoaCustomPriceError, .invalidField(.cacheRead))
            }
        }
        XCTAssertThrowsError(try MoaCustomPrices.parse(input: "", output: "0", cacheRead: "", cacheCreation: "")) {
            XCTAssertEqual($0 as? MoaCustomPriceError, .noPositivePrice)
        }
    }

    func testRejectedPriceCannotOverwriteStoredPrice() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-price-validation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = MoaUsagePricingOverrideController(environment: ["HOME": home.path])
        try controller.upsert(source: .codex, model: "test", inputUSDPerMillion: 0.000012345678901234,
                              outputUSDPerMillion: 1, cacheReadUSDPerMillion: 0, cacheCreationUSDPerMillion: nil)
        let before = try XCTUnwrap(controller.override(source: .codex, model: "test"))
        XCTAssertThrowsError(try controller.upsert(source: .codex, model: "test", inputUSDPerMillion: -1,
                                                    outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil))
        XCTAssertThrowsError(try controller.upsert(source: .codex, model: "test", inputUSDPerMillion: 1,
                                                    outputUSDPerMillion: 1, cacheReadUSDPerMillion: .infinity, cacheCreationUSDPerMillion: nil))
        XCTAssertEqual(controller.override(source: .codex, model: "test"), before)
        let reloaded = MoaUsagePricingOverrideController(environment: ["HOME": home.path])
        let restored = try XCTUnwrap(reloaded.override(source: .codex, model: "test"))
        XCTAssertEqual(restored.inputUSDPerMillion, before.inputUSDPerMillion)
        XCTAssertEqual(restored.outputUSDPerMillion, before.outputUSDPerMillion)
        XCTAssertEqual(restored.cacheReadUSDPerMillion, before.cacheReadUSDPerMillion)
    }

    func testCorruptPriceFileIsNotOverwrittenAndCanBeRetried() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-price-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let controller = MoaUsagePricingOverrideController(environment: ["HOME": home.path])
        try controller.upsert(source: .codex, model: "test", inputUSDPerMillion: 2,
                              outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil)
        let file = home.appendingPathComponent(".moa/usage-pricing-overrides.json")
        let valid = try Data(contentsOf: file)
        let broken = Data("{invalid".utf8)
        try broken.write(to: file)
        let corruptedController = MoaUsagePricingOverrideController(environment: ["HOME": home.path])
        XCTAssertTrue(corruptedController.overrides().isEmpty)
        XCTAssertThrowsError(try corruptedController.upsert(source: .codex, model: "other", inputUSDPerMillion: 1,
                                                             outputUSDPerMillion: 1, cacheReadUSDPerMillion: nil, cacheCreationUSDPerMillion: nil))
        XCTAssertThrowsError(try corruptedController.remove(source: .codex, model: "test"))
        XCTAssertEqual(try Data(contentsOf: file), broken)
        try valid.write(to: file)
        XCTAssertEqual(corruptedController.override(source: .codex, model: "test")?.inputUSDPerMillion, 2)
    }
}
#endif
