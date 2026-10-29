#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class MoaMaintenanceRegressionTests: XCTestCase {
    private let fm = FileManager.default

    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = fm.temporaryDirectory.appendingPathComponent("moa-maintenance-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try body(home)
    }

    private func mode(_ url: URL) throws -> Int {
        try XCTUnwrap(fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    func testRefusedQuitPreventsConfigurationWritesAndLaunch() throws {
        try withHome { home in
            let file = home.appendingPathComponent("auth.json")
            try Data("before".utf8).write(to: file)
            let controller = CodexAppController(environment: ["HOME": home.path])
            controller.testingQuit = { throw CocoaError(.userCancelled) }
            controller.testingOpen = { XCTFail("A refused quit must not reopen the client") }
            XCTAssertThrowsError(try controller.changeConfiguration { try Data("after".utf8).write(to: file) })
            XCTAssertEqual(try String(contentsOf: file), "before")
        }
    }

    func testSwitchReadsFinalOutgoingCredentialsAfterQuitAndThenLaunches() throws {
        try withHome { home in
            let file = home.appendingPathComponent("auth.json")
            var events: [String] = []
            let controller = CodexAppController(environment: ["HOME": home.path])
            controller.testingQuit = {
                events.append("quit")
                try Data("refreshed-outgoing".utf8).write(to: file)
            }
            controller.testingOpen = {
                XCTAssertEqual(try String(contentsOf: file), "target")
                events.append("open")
            }
            let result = try controller.changeConfiguration {
                XCTAssertEqual(try String(contentsOf: file), "refreshed-outgoing")
                events.append("write")
                try Data("target".utf8).write(to: file)
                return "selected"
            }
            XCTAssertEqual(result, "selected")
            XCTAssertEqual(events, ["quit", "write", "open"])
        }
    }

    func testFailedLaunchReportsSavedConfigurationInsteadOfSuccess() throws {
        try withHome { home in
            let file = home.appendingPathComponent("auth.json")
            let controller = CodexAppController(environment: ["HOME": home.path])
            controller.testingQuit = {}
            controller.testingOpen = { throw CocoaError(.executableNotLoadable) }
            XCTAssertThrowsError(try controller.changeConfiguration { try Data("target".utf8).write(to: file) }) { error in
                XCTAssertTrue(error.localizedDescription.contains("configuration was saved"))
            }
            XCTAssertEqual(try String(contentsOf: file), "target")
        }
    }

    func testFailedMutationDoesNotLaunchAndInactiveEditDoesNotRestart() throws {
        let controller = CodexAppController()
        controller.testingQuit = {}
        controller.testingOpen = { XCTFail("Failed configuration writes must not report a launch") }
        XCTAssertThrowsError(try controller.changeConfiguration { throw CocoaError(.fileWriteNoPermission) })
        controller.testingQuit = { XCTFail("An inactive profile edit must not quit the client") }
        XCTAssertEqual(try controller.changeConfiguration(if: false) { 7 }, 7)
    }

    func testMissingClientLaunchIsAnError() throws {
        try withHome { home in
            let controller = CodexAppController(environment: ["HOME": home.path, "CODEX_APP": home.appendingPathComponent("Missing.app").path])
            XCTAssertThrowsError(try controller.openCodex())
            XCTAssertThrowsError(try controller.reopenCodex())
        }
    }

    func testJSONLReaderPreservesChunkBoundariesCRLFAndFinalLine() throws {
        try withHome { home in
            let file = home.appendingPathComponent("lines.jsonl")
            let first = String(repeating: "x", count: 64 * 1024 - 1)
            try Data((first + "\r\n\nlast").utf8).write(to: file)
            var lines: [Data] = []
            try MoaJSONLReader.scan(fileURL: file) { line, truncated in
                XCTAssertFalse(truncated)
                lines.append(line)
            }
            XCTAssertEqual(lines, [Data(first.utf8), Data(), Data("last".utf8)])
        }
    }

    func testOversizedLinesKeepBoundedPrefixesAndRecoverAtNewline() throws {
        try withHome { home in
            let file = home.appendingPathComponent("large.jsonl")
            var data = Data(repeating: 120, count: 4 * 1024 * 1024)
            data.append(Data("\nvalid\n".utf8))
            data.append(Data(repeating: 121, count: 128 * 1024))
            try data.write(to: file)
            var lengths: [Int] = []
            var truncatedLines: [Bool] = []
            try MoaJSONLReader.scan(fileURL: file, maximumLineBytes: 1024) { line, truncated in
                lengths.append(line.count)
                truncatedLines.append(truncated)
                if !truncated { XCTAssertEqual(String(data: line, encoding: .utf8), "valid") }
            }
            XCTAssertEqual(lengths, [1024, 5, 1024])
            XCTAssertEqual(truncatedLines, [true, false, true])
        }
    }

    func testUsageScannersRecoverAfterOversizedLinesAndPreserveCodexModelContext() throws {
        try withHome { home in
            let codex = home.appendingPathComponent(".codex/sessions")
            let claude = home.appendingPathComponent(".claude/projects/project")
            try fm.createDirectory(at: codex, withIntermediateDirectories: true)
            try fm.createDirectory(at: claude, withIntermediateDirectories: true)
            var context = Data(#"{"type":"turn_context","payload":{"model":"gpt-5.5","padding":""#.utf8)
            context.append(Data(repeating: 120, count: MoaJSONLReader.maximumLineBytes + 1))
            context.append(Data("\"}}\n".utf8))
            context.append(Data(#"{"type":"token_usage_record","timestamp":"2026-10-28T00:00:00Z","payload":{"response_id":"one","usage":{"input_tokens":100,"output_tokens":10}}}"#.utf8))
            try context.write(to: codex.appendingPathComponent("session.jsonl"))
            var claudeData = Data(repeating: 120, count: MoaJSONLReader.maximumLineBytes + 1)
            claudeData.append(Data("\n".utf8))
            claudeData.append(Data(#"{"type":"assistant","timestamp":"2026-10-28T00:00:00Z","message":{"id":"one","model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":10}}}"#.utf8))
            try claudeData.write(to: claude.appendingPathComponent("session.jsonl"))
            XCTAssertEqual(try CodexUsageScanner(environment: ["HOME": home.path]).loadReport().totalTokens, 110)
            XCTAssertEqual(try ClaudeUsageScanner(environment: ["HOME": home.path]).loadReport().totalTokens, 110)
        }
    }

    func testSensitiveStoresAndBackupsUsePrivatePermissions() throws {
        try withHome { home in
            let controller = ConfigProfileController(environment: ["HOME": home.path])
            let profile = try controller.addProfile(name: "Fixture", baseURL: "https://fixture.invalid/v1", apiKey: "synthetic")
            _ = try controller.applyProfile(id: profile.id)
            try controller.backupCodexFiles()
            for directory in [controller.moaHome, controller.officialAuthAccountsDir, controller.backupDir] {
                XCTAssertEqual(try mode(directory), 0o700)
            }
            for file in [controller.databaseURL, controller.moaAuthURL, controller.codexAuthURL, controller.codexConfigURL] {
                XCTAssertEqual(try mode(file), 0o600)
            }
            for file in try fm.contentsOfDirectory(at: controller.backupDir, includingPropertiesForKeys: nil) {
                XCTAssertEqual(try mode(file), 0o600)
            }
        }
    }

    func testSecureWritesRejectSymlinksAndCleanFailedTemporaryFiles() throws {
        try withHome { home in
            let target = home.appendingPathComponent("target")
            let link = home.appendingPathComponent("auth.json")
            try Data("unchanged".utf8).write(to: target)
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
            XCTAssertThrowsError(try MoaSecureFile.write(Data("replacement".utf8), to: link))
            XCTAssertEqual(try String(contentsOf: target), "unchanged")
            let directory = home.appendingPathComponent("blocked")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            XCTAssertThrowsError(try MoaSecureFile.write(Data("replacement".utf8), to: directory)) { error in
                XCTAssertEqual((error as NSError).userInfo[NSFilePathErrorKey] as? String, directory.path)
                XCTAssertTrue(error.localizedDescription.contains(directory.path))
            }
            XCTAssertFalse(try fm.contentsOfDirectory(atPath: home.path).contains { $0.hasPrefix(".moa-private-") })
        }
    }

    func testAutomaticRecoveryPackagesStayLocalPrivateAndSeparateFromExports() throws {
        try withHome { home in
            let environment = ["HOME": home.path]
            let profiles = ConfigProfileController(environment: environment)
            _ = try profiles.addProfile(name: "Fixture", baseURL: "https://fixture.invalid/v1", apiKey: "synthetic")
            let controller = MoaDataPackageController(environment: environment)
            let exported = home.appendingPathComponent("Downloads/export.zip")
            try controller.exportDataPackage(to: exported)
            XCTAssertEqual(try mode(exported), 0o600)
            let imported = try controller.importDataPackage(from: exported)
            try fm.createDirectory(at: controller.iCloudDriveRoot, withIntermediateDirectories: true)
            let enabled = try controller.enableICloudStorage()
            let disabled = try controller.disableICloudStorage()
            for package in [imported, enabled, disabled] {
                XCTAssertEqual(package.deletingLastPathComponent(), controller.recoveryDirectory)
                XCTAssertEqual(try mode(package), 0o600)
                XCTAssertFalse(package.path.hasPrefix(controller.iCloudDriveRoot.path))
            }
            XCTAssertEqual(try mode(controller.recoveryDirectory), 0o700)
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: exported.deletingLastPathComponent().path), ["export.zip"])
        }
    }

    func testRecoveryRetentionPrunesOnlyOldManagedArchives() throws {
        try withHome { home in
            let controller = MoaDataPackageController(environment: ["HOME": home.path])
            try MoaSecureFile.ensurePrivateDirectory(controller.recoveryDirectory)
            let unrelated = controller.recoveryDirectory.appendingPathComponent("keep.zip")
            try Data().write(to: unrelated)
            for index in 0..<15 {
                let url = controller.recoveryDirectory.appendingPathComponent("Moa-Data-Rollback-fixture-\(index).zip")
                try Data().write(to: url)
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: url.path)
            }
            let current = controller.recoveryDirectory.appendingPathComponent("Moa-Data-Rollback-fixture-0.zip")
            // The new recovery snapshot must survive even if the clock moved back.
            try controller.pruneRecoveryPackages(preserving: current)
            let remaining = try fm.contentsOfDirectory(at: controller.recoveryDirectory, includingPropertiesForKeys: nil)
            XCTAssertEqual(remaining.count, MoaDataPackageController.retainedRecoveryPackageCount + 1)
            XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
            XCTAssertTrue(fm.fileExists(atPath: current.path))
            XCTAssertFalse(fm.fileExists(atPath: controller.recoveryDirectory.appendingPathComponent("Moa-Data-Rollback-fixture-1.zip").path))
            XCTAssertTrue(fm.fileExists(atPath: controller.recoveryDirectory.appendingPathComponent("Moa-Data-Rollback-fixture-14.zip").path))
        }
    }
}

final class MoaProviderProbeRegressionTests: XCTestCase {
    private func probe(statuses: [Int], body: String? = nil, claude: Bool = false) async throws -> ProviderConnectionTestResult {
        ProbeProtocol.reset(statuses, body: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbeProtocol.self]
        let session = URLSession(configuration: configuration)
        ProviderConnectionTester.testingURLSession = session
        defer { ProviderConnectionTester.testingURLSession = nil; session.invalidateAndCancel() }
        if claude {
            return try await ProviderConnectionTester.testClaude(baseURL: "https://fixture.invalid", apiKey: "synthetic", models: ["fixture"])
        }
        return try await ProviderConnectionTester.testCodex(baseURL: "https://fixture.invalid", apiKey: "synthetic", modelOverride: "fixture")
    }

    func testProbeUsesSupportedTokenBudget() async throws {
        _ = try await probe(statuses: [200])
        let request = try XCTUnwrap(ProbeProtocol.requests.first)
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = stream.read(&bytes, maxLength: bytes.count)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes.prefix(max(0, count)))) as? [String: Any])
        XCTAssertEqual(body["max_output_tokens"] as? Int, 16)
        XCTAssertEqual(body["input"] as? String, "ping")
    }

    func testBadRequestPreservesFirstErrorAndDoesNotTryAnotherEndpoint() async {
        do {
            _ = try await probe(statuses: [400, 404])
            XCTFail("HTTP 400 must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("first endpoint error"))
            XCTAssertLessThan(error.localizedDescription.count, 400)
        }
        XCTAssertEqual(ProbeProtocol.requests.map { $0.url!.path }, ["/v1/responses"])
    }

    func testMissingOrUnsupportedEndpointCanTryTheAlternatePath() async throws {
        for status in [404, 405] {
            let result = try await probe(statuses: [status, 200])
            XCTAssertEqual(result.endpoint, "https://fixture.invalid/responses")
            XCTAssertEqual(ProbeProtocol.requests.map { $0.url!.path }, ["/v1/responses", "/responses"])
        }
    }

    func testCancelledRequestDoesNotTryAnotherEndpoint() async {
        do {
            _ = try await probe(statuses: [NSURLErrorCancelled, 200])
            XCTFail("A cancelled probe must fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
        XCTAssertEqual(ProbeProtocol.requests.map { $0.url!.path }, ["/v1/responses"])
    }

    func testSuccessfulHTTPStatusStillRequiresTheExpectedAPIResponse() async {
        for claude in [false, true] {
            for body in ["<html>synthetic-private-login-page</html>", "", "{}", "[]",
                         #"{"error":{"message":"synthetic-private-error"}}"#,
                         #"{"object":"chat.completion","choices":[]}"#] {
                do {
                    _ = try await probe(statuses: [200, 200], body: body, claude: claude)
                    XCTFail("Invalid response must fail: \(body)")
                } catch {
                    XCTAssertFalse(error.localizedDescription.contains("synthetic-private"))
                }
                XCTAssertEqual(ProbeProtocol.requests.count, 1, "An invalid 200 response must not trigger a second billable request")
            }
        }
    }

    func testResponsesAcceptCompletedAndTokenLimitedResults() async throws {
        for status in ["completed", "incomplete"] {
            let body = #"{"object":"response","status":"\#(status)","output":[],"error":null,"incomplete_details":{"reason":"max_output_tokens"},"future":true}"#
            let result = try await probe(statuses: [200], body: body)
            XCTAssertEqual(result.endpoint, "https://fixture.invalid/v1/responses")
        }
        // Optional status and Content-Type are not required for compatible providers.
        _ = try await probe(statuses: [200], body: #"{"object":"response","output":[]}"#)
    }

    func testFailedOrMismatchedAPIResponsesAreRejected() async {
        let responses = [
            #"{"object":"response","status":"failed","output":[],"error":null}"#,
            #"{"object":"response","status":"queued","output":[]}"#,
            #"{"object":"response","status":"completed","output":[],"error":{"message":"failed"}}"#,
            #"{"object":"response","output":"not-an-array"}"#,
            #"{"type":"message","role":"assistant","content":[]}"#
        ]
        let messages = [
            #"{"type":"message","role":"user","content":[]}"#,
            #"{"type":"message","role":"assistant","content":"not-an-array"}"#,
            #"{"type":"message","role":"assistant","content":[],"error":{"message":"failed"}}"#,
            #"{"object":"response","status":"completed","output":[]}"#
        ]
        for (claude, bodies) in [(false, responses), (true, messages)] {
            for body in bodies {
                do {
                    _ = try await probe(statuses: [200], body: body, claude: claude)
                    XCTFail("Unexpected API response accepted: \(body)")
                } catch {}
                XCTAssertEqual(ProbeProtocol.requests.count, 1)
            }
        }
    }

    func testClaudeMessagesResponseStillPasses() async throws {
        let body = #"{"type":"message","role":"assistant","content":[{"type":"text","text":"pong"}],"stop_reason":"max_tokens"}"#
        let result = try await probe(statuses: [200], body: body, claude: true)
        XCTAssertEqual(result.endpoint, "https://fixture.invalid/v1/messages")
        XCTAssertEqual(ProbeProtocol.requests.first?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }
}

private final class ProbeProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var statuses: [Int] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var responseBody: String?
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    static func reset(_ next: [Int], body: String?) {
        lock.lock(); defer { lock.unlock() }
        statuses = next; recorded = []; responseBody = body
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        let responseBody = Self.responseBody
        Self.lock.unlock()
        if status == NSURLErrorCancelled {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let body = responseBody ?? (status == 200
            ? #"{"object":"response","status":"completed","output":[]}"#
            : "first endpoint error " + String(repeating: "x", count: 1000))
        let data = Data(body.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
