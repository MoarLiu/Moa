import Foundation
import XCTest
@testable import Moa

final class MoaUpdaterRegressionTests: XCTestCase {
    private func entry(_ version: String, asset: Bool) -> String {
        let architecture: String
        #if arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "arm64"
        #endif
        return """
        <entry><title>v\(version)</title><link rel="alternate" href="https://github.com/MoarLiu/Moa/releases/tag/v\(version)"/>
        <content>\(asset ? "Moa-\(version)-macos-\(architecture).dmg" : "No assets")</content></entry>
        """
    }

    func testFeedDoesNotSkipStableReleaseMissingAssets() throws {
        let feed = "<feed>\(entry("3.0.0", asset: false))\(entry("2.0.0", asset: true))</feed>"
        XCTAssertThrowsError(try MoaUpdateController.releaseInfo(fromAtomFeed: feed)) { error in
            guard case MoaUpdateError.missingReleaseAsset = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testFeedSkipsPrereleaseBeforeCheckingItsAssets() throws {
        let feed = "<feed>\(entry("3.0.0-rc.1", asset: false))\(entry("2.0.0", asset: true))</feed>"
        XCTAssertEqual(try MoaUpdateController.releaseInfo(fromAtomFeed: feed).version, "2.0.0")
    }

    func testMissingAPIAssetDoesNotFallBackToFeed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        UpdateURLProtocol.reset()
        do {
            _ = try await MoaUpdateController(session: session).checkForUpdate()
            XCTFail("Expected a missing asset error")
        } catch MoaUpdateError.missingReleaseAsset {
            XCTAssertEqual(UpdateURLProtocol.requests, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallerWaitsForOldProcessAndInstalls() throws {
        try withInstaller { fixture in
            let old = Process()
            old.executableURL = URL(fileURLWithPath: "/bin/sleep")
            old.arguments = ["1"]
            try old.run()
            defer { if old.isRunning { old.terminate(); old.waitUntilExit() } }
            let start = Date()
            let status = try fixture.run(pid: old.processIdentifier)
            XCTAssertEqual(status, 0)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.7)
            XCTAssertEqual(try String(contentsOf: fixture.app.appendingPathComponent("version"), encoding: .utf8), "new")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.log.path))
        }
    }

    func testMountFailurePreservesAppAndReportsFailure() throws {
        try withInstaller { fixture in
            XCTAssertNotEqual(try fixture.run(pid: 99999999, failMount: true), 0)
            XCTAssertEqual(try String(contentsOf: fixture.app.appendingPathComponent("version"), encoding: .utf8), "old")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.log.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.alert.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.opened.path))
        }
    }

    func testInstallerDoesNotReplaceAppIfOldProcessStaysRunning() throws {
        try withInstaller { fixture in
            let old = Process()
            old.executableURL = URL(fileURLWithPath: "/bin/sleep")
            old.arguments = ["5"]
            try old.run()
            defer { if old.isRunning { old.terminate(); old.waitUntilExit() } }
            XCTAssertNotEqual(try fixture.run(pid: old.processIdentifier, shortWait: true), 0)
            XCTAssertEqual(try String(contentsOf: fixture.app.appendingPathComponent("version"), encoding: .utf8), "old")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.opened.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.alert.path))
        }
    }

    func testLaunchFailureRestoresPreviousApp() throws {
        try withInstaller { fixture in
            XCTAssertNotEqual(try fixture.run(pid: 99999999, failFirstOpen: true), 0)
            XCTAssertEqual(try String(contentsOf: fixture.app.appendingPathComponent("version"), encoding: .utf8), "old")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.log.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.alert.path))
            XCTAssertEqual(try String(contentsOf: fixture.opened, encoding: .utf8).split(separator: "\n").count, 2)
        }
    }

    func testCopyFailureKeepsPreviousApp() throws {
        try withInstaller { fixture in
            XCTAssertNotEqual(try fixture.run(pid: 99999999, failCopy: true), 0)
            XCTAssertEqual(try String(contentsOf: fixture.app.appendingPathComponent("version"), encoding: .utf8), "old")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.log.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.opened.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.work.path))
        }
    }

    private func withInstaller(_ body: (InstallerFixture) throws -> Void) throws {
        let fixture = try InstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try body(fixture)
    }
}

private final class UpdateURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        let body = #"{"tag_name":"v999.0.0","name":"999.0.0","html_url":"https://github.com/MoarLiu/Moa/releases/tag/v999.0.0","assets":[]}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class InstallerFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("moa-updater-test-\(UUID().uuidString)")
    var app: URL { root.appendingPathComponent("Moa.app") }
    var log: URL { root.appendingPathComponent("installer.log") }
    var opened: URL { root.appendingPathComponent("opened") }
    var alert: URL { root.appendingPathComponent("alert") }
    var mount: URL { root.appendingPathComponent("mount") }
    var work: URL { root.appendingPathComponent("work") }

    init() throws {
        let fm = FileManager.default
        for dir in [app, mount.appendingPathComponent("Moa.app"), work, root.appendingPathComponent("backup.app"), root.appendingPathComponent("bin")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "old".write(to: app.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try "new".write(to: mount.appendingPathComponent("Moa.app/version"), atomically: true, encoding: .utf8)
        try mock("hdiutil", "if [[ \"$1\" == attach && \"${FAIL_MOUNT:-0}\" == 1 ]]; then exit 1; fi\nexit 0")
        try mock("awk", "printf '%s\\n' \"$TEST_MOUNT\"")
        try mock("ditto", "if [[ \"${FAIL_COPY:-0}\" == 1 ]]; then exit 1; fi\n/bin/cp -R \"${@: -2:1}\" \"${@: -1}\"")
        try mock("codesign", "exit 0")
        try mock("spctl", "exit 0")
        try mock("open", "echo open >> \"$TEST_OPENED\"\nif [[ \"${FAIL_FIRST_OPEN:-0}\" == 1 && $(/usr/bin/wc -l < \"$TEST_OPENED\") -eq 1 ]]; then exit 1; fi")
        try mock("osascript", "touch \"$TEST_ALERT\"")
    }

    private func mock(_ name: String, _ body: String) throws {
        let url = root.appendingPathComponent("bin/\(name)")
        try ("#!/bin/bash\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func run(pid: Int32, failMount: Bool = false, failFirstOpen: Bool = false, failCopy: Bool = false, shortWait: Bool = false) throws -> Int32 {
        var script = MoaUpdateController.installerScript
        if shortWait { script = script.replacingOccurrences(of: "{1..300}", with: "{1..3}") }
        for path in ["/usr/bin/hdiutil", "/usr/bin/awk", "/usr/bin/ditto", "/usr/bin/codesign", "/usr/sbin/spctl", "/usr/bin/open", "/usr/bin/osascript"] {
            script = script.replacingOccurrences(of: path, with: root.appendingPathComponent("bin/" + URL(fileURLWithPath: path).lastPathComponent).path)
        }
        let scriptURL = root.appendingPathComponent("installer.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, root.appendingPathComponent("update.dmg").path, app.path, root.appendingPathComponent("backup.app").path, log.path, work.path, scriptURL.path, String(pid)]
        var environment = ProcessInfo.processInfo.environment
        environment["TEST_MOUNT"] = mount.path
        environment["TEST_OPENED"] = opened.path
        environment["TEST_ALERT"] = alert.path
        environment["FAIL_MOUNT"] = failMount ? "1" : "0"
        environment["FAIL_FIRST_OPEN"] = failFirstOpen ? "1" : "0"
        environment["FAIL_COPY"] = failCopy ? "1" : "0"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
