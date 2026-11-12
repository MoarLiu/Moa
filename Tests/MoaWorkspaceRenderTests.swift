#if !MOA_TESTING
import AppKit
import SwiftUI
import XCTest
@testable import Moa

/// Renders the real workspace views offscreen to tmp/ui-review so UI changes can
/// be reviewed without screen-recording permission. Not a behavioural test:
/// it only fails if a view cannot be hosted or drawn.
final class MoaWorkspaceRenderTests: XCTestCase {
    private func outputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/ui-review")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor func testRenderWorkspaceSurfaces() throws {
        let directory = try outputDirectory()
        _ = NSApplication.shared
        MoaRuntimeMode.suppressesUserInteraction = true
        let app = AppDelegate()
        let navigation = MoaWorkspaceNavigation()
        let accounts = MoaAccountManagerModel(app: app)

        for (name, destination) in [("overview", MoaWorkspaceDestination.overview),
                                     ("settings", .settings),
                                     ("clients", .client(.codex))] {
            navigation.destination = destination
            for (suffix, size) in [("wide", NSSize(width: 1280, height: 820)), ("compact", NSSize(width: 760, height: 820))] {
                let view = MoaWorkspaceView(app: app, navigation: navigation, accounts: accounts, usage: app.usageCoordinator)
                    .frame(width: size.width, height: size.height)
                for appearance in ["light", "dark"] {
                    try render(AnyView(view), size: size, appearance: appearance,
                               to: directory.appendingPathComponent("\(name)-\(suffix)-\(appearance).png"))
                }
            }
        }
    }

    @MainActor func testRenderPriceSettings() throws {
        let directory = try outputDirectory()
        _ = NSApplication.shared
        MoaRuntimeMode.suppressesUserInteraction = true
        let app = AppDelegate()
        let size = NSSize(width: 900, height: 560)
        let view = MoaWorkspaceSettingsView(app: app, initialTab: 1)
            .foregroundStyle(MoaWorkspaceTheme.text)
            .frame(width: size.width, height: size.height)
            .background(MoaWorkspaceTheme.canvas)
        for appearance in ["light", "dark"] {
            try render(AnyView(view), size: size, appearance: appearance,
                       to: directory.appendingPathComponent("settings-prices-\(appearance).png"))
        }
    }

    @MainActor private func render(_ view: AnyView, size: NSSize, appearance: String, to url: URL) throws {
        // A real (offscreen) window, so list styles and materials draw as they do
        // in the app; a bare hosting view leaves them blank.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<40 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw XCTSkip("no bitmap representation")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("no png data")
        }
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 1000, url.lastPathComponent)
    }
}
#endif
