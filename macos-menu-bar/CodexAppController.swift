import AppKit
import Darwin
import Foundation

private enum CodexAppError: LocalizedError {
    case clientUnavailable
    case launchFailed
    case configurationSavedButLaunchFailed(String)
    case configurationChangeFailed(String)
    case configurationRestored(String)
    case configurationRecoveryLaunchFailed(String, String)
    case clientStillRunning
    case migrationProcessesRunning
    case processCheckFailed

    var errorDescription: String? {
        switch self {
        case .clientUnavailable:
            return MoaL10n.text("ChatGPT is not installed or its application path is unavailable.")
        case .launchFailed:
            return MoaL10n.text("ChatGPT could not be opened. Open the app manually and try again.")
        case .configurationSavedButLaunchFailed(let details):
            if details == CodexAppError.launchFailed.localizedDescription {
                return MoaL10n.text("The Codex configuration was saved, but ChatGPT could not be opened. Open it manually.")
            }
            return MoaL10n.format("The Codex configuration was saved. Open ChatGPT manually. %@", details)
        case .configurationChangeFailed(let details):
            return MoaL10n.format("The configuration change failed. ChatGPT was not reopened. Check the configuration before opening it manually. %@", details)
        case .configurationRestored(let details):
            return MoaL10n.format("The configuration change failed. ChatGPT was reopened with its previous configuration. %@", details)
        case .configurationRecoveryLaunchFailed(let details, let launch):
            return MoaL10n.format("The configuration change failed and the previous configuration is available, but ChatGPT could not be reopened. %@ %@", details, launch)
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

    #if MOA_TESTING || MOA_TEST_SUPPORT
    var testingQuit: (() throws -> Void)?
    var testingOpen: (() throws -> Void)?
    var testingIsRunning: (() -> Bool)?
    #endif

    func reopenCodex() throws {
        try quitCodex()
        try openCodex()
    }

    func reopenCodexSafely() {
        do { try reopenCodex() }
        catch { enhancementRuntime.recordError(error) }
    }

    /// Mutations run only after a graceful quit. A failed launch must not be
    /// presented as a successful switch; the saved configuration remains usable.
    func changeConfiguration<T>(if restart: Bool = true, _ change: () throws -> T) throws -> T {
        guard restart else { return try change() }
        let wasRunning = isCodexRunning()
        try quitCodex()
        let value: T
        do { value = try change() }
        catch {
            let safeToReopen: Bool
            switch error {
            case let transaction as CodexStateTransactionError: safeToReopen = transaction.canReopenClient
            case MoaDataAccessError.busy: safeToReopen = true
            default: safeToReopen = false
            }
            guard wasRunning, safeToReopen else {
                throw CodexAppError.configurationChangeFailed(error.localizedDescription)
            }
            do { try openCodex() }
            catch let launchError {
                throw CodexAppError.configurationRecoveryLaunchFailed(error.localizedDescription, launchError.localizedDescription)
            }
            throw CodexAppError.configurationRestored(error.localizedDescription)
        }
        do { try openCodex() }
        catch { throw CodexAppError.configurationSavedButLaunchFailed(error.localizedDescription) }
        return value
    }

    func quitCodex() throws {
        #if MOA_TESTING || MOA_TEST_SUPPORT
        if let testingQuit { try testingQuit(); return }
        #endif
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

    func openCodex() throws {
        #if MOA_TESTING || MOA_TEST_SUPPORT
        if let testingOpen { try testingOpen(); return }
        #endif
        guard let codexApp else { throw CodexAppError.clientUnavailable }
        do {
            if CodexStatusLineSettings(defaults: defaults).enabled && !isCodexRunning() {
                try enhancementRuntime.start(app: codexApp, environment: environment)
            } else {
                guard run("/usr/bin/open", [codexApp.path]) == 0 else { throw CodexAppError.launchFailed }
            }
            guard waitForCodexRunning(true, timeout: 12) else { throw CodexAppError.launchFailed }
        } catch {
            enhancementRuntime.recordError(error)
            throw error
        }
    }

    private func quitCodexIfNeeded() -> Bool {
        let applications = runningCodexApplications()
        guard !applications.isEmpty else { return true }
        let requests = applications.map { $0.terminate() }
        guard requests.allSatisfy({ $0 }) else { return false }
        return waitForCodexRunning(false, timeout: 12)
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
        #if MOA_TESTING || MOA_TEST_SUPPORT
        if let testingIsRunning { return testingIsRunning() }
        #endif
        return !runningCodexApplications().isEmpty
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
