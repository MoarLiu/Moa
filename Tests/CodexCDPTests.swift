#if !MOA_TESTING
import CryptoKit
import Foundation
import Network
import XCTest
@testable import Moa

/// A loopback-only protocol fixture, unrelated to any running application.
private final class CDPFixture {
    let queue = DispatchQueue(label: "Moa.CDPFixture")
    let listener: NWListener
    var port: UInt16 { listener.port!.rawValue }
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ready = State()
            listener.stateUpdateHandler = { state in
                guard !ready.started else { return }
                if case .ready = state { ready.started = true; continuation.resume() }
                if case .failed(let error) = state { ready.started = true; continuation.resume(throwing: error) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.read(connection, state: State())
            }
            listener.start(queue: queue)
        }
    }
    func stop() {
        queue.sync { connections.forEach { $0.cancel() }; listener.cancel() }
    }
    private final class State {
        var started = false
        var buffer = Data()
        var upgraded = false
        var deferred: [[String: Any]] = []
    }
    private func read(_ connection: NWConnection, state: State) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil, !complete else { return }
            if let data { state.buffer.append(data) }
            if !state.upgraded {
                if let end = state.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let header = String(decoding: state.buffer[..<end.upperBound], as: UTF8.self)
                    state.buffer.removeSubrange(..<end.upperBound)
                    if header.hasPrefix("GET /json/list ") {
                        let body = try! JSONSerialization.data(withJSONObject: [
                            ["id": "main", "type": "page", "url": "app://-/index.html", "webSocketDebuggerUrl": "ws://127.0.0.1:\(self.port)/devtools/page/main"],
                            ["id": "prewarm", "type": "page", "url": "app://-/index.html?initialRoute=%2Fchatgpt%2Fquick-chat-prewarm", "webSocketDebuggerUrl": "ws://127.0.0.1:\(self.port)/devtools/page/prewarm"],
                            ["id": "pet", "type": "page", "url": "app://-/index.html?initialRoute=%2Favatar-overlay", "webSocketDebuggerUrl": "ws://127.0.0.1:\(self.port)/devtools/page/pet"],
                            ["id": "untrusted", "type": "page", "url": "app://-/index.html", "webSocketDebuggerUrl": "ws://example.com:\(self.port)/devtools/page/other"]
                        ])
                        var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                        response.append(body)
                        connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                        return
                    }
                    guard let line = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }) else { connection.cancel(); return }
                    let key = String(line.dropFirst("sec-websocket-key:".count)).trimmingCharacters(in: .whitespaces)
                    let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
                    let accept = Data(digest).base64EncodedString()
                    let response = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8)
                    connection.send(content: response, completion: .contentProcessed { _ in })
                    state.upgraded = true
                }
            }
            if state.upgraded {
                while let payload = self.frame(&state.buffer) {
                    guard let value = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                          let id = value["id"] as? Int, let method = value["method"] as? String else { continue }
                    if method == "Hang" { continue }
                    if ["One", "Two"].contains(method) {
                        state.deferred.append(["id": id, "result": ["method": method]])
                        if state.deferred.count == 2 {
                            self.send(["method": "Runtime.bindingCalled", "params": ["payload": "fixture"]], connection)
                            for response in state.deferred.reversed() { self.send(response, connection) }
                            state.deferred.removeAll()
                        }
                    } else { self.send(["id": id, "result": ["method": method]], connection) }
                }
            }
            if state.buffer.count < 1024 * 1024 { self.read(connection, state: state) }
            else { connection.cancel() }
        }
    }
    private func frame(_ buffer: inout Data) -> Data? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }
        var length = Int(bytes[1] & 127), offset = 2
        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = Int(bytes[2]) * 256 + Int(bytes[3]); offset = 4
        } else if length == 127 { return nil }
        let masked = bytes[1] & 128 != 0
        let header = offset + (masked ? 4 : 0)
        guard bytes.count >= header + length else { return nil }
        let data = Data((0..<length).map { bytes[header + $0] ^ (masked ? bytes[offset + $0 % 4] : 0) })
        buffer.removeFirst(header + length)
        return data
    }
    private func send(_ value: [String: Any], _ connection: NWConnection) {
        let data = try! JSONSerialization.data(withJSONObject: value)
        var frame = Data([0x81])
        if data.count < 126 { frame.append(UInt8(data.count)) }
        else { frame.append(contentsOf: [126, UInt8(data.count >> 8), UInt8(data.count & 255)]) }
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }
}

final class CodexCDPTests: XCTestCase {
    func testAuxiliaryWindowsCannotMakeTheMainPageAmbiguous() {
        XCTAssertTrue(CodexCDPConnection.allowedPage("app://-/index.html?initialRoute=%2Flocal%2Fthread-12345678"))
        for route in ["%2Favatar-overlay", "%2Fchatgpt%2Fquick-chat-prewarm", "%2Fchatgpt%2Fquick-chat", "%2Fchatgpt%2Fquick-chat%2Fthread"] {
            XCTAssertFalse(CodexCDPConnection.allowedPage("app://-/index.html?initialRoute=" + route))
        }
        XCTAssertFalse(CodexCDPConnection.allowedPage("app://user@-/index.html"))
    }

    func testDiscoveryAndOutOfOrderResponsesKeepEventsSeparate() async throws {
        let fixture = try CDPFixture(); try await fixture.start()
        defer { fixture.stop() }
        let connection = CodexCDPConnection()
        let targets = try await connection.discover(port: fixture.port)
        XCTAssertEqual(targets.map(\.id), ["main"])
        let url = try XCTUnwrap(CodexCDPConnection.allowedSocket(try XCTUnwrap(targets.first?.webSocketDebuggerUrl), port: fixture.port))
        await connection.connect(url)
        async let one = connection.command("One")
        async let two = connection.command("Two")
        let results = try await (one, two)
        XCTAssertEqual(results.0["method"] as? String, "One")
        XCTAssertEqual(results.1["method"] as? String, "Two")
        let events = await connection.drainEvents()
        XCTAssertEqual(events.first?["method"] as? String, "Runtime.bindingCalled")
        await connection.disconnect()
    }

    func testTimeoutAndCancellationDoNotBreakFollowingCommands() async throws {
        let fixture = try CDPFixture(); try await fixture.start()
        defer { fixture.stop() }
        let connection = CodexCDPConnection()
        let url = try XCTUnwrap(CodexCDPConnection.allowedSocket("ws://127.0.0.1:\(fixture.port)/devtools/page/main", port: fixture.port))
        await connection.connect(url)
        do { _ = try await connection.command("Hang", timeout: 50_000_000); XCTFail("must time out") }
        catch { XCTAssertTrue(error is CodexEnhancementError) }
        let task = Task { try await connection.command("Hang") }
        task.cancel()
        do { _ = try await task.value; XCTFail("must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await connection.command("Echo")
        XCTAssertEqual(result["method"] as? String, "Echo")
        await connection.disconnect()
    }
}
#endif
