import AppKit
import Darwin
import Foundation

private enum CodexAppError: LocalizedError {
    case clientStillRunning

    var errorDescription: String? {
        MoaL10n.text("ChatGPT could not be closed. Finish the active task and try again.")
    }
}

enum CodexDesktopApplication {
    static let bundleIdentifier = "com.openai.codex"

    static func applicationURL(environment: [String: String]) -> URL? {
        let fileManager = FileManager.default
        if let override = environment["CODEX_APP"], !override.isEmpty {
            let url = URL(fileURLWithPath: override).resolvingSymlinksInPath().standardizedFileURL
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           fileManager.fileExists(atPath: installed.path) {
            return installed.resolvingSymlinksInPath().standardizedFileURL
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        for path in ["/Applications/ChatGPT.app", "\(home)/Applications/ChatGPT.app",
                     "/Applications/Codex.app", "\(home)/Applications/Codex.app"] {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: path), Bundle(url: url)?.bundleIdentifier == bundleIdentifier {
                return url
            }
        }
        return nil
    }
}

/// Client lifecycle only. Configuration preferences remain owned by Codex.
final class CodexAppController: Sendable {
    private let environment: [String: String]
    private var codexApp: URL? { CodexDesktopApplication.applicationURL(environment: environment) }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func reopenCodex() {
        guard quitCodexIfNeeded() else { return }
        openCodexIfAvailable()
    }

    func quitCodex() throws {
        guard quitCodexIfNeeded() else { throw CodexAppError.clientStillRunning }
    }

    func openCodex() {
        openCodexIfAvailable()
    }

    @discardableResult
    private func quitCodexIfNeeded() -> Bool {
        let applications = runningCodexApplications()
        guard !applications.isEmpty else { return true }
        applications.forEach { _ = $0.terminate() }
        if waitForCodexRunning(false, timeout: 4) { return true }
        runningCodexApplications().forEach { _ = $0.forceTerminate() }
        return waitForCodexRunning(false, timeout: 3)
    }

    private func openCodexIfAvailable() {
        guard let codexApp else { return }
        _ = run("/usr/bin/open", [codexApp.path])
    }

    private func runningCodexApplications() -> [NSRunningApplication] {
        guard let codexApp else { return [] }
        let identifier = Bundle(url: codexApp)?.bundleIdentifier ?? CodexDesktopApplication.bundleIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { application in
            guard application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == codexApp.resolvingSymlinksInPath().standardizedFileURL.path,
                  application.processIdentifier > 0 else { return false }
            // AppKit termination state waits for a main run-loop turn. Check
            // process existence too so synchronous reopen cannot poll stale apps.
            return Darwin.kill(application.processIdentifier, 0) == 0 || errno == EPERM
        }
    }

    private func isCodexRunning() -> Bool {
        !runningCodexApplications().isEmpty
    }

    private func waitForCodexRunning(_ running: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCodexRunning() == running {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return isCodexRunning() == running
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> Int32 {
        MoaProcessRunner.run(executable, arguments)
    }

}
