import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func rebuildProfileMenu() { mainMenuCoordinator.rebuildProfileMenu() }
    func rebuildZCodeMenu() { mainMenuCoordinator.rebuildZCodeMenu() }
    func providerPresetSubmenuItem(title: String, presets: [MoaProviderPreset]) -> NSMenuItem {
        mainMenuCoordinator.providerPresetSubmenuItem(title: title, presets: presets)
    }
    func rebuildClaudeDesktopProfilesMenu() { mainMenuCoordinator.rebuildClaudeDesktopProfilesMenu() }
    @objc func addProfileAction() { providerActionCoordinator.addProfileAction() }
    @objc func addProviderPresetAction(_ sender: NSMenuItem) { providerActionCoordinator.addProviderPresetAction(sender) }
    func addProviderPresetProfile(_ input: (name: String, baseURL: String, apiKey: String), preset: MoaProviderPreset) {
        providerActionCoordinator.addProviderPresetProfile(input, preset: preset)
    }
    @objc func testCodexActiveProviderAction() { providerActionCoordinator.testCodexActiveProviderAction() }
    func testCodexProvider(_ profile: ConfigProfile) async throws -> ProviderConnectionTestResult {
        try await providerActionCoordinator.testCodexProvider(profile)
    }
    @objc func copyCodexConfigAction() { providerActionCoordinator.copyCodexConfigAction() }
    func codexConfigSnippet(for profile: ConfigProfile) throws -> String { try providerActionCoordinator.codexConfigSnippet(for: profile) }
    func codexConfigSnippetContent(for readyProfile: ConfigProfile) -> String { providerActionCoordinator.codexConfigSnippetContent(for: readyProfile) }
    func codexProviderSnippetID(for profile: ConfigProfile) -> String { providerActionCoordinator.codexProviderSnippetID(for: profile) }
}
