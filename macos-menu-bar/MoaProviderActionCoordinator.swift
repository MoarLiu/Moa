import AppKit
import Foundation
import SwiftUI

final class MoaProviderActionCoordinator {
    unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
    }

    var profileController: ConfigProfileController { app.profileController }
    var statusItemText: NSMenuItem { app.statusItemText }

    func rebuildCodexProviderMenus() { app.rebuildCodexProviderMenus() }
    func showError(_ message: String) { app.showError(message) }
    func showAddProfilePanel() -> (name: String, baseURL: String, apiKey: String)? { app.showAddProfilePanel() }
    func copyToPasteboard(_ text: String) { app.copyToPasteboard(text) }

    func addProfileAction() {
        guard let input = showAddProfilePanel() else {
            return
        }

        do {
            _ = try profileController.addProfile(name: input.name, baseURL: input.baseURL, apiKey: input.apiKey)
            rebuildCodexProviderMenus()
            statusItemText.title = AppDelegate.statusTitle("Added %@", input.name)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func testCodexActiveProviderAction() {
        guard let profile = try? profileController.selectedProfile() else {
            showError(MoaL10n.text("Select a configuration before testing."))
            return
        }

        statusItemText.title = AppDelegate.statusTitle("Testing %@...", profile.name)
        Task.detached { [weak self] in
            guard let self else { return }
            let result: Result<ProviderConnectionTestResult, Error>
            do {
                result = .success(try await self.testCodexProvider(profile))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                switch result {
                case .success(let testResult):
                    self.rebuildCodexProviderMenus()
                    self.statusItemText.title = AppDelegate.statusTitle("Connection works: %@", testResult.model)
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Connection works"),
                        informativeText: MoaL10n.format("Model: %@\nEndpoint: %@", testResult.model, testResult.endpoint),
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.rebuildCodexProviderMenus()
                    self.statusItemText.title = AppDelegate.statusTitle("Connection test failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    func testCodexProvider(_ profile: ConfigProfile) async throws -> ProviderConnectionTestResult {
        try await ProviderConnectionTester.testCodex(
            baseURL: profile.baseURL,
            apiKey: profile.apiKey,
            modelOverride: profile.resolvedTestModel
        )
    }

    func copyCodexConfigAction() {
        guard let profile = try? profileController.selectedProfile() else {
            showError(MoaL10n.text("Select a configuration before copying."))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try self.codexConfigSnippet(for: profile)
            }

            DispatchQueue.main.async {
                switch result {
                case .success(let snippet):
                    self.copyToPasteboard(snippet)
                    self.rebuildCodexProviderMenus()
                    self.statusItemText.title = AppDelegate.statusTitle("Codex config copied")
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Codex config copied"),
                        informativeText: MoaL10n.text("The selected Codex provider config snippet is on the clipboard."),
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = AppDelegate.statusTitle("Failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    func codexConfigSnippet(for profile: ConfigProfile) throws -> String {
        codexConfigSnippetContent(for: profile)
    }

    func codexConfigSnippetContent(for readyProfile: ConfigProfile) -> String {
        let providerID = codexProviderSnippetID(for: readyProfile)
        let model = readyProfile.resolvedModel
            ?? readyProfile.resolvedTestModel
            ?? ProviderConnectionTester.codexTestModel
        let block = MoaCodexConfigEditor.providerBlock(
            providerID: providerID,
            displayName: readyProfile.name,
            baseURL: readyProfile.baseURL,
            apiKey: readyProfile.apiKey,
            extraLines: []
        )

        return """
        model = "\(AppDelegate.tomlEscaped(model))"
        model_provider = "\(AppDelegate.tomlEscaped(providerID))"

        \(block)
        """
    }

    func codexProviderSnippetID(for profile: ConfigProfile) -> String {
        let slug = AppDelegate.identifierSlug(profile.name)
        return slug.isEmpty ? "moa-provider" : "moa-\(slug)"
    }
}
