import AppKit
import Combine
import SwiftUI

enum MoaAccountClient: Hashable {
    case codex, claude, workbuddy, workbuddyCN, deepseek, antigravity
}

/// Shared by menu actions and account windows. All access is on the main thread.
final class MoaAccountOperationState: ObservableObject {
    struct Operation: Equatable {
        let id: UUID
        let message: String
    }

    @Published private(set) var active: [MoaAccountClient: Operation] = [:]

    func begin(_ client: MoaAccountClient, message: String) -> UUID? {
        guard active[client] == nil else { return nil }
        let id = UUID()
        active[client] = Operation(id: id, message: message)
        return id
    }

    func finish(_ client: MoaAccountClient, id: UUID) {
        guard active[client]?.id == id else { return }
        active.removeValue(forKey: client)
    }
}

final class MoaFeedbackCenter: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    static let shared = MoaFeedbackCenter()
    @Published private(set) var message: Message?
    private var dismissal: DispatchWorkItem?
    var anchorRect: (() -> NSRect?)?
    private var panel: NSPanel?

    func show(title: String, detail: String) {
        dismissal?.cancel()
        let next = Message(title: title, detail: detail)
        message = next
        panel?.close()
        panel = nil
        // A menu-only action also needs visible feedback, without activating
        // Moa or making a window key. Open app windows use their inline banner.
        if !MoaRuntimeMode.suppressesUserInteraction, let app = NSApp,
           !app.isActive || !app.windows.contains(where: {
               $0.styleMask.contains(.titled) && $0.isVisible && $0.isOnActiveSpace
                   && !$0.isMiniaturized && !($0 is NSPanel)
           }) {
            let host = NSHostingView(rootView: MoaFeedbackBanner(feedback: self).frame(width: 380))
            let size = host.fittingSize
            let toast = MoaFeedbackPanel(contentRect: NSRect(origin: .zero, size: size),
                                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            toast.isReleasedWhenClosed = false
            toast.isOpaque = false
            toast.backgroundColor = .clear
            toast.level = .floating
            toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            toast.contentView = host
            let anchor = anchorRect?() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
            let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
            toast.setFrameOrigin(NSPoint(x: max(visible.minX, min(anchor.maxX - size.width, visible.maxX - size.width)),
                                         y: max(visible.minY, min(anchor.minY - size.height, visible.maxY - size.height))))
            panel = toast
            toast.orderFrontRegardless()
        }
        let work = DispatchWorkItem { [weak self] in self?.dismiss(id: next.id) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dismiss(id: UUID) {
        guard message?.id == id else { return }
        dismissal?.cancel()
        dismissal = nil
        message = nil
        panel?.close()
        panel = nil
    }
}

private final class MoaFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct MoaFeedbackBanner: View {
    @ObservedObject var feedback = MoaFeedbackCenter.shared

    var body: some View {
        if let message = feedback.message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MoaTheme.tint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title).font(.headline)
                    Text(message.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { feedback.dismiss(id: message.id) } label: {
                    Label(MoaL10n.text("Dismiss"), systemImage: "xmark").labelStyle(.iconOnly)
                }.buttonStyle(.borderless)
            }
            .padding(14)
            .frame(maxWidth: 420, alignment: .leading)
            .background(MoaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MoaTheme.border))
            .shadow(color: MoaTheme.softShadow, radius: 12, y: 5)
            .padding(16)
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    func moaFeedbackBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { MoaFeedbackBanner() }
    }
}
