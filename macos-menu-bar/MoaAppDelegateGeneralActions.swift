import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    @objc func updatePricesAction() {
        guard !usageCoordinator.isUpdatingPrices else { return }
        statusItemText.title = Self.statusTitle("Updating Prices…")
        usageCoordinator.updatePrices { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.statusItemText.title = Self.statusTitle("Prices Updated")
                MoaNonBlockingAlert.present(
                    messageText: MoaL10n.text("Prices Updated"),
                    informativeText: MoaL10n.format("Fetched pricing data for %d models. Usage estimates are refreshing; your custom prices are unchanged.", self.usageCoordinator.pricingModelCount),
                    tone: .success
                )
            case .failure(let error):
                self.statusItemText.title = Self.statusTitle("Price Update Failed")
                MoaNonBlockingAlert.present(
                    messageText: MoaL10n.text("Price Update Failed"),
                    informativeText: MoaL10n.format("%@\nPrevious prices and custom prices are still available. Try again later.", error.localizedDescription),
                    tone: .warning
                )
            }
        }
    }

    @objc func refreshStatusAction() {
        usageCoordinator.refreshCodex(forceRefresh: true)
    }

    @objc func openCodexAction() {
        performCodexLaunch()
    }

    @objc func checkUpdateAction() {
        statusItemText.title = Self.statusTitle("Checking for updates...")

        Task {
            do {
                let result = try await updateCoordinator.checkNow(userInitiated: true)
                await MainActor.run {
                    switch result {
                    case .upToDate(let version, let build):
                        let buildText = build.map { " (\($0))" } ?? ""
                        statusItemText.title = Self.statusTitle("Moa is up to date")
                        MoaNonBlockingAlert.present(
                            messageText: MoaL10n.text("Moa is up to date"),
                            informativeText: MoaL10n.format("Latest release: %@.", "\(version)\(buildText)"),
                            tone: .success
                        )
                    case .updateAvailable(let update):
                        presentUpdatePrompt(update)
                    }
                }
            } catch {
                await MainActor.run {
                    NSSound.beep()
                    statusItemText.title = Self.statusTitle("Update check failed")
                    showUpdateCheckError(error)
                }
            }
        }
    }

    @objc func openSettingsAboutAction() {
        workspaceWindow.navigation.showSettings(.about)
        workspaceWindow.show()
    }

    @objc func relaunchMoaAction() {
        guard !MoaRuntimeMode.suppressesUserInteraction,
              Bundle.main.bundleURL.pathExtension == "app" else { return }
        let appURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            NSApp.terminate(nil)
        }
    }

    func showUpdateCheckError(_ error: Error) {
        guard
            let updateError = error as? MoaUpdateError,
            updateError.isNetworkFailure
        else {
            showError(error.localizedDescription)
            return
        }

        let choice = MoaNonBlockingAlert.choose(
            messageText: MoaL10n.text("Update check failed"),
            informativeText: error.localizedDescription,
            primaryButtonTitle: MoaL10n.text("Open GitHub Releases"),
            cancelButtonTitle: MoaL10n.text("OK"),
            tone: .warning
        )
        if choice == .primary {
            NSWorkspace.shared.open(MoaUpdateController.releasesURL)
        }
    }

    func presentUpdatePrompt(_ update: MoaUpdateInfo) {
        let buildText = update.build.map { " (\($0))" } ?? ""
        let choice = MoaNonBlockingAlert.choose(
            messageText: MoaL10n.text("Update Available"),
            informativeText: MoaL10n.format("Moa %@ is available. Moa can download, verify, and install the update now.", "\(update.version)\(buildText)"),
            primaryButtonTitle: MoaL10n.text("Download and Install"),
            secondaryButtonTitle: MoaL10n.text("Open GitHub Releases"),
            tone: .info
        )

        switch choice {
        case .primary:
            installUpdate(update)
        case .secondary:
            NSWorkspace.shared.open(update.releaseURL)
        case .cancel:
            statusItemText.title = Self.statusTitle("Update canceled")
        }
    }

    func installUpdate(_ update: MoaUpdateInfo) {
        statusItemText.title = Self.statusTitle("Downloading update...")
        Task {
            do {
                try await updateController.downloadAndInstall(update)
            } catch {
                await MainActor.run {
                    NSSound.beep()
                    statusItemText.title = Self.statusTitle("Update failed")
                    showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func showQuickSwitcherAction() {
        quickSwitcher.toggle()
    }

    @objc func exportDataPackageAction() {
        guard let options = MoaRelease1100Panels.showExportDataPackageOptions() else {
            return
        }

        let panel = NSSavePanel()
        panel.title = MoaL10n.text("Export Moa Data Package")
        let prefix = options.scope == .configOnly ? "Moa-Config-Backup" : "Moa-Data-Backup"
        panel.nameFieldStringValue = dataPackageController.defaultDataPackageURL(prefix: prefix).lastPathComponent
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        statusItemText.title = Self.statusTitle("Exporting Moa data...")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try self.dataPackageController.exportDataPackage(
                    to: destination,
                    scope: options.scope,
                    password: options.password
                )
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.statusItemText.title = Self.statusTitle("Exported Moa data package")
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Moa Data Exported"),
                        informativeText: options.password != nil
                            ? MoaL10n.format("Encrypted Schema 3 package saved to:\n%@", url.path)
                            : url.path,
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = Self.statusTitle("Export failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func importDataPackageAction() {
        let panel = NSOpenPanel()
        panel.title = MoaL10n.text("Import Moa Data Package")
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let packageURL = panel.url else {
            return
        }

        var password: String?
        if let inspection = try? dataPackageController.inspectDataPackage(at: packageURL),
           inspection.isEncrypted {
            guard let entered = MoaRelease1100Panels.showImportPasswordPrompt(inspection: inspection) else {
                return
            }
            password = entered
        }

        guard confirmDataPackageImport() else {
            return
        }

        statusItemText.title = Self.statusTitle("Importing Moa data...")
        NotificationCenter.default.post(name: MoaDataRoot.willChangeNotification, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try self.dataPackageController.importDataPackage(from: packageURL, password: password)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let rollbackURL):
                    self.refreshStatus()
                    NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
                    self.statusItemText.title = Self.statusTitle("Imported Moa data package")
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Moa Data Imported"),
                        informativeText: MoaL10n.format("Rollback package: %@\nRestart Moa if any window still shows old data.", rollbackURL.path),
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = Self.statusTitle("Import failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    func restoreRecoveryBackup(_ entry: MoaBackupEntry, onComplete: @escaping () -> Void) {
        guard MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.format("Restore \"%@\"?", entry.name),
            informativeText: MoaL10n.text("Moa will save a fresh rollback snapshot of your current data first, then restore this recovery package."),
            primaryButtonTitle: MoaL10n.text("Restore"),
            tone: .warning
        ) else { return }

        statusItemText.title = Self.statusTitle("Importing Moa data...")
        NotificationCenter.default.post(name: MoaDataRoot.willChangeNotification, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try self.backupManager.restoreRecoveryPackage(entry)
            }
            DispatchQueue.main.async {
                onComplete()
                switch result {
                case .success(let rollbackURL):
                    self.refreshStatus()
                    NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
                    self.statusItemText.title = Self.statusTitle("Restored recovery backup")
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Recovery Package Restored"),
                        informativeText: MoaL10n.format("A backup of your previous data was saved to:\n%@", rollbackURL.path),
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = Self.statusTitle("Restore failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    func deleteBackupEntry(_ entry: MoaBackupEntry, onComplete: @escaping () -> Void) {
        let isDownloads = entry.kind == .legacyDownloadsBackup
        guard MoaNonBlockingAlert.confirm(
            messageText: isDownloads
                ? MoaL10n.format("Move \"%@\" to Trash?", entry.name)
                : MoaL10n.format("Delete backup \"%@\"?", entry.name),
            informativeText: isDownloads
                ? MoaL10n.text("Moves this unencrypted backup archive from Downloads to the Trash.")
                : MoaL10n.text("Permanently removes this backup snapshot from disk."),
            primaryButtonTitle: MoaL10n.text(isDownloads ? "Move to Trash" : "Delete"),
            tone: .danger
        ) else { return }
        do {
            try backupManager.deleteBackup(entry)
            onComplete()
        } catch {
            NSSound.beep()
            showError(error.localizedDescription)
        }
    }

    @objc func exportDiagnosticPackageAction() {
        let panel = NSSavePanel()
        panel.title = MoaL10n.text("Export Diagnostic Package")
        panel.nameFieldStringValue = dataPackageController.defaultDiagnosticPackageURL().lastPathComponent
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        statusItemText.title = Self.statusTitle("Exporting diagnostics...")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try self.dataPackageController.exportDiagnosticPackage(to: destination)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.statusItemText.title = Self.statusTitle("Exported diagnostics")
                    MoaNonBlockingAlert.present(
                        messageText: MoaL10n.text("Diagnostic Package Exported"),
                        informativeText: url.path,
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = Self.statusTitle("Diagnostic export failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func toggleICloudStorageAction() {
        let enabled = dataPackageController.isICloudStorageEnabled()
        guard confirmICloudStorageChange(enabling: !enabled) else {
            return
        }

        statusItemText.title = enabled ? Self.statusTitle("Moving Moa data to this Mac...") : Self.statusTitle("Moving Moa data to iCloud...")
        NotificationCenter.default.post(name: MoaDataRoot.willChangeNotification, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                if enabled {
                    return try self.dataPackageController.disableICloudStorage()
                }
                return try self.dataPackageController.enableICloudStorage()
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let rollbackURL):
                    self.configureMoaDataMenu()
                    NotificationCenter.default.post(name: MoaDataRoot.didChangeNotification, object: nil)
                    self.statusItemText.title = enabled ? Self.statusTitle("Moa data moved to this Mac") : Self.statusTitle("Moa data stored in iCloud")
                    MoaNonBlockingAlert.present(
                        messageText: enabled ? MoaL10n.text("Moa Data Moved to This Mac") : MoaL10n.text("Moa Data Stored in iCloud"),
                        informativeText: MoaL10n.format("Rollback package: %@\nRestart Moa if any window still shows old data.", rollbackURL.path),
                        tone: .success
                    )
                case .failure(let error):
                    NSSound.beep()
                    self.statusItemText.title = Self.statusTitle("iCloud data move failed")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc func openMoaDataFolderAction() {
        dataPackageController.openMoaHome()
    }

    @objc func openICloudDataFolderAction() {
        dataPackageController.openICloudMoaHome()
    }

    func confirmSensitiveDataPackageExport() -> Bool {
        MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Export Moa Data Package?"),
            informativeText: MoaL10n.text("This package contains your full Moa data folder, including provider API keys and local configuration. Store it only in a trusted place."),
            primaryButtonTitle: MoaL10n.text("Export"),
            tone: .warning
        )
    }

    func confirmDataPackageImport() -> Bool {
        MoaNonBlockingAlert.confirm(
            messageText: MoaL10n.text("Import Moa Data Package?"),
            informativeText: MoaL10n.text("Importing replaces the current Moa data folder. Moa will create a rollback package first."),
            primaryButtonTitle: MoaL10n.text("Import"),
            tone: .warning
        )
    }

    func confirmICloudStorageChange(enabling: Bool) -> Bool {
        MoaNonBlockingAlert.confirm(
            messageText: enabling ? MoaL10n.text("Store Moa Data in iCloud?") : MoaL10n.text("Move Moa Data Back to This Mac?"),
            informativeText: enabling
                ? MoaL10n.text("If iCloud Drive/Moa already has Moa data, Moa will use that existing iCloud folder and will not overwrite it. If it is empty, Moa will copy the current ~/.moa contents there. Provider API keys, auth.json, config.toml, and profile databases may be stored in iCloud.")
                : MoaL10n.text("Moa will copy iCloud Drive/Moa back to ~/.moa, then use the local folder as its data folder."),
            primaryButtonTitle: enabling ? MoaL10n.text("Use iCloud") : MoaL10n.text("Use This Mac"),
            tone: .warning
        )
    }

    @objc func openMoaFolderAction() {
        profileController.openMoaFolder()
    }

    @objc func openCodexFolderAction() {
        profileController.openCodexFolder()
    }

    @objc func reopenCodexAction() {
        guard let token = accountOperations.begin(.codex, message: MoaL10n.text("Reopening Codex...")) else { return }
        statusItemText.title = Self.statusTitle("Reopening Codex...")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.controller.reopenCodex() }

            DispatchQueue.main.async {
                self.accountOperations.finish(.codex, id: token)
                self.refreshStatus()
                if case .failure(let error) = result { self.showError(error.localizedDescription) }
            }
        }
    }

    private func performCodexLaunch() {
        guard let token = accountOperations.begin(.codex, message: MoaL10n.text("Opening Codex...")) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.controller.openCodex() }
            DispatchQueue.main.async {
                self.accountOperations.finish(.codex, id: token)
                if case .failure(let error) = result { self.showError(error.localizedDescription) }
            }
        }
    }

    @objc func quitAction() {
        NSApp.terminate(nil)
    }
}
