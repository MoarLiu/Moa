import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func rebuildProfileMenu() { mainMenuCoordinator.rebuildProfileMenu() }
    func rebuildZCodeMenu() { mainMenuCoordinator.rebuildZCodeMenu() }
    func rebuildClaudeDesktopProfilesMenu() { mainMenuCoordinator.rebuildClaudeDesktopProfilesMenu() }
    @objc func addProfileAction() { providerActionCoordinator.addProfileAction() }
    @objc func testCodexActiveProviderAction() { providerActionCoordinator.testCodexActiveProviderAction() }
    func testCodexProvider(_ profile: ConfigProfile) async throws -> ProviderConnectionTestResult {
        try await providerActionCoordinator.testCodexProvider(profile)
    }
    @objc func copyCodexConfigAction() { providerActionCoordinator.copyCodexConfigAction() }
    func codexConfigSnippet(for profile: ConfigProfile) throws -> String { try providerActionCoordinator.codexConfigSnippet(for: profile) }
    func codexConfigSnippetContent(for readyProfile: ConfigProfile) -> String { providerActionCoordinator.codexConfigSnippetContent(for: readyProfile) }
    func codexProviderSnippetID(for profile: ConfigProfile) -> String { providerActionCoordinator.codexProviderSnippetID(for: profile) }
}
