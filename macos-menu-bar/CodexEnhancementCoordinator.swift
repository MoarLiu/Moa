import AppKit
import Foundation

final class CodexEnhancementCoordinator: NSObject, @unchecked Sendable {
    private let controller: CodexAppController
    private let defaults: UserDefaults
    private let runtime: CodexEnhancementRuntime
    private let operations: MoaAccountOperationState
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    private var running = false
    private let toggleItem = NSMenuItem()
    private let stateItem = NSMenuItem()
    private let optionsItem = NSMenuItem(title: MoaL10n.text("Status Line Settings"), action: nil, keyEquivalent: "")
    private let contextItem = NSMenuItem()
    private let cacheItem = NSMenuItem()
    private let belowItem = NSMenuItem()

    init(controller: CodexAppController, operations: MoaAccountOperationState,
         defaults: UserDefaults = .standard, runtime: CodexEnhancementRuntime = .shared) {
        self.controller = controller; self.defaults = defaults; self.runtime = runtime
        self.operations = operations
        super.init()
        toggleItem.title = MoaL10n.text("Show Generation Rate (Estimated)")
        toggleItem.target = self; toggleItem.action = #selector(toggle)
        stateItem.isEnabled = false
        let options = NSMenu()
        options.autoenablesItems = false
        for (item, title, action) in [
            (contextItem, "Show Request Tokens and Context", #selector(toggleContext)),
            (cacheItem, "Show Input Cache Hit Rate", #selector(toggleCache)),
            (belowItem, "Use Layout Below the Composer", #selector(toggleBelow))
        ] {
            item.title = MoaL10n.text(title); item.target = self; item.action = action; options.addItem(item)
        }
        options.addItem(.separator())
        let reopen = NSMenuItem(title: MoaL10n.text("Reopen ChatGPT to Apply"), action: #selector(reopen), keyEquivalent: "")
        reopen.target = self; options.addItem(reopen)
        let explanation = NSMenuItem(title: MoaL10n.text("Uses a local debug connection; finish active tasks before reopening."), action: nil, keyEquivalent: "")
        explanation.isEnabled = false; options.addItem(explanation)
        optionsItem.submenu = options
        refreshChecks()
        stateItem.title = MoaL10n.text("Status line: off")
    }

    var menuItems: [NSMenuItem] { [toggleItem, stateItem, optionsItem] }

    func start() {
        running = true
        restartWorker()
    }

    func stop() { running = false; generation = UUID(); worker?.cancel(); worker = nil }

    @objc private func toggle() { change { $0.enabled.toggle() } }
    @objc private func toggleContext() { change { $0.showContext.toggle() } }
    @objc private func toggleCache() { change { $0.showCache.toggle() } }
    @objc private func toggleBelow() { change { $0.belowComposer.toggle() } }
    @objc private func reopen() {
        guard let token = operations.begin(.codex, message: MoaL10n.text("Reopening Codex...")) else { return }
        let controller = controller
        let operations = operations
        Task.detached {
            controller.reopenCodexSafely()
            await MainActor.run { operations.finish(.codex, id: token) }
        }
    }

    private func change(_ edit: (inout CodexStatusLineSettings) -> Void) {
        var settings = CodexStatusLineSettings(defaults: defaults)
        edit(&settings); settings.save(to: defaults)
        refreshChecks(); restartWorker()
    }

    private func refreshChecks() {
        let settings = CodexStatusLineSettings(defaults: defaults)
        toggleItem.state = settings.enabled ? .on : .off
        contextItem.state = settings.showContext ? .on : .off
        cacheItem.state = settings.showCache ? .on : .off
        belowItem.state = settings.belowComposer ? .on : .off
    }

    private func restartWorker() {
        let old = worker
        old?.cancel()
        generation = UUID()
        let token = generation
        let settings = CodexStatusLineSettings(defaults: defaults)
        let runtime = runtime
        guard running else { return }
        worker = Task.detached { [weak self] in
            // Dispose the old isolated world before installing a replacement in that world.
            await old?.value
            guard !Task.isCancelled else { return }
            if !settings.enabled {
                while !Task.isCancelled {
                    let launched = runtime.launch != nil
                    await self?.setStatus(launched ? "Status line: off; reopen to restore normal launch" : "Status line: off", token: token)
                    if !launched { break }
                    do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
                }
                return
            }
            await self?.run(settings: settings, token: token)
        }
    }

    @MainActor private func setStatus(_ title: String, token: UUID) {
        guard running, generation == token else { return }
        stateItem.title = MoaL10n.text(title)
    }

    private func run(settings: CodexStatusLineSettings, token: UUID) async {
        var delay: UInt64 = 1
        while !Task.isCancelled {
            guard let launch = runtime.launch else {
                await setStatus(runtime.error ?? "Status line: waiting for ChatGPT to reopen through Moa", token: token)
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                continue
            }
            let connection = CodexCDPConnection()
            var context: Int?
            do {
                try CodexEnhancementRuntime.verifyListener(launch)
                let targets = try await connection.discover(port: launch.port)
                // A single verified main page is supported initially; never guess between windows.
                guard targets.count == 1, let text = targets[0].webSocketDebuggerUrl,
                      let url = CodexCDPConnection.allowedSocket(text, port: launch.port) else {
                    throw CodexEnhancementError.mainPage
                }
                await connection.connect(url)
                _ = try await connection.command("Page.enable")
                let tree = try await connection.command("Page.getFrameTree")
                guard let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                      let frameID = frame["id"] as? String,
                      let frameURL = frame["url"] as? String, CodexCDPConnection.allowedPage(frameURL) else {
                    throw CodexEnhancementError.protocolFailure
                }
                _ = try await connection.command("Runtime.enable")
                let world = try await connection.command("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "MoaStatusLine", "grantUniveralAccess": false])
                guard let worldID = world["executionContextId"] as? Int else { throw CodexEnhancementError.protocolFailure }
                context = worldID
                _ = try await connection.command("Runtime.addBinding", ["name": "__moaStatusLineRequest", "executionContextId": worldID])
                let epoch = UUID().uuidString
                try await evaluate(try CodexStatusLineScript.installation(settings: settings, epoch: epoch), context: worldID, connection: connection)
                delay = 1
                await setStatus("Status line: connected; waiting for a local chat", token: token)
                // Drop setup events (including initial frame/context creation), but retain subscriptions.
                var events = await connection.drainEvents().filter { $0["method"] as? String == "Runtime.bindingCalled" }
                let index = CodexSessionIndex(environment: launch.environment)
                var thread = "", subscription = 0
                var reader: CodexLiveUsageReader?
                while !Task.isCancelled {
                    var interval: UInt64 = 5
                    guard runtime.launch?.generation == launch.generation else { break }
                    events += await connection.drainEvents()
                    for event in events {
                        let method = event["method"] as? String
                        let params = event["params"] as? [String: Any] ?? [:]
                        if method == "Runtime.executionContextsCleared"
                            || method == "Page.frameNavigated" && ((params["frame"] as? [String: Any])?["id"] as? String) == frameID
                            || method == "Runtime.executionContextDestroyed" && params["executionContextId"] as? Int == worldID {
                            throw CodexEnhancementError.protocolFailure
                        }
                        guard method == "Runtime.bindingCalled", params["name"] as? String == "__moaStatusLineRequest",
                              params["executionContextId"] as? Int == worldID,
                              let payload = params["payload"] as? String, payload.utf8.count < 2048,
                              let data = payload.data(using: .utf8),
                              let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              request["version"] as? Int == 1, request["epoch"] as? String == epoch,
                              let next = request["threadID"] as? String,
                              let nextSubscription = request["subscription"] as? Int, nextSubscription >= subscription,
                              next.isEmpty || CodexLiveMetrics.validThreadID(next) else { continue }
                        if next != thread || nextSubscription != subscription { reader = nil }
                        thread = next; subscription = nextSubscription
                        switch request["status"] as? String {
                        case "unsupported":
                            thread = ""; reader = nil
                            await setStatus("Status line: layout unsupported; try the below-composer layout", token: token)
                        case "no-thread":
                            thread = ""; reader = nil
                            await setStatus("Status line: connected; waiting for a local chat", token: token)
                        case "ready": await setStatus("Status line: enabled", token: token)
                        default: thread = ""; reader = nil
                        }
                    }
                    events.removeAll(keepingCapacity: true)
                    if !thread.isEmpty {
                        if reader == nil, let url = index.file(for: thread) { reader = CodexLiveUsageReader(url: url, threadID: thread) }
                        var snapshot = CodexLiveSnapshot(threadID: thread)
                        if let current = reader {
                            do { snapshot = try current.read() }
                            catch { reader = nil; snapshot.state = "unavailable" }
                        } else { snapshot.state = "unavailable" }
                        if snapshot.state == "unavailable" { await setStatus("Status line: no local usage record for this chat", token: token) }
                        else { await setStatus("Status line: enabled", token: token) }
                        if snapshot.state == "active", let timestamp = snapshot.observedAt,
                           Date().timeIntervalSince1970 - timestamp < 120 { interval = 1 }
                        try await evaluate(try CodexStatusLineScript.update(snapshot, subscription: subscription), context: worldID, connection: connection)
                    } else {
                        try await evaluate("globalThis.__moaCodexStatusLine?.keepAlive()", context: worldID, connection: connection)
                    }
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                }
            } catch {
                if !Task.isCancelled { await setStatus(error.localizedDescription, token: token) }
            }
            // Cleanup must run outside the cancelled task, so command cancellation does not skip it.
            await Task.detached {
                if let context {
                    _ = try? await connection.command("Runtime.evaluate", ["expression": "globalThis.__moaCodexStatusLine?.dispose()", "contextId": context], timeout: 500_000_000)
                }
                await connection.disconnect()
            }.value
            if Task.isCancelled { return }
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            delay = min(30, delay * 2)
        }
    }

    private func evaluate(_ expression: String, context: Int, connection: CodexCDPConnection) async throws {
        let result = try await connection.command("Runtime.evaluate", ["expression": expression, "contextId": context, "returnByValue": true])
        if result["exceptionDetails"] != nil { throw CodexEnhancementError.protocolFailure }
    }
}
