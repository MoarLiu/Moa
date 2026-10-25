import Darwin
import Foundation

enum MoaProcessRunner {
    static let timeoutStatus: Int32 = 124

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return 127
        }
        if exited.wait(timeout: .now() + max(0, timeout)) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut {
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                // Reap the child before callers remove staging files or release
                // an exclusive data operation that the child could still mutate.
                process.waitUntilExit()
            }
            return timeoutStatus
        }
        return process.terminationStatus
    }
}
