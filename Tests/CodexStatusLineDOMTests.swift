#if !MOA_TESTING
import AppKit
import WebKit
import XCTest
@testable import Moa

/// An isolated HTML fixture. This never opens, attaches to, or changes the installed client.
@MainActor
final class CodexStatusLineDOMTests: XCTestCase, WKNavigationDelegate {
    private var navigation: CheckedContinuation<Void, Error>?
    private var web: WKWebView!

    private func loadFixture() async throws {
        _ = NSApplication.shared
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        web.navigationDelegate = self
        let html = """
        <html lang="en"><head><style>body{margin:0} [data-composer-footer-responsive]{display:flex;width:650px;justify-content:space-between}.leading{display:flex;gap:8px}</style></head><body>
        <div data-codex-composer-root data-composer-placement="thread">
        <div data-above-composer-conversation-id="thread-12345678"></div>
        <div data-composer-surface-variant="default"><textarea></textarea>
        <div data-composer-footer-responsive><div class="leading"><button data-composer-navigation-target="add-context">+</button></div><button id="send">Send</button></div>
        </div></div></body></html>
        """
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            web.loadHTMLString(html, baseURL: URL(string: "https://fixture.invalid"))
        }
        _ = try await evaluate("globalThis.messages=[];globalThis.__moaStatusLineRequest=s=>messages.push(JSON.parse(s));true")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume(); self.navigation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error); self.navigation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error); self.navigation = nil
    }
    private func evaluate(_ expression: String) async throws -> Any {
        try await web.evaluateJavaScript(expression) ?? NSNull()
    }
    private func install(below: Bool = false) async throws {
        var settings = CodexStatusLineSettings(); settings.belowComposer = below
        _ = try await evaluate(try CodexStatusLineScript.installation(settings: settings, epoch: "test-epoch") + ";true")
    }
    private func update(_ id: String, rate: Double, subscription: Int) async throws {
        let snapshot = CodexLiveSnapshot(threadID: id, tokensPerSecond: rate, observedAt: Date().timeIntervalSince1970, state: "active")
        _ = try await evaluate(try CodexStatusLineScript.update(snapshot, subscription: subscription) + ";true")
    }

    func testMountUpdateSwitchAndDisposeDoNotReplaceNativeControls() async throws {
        try await loadFixture()
        try await install()
        try await update("thread-12345678", rate: 80, subscription: 1)
        let initial = try await evaluate("document.getElementById('moa-codex-statusline').textContent") as? String
        XCTAssertEqual(initial, "⚡ ~80 t/s")
        let send = try await evaluate("document.getElementById('send').textContent") as? String
        XCTAssertEqual(send, "Send")
        _ = try await evaluate("document.querySelector('[data-above-composer-conversation-id]').setAttribute('data-above-composer-conversation-id','thread-87654321');true")
        // The old request's delayed completion must not paint a value into the new thread.
        try await update("thread-12345678", rate: 999, subscription: 1)
        let switched = try await evaluate("document.getElementById('moa-codex-statusline').textContent") as? String
        XCTAssertEqual(switched, "⚡ -- t/s")
        try await update("thread-87654321", rate: 25, subscription: 2)
        let next = try await evaluate("document.getElementById('moa-codex-statusline').textContent") as? String
        XCTAssertEqual(next, "⚡ ~25 t/s")
        try await install()
        let count = try await evaluate("document.querySelectorAll('#moa-codex-statusline').length") as? Int
        XCTAssertEqual(count, 1)
        _ = try await evaluate("globalThis.__moaCodexStatusLine.dispose();true")
        let remaining = try await evaluate("document.querySelectorAll('[id^=moa-codex-statusline]').length") as? Int
        XCTAssertEqual(remaining, 0)
    }

    func testHomeDraftAndExpiredLeaseRemoveOldValues() async throws {
        try await loadFixture(); try await install(below: true)
        _ = try await evaluate("document.querySelector('[data-codex-composer-root]').setAttribute('data-composer-placement','home');true")
        var count = try await evaluate("document.querySelectorAll('#moa-codex-statusline').length") as? Int
        XCTAssertEqual(count, 0)
        _ = try await evaluate("document.querySelector('[data-codex-composer-root]').setAttribute('data-composer-placement','thread');true")
        count = try await evaluate("document.querySelectorAll('#moa-codex-statusline').length") as? Int
        XCTAssertEqual(count, 1)
        _ = try await evaluate("Date.now=()=>new Date().getTime()+31000;document.dispatchEvent(new Event('visibilitychange'));true")
        count = try await evaluate("document.querySelectorAll('[id^=moa-codex-statusline]').length") as? Int
        XCTAssertEqual(count, 0)
    }

    func testUnsupportedLayoutReportsFailureAndCompatibilityLayoutWorks() async throws {
        try await loadFixture()
        _ = try await evaluate("document.querySelector('.leading').style.display='block';true")
        try await install()
        let status = try await evaluate("messages.at(-1).status") as? String
        XCTAssertEqual(status, "unsupported")
        try await install(below: true)
        let below = try await evaluate("document.getElementById('moa-codex-statusline').dataset.below") as? String
        XCTAssertEqual(below, "true")
    }

    func testPlacementOnInnerFormStillIdentifiesTheLocalChat() async throws {
        try await loadFixture()
        _ = try await evaluate("const root=document.querySelector('[data-codex-composer-root]');root.removeAttribute('data-composer-placement');const form=document.createElement('form');form.setAttribute('data-composer-placement','thread');while(root.firstChild)form.append(root.firstChild);root.append(form);true")
        try await install()
        let status = try await evaluate("messages.at(-1).status") as? String
        XCTAssertEqual(status, "ready")
        try await update("thread-12345678", rate: 80, subscription: 1)
        let label = try await evaluate("document.getElementById('moa-codex-statusline').textContent") as? String
        XCTAssertEqual(label, "⚡ ~80 t/s")
    }

    func testOverflowAndMultipleComposersNeverLeaveAStaleInlineNode() async throws {
        try await loadFixture()
        _ = try await evaluate("document.querySelector('[data-composer-footer-responsive]').style.width='10px';true")
        try await install()
        let status = try await evaluate("messages.at(-1).status") as? String
        XCTAssertEqual(status, "unsupported")
        var count = try await evaluate("document.querySelectorAll('#moa-codex-statusline').length") as? Int
        XCTAssertEqual(count, 0)
        try await install(below: true)
        _ = try await evaluate("const copy=document.querySelector('[data-codex-composer-root]').cloneNode(true);copy.querySelectorAll('[id^=moa-codex-statusline]').forEach(n=>n.remove());document.body.append(copy);true")
        count = try await evaluate("document.querySelectorAll('#moa-codex-statusline').length") as? Int
        XCTAssertEqual(count, 0)
        let last = try await evaluate("messages.at(-1).status") as? String
        XCTAssertEqual(last, "no-thread")
    }
}
#endif
