#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class CodexLiveUsageTests: XCTestCase {
    private let thread = "thread-12345678"

    private func line(_ type: String, _ payload: [String: Any], _ second: Int = 0) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "type": type, "payload": payload,
            "timestamp": String(format: "2026-10-27T00:00:%02dZ", second)
        ], options: [.sortedKeys])
        data.append(10); return data
    }
    private func counts(_ output: Int, input: Int = 1000) -> [String: Int] {
        ["input_tokens": input, "cached_input_tokens": input / 2, "output_tokens": output,
         "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }
    private func begin(_ metrics: inout CodexLiveMetrics, turn: String = "turn-one", model: String = "test-model") throws {
        metrics.consume(try line("event_msg", ["type": "task_started", "turn_id": turn, "model_context_window": 10000]))
        metrics.consume(try line("turn_context", ["turn_id": turn, "model": model]))
    }
    private func record(_ output: Int, total: Int, id: String, second: Int, turn: String = "turn-one") throws -> Data {
        try line("token_usage_record", ["thread_id": thread, "turn_id": turn, "response_id": id,
                                        "usage": counts(output), "thread_token_usage": counts(total, input: total * 10)], second)
    }
    private func legacy(_ output: Int, total: Int, second: Int) throws -> Data {
        try line("event_msg", ["type": "token_count", "info": ["last_token_usage": counts(output),
                  "total_token_usage": counts(total, input: total * 10), "model_context_window": 10000]], second)
    }

    func testMirrorsDeduplicateInEitherOrderAndReasoningIsNotAddedAgain() throws {
        for legacyFirst in [false, true] {
            var metrics = CodexLiveMetrics(threadID: thread)
            try begin(&metrics)
            for (output, total, id, second) in [(100, 100, "one", 0), (200, 300, "two", 10)] {
                let new = try record(output, total: total, id: id, second: second)
                let old = try legacy(output, total: total, second: second)
                for data in legacyFirst ? [old, new, new, old] : [new, old, new, old] { metrics.consume(data) }
            }
            XCTAssertEqual(try XCTUnwrap(metrics.snapshot.tokensPerSecond), 20, accuracy: 0.001)
            XCTAssertEqual(metrics.snapshot.requestTokens, 1200)
            XCTAssertEqual(metrics.snapshot.contextPercent, 12)
            XCTAssertEqual(metrics.snapshot.cachePercent, 50)
        }
    }

    func testWeightedIntervalsAndTurnModelChanges() throws {
        var metrics = CodexLiveMetrics(threadID: thread)
        try begin(&metrics)
        metrics.consume(try record(100, total: 100, id: "a", second: 0))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
        metrics.consume(try record(200, total: 300, id: "b", second: 2))
        metrics.consume(try record(100, total: 400, id: "c", second: 12))
        XCTAssertEqual(try XCTUnwrap(metrics.snapshot.tokensPerSecond), 25, accuracy: 0.001)
        metrics.consume(try line("turn_context", ["model": "other-model", "turn_id": "turn-one"]))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
        XCTAssertNil(metrics.snapshot.contextPercent)
        try begin(&metrics, turn: "turn-two")
        metrics.consume(try record(100, total: 500, id: "d", second: 20, turn: "turn-two"))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
    }

    func testLegacyOnlyHistoryAndForeignThreadsDoNotContaminateCurrentTurn() throws {
        var metrics = CodexLiveMetrics(threadID: thread)
        metrics.consume(try legacy(1000, total: 1000, second: 0))
        XCTAssertNil(metrics.snapshot.requestTokens)
        try begin(&metrics)
        metrics.consume(try legacy(100, total: 1100, second: 10))
        metrics.consume(try legacy(200, total: 1300, second: 20))
        metrics.consume(try line("token_usage_record", ["thread_id": "another-thread", "turn_id": "turn-one", "usage": counts(9999)], 21))
        XCTAssertEqual(metrics.snapshot.tokensPerSecond, 20)
        metrics.consume(try line("event_msg", ["type": "turn_aborted", "turn_id": "turn-one"], 22))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
        XCTAssertEqual(metrics.snapshot.state, "stopped")
    }

    func testMissingTurnIdentityDoesNotProduceSpeed() throws {
        var metrics = CodexLiveMetrics(threadID: thread)
        metrics.consume(try line("turn_context", ["model": "test-model"]))
        metrics.consume(try legacy(100, total: 100, second: 0))
        metrics.consume(try legacy(200, total: 300, second: 10))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
    }

    func testInvalidTimeGapCannotRelabelAnOldRateAsFresh() throws {
        var metrics = CodexLiveMetrics(threadID: thread)
        try begin(&metrics)
        metrics.consume(try record(100, total: 100, id: "a", second: 0))
        metrics.consume(try record(200, total: 300, id: "b", second: 10))
        XCTAssertEqual(metrics.snapshot.tokensPerSecond, 20)
        let data = try line("token_usage_record", ["turn_id": "turn-one", "response_id": "c",
                    "usage": counts(100), "thread_token_usage": counts(400, input: 4000)], 20)
        let later = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "00:00:20", with: "00:10:20")
        metrics.consume(Data(later.utf8))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
    }

    func testIncrementalReadWaitsForNewlineAndResetsAfterAtomicReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("rollout.jsonl")
        var initial = Data()
        initial.append(try line("event_msg", ["type": "task_started", "turn_id": "turn-one"]))
        initial.append(try line("turn_context", ["model": "test-model", "turn_id": "turn-one"]))
        initial.append(try record(100, total: 100, id: "a", second: 0))
        try initial.write(to: file)
        let reader = CodexLiveUsageReader(url: file, threadID: thread)
        XCTAssertNil(try reader.read().tokensPerSecond)
        let readCount = reader.bytesRead
        _ = try reader.read()
        XCTAssertEqual(reader.bytesRead, readCount)
        let next = try record(200, total: 300, id: "b", second: 10)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: next.dropLast())
        XCTAssertNil(try reader.read().tokensPerSecond)
        try handle.write(contentsOf: Data([10])); try handle.close()
        XCTAssertEqual(try reader.read().tokensPerSecond, 20)
        let replacement = try line("turn_context", ["model": "new-model", "turn_id": "turn-two"])
        try replacement.write(to: file, options: .atomic)
        let reset = try reader.read()
        XCTAssertEqual(reset.model, "new-model")
        XCTAssertNil(reset.tokensPerSecond)
        XCTAssertNil(reset.requestTokens)
    }

    func testOversizedToolLineAndSplitUTF8DoNotBlockUsage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.jsonl")
        var data = Data(repeating: 65, count: 600 * 1024); data.append(10)
        data.append(try line("event_msg", ["type": "task_started", "turn_id": "turn-one"]))
        data.append(try line("turn_context", ["model": "模型", "turn_id": "turn-one"]))
        data.append(try record(100, total: 100, id: "a", second: 0))
        data.append(try record(200, total: 300, id: "b", second: 10))
        try data.write(to: file)
        let reader = CodexLiveUsageReader(url: file, threadID: thread)
        XCTAssertEqual(try reader.read().tokensPerSecond, 20)
        XCTAssertEqual(try reader.read().model, "模型")
    }

    func testIndexChecksMetadataAndRejectsPathTraversalAndSymlinks() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessions.appendingPathComponent("rollout-\(thread).jsonl")
        try line("session_meta", ["id": "wrong-thread"]).write(to: file)
        let index = CodexSessionIndex(environment: ["CODEX_HOME": home.path])
        XCTAssertNil(index.file(for: thread))
        XCTAssertNil(index.file(for: "../../anything"))
        try line("session_meta", ["id": thread]).write(to: file)
        let found = try XCTUnwrap(index.file(for: thread, now: Date().addingTimeInterval(6)))
        let foundIdentity = try FileManager.default.attributesOfItem(atPath: found.path)[.systemFileNumber] as? NSNumber
        let expectedIdentity = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        XCTAssertEqual(foundIdentity, expectedIdentity)
        let linked = sessions.appendingPathComponent("rollout-linked-thread.jsonl")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: file)
        XCTAssertNil(index.file(for: "linked-thread", now: Date().addingTimeInterval(12)))
    }

    func testSettingsAndEndpointValidationAreLocalAndDefaultOff() throws {
        let name = "MoaStatusLineTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(CodexStatusLineSettings(defaults: defaults).enabled)
        var settings = CodexStatusLineSettings(); settings.enabled = true; settings.showContext = true
        settings.save(to: defaults)
        XCTAssertEqual(CodexStatusLineSettings(defaults: defaults), settings)
        XCTAssertTrue(CodexEnhancementRuntime.isLoopbackListener("p123\nn127.0.0.1:9229\n", port: 9229))
        XCTAssertFalse(CodexEnhancementRuntime.isLoopbackListener("p123\nn*:9229\n", port: 9229))
        XCTAssertNil(CodexCDPConnection.allowedSocket("ws://example.com:9229/devtools/page/1", port: 9229))
        XCTAssertNil(CodexCDPConnection.allowedSocket("ws://127.0.0.1:9230/devtools/page/1", port: 9229))
        XCTAssertTrue(CodexCDPConnection.allowedPage("app://-/index.html#/thread/123"))
        XCTAssertFalse(CodexCDPConnection.allowedPage("https://example.com/index.html"))
        XCTAssertFalse(CodexEnhancementRuntime.arguments(port: 9229).contains { $0.contains("origins=*") })
    }

    func testCounterResetRebasesAndDistinctIdenticalRequestsRemainSamples() throws {
        var metrics = CodexLiveMetrics(threadID: thread)
        try begin(&metrics)
        metrics.consume(try record(100, total: 100, id: "a", second: 0))
        metrics.consume(try record(100, total: 200, id: "b", second: 10))
        XCTAssertEqual(metrics.snapshot.tokensPerSecond, 10)
        metrics.consume(try record(50, total: 50, id: "c", second: 20))
        XCTAssertNil(metrics.snapshot.tokensPerSecond)
        metrics.consume(try record(50, total: 100, id: "d", second: 30))
        XCTAssertEqual(metrics.snapshot.tokensPerSecond, 5)
    }

    func testEnhancementLaunchUsesOnlyTheFixtureAndPreservesTheRequestedHome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Fixture.app")
        let executable = app.appendingPathComponent("Contents/MacOS/fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist: [String: Any] = ["CFBundleIdentifier": "com.openai.codex", "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let output = root.appendingPathComponent("args.txt")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$CODEX_HOME\" \"$@\" > \"$MOA_FIXTURE_ARGS\"\nexec /bin/sleep 30\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let runtime = CodexEnhancementRuntime()
        try runtime.start(app: app, environment: ["CODEX_HOME": root.appendingPathComponent("logs").path, "MOA_FIXTURE_ARGS": output.path])
        let launch = try XCTUnwrap(runtime.launch)
        defer { if launch.process.isRunning { launch.process.terminate(); launch.process.waitUntilExit() } }
        for _ in 0..<50 {
            if (try? String(contentsOf: output).contains("--remote-debugging-port=")) == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let arguments = try String(contentsOf: output)
        XCTAssertTrue(arguments.hasPrefix(root.appendingPathComponent("logs").path + "\n"))
        XCTAssertTrue(arguments.contains("--remote-debugging-address=127.0.0.1"))
        XCTAssertTrue(arguments.contains("--remote-debugging-port=\(launch.port)"))
        // The sleep fixture has no debug listener: ownership validation must fail closed.
        XCTAssertThrowsError(try CodexEnhancementRuntime.verifyListener(launch))
    }
}
#endif
