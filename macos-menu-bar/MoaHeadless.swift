import AppKit
import Foundation

func runHeadlessCommandIfNeeded() -> Int32? {
    if CommandLine.arguments.contains("--repair-antigravity-keychain-access") {
        do {
            let count = try AntigravityKeychain.repairMoaAccess()
            print("Updated Moa access for \(count) Antigravity Keychain items; credential data was not read or changed.")
            return 0
        } catch {
            fputs("Moa: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
    let environment = ProcessInfo.processInfo.environment
    guard let profileID = environment["MoaApplyProfileID"], !profileID.isEmpty else {
        return nil
    }

    let controller = ConfigProfileController(environment: environment)
    do {
        try CodexAppController(environment: environment).quitCodex()
        _ = try controller.applyProfile(id: profileID)
        return 0
    } catch {
        fputs("Moa: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

#if !MOA_TESTING
@main
private enum MoaApplication {
    static func main() {
        do {
            try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded()
        } catch {
            NSLog("Moa legacy Moa-Lite data migration failed: \(error.localizedDescription)")
        }

        if let exitCode = runHeadlessCommandIfNeeded() {
            exit(exitCode)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
#endif
