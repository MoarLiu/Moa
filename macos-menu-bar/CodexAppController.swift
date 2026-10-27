import AppKit
import Darwin
import Foundation

private enum CodexAppError: LocalizedError {
    case clientStillRunning
    case migrationProcessesRunning
    case processCheckFailed

    var errorDescription: String? {
        switch self {
        case .clientStillRunning:
            return MoaL10n.text("ChatGPT could not be closed. Finish the active task and try again.")
        case .migrationProcessesRunning:
            return MoaL10n.text("Close all ChatGPT and Codex desktop and CLI instances before migrating history, and keep them closed until migration completes.")
        case .processCheckFailed:
            return MoaL10n.text("Could not check for running Codex processes. History migration was stopped.")
        }
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
final class CodexAppController: @unchecked Sendable {
    private let environment: [String: String]
    private let enhancementRuntime: CodexEnhancementRuntime
    private let defaults: UserDefaults
    private var codexApp: URL? { CodexDesktopApplication.applicationURL(environment: environment) }

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         defaults: UserDefaults = .standard, enhancementRuntime: CodexEnhancementRuntime = .shared) {
        self.environment = environment
        self.defaults = defaults
        self.enhancementRuntime = enhancementRuntime
    }

    func reopenCodex() {
        if CodexStatusLineSettings(defaults: defaults).enabled || enhancementRuntime.launch != nil {
            reopenCodexSafely()
            return
        }
        guard quitCodexIfNeeded() else { return }
        openCodexIfAvailable()
    }

    /// Enabling a display feature must never force-terminate an active client.
    func reopenCodexSafely() {
        guard quitCodexIfNeeded(allowForce: false) else {
            enhancementRuntime.recordError(CodexEnhancementError.clientRunning)
            return
        }
        openCodexIfAvailable()
    }

    func quitCodex() throws {
        guard quitCodexIfNeeded() else { throw CodexAppError.clientStillRunning }
    }

    func verifyHistoryMigrationQuiescence() throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: CodexDesktopApplication.bundleIdentifier).isEmpty else {
            throw CodexAppError.migrationProcessesRunning
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-u", String(getuid()), "-o", "comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CodexAppError.processCheckFailed }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let commands = String(data: data, encoding: .utf8) else {
            throw CodexAppError.processCheckFailed
        }
        if commands.split(separator: "\n").contains(where: { Self.isCodexProcessCommand(String($0)) }) {
            throw CodexAppError.migrationProcessesRunning
        }
    }

    static func isCodexProcessCommand(_ command: String) -> Bool {
        let name = URL(fileURLWithPath: command.trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent.lowercased()
        return name == "codex" || name == "codex-cli" || name.hasPrefix("codex-")
    }

    func openCodex() {
        openCodexIfAvailable()
    }

    @discardableResult
    private func quitCodexIfNeeded(allowForce: Bool = true) -> Bool {
        let applications = runningCodexApplications()
        guard !applications.isEmpty else { return true }
        applications.forEach { _ = $0.terminate() }
        if waitForCodexRunning(false, timeout: allowForce ? 4 : 12) { return true }
        guard allowForce else { return false }
        runningCodexApplications().forEach { _ = $0.forceTerminate() }
        return waitForCodexRunning(false, timeout: 3)
    }

    private func openCodexIfAvailable() {
        guard let codexApp else {
            if CodexStatusLineSettings(defaults: defaults).enabled { enhancementRuntime.recordError(CodexEnhancementError.unavailable) }
            return
        }
        if CodexStatusLineSettings(defaults: defaults).enabled && !isCodexRunning() {
            do { try enhancementRuntime.start(app: codexApp, environment: environment) }
            catch { enhancementRuntime.recordError(error) }
            return
        }
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
