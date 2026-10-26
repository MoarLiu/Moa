import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    @objc func showAllAccountsAction() { accountManagerWindow.show() }
    @objc func showUsageOverviewAction() { usageInsightsWindow.show() }
    @objc func refreshUsageAction() {
        if !usageInsightsWindow.refreshIfKey() { usageCoordinator.refreshAllUsage() }
    }

    func configureMenu() { mainMenuCoordinator.configureMenu() }
    func menuWillOpen(_ menu: NSMenu) { mainMenuCoordinator.menuWillOpen(menu) }
    func configureMoaDataMenu() { mainMenuCoordinator.configureMoaDataMenu() }
    func refreshStatus() { mainMenuCoordinator.refreshStatus() }
}
