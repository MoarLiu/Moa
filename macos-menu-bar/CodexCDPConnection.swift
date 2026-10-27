import Foundation

actor CodexCDPConnection {
    struct Target: Decodable {
        let id: String
        let type: String
        let url: String
        let webSocketDebuggerUrl: String?
    }
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeout: Task<Void, Never>
    }
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private var events: [[String: Any]] = []

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.connectionProxyDictionary = [:]
        self.session = session ?? URLSession(configuration: config)
    }

    static func allowedPage(_ text: String) -> Bool {
        guard let url = URLComponents(string: text), url.scheme == "app", url.host == "-",
              url.path == "/index.html", url.user == nil, url.password == nil else { return false }
        // Hidden quick-chat prewarm and pet windows share the main page's pathname.
        // Their explicit initial routes distinguish them from an actual chat window.
        let route = url.queryItems?.first { $0.name.lowercased() == "initialroute" }?.value?.lowercased() ?? ""
        let auxiliary = ["/avatar-overlay", "/chatgpt/quick-chat", "/chatgpt/quick-chat-prewarm"]
        return !auxiliary.contains(route) && !route.hasPrefix("/chatgpt/quick-chat/")
    }

    static func allowedSocket(_ text: String, port: UInt16) -> URL? {
        guard let url = URL(string: text), url.scheme == "ws", url.host == "127.0.0.1",
              url.port == Int(port), url.user == nil, url.password == nil,
              url.path.hasPrefix("/devtools/page/") else { return nil }
        return url
    }

    func discover(port: UInt16) async throws -> [Target] {
        let url = URL(string: "http://127.0.0.1:\(port)/json/list")!
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "127.0.0.1", response.url?.port == Int(port), data.count <= 1024 * 1024 else {
            throw CodexEnhancementError.protocolFailure
        }
        return try JSONDecoder().decode([Target].self, from: data).filter {
            $0.type == "page" && Self.allowedPage($0.url)
                && $0.webSocketDebuggerUrl.flatMap { Self.allowedSocket($0, port: port) } != nil
        }
    }

    func connect(_ url: URL) {
        disconnect()
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 1024 * 1024
        socket = task; task.resume()
        receiver = Task { [weak self] in await self?.receive(task) }
    }

    func command(_ method: String, _ params: [String: Any] = [:], timeout: UInt64 = 5_000_000_000) async throws -> [String: Any] {
        guard let socket else { throw CodexEnhancementError.protocolFailure }
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let message = String(decoding: data, as: UTF8.self)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                    await self?.fail(id, error: CodexEnhancementError.timeout)
                }
                pending[id] = Pending(continuation: continuation, timeout: timer)
                Task { [weak self] in
                    do { try await socket.send(.string(message)) }
                    catch { await self?.fail(id, error: error) }
                }
            }
        }, onCancel: { Task { await self.fail(id, error: CancellationError()) } })
    }

    func drainEvents() -> [[String: Any]] {
        let result = events; events.removeAll(keepingCapacity: true); return result
    }

    func disconnect() {
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        let old = pending; pending.removeAll(); events.removeAll()
        for request in old.values {
            request.timeout.cancel(); request.continuation.resume(throwing: CodexEnhancementError.protocolFailure)
        }
    }

    private func fail(_ id: Int, error: Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel(); request.continuation.resume(throwing: error)
    }

    private func receive(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                guard socket === task else { return }
                let data: Data
                switch message {
                case .string(let value): data = Data(value.utf8)
                case .data(let value): data = value
                @unknown default: continue
                }
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let id = value["id"] as? Int {
                    guard let request = pending.removeValue(forKey: id) else { continue }
                    request.timeout.cancel()
                    if value["error"] != nil { request.continuation.resume(throwing: CodexEnhancementError.protocolFailure) }
                    else { request.continuation.resume(returning: value["result"] as? [String: Any] ?? [:]) }
                } else {
                    if events.count >= 128 { throw CodexEnhancementError.protocolFailure }
                    events.append(value)
                }
            }
        } catch {
            if socket === task { disconnect() }
        }
    }
}
