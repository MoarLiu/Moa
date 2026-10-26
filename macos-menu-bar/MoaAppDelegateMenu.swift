import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func configureMenu() { mainMenuCoordinator.configureMenu() }
    func menuWillOpen(_ menu: NSMenu) { mainMenuCoordinator.menuWillOpen(menu) }
    func configureMoaDataMenu() { mainMenuCoordinator.configureMoaDataMenu() }
    func refreshStatus() { mainMenuCoordinator.refreshStatus() }

    @objc func toggleFastModeAction(_ sender: NSMenuItem) {
        applyFastMode(sender.state != .on)
    }

    @objc func openRemoteConnectionsSettingsAction() {
        controller.openRemoteConnectionsSettings()
    }
}
