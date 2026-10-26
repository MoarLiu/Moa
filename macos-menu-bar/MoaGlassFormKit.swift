import AppKit
import SwiftUI

// 统一的玻璃风格表单弹窗工具集。
// 让原本用原生 AppKit 控件搭建的配置类弹窗(Codex/Claude 配置、勿扰时段、
// 用量提醒、自定义价格)复用与「日志 / 提醒事项」一致的 SwiftUI 玻璃外观:
// 复用 MoaModalPanelStyle 的玻璃外壳 + runModal 流程,内容则是 SwiftUI。

/// 把一个 SwiftUI 视图托管进玻璃弹窗并以 modal 方式运行,返回 modal 响应码。
/// 弹窗高度按内容自适应:在固定宽度下测量 SwiftUI 内容需要的合身高度,
/// 避免硬编码高度导致弹窗过高、底部大片留白。`fallbackHeight` 仅在测量失败时兜底。
/// 视图内部通过传入的闭包调用 `MoaGlassModalHost.finish(_:)` 结束会话,
/// 调用方在闭包里捕获结果(与 AIQuickActionEditorPanelView 相同的模式)。
enum MoaGlassModalHost {
    /// Ends the running glass modal.
    static func finish(_ response: NSApplication.ModalResponse) {
        NSApp.stopModal(withCode: response)
    }

    static func fittingHeight<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> CGFloat {
        // Constrain SwiftUI's proposed width, not just the NSView's Auto Layout
        // width. Otherwise wrapping fields can be measured at zero width.
        let view = MoaInteractiveHostingView(rootView: content()
            .environment(\.moaMeasuringForm, true)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
        view.frame.size.width = width
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.height
    }

    static func hostingView<Content: View>(for content: Content) -> NSView {
        let view = MoaModalHostingView(rootView: content)
        // The panel owns its size; focus/state updates must not grow it back
        // to the scroll content's natural height after presentation.
        if #available(macOS 13.0, *) { view.sizingOptions = [] }
        return view
    }

    @discardableResult
    static func runModal<Content: View>(
        width: CGFloat,
        fallbackHeight: CGFloat,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> NSApplication.ModalResponse {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let resolvedWidth = min(width, max(240, visible.width - 48))
        // Measure the natural body without a scroll view, then install a fresh
        // live view whose body can shrink while the header/footer stay visible.
        let measuredHeight = fittingHeight(width: resolvedWidth, content: content)

        let resolvedHeight = MoaModalLayoutMetrics.height(measured: measuredHeight, fallback: fallbackHeight, available: visible.height)
        let hostingView = hostingView(for: content())

        let panel = MoaModalPanelStyle.makePanel(
            contentRect: NSRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight),
            title: title
        )
        panel.becomesKeyOnlyIfNeeded = false
        MoaModalPanelStyle.installModalCancelHandler({
            MoaGlassModalHost.finish(.cancel)
        }, in: panel)

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        MoaModalPanelStyle.installGlassContent(hostingView, in: panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                     y: visible.midY - panel.frame.height / 2))
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
    override var intrinsicContentSize: NSSize {
        if #available(macOS 13.0, *) { return super.intrinsicContentSize }
        // macOS 12 has no sizingOptions; explicit panel constraints own sizing.
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    // AppKit consults this before delivering a click. Answering yes turns every
    // click on a SwiftUI control into a window drag, so it must stay off; the
    // panel is borderless and cannot be dragged by its background.
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Action button for glass modals, backed by a real NSButton.
/// A SwiftUI Button inside a panel run by NSApp.runModal accepts the click but
/// runs its action only when the modal session ends; an AppKit button performs
/// its target-action immediately, the way a normal modal dialog behaves.
struct MoaModalButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentEnabled
    enum Prominence {
        case normal
        case prominent
    }

    var title: String
    var prominence: Prominence = .normal
    var keyEquivalent: String = ""
    var isEnabled: Bool = true
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.fire))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if !keyEquivalent.isEmpty {
            button.keyEquivalent = keyEquivalent
        }
        button.isEnabled = isEnabled && environmentEnabled
        if prominence == .prominent {
            button.bezelColor = NSColor(MoaTheme.tint)
            // Share semantic colors with SwiftUI; native bezel rendering also
            // depends on the system appearance and window activation state.
            button.contentTintColor = MoaTheme.onTintAppKit
        }
        return button
    }

    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.action = action
        if view.title != title { view.title = title }
        view.isEnabled = isEnabled && environmentEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func fire() {
            action()
        }
    }
}

enum MoaModalLayoutMetrics {
    static func height(measured: CGFloat, fallback: CGFloat, available: CGFloat) -> CGFloat {
        min(max(measured.isFinite && measured > 1 ? ceil(measured) : fallback, 120), max(120, available - 64))
    }
}

private struct MoaMeasuringFormKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var moaMeasuringForm: Bool {
        get { self[MoaMeasuringFormKey.self] }
        set { self[MoaMeasuringFormKey.self] = newValue }
    }
}

struct MoaModalForm<Header: View, Fields: View, Footer: View>: View {
    @Environment(\.moaMeasuringForm) private var measuring
    let header: Header
    let fields: Fields
    let footer: Footer

    init(@ViewBuilder header: () -> Header, @ViewBuilder fields: () -> Fields, @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.fields = fields()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(maxWidth: .infinity, alignment: .leading).padding(MoaTheme.formInset)
            Divider()
            if measuring {
                fields.frame(maxWidth: .infinity, alignment: .topLeading).padding(MoaTheme.formInset)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        fields.frame(maxWidth: .infinity, alignment: .topLeading).padding(MoaTheme.formInset)
                    }
                    .onPreferenceChange(MoaFormStatusPreferenceKey.self) { message in
                        if !message.isEmpty { proxy.scrollTo("moa-form-status", anchor: .bottom) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer.padding(.horizontal, MoaTheme.formInset).padding(.vertical, 16)
                .background(MoaTheme.glassToolbarFill)
        }
        .moaGlassPanel(radius: MoaTheme.formRadius, shadowRadius: 28, shadowOpacity: 0.36)
    }
}

struct MoaFormStatusPreferenceKey: PreferenceKey {
    static let defaultValue = ""
    static func reduce(value: inout String, nextValue: () -> String) { value = nextValue() }
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
