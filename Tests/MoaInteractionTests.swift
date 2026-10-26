#if !MOA_TESTING
import AppKit
import SwiftUI
import XCTest
@testable import Moa

final class MoaInteractionTests: XCTestCase {
    @MainActor func testClientOperationsCoordinateMenuAndWindowAndIgnoreStaleCompletion() throws {
        let state = MoaAccountOperationState()
        XCTAssertEqual(MoaAccountGroup.codexOfficial.client, MoaAccountGroup.codexConfig.client)
        let first = try XCTUnwrap(state.begin(.workbuddy, message: "switch"))
        XCTAssertNil(state.begin(.workbuddy, message: "duplicate window click"))
        let other = try XCTUnwrap(state.begin(.workbuddyCN, message: "save"))
        state.finish(.workbuddy, id: first)
        let next = try XCTUnwrap(state.begin(.workbuddy, message: "retry"))
        state.finish(.workbuddy, id: first)
        XCTAssertEqual(state.active[.workbuddy]?.id, next)
        XCTAssertEqual(state.active[.workbuddyCN]?.id, other)
        state.finish(.workbuddy, id: next)
        state.finish(.workbuddyCN, id: other)
        XCTAssertTrue(state.active.isEmpty)
    }

    @MainActor func testNativeRefreshMenuActionAndBusyAvailability() throws {
        _ = NSApplication.shared
        let item = MoaUsageRefreshMenuItem()
        var calls = 0
        XCTAssertNil(item.view)
        XCTAssertFalse(item.isEnabled)
        item.onRefresh = { calls += 1 }
        let action = try XCTUnwrap(item.action)
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
        XCTAssertEqual(calls, 1)
        item.setRefreshing(true)
        XCTAssertFalse(item.isEnabled)
        _ = NSApp.sendAction(action, to: item.target, from: item)
        XCTAssertEqual(calls, 1)
        item.setRefreshing(false)
        XCTAssertTrue(item.isEnabled)
        item.onRefresh = nil
        XCTAssertFalse(item.isEnabled)
    }

    @MainActor func testOldFeedbackDismissalCannotClearNewFeedback() throws {
        MoaRuntimeMode.suppressesUserInteraction = true
        let feedback = MoaFeedbackCenter()
        feedback.show(title: "copied", detail: "first")
        let first = try XCTUnwrap(feedback.message?.id)
        feedback.show(title: "updated", detail: "second")
        let second = try XCTUnwrap(feedback.message?.id)
        feedback.dismiss(id: first)
        XCTAssertEqual(feedback.message?.id, second)
        feedback.dismiss(id: second)
        XCTAssertNil(feedback.message)
    }

    @MainActor func testLongFormKeepsNativeActionsInsideSmallPanel() throws {
        _ = NSApplication.shared
        let form = MoaModalForm {
            MoaModalHeader(icon: "gearshape", title: "Layout probe", message: nil)
        } fields: {
            Text(Array(repeating: "Long validation and configuration content", count: 80).joined(separator: "\n"))
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            HStack {
                Spacer()
                MoaModalButton(title: "Cancel") { }
                MoaModalButton(title: "Save", prominence: .prominent) { }
            }
        }
        let panel = MoaModalPanelStyle.makePanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), title: "Probe")
        defer { panel.close() }
        let host = MoaGlassModalHost.hostingView(for: form)
        MoaModalPanelStyle.installGlassContent(host, in: panel)
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(root.bounds.height, 360, accuracy: 1)
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let actions = buttons(root)
        XCTAssertEqual(actions.count, 2)
        for button in actions {
            let rect = button.convert(button.bounds, to: root)
            XCTAssertGreaterThanOrEqual(rect.minY, 0)
            XCTAssertLessThanOrEqual(rect.maxY, root.bounds.height)
            XCTAssertGreaterThan(rect.height, 0)
        }
    }

    func testModalHeightLimitsAndInvalidMeasurementFallback() {
        XCTAssertEqual(MoaModalLayoutMetrics.height(measured: 900, fallback: 400, available: 600), 536)
        XCTAssertEqual(MoaModalLayoutMetrics.height(measured: .nan, fallback: 300, available: 800), 300)
        XCTAssertEqual(MoaModalLayoutMetrics.height(measured: 280, fallback: 400, available: 800), 280)
    }

    @MainActor func testActualAlertFormMeasuresAtItsRequestedWidth() {
        _ = NSApplication.shared
        let height = MoaGlassModalHost.fittingHeight(width: 500) {
            DailyUsageAlertFormView(title: "Daily Usage Alert", initialEnabled: true, initialThresholdText: "10",
                                    onSave: { _ in }, onCancel: {})
        }
        XCTAssertGreaterThan(height, 240)
        XCTAssertLessThan(height, 520, "A short form must not expand to the display's full height")
    }
}
#endif
