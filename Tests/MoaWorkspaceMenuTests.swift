#if !MOA_TESTING
import AppKit
import XCTest
@testable import Moa

final class MoaWorkspaceMenuTests: XCTestCase {
    func testInstalledClientsComeFirstAndUnknownDetectionKeepsTheOriginalOrder() {
        let all = MoaWorkspaceClient.allCases
        // Nothing detected, or everything: no client is singled out as missing.
        for installed in [Set<MoaWorkspaceClient>(), Set(all)] {
            let ordered = MoaClientInstallation.orderedClients(installed)
            XCTAssertEqual(ordered.map(\.client), all)
            XCTAssertTrue(ordered.allSatisfy(\.present))
        }
        let ordered = MoaClientInstallation.orderedClients([.zcode, .claude])
        XCTAssertEqual(ordered.map(\.client), [.claude, .zcode, .codex, .antigravity, .deepseek, .workbuddyCN, .workbuddy])
        XCTAssertEqual(ordered.map(\.present), [true, true, false, false, false, false, false])
    }

    @MainActor func testMenuKeepsEveryClientReachableWhenFoldingMissingOnes() {
        _ = NSApplication.shared
        MoaRuntimeMode.suppressesUserInteraction = true
        let app = AppDelegate()
        app.mainMenuCoordinator.configureMenu()
        let clientItems = [app.codexProfilesItem, app.claudeDesktopProfilesItem, app.zcodeItem, app.workbuddyCNItem,
                           app.workbuddyItem, app.deepseekCoordinator.item, app.antigravityCoordinator.item]
        let installed = MoaClientInstallation.installed()
        let folds = !installed.isEmpty && installed.count < clientItems.count

        for pass in 0..<2 {
            // Arranging again, as every menu opening does, must not duplicate or drop items.
            if pass == 1 { app.mainMenuCoordinator.arrangeClientItems() }
            let top = app.menu.items
            let other = top.first { $0.submenu?.title == MoaL10n.text("Other Clients") }
            let folded = other?.submenu?.items ?? []
            for item in clientItems {
                let places = top.filter { $0 === item }.count + folded.filter { $0 === item }.count
                XCTAssertEqual(places, 1, "\(item.title) must appear exactly once")
                XCTAssertNotNil(item.submenu, "\(item.title) keeps its own submenu")
            }
            XCTAssertEqual(other != nil, folds)
            XCTAssertEqual(folded.count, folds ? clientItems.count - installed.count : 0)
            // The client block stays between the status row and the Accounts entry.
            let indexes = top.enumerated().filter { entry in clientItems.contains { $0 === entry.element } }.map(\.offset)
            if let first = indexes.first, let last = indexes.last {
                XCTAssertEqual(last - first + 1, indexes.count, "client items stay contiguous")
            }
        }
    }
}
#endif
