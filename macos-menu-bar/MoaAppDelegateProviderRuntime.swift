import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    func rebuildCodexProviderMenus() {
        rebuildProfileMenu()
    }

    func currentCodexSelectionName() -> String {
        if let profileName = profileController.selectedProfileName() {
            return profileName
        }

        if let accountName = profileController.selectedOfficialAccountName() {
            return "\(MoaL10n.text("Official")) · \(accountName)"
        }

        return MoaL10n.text("Official")
    }

    func rebuildClaudeProviderMenus() {
        rebuildClaudeDesktopProfilesMenu()
    }
}
