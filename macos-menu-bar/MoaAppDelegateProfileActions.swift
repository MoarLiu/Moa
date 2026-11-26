import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    @objc func testClaudeActiveProviderAction() { profileActionCoordinator.testClaudeActiveProviderAction() }
    @objc func copyClaudeCodeConfigAction() { profileActionCoordinator.copyClaudeCodeConfigAction() }
    @objc func editProfileAction(_ sender: NSMenuItem) { profileActionCoordinator.editProfileAction(sender) }
    @objc func deleteProfileAction(_ sender: NSMenuItem) { profileActionCoordinator.deleteProfileAction(sender) }
    @objc func importCodexProfilesAction() { profileActionCoordinator.importCodexProfilesAction() }
    @objc func exportCodexProfilesAction() { profileActionCoordinator.exportCodexProfilesAction() }
    @objc func showCodexDailyUsageAlertAction() { profileActionCoordinator.showCodexDailyUsageAlertAction() }
    @objc func showCodexUsageDetailsAction() { profileActionCoordinator.showCodexUsageDetailsAction() }
    @objc func migrateCodexSessionModelProviderAction() { profileActionCoordinator.migrateCodexSessionModelProviderAction() }
    @objc func addClaudeDesktopProviderAction() { profileActionCoordinator.addClaudeDesktopProviderAction() }
    @objc func editClaudeDesktopProviderAction(_ sender: NSMenuItem) { profileActionCoordinator.editClaudeDesktopProviderAction(sender) }
    @objc func deleteClaudeDesktopProviderAction(_ sender: NSMenuItem) { profileActionCoordinator.deleteClaudeDesktopProviderAction(sender) }
    @objc func importClaudeDesktopProfilesAction() { profileActionCoordinator.importClaudeDesktopProfilesAction() }
    @objc func exportClaudeDesktopProfilesAction() { profileActionCoordinator.exportClaudeDesktopProfilesAction() }
    @objc func showClaudeDailyUsageAlertAction() { profileActionCoordinator.showClaudeDailyUsageAlertAction() }
    @objc func showClaudeUsageDetailsAction() { profileActionCoordinator.showClaudeUsageDetailsAction() }
    @objc func showZCodeDailyUsageAlertAction() { profileActionCoordinator.showZCodeDailyUsageAlertAction() }
    @objc func showZCodeUsageDetailsAction() { profileActionCoordinator.showZCodeUsageDetailsAction() }
    @objc func applyZCodeOfficialModeAction() { profileActionCoordinator.applyZCodeOfficialModeAction() }
    @objc func openZCodeAction() { profileActionCoordinator.openZCodeAction() }
    @objc func reopenZCodeAction() { profileActionCoordinator.reopenZCodeAction() }
    @objc func openZCodeFolderAction() { profileActionCoordinator.openZCodeFolderAction() }
    @objc func applyClaudeDesktopProviderAction(_ sender: NSMenuItem) { profileActionCoordinator.applyClaudeDesktopProviderAction(sender) }
    @objc func restoreClaudeDesktopOfficialAction() { profileActionCoordinator.restoreClaudeDesktopOfficialAction() }
    @objc func openClaudeDesktopAction() { profileActionCoordinator.openClaudeDesktopAction() }
    @objc func reopenClaudeDesktopAction() { profileActionCoordinator.reopenClaudeDesktopAction() }
    @objc func openClaudeDesktopFolderAction() { profileActionCoordinator.openClaudeDesktopFolderAction() }
    @objc func openClaudeDesktop3PFolderAction() { profileActionCoordinator.openClaudeDesktop3PFolderAction() }
    @objc func restoreCodexOfficialAction() { profileActionCoordinator.restoreCodexOfficialAction() }
    @objc func applyCodexOfficialNoAccountAction() { profileActionCoordinator.applyCodexOfficialNoAccountAction() }
    @objc func applyCodexOfficialAccountAction(_ sender: NSMenuItem) { profileActionCoordinator.applyCodexOfficialAccountAction(sender) }
    @objc func showAccountManagerAction(_ sender: NSMenuItem) {
        let group = (sender.representedObject as? String).flatMap(MoaAccountGroup.init(rawValue:))
        accountManagerWindow.show(group: group)
    }

    @objc func addCodexOfficialAccountAction() { profileActionCoordinator.addCodexOfficialAccountAction() }
    @objc func addAnotherCodexOfficialAccountAction() { profileActionCoordinator.addAnotherCodexOfficialAccountAction() }
    @objc func renameCodexOfficialAccountAction() { profileActionCoordinator.renameCodexOfficialAccountAction() }
    @objc func deleteCodexOfficialAccountAction() { profileActionCoordinator.deleteCodexOfficialAccountAction() }
    @objc func applyProfileAction(_ sender: NSMenuItem) { profileActionCoordinator.applyProfileAction(sender) }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportProfiles(groupName: String, suggestedFileName: String, exporter: (Bool) throws -> Data) {
        switch MoaProviderProfileTransfer.exportProfiles(
            groupName: groupName,
            suggestedFileName: suggestedFileName,
            exporter: exporter
        ) {
        case .success:
            statusItemText.title = Self.statusTitle("Exported %@", groupName)
        case .failure(let error):
            NSSound.beep()
            statusItemText.title = Self.statusTitle("Failed")
            showError(error.localizedDescription)
        case nil:
            return
        }
    }

    func importProfiles(groupName: String, importer: (Data) throws -> Int, onImported: () -> Void) {
        switch MoaProviderProfileTransfer.importProfiles(groupName: groupName, importer: importer) {
        case .success(let count):
            onImported()
            statusItemText.title = Self.statusTitle("Imported %d %@ profiles", count, groupName)
        case .failure(let error):
            NSSound.beep()
            statusItemText.title = Self.statusTitle("Failed")
            showError(error.localizedDescription)
        case nil:
            return
        }
    }

    func showDailyUsageAlertPanel(kind: DailyUsageAlertKind) {
        let title = String(format: MoaL10n.text("Set %@ Daily Usage Alert"), kind.displayName)
        let initialThreshold = DailyUsageAlertController.threshold(for: kind)
        let initialText = initialThreshold.map { String(format: "%.2f", $0) } ?? ""
        let initialWarnAt80 = DailyUsageAlertController.warning80Enabled(for: kind)

        var didSave = false
        var savedThreshold: Double?
        var savedWarnAt80 = false

        MoaGlassModalHost.runModal(width: 500, fallbackHeight: 400, title: title) {
            DailyUsageAlertFormView(
                title: title,
                initialEnabled: initialThreshold != nil,
                initialThresholdText: initialText,
                initialWarnAt80: initialWarnAt80,
                onSave: { threshold, warnAt80 in
                    didSave = true
                    savedThreshold = threshold
                    savedWarnAt80 = warnAt80
                    MoaGlassModalHost.finish(.OK)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }

        guard didSave else { return }
        DailyUsageAlertController.setThreshold(savedThreshold, for: kind)
        DailyUsageAlertController.setWarning80Enabled(savedThreshold != nil && savedWarnAt80, for: kind)
        if savedThreshold != nil {
            notificationManager.requestAuthorizationIfNeeded()
        }
        statusItemText.title = Self.statusTitle("Updated %@ daily usage alert", kind.displayName)
    }

    func maybeShowDailyUsageAlert(kind: DailyUsageAlertKind, summary: CodexUsageSummary) {
        guard let level = DailyUsageAlertController.pendingAlertLevel(kind: kind, summary: summary),
              let threshold = DailyUsageAlertController.threshold(for: kind)
        else {
            return
        }

        let todayText = DailyUsageAlertController.currency(summary.todayCostUSD)
        let thresholdText = DailyUsageAlertController.currency(threshold)
        let title: String
        let body: String
        let identifierSuffix: String

        switch level {
        case .warning80:
            title = String(format: MoaL10n.text("%@ daily usage reached 80%% of threshold"), kind.displayName)
            body = String(format: MoaL10n.text("Today's local estimate is %@, approaching your %@ threshold."), todayText, thresholdText)
            statusItemText.title = Self.statusTitle("%@ daily usage reached 80%% of threshold", kind.displayName)
            identifierSuffix = "warn80"
        case .reached:
            title = String(format: MoaL10n.text("%@ daily usage reached the alert threshold"), kind.displayName)
            body = String(format: MoaL10n.text("Today's local estimate is %@, reaching your threshold of %@."), todayText, thresholdText)
            statusItemText.title = Self.statusTitle("%@ daily usage reached threshold", kind.displayName)
            identifierSuffix = "reached"
        }

        notificationManager.post(
            identifier: "moa.daily-usage.\(kind.rawValue).\(identifierSuffix).\(MoaUsageReport.dayKey(from: summary.updatedAt))",
            title: title,
            body: body,
            action: .openUsage(kind.usageSource)
        )
    }

    func showCombinedUsageBudgetPanel() {
        let initialDaily = DailyUsageAlertController.combinedThreshold(for: .daily)
        let initialDailyWarn80 = DailyUsageAlertController.combinedWarning80Enabled(for: .daily)
        let initialMonthly = DailyUsageAlertController.combinedThreshold(for: .monthly)
        let initialMonthlyWarn80 = DailyUsageAlertController.combinedWarning80Enabled(for: .monthly)

        var didSave = false
        var savedDaily: Double?
        var savedDailyWarn80 = false
        var savedMonthly: Double?
        var savedMonthlyWarn80 = false

        MoaGlassModalHost.runModal(width: 500, fallbackHeight: 460, title: MoaL10n.text("Combined Usage Budgets")) {
            MoaCombinedBudgetFormView(
                initialDailyThreshold: initialDaily,
                initialDailyWarn80: initialDailyWarn80,
                initialMonthlyThreshold: initialMonthly,
                initialMonthlyWarn80: initialMonthlyWarn80,
                onSave: { daily, dailyW80, monthly, monthlyW80 in
                    didSave = true
                    savedDaily = daily
                    savedDailyWarn80 = dailyW80
                    savedMonthly = monthly
                    savedMonthlyWarn80 = monthlyW80
                    MoaGlassModalHost.finish(.OK)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }

        guard didSave else { return }
        DailyUsageAlertController.setCombinedThreshold(savedDaily, for: .daily)
        DailyUsageAlertController.setCombinedWarning80Enabled(savedDailyWarn80, for: .daily)
        DailyUsageAlertController.setCombinedThreshold(savedMonthly, for: .monthly)
        DailyUsageAlertController.setCombinedWarning80Enabled(savedMonthlyWarn80, for: .monthly)
        if savedDaily != nil || savedMonthly != nil {
            notificationManager.requestAuthorizationIfNeeded()
        }
        statusItemText.title = Self.statusTitle("Updated combined usage budgets")
    }

    func maybeShowCombinedUsageBudgetAlerts(summaries: [MoaUsageSource: CodexUsageSummary]) {
        guard DailyUsageAlertController.hasAnyCombinedBudget() else { return }
        let now = Date()
        let todayTotal = summaries.values.reduce(0) { $0 + $1.todayCostUSD }
        if let level = DailyUsageAlertController.pendingCombinedAlertLevel(period: .daily, costUSD: todayTotal, date: now),
           let threshold = DailyUsageAlertController.combinedThreshold(for: .daily) {
            postCombinedBudgetNotification(period: .daily, level: level, costUSD: todayTotal, threshold: threshold, date: now)
        }
        if DailyUsageAlertController.combinedThreshold(for: .monthly) != nil {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let batch = self.usageCoordinator.loadCombinedReport(forceRefresh: false, now: now)
                guard let report = batch.report else { return }
                let monthCost = MoaUsageAnalytics.currentMonthCostUSD(in: report, now: now)
                DispatchQueue.main.async {
                    if let level = DailyUsageAlertController.pendingCombinedAlertLevel(period: .monthly, costUSD: monthCost, date: now),
                       let threshold = DailyUsageAlertController.combinedThreshold(for: .monthly) {
                        self.postCombinedBudgetNotification(period: .monthly, level: level, costUSD: monthCost, threshold: threshold, date: now)
                    }
                }
            }
        }
    }

    private func postCombinedBudgetNotification(
        period: MoaCombinedBudgetPeriod,
        level: DailyUsageAlertLevel,
        costUSD: Double,
        threshold: Double,
        date: Date
    ) {
        let spentText = DailyUsageAlertController.currency(costUSD)
        let thresholdText = DailyUsageAlertController.currency(threshold)
        let periodName = period.displayName
        let title: String
        let body: String
        let suffix: String
        switch level {
        case .warning80:
            title = MoaL10n.format("%@ reached 80%%", periodName)
            body = MoaL10n.format("Local combined estimate is %@, approaching your %@ budget.", spentText, thresholdText)
            suffix = "warn80"
        case .reached:
            title = MoaL10n.format("%@ reached", periodName)
            body = MoaL10n.format("Local combined estimate is %@, reaching your %@ budget.", spentText, thresholdText)
            suffix = "reached"
        }
        let bucket = period == .daily ? MoaUsageReport.dayKey(from: date) : MoaUsageReport.monthKey(from: date)
        notificationManager.post(
            identifier: "moa.combined-budget.\(period.rawValue).\(suffix).\(bucket)",
            title: title,
            body: body,
            action: .openUsage(nil)
        )
    }

    func showAddProfilePanel() -> (name: String, baseURL: String, apiKey: String)? {
        MoaProviderProfilePanels.showAddCodexProfile()
    }

    func showEditProfilePanel(for profile: ConfigProfile) -> (name: String, baseURL: String, apiKey: String)? {
        MoaProviderProfilePanels.showEditCodexProfile(for: profile)
    }

    func showOfficialAccountNamePanel(
        title: String,
        message: String,
        buttonTitle: String,
        initialName: String
    ) -> String? {
        MoaProviderProfilePanels.showOfficialAccountName(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            initialName: initialName
        )
    }

    func showAddClaudeDesktopProviderPanel() -> (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])? {
        MoaProviderProfilePanels.showAddClaudeDesktopProvider()
    }

    func showEditClaudeDesktopProviderPanel(
        for profile: ClaudeDesktopProviderProfile
    ) -> (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])? {
        MoaProviderProfilePanels.showEditClaudeDesktopProvider(for: profile)
    }

    func showError(_ message: String) {
        MoaNonBlockingAlert.present(messageText: "Moa", informativeText: message, tone: .warning)
    }
}
