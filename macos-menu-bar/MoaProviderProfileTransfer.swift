import AppKit
import Foundation
import UniformTypeIdentifiers

enum MoaProviderProfileTransfer {
    static func exportProfiles(
        groupName: String,
        suggestedFileName: String,
        exporter: (Bool) throws -> Data
    ) -> Result<Void, Error>? {
        guard let includeAPIKeys = profileExportAPIKeyChoice(groupName: groupName) else {
            return nil
        }

        let panel = NSSavePanel()
        panel.title = String(format: MoaL10n.text("Export %@ Profiles"), groupName)
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let data = try exporter(includeAPIKeys)
            try MoaSecureFile.write(data, to: url)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func importProfiles(
        groupName: String,
        importer: (Data) throws -> Int
    ) -> Result<Int, Error>? {
        let panel = NSOpenPanel()
        panel.title = String(format: MoaL10n.text("Import %@ Profiles"), groupName)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return .success(try importer(data))
        } catch {
            return .failure(error)
        }
    }

    private static func profileExportAPIKeyChoice(groupName: String) -> Bool? {
        let choice = MoaNonBlockingAlert.choose(
            messageText: String(format: MoaL10n.text("Export %@ Profiles"), groupName),
            informativeText: MoaL10n.text("API keys are excluded by default and this is best for migrating configuration structure. Include API keys only when you trust the destination."),
            primaryButtonTitle: MoaL10n.text("Exclude API Keys"),
            secondaryButtonTitle: MoaL10n.text("Include API Keys"),
            cancelButtonTitle: MoaL10n.text("Cancel"),
            tone: .info
        )

        switch choice {
        case .primary:
            return false
        case .secondary:
            return true
        case .cancel:
            return nil
        }
    }
}
