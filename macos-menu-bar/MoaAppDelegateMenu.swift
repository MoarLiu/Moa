import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    @objc func showWorkspaceAction() { workspaceWindow.show(.overview) }
    @objc func showAllAccountsAction() { accountManagerWindow.show() }
    @objc func showUsageOverviewAction() {
        workspaceWindow.navigation.showUsage()
        workspaceWindow.show()
    }
    @objc func refreshUsageAction() {
        if workspaceWindow.isKey {
            workspaceWindow.refresh()
            return
        }
        if !usageInsightsWindow.refreshIfKey() { usageCoordinator.refreshAllUsage() }
    }

    func configureMenu() { mainMenuCoordinator.configureMenu() }
    func menuWillOpen(_ menu: NSMenu) { mainMenuCoordinator.menuWillOpen(menu) }
    func configureMoaDataMenu() { mainMenuCoordinator.configureMoaDataMenu() }
    func refreshStatus() { mainMenuCoordinator.refreshStatus() }
}
