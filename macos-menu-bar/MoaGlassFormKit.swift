import AppKit
import SwiftUI

// 统一的玻璃风格表单弹窗工具集。
// 让原本用原生 AppKit 控件搭建的配置类弹窗(Codex/Claude 配置、勿扰时段、
// 用量提醒、自定义价格)复用与「日志 / 提醒事项」一致的 SwiftUI 玻璃外观:
// 复用 MoaModalPanelStyle 的玻璃外壳 + runModal 流程,内容则是 SwiftUI。

/// 把一个 SwiftUI 视图托管进玻璃弹窗并以 modal 方式运行,返回 modal 响应码。
/// 弹窗高度按内容自适应:在固定宽度下测量 SwiftUI 内容需要的合身高度,
/// 避免硬编码高度导致弹窗过高、底部大片留白。`fallbackHeight` 仅在测量失败时兜底。
/// 视图内部通过传入的闭包调用 `NSApp.stopModal(withCode:)` 结束会话,
/// 调用方在闭包里捕获结果(与 AIQuickActionEditorPanelView 相同的模式)。
enum MoaGlassModalHost {
    @discardableResult
    static func runModal<Content: View>(
        width: CGFloat,
        fallbackHeight: CGFloat,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> NSApplication.ModalResponse {
        let hostingView = MoaModalHostingView(rootView: content())

        // 在固定宽度下测量内容合身高度(含多行文本换行),据此决定弹窗高度。
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.isActive = true
        hostingView.layoutSubtreeIfNeeded()
        let measuredHeight = hostingView.fittingSize.height
        widthConstraint.isActive = false

        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 1000) - 80
        let resolvedHeight = min(max(measuredHeight > 1 ? measuredHeight : fallbackHeight, 120), maxHeight)

        let panel = MoaModalPanelStyle.makePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: resolvedHeight),
            title: title
        )
        panel.becomesKeyOnlyIfNeeded = false
        MoaModalPanelStyle.installModalCancelHandler({
            NSApp.stopModal(withCode: .cancel)
        }, in: panel)

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        MoaModalPanelStyle.installGlassContent(hostingView, in: panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        // A text field with focus swallows Escape before any view sees it, so
        // watch the panel's own key events and close on Escape regardless.
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window == panel, event.keyCode == 53 else { return event }
            (panel as? MoaModalPanel)?.cancelOperation(nil)
            return nil
        }
        let response = NSApp.runModal(for: panel)
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        panel.close()
        return response
    }
}

private final class MoaModalHostingView<Content: View>: MoaInteractiveHostingView<Content> {
    // The panel is borderless, so the only way to drag it is by its background.
    // This hosting view receives SwiftUI button, toggle, and picker clicks, so
    // mouseDownCanMoveWindow must stay off. mouseDown drags only the empty area.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard !isInteractiveControl(at: event.locationInWindow) else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    private func isInteractiveControl(at windowPoint: NSPoint) -> Bool {
        guard let superviewPoint = superview?.convert(windowPoint, from: nil) else { return false }
        if let hit = hitTest(superviewPoint) {
            var view: NSView? = hit
            while let current = view, current !== self {
                if current is NSControl || current is NSTextView { return true }
                view = current.superview
            }
        }
        // Bordered buttons, custom glass buttons, toggles, and menu pickers do not
        // hit-test as NSControls. SwiftUI places a non-hit-testable proxy at the
        // control frame; clicks there must reach the hosting view, and only the
        // remaining empty area starts a window drag.
        let localPoint = convert(windowPoint, from: nil)
        return subviews.contains { $0.frame.contains(localPoint) }
    }
}

/// 状态 / 校验提示文字的语气。
enum MoaFormStatusTone {
    case neutral
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return MoaTheme.leaf
        case .warning:
            return MoaTheme.amber
        case .error:
            return MoaTheme.coral
        }
    }
}

/// 弹窗顶部的图标 + 标题 + 说明,沿用浮窗 Alert 的视觉。
struct MoaModalHeader: View {
    var icon: String
    var tint: Color = MoaTheme.tint
    var title: String
    var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 表单字段上方的小标题。
struct MoaModalFieldLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// 单行输入框的统一玻璃外观(去系统 bezel,玻璃底 + 发丝边框)。
    func moaModalFieldChrome(height: CGFloat = 40, radius: CGFloat = 12) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 13)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MoaTheme.tint.opacity(0.22), lineWidth: 1)
            )
    }

    /// 弹窗整体外框:统一内边距 + 玻璃面板背景。
    /// 高度交给内容自然撑开(配合 MoaGlassModalHost 的合身测量),
    /// 因此这里不用 maxHeight: .infinity,避免底部留白。
    func moaModalFormBody() -> some View {
        self
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .moaGlassPanel(radius: 28, liquidOpacity: 0.18, shadowRadius: 28, shadowOpacity: 0.36)
    }
}
