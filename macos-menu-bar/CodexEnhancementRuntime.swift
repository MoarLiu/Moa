import AppKit
import Darwin
import Foundation

struct CodexStatusLineSettings: Equatable {
    var enabled = false
    var showContext = false
    var showCache = false
    var belowComposer = false

    init() {}
    init(defaults: UserDefaults) {
        enabled = defaults.bool(forKey: "codexStatusLine.enabled")
        showContext = defaults.bool(forKey: "codexStatusLine.context")
        showCache = defaults.bool(forKey: "codexStatusLine.cache")
        belowComposer = defaults.bool(forKey: "codexStatusLine.below")
    }
    func save(to defaults: UserDefaults) {
        defaults.set(enabled, forKey: "codexStatusLine.enabled")
        defaults.set(showContext, forKey: "codexStatusLine.context")
        defaults.set(showCache, forKey: "codexStatusLine.cache")
        defaults.set(belowComposer, forKey: "codexStatusLine.below")
    }
}

enum CodexEnhancementError: LocalizedError {
    case unavailable, listener, clientRunning, protocolFailure, timeout, resource, mainPage
    var errorDescription: String? {
        switch self {
        case .unavailable: return MoaL10n.text("Status line: waiting for ChatGPT to reopen through Moa")
        case .listener: return MoaL10n.text("Status line: could not verify the local client connection")
        case .clientRunning: return MoaL10n.text("Status line: quit ChatGPT manually, then choose Open Codex in Moa")
        case .protocolFailure: return MoaL10n.text("Status line: client connection interrupted")
        case .timeout: return MoaL10n.text("Status line: client connection timed out")
        case .resource: return MoaL10n.text("Status line: display resource is missing")
        case .mainPage: return MoaL10n.text("Status line: main chat window unavailable or ambiguous")
        }
    }
}

/// Launch ownership is in memory only. We never discover or attach to arbitrary debug ports.
final class CodexEnhancementRuntime: @unchecked Sendable {
    static let shared = CodexEnhancementRuntime()
    struct Launch: @unchecked Sendable {
        let process: Process
        let port: UInt16
        let generation: UUID
        let environment: [String: String]
    }
    private let lock = NSLock()
    private var ownedLaunch: Launch?
    private var launchError: String?

    var launch: Launch? {
        lock.lock(); defer { lock.unlock() }
        guard let ownedLaunch, ownedLaunch.process.isRunning else { return nil }
        return ownedLaunch
    }
    var error: String? { lock.lock(); defer { lock.unlock() }; return launchError }
    func recordError(_ error: Error) { lock.lock(); launchError = error.localizedDescription; lock.unlock() }

    func start(app: URL, environment: [String: String]) throws {
        lock.lock(); defer { lock.unlock() }
        if ownedLaunch?.process.isRunning == true { return }
        guard let executable = Bundle(url: app)?.executableURL,
              Bundle(url: app)?.bundleIdentifier == CodexDesktopApplication.bundleIdentifier else {
            throw CodexEnhancementError.unavailable
        }
        let port = try Self.unusedLoopbackPort()
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(port: port)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let launch = Launch(process: process, port: port, generation: UUID(), environment: environment)
        ownedLaunch = launch; launchError = nil
    }

    static func arguments(port: UInt16) -> [String] {
        ["--remote-debugging-address=127.0.0.1", "--remote-debugging-port=\(port)",
         "--remote-allow-origins=http://127.0.0.1:\(port)"]
    }

    static func unusedLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CodexEnhancementError.listener }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw CodexEnhancementError.listener }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        guard result == 0 else { throw CodexEnhancementError.listener }
        return UInt16(bigEndian: address.sin_port)
    }

    /// Run before discovery; only this launched process may own a loopback-only listener.
    static func verifyListener(_ launch: Launch) throws {
        guard launch.process.isRunning else { throw CodexEnhancementError.unavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", String(launch.process.processIdentifier),
                             "-iTCP:\(launch.port)", "-sTCP:LISTEN", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        guard done.wait(timeout: .now() + 2) == .success else {
            process.terminate(); throw CodexEnhancementError.listener
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0, Self.isLoopbackListener(output, port: launch.port),
              launch.process.isRunning else { throw CodexEnhancementError.listener }
    }

    static func isLoopbackListener(_ output: String, port: UInt16) -> Bool {
        let names = output.split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        return !names.isEmpty && names.allSatisfy { $0 == "127.0.0.1:\(port)" || $0 == "[::1]:\(port)" }
    }
}
