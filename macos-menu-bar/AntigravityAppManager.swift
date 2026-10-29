import AppKit
import Darwin
import Foundation
import Security

/// Verify the publisher before using an installed app for credential operations or ACL creation.
/// Bundle identifiers and executable paths alone are not proof of Google's identity.
enum AntigravityInstallation {
    static func validatedURL() throws -> URL {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AntigravityAppManager.bundleID) else {
            throw invalidSignature
        }
        let resolved = url.resolvingSymlinksInPath()
        try validate(resolved)
        return resolved
    }

    static func validate(_ app: URL) throws {
        try validateCode(at: app, identifier: AntigravityAppManager.bundleID)
        // Validate the backend separately: it is explicitly granted access to the live login.
        let backend = app.appendingPathComponent("Contents/Resources/bin/language_server")
        guard backend.resolvingSymlinksInPath().path.hasPrefix(app.resolvingSymlinksInPath().path + "/") else {
            throw invalidSignature
        }
        try validateCode(at: backend, identifier: "language_server")
    }

    private static func validateCode(at url: URL, identifier: String) throws {
        // Google's Developer ID requirement; ad-hoc signatures and lookalike bundles fail closed.
        let requirementText = "identifier \"\(identifier)\" and anchor apple generic "
            + "and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
            + "and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw invalidSignature
        }
    }

    private static var invalidSignature: AntigravityError {
        .message("Antigravity's app or backend signature could not be verified as Google software. Reinstall the official Antigravity App before managing logins.")
    }
}

protocol AntigravityAppManaging {
    var isRunning: Bool { get }
    func validateInstallation() throws
    func ensureNoOtherClients() throws
    func ensureStopped() throws
    func quit() throws
    func launch() throws
}

final class AntigravityAppManager: AntigravityAppManaging {
    static let bundleID = "com.google.antigravity"
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    private func appURL() throws -> URL {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID),
              let bundle = Bundle(url: url),
              (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.hasPrefix("2.") == true,
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/Resources/bin/language_server").path) else {
            throw AntigravityError.message("Install Antigravity App 2.x before managing its accounts. Antigravity IDE uses a different login store.")
        }
        return url.resolvingSymlinksInPath()
    }

    func validateInstallation() throws { try AntigravityInstallation.validate(appURL()) }

    static func isSharedClient(executable: String) -> Bool {
        let lower = executable.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        return name == "agy" || name == "antigravity" || lower.contains("/antigravity ide.app/")
            || (name.hasPrefix("language_server") && (lower.contains("antigravity") || lower.contains("/.gemini/")))
    }

    private func clientExecutables() throws -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw AntigravityError.message("Unable to check Antigravity processes. Close Antigravity, agy, and its IDE extensions, then try again.") }
        var pids = [pid_t](repeating: 0, count: Int(count) + 1024)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard found > 0, Int(found) < pids.count else { throw AntigravityError.message("Unable to check Antigravity processes. Close Antigravity, agy, and its IDE extensions, then try again.") }
        var paths: [String] = []
        for pid in pids.prefix(Int(found)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { continue }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            if length > 0 { paths.append(String(cString: path)) }
            else if Darwin.kill(pid, 0) == 0 { throw AntigravityError.message("Unable to check Antigravity processes. Close Antigravity, agy, and its IDE extensions, then try again.") }
        }
        return paths
    }

    func ensureNoOtherClients() throws {
        let prefix = try appURL().path + "/"
        guard try !clientExecutables().contains(where: { !$0.hasPrefix(prefix) && Self.isSharedClient(executable: $0) }) else {
            throw AntigravityError.message("Close agy, Antigravity IDE, and Antigravity IDE extensions before saving or switching accounts. They share the active login.")
        }
    }

    func ensureStopped() throws {
        let prefix = try appURL().path + "/"
        guard !isRunning,
              try !clientExecutables().contains(where: { $0.hasPrefix(prefix) || Self.isSharedClient(executable: $0) }) else {
            throw AntigravityError.message("Antigravity or a shared login process is still running. Close it before changing accounts.")
        }
    }

    func quit() throws {
        precondition(!Thread.isMainThread)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        DispatchQueue.main.sync { for app in apps { _ = app.terminate() } }
        let deadline = Date().addingTimeInterval(20)
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !isRunning else { throw AntigravityError.message("Antigravity did not quit. Finish active tasks and quit it, then try again.") }
        // The Electron app may disappear just before its backend exits.
        let backendDeadline = Date().addingTimeInterval(5)
        while Date() < backendDeadline {
            do { try ensureStopped(); return } catch { Thread.sleep(forTimeInterval: 0.1) }
        }
        try ensureStopped()
    }

    func launch() throws {
        precondition(!Thread.isMainThread)
        let url = try appURL()
        try AntigravityInstallation.validate(url)
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                failure = error
                done.signal()
            }
        }
        guard done.wait(timeout: .now() + 20) == .success, failure == nil else {
            throw AntigravityError.message("Unable to open Antigravity. Open it manually and check the selected account.")
        }
    }
}
