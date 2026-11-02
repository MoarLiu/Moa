#if !MOA_TESTING
import AppKit
import XCTest
@testable import Moa

final class MoaWorkspaceTests: XCTestCase {
    func testCapabilityRoutingKeepsUnsupportedFeaturesAndEditionsSeparate() {
        XCTAssertNil(MoaWorkspaceClient.antigravity.usageSource)
        XCTAssertNil(MoaWorkspaceClient.deepseek.usageSource)
        XCTAssertTrue(MoaWorkspaceClient.zcode.groups.isEmpty)
        XCTAssertEqual(MoaWorkspaceClient.zcode.usageSource, .zcode)
        XCTAssertEqual(MoaWorkspaceClient.claude.groups, [.claude])
        XCTAssertEqual(MoaWorkspaceClient.codex.groups, [.codexOfficial, .codexConfig])
        XCTAssertNotEqual(MoaWorkspaceClient.workbuddy.bundleID, MoaWorkspaceClient.workbuddyCN.bundleID)
        XCTAssertNotEqual(MoaWorkspaceClient.workbuddy.usageSource, MoaWorkspaceClient.workbuddyCN.usageSource)
        XCTAssertNotEqual(MoaWorkspaceClient.workbuddy.operationClient, MoaWorkspaceClient.workbuddyCN.operationClient)
        XCTAssertEqual(MoaWorkspaceClient.workbuddy.logoName, MoaWorkspaceClient.workbuddyCN.logoName)
        let groups = MoaWorkspaceClient.allCases.flatMap(\.groups)
        XCTAssertEqual(Set(groups), Set(MoaAccountGroup.allCases))
        XCTAssertEqual(groups.count, Set(groups).count)
    }

    func testNavigationPreservesSpecificProviderAndUsageEntrypoints() {
        let navigation = MoaWorkspaceNavigation()
        navigation.showAccount(.codexConfig)
        XCTAssertEqual(navigation.destination, .client(.codex))
        XCTAssertEqual(navigation.accountGroup, .codexConfig)
        navigation.showAccount(.workbuddyCN)
        XCTAssertEqual(navigation.destination, .client(.workbuddyCN))
        navigation.showUsage(.workbuddyCN)
        XCTAssertEqual(navigation.destination, .usage)
        XCTAssertEqual(navigation.usageSource, .workbuddyCN)
        navigation.showUsage()
        XCTAssertNil(navigation.usageSource)
        let firstRequest = navigation.usageRequest
        navigation.showUsage()
        XCTAssertNotEqual(navigation.usageRequest, firstRequest,
                          "Repeated usage entry points must reset an independently changed report picker.")
    }

    func testUnknownUsageIsNotDisplayedAsZeroAndTotalsUseTodayOnly() throws {
        XCTAssertNil(MoaWorkspaceUsageTotal.make([:]))
        func summary(cost: Double, tokens: Int) -> CodexUsageSummary {
            CodexUsageSummary(todayCostUSD: cost, totalCostUSD: 999, todayTokens: tokens,
                              totalTokens: 999_999, cacheHitPercent: 40, topModelName: nil,
                              topModelTokens: 0, topModelPercent: 0, updatedAt: Date())
        }
        let total = try XCTUnwrap(MoaWorkspaceUsageTotal.make([
            .codex: summary(cost: 2.5, tokens: 100),
            .workbuddyCN: summary(cost: 1.25, tokens: 200)
        ]))
        XCTAssertEqual(total.costUSD, 3.75, accuracy: 0.0001)
        XCTAssertEqual(total.tokens, 300)
        XCTAssertEqual(total.loadedSources, 2)
    }

    @MainActor func testDataRootChangeDiscardsAnInFlightSummaryEvenIfTheNextScanFails() throws {
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-workspace-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = ["HOME": home.path]
        let store = MoaUsagePricingCatalogStore(environment: environment)
        let source = URL(string: "https://fixture.invalid/prices")!
        _ = try store.merge(MoaUsagePricingCatalogSnapshot(sourceURL: source.absoluteString, fetchedAt: Date(), models: [
            "codex": ["fixture": MoaUsageRemotePricing(inputUSDPerMillion: 1, outputUSDPerMillion: 1)]
        ]))
        try store.recordSuccessfulCheck(at: Date())
        let updater = MoaUsagePricingUpdateCoordinator(updater: MoaUsagePricingUpdater(store: store, sourceURL: source))
        let coordinator = MoaUsageCoordinator(
            codexScanner: CodexUsageScanner(environment: environment),
            claudeScanner: ClaudeUsageScanner(environment: environment),
            zcodeScanner: ZCodeUsageScanner(environment: environment),
            workbuddyScanner: WorkBuddyUsageScanner(environment: environment),
            workbuddyCNScanner: WorkBuddyUsageScanner(environment: environment, edition: .china),
            pricingUpdateCoordinator: updater
        )
        defer { coordinator.stop() }
        let summary = CodexUsageSummary(todayCostUSD: 123, totalCostUSD: 123, todayTokens: 456,
                                       totalTokens: 456, cacheHitPercent: 0, topModelName: nil,
                                       topModelTokens: 0, topModelPercent: 0, updatedAt: Date())
        for source in MoaUsageSource.allCases {
            coordinator.testingSetLoader(source) { _ in summary }
        }
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        coordinator.testingSetLoader(.codex) { _ in
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return summary
        }
        var delivered = 0
        coordinator.onCodexSummaryLoaded = { _ in delivered += 1 }
        coordinator.start()
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        coordinator.testingSetLoader(.codex) { _ in
            throw NSError(domain: "MoaWorkspaceFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "new root unavailable"])
        }
        NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
        release.signal()
        let deadline = Date().addingTimeInterval(4)
        while coordinator.testingInFlightCount > 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(coordinator.testingInFlightCount, 0)
        XCTAssertNil(coordinator.workspaceSummaries[.codex], "An old root's cost must not reappear as the new root's data.")
        XCTAssertEqual(coordinator.workspaceFailures[.codex], "new root unavailable")
        XCTAssertEqual(delivered, 0, "Stale scans must not trigger usage alerts either.")
    }

    @MainActor func testBundledDesignAssetsDecodeWithoutRemoteOrInstalledAppDependencies() throws {
        for client in MoaWorkspaceClient.allCases {
            let url = try XCTUnwrap(MoaUIResources.url(client.logoName, folder: "Brands", extension: "png"))
            XCTAssertTrue(url.isFileURL)
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertEqual(image.size.width / image.size.height, 1, accuracy: 0.001)
        }
        for name in ["overview", "usage", "settings", "account"] {
            let image = try XCTUnwrap(MoaUIResources.image(name, folder: "Navigation", extension: "svg"))
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }
}
#endif
