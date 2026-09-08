import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func configureMenu() { mainMenuCoordinator.configureMenu() }
    func menuWillOpen(_ menu: NSMenu) { mainMenuCoordinator.menuWillOpen(menu) }
    func configureMoaDataMenu() { mainMenuCoordinator.configureMoaDataMenu() }
    func refreshStatus() { mainMenuCoordinator.refreshStatus() }

    func restoreActiveProviderBridgeIfNeeded() {
        guard profileController.isProviderBridgeModeSelected() else {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let result = Result {
                let profile = try self.preparedProviderBridgeRuntimeProfile()
                let running = try self.ensureProviderBridge(for: profile)
                return try self.profileController.applyProviderBridgeGateway(profile: running)
            }

            DispatchQueue.main.async {
                switch result {
                case .success(let runningProfile):
                    self.providerBridgeLastErrorSummary = ""
                    self.rebuildCodexProviderMenus()
                    self.statusItemText.title = Self.statusTitle(
                        "Bridge ready: %@ · :%d",
                        runningProfile.name,
                        self.providerBridgeServer.snapshot().port ?? runningProfile.resolvedBridgePort
                    )
                case .failure(let error):
                    self.providerBridgeLastErrorSummary = error.localizedDescription
                    self.rebuildCodexProviderMenus()
                    self.statusItemText.title = Self.statusTitle("Bridge failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @discardableResult
    func ensureProviderBridge(for profile: ConfigProfile) throws -> ConfigProfile {
        guard profile.usesLocalProviderBridge else {
            return profile
        }

        let snapshot = providerBridgeServer.snapshot()
        let tokenHashPrefix = profile.bridgeToken.map { MoaProviderBridgeToken.sha256Prefix($0) }
        if snapshot.isRunning,
           snapshot.profileID == profile.id,
           snapshot.tokenHashPrefix == tokenHashPrefix {
            return profile
        }

        let port = try providerBridgeServer.start(configuration: MoaProviderBridgeServerConfiguration(profile: profile))
        guard port != profile.resolvedBridgePort else {
            return profile
        }

        do {
            return try providerBridgeProfileController.updateBridgeRuntime(id: profile.id, port: port)
        } catch {
            providerBridgeServer.stop()
            throw error
        }
    }

    func stopProviderBridge() {
        providerBridgeServer.stop()
        rebuildCodexProviderMenus()
        statusItemText.title = Self.statusTitle("Provider Bridge stopped")
    }

    @objc func toggleFastModeAction(_ sender: NSMenuItem) {
        applyFastMode(sender.state != .on)
    }

    @objc func openRemoteConnectionsSettingsAction() {
        controller.openRemoteConnectionsSettings()
    }
}
