import AppKit
import SwiftUI

enum MoaNonBlockingAlert {
    static func present(messageText: String, informativeText: String, tone: MoaAlertTone = .info) {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = tone.alertStyle
            alert.addButton(withTitle: MoaL10n.text("OK"))
            alert.buttons.first?.keyEquivalent = "\r"
            alert.window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    static func choose(
        messageText: String,
        informativeText: String,
        primaryButtonTitle: String,
        secondaryButtonTitle: String? = nil,
        cancelButtonTitle: String = MoaL10n.text("Cancel"),
        tone: MoaAlertTone = .info
    ) -> MoaAlertChoice {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return .cancel }
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = tone.alertStyle
        alert.addButton(withTitle: primaryButtonTitle)
        if let secondaryButtonTitle {
            alert.addButton(withTitle: secondaryButtonTitle)
        }
        alert.addButton(withTitle: cancelButtonTitle)
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            return .primary
        case .alertSecondButtonReturn:
            return secondaryButtonTitle == nil ? .cancel : .secondary
        case .alertThirdButtonReturn:
            return .cancel
        default:
            return .cancel
        }
    }

    static func confirm(
        messageText: String,
        informativeText: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String = MoaL10n.text("Cancel"),
        tone: MoaAlertTone = .warning
    ) -> Bool {
        choose(
            messageText: messageText,
            informativeText: informativeText,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle,
            tone: tone
        ) == .primary
    }

    static func promptText(
        messageText: String,
        informativeText: String,
        initialValue: String = "",
        placeholder: String = "",
        primaryButtonTitle: String = MoaL10n.text("Save"),
        cancelButtonTitle: String = MoaL10n.text("Cancel"),
        tone: MoaAlertTone = .info
    ) -> String? {
        guard !MoaRuntimeMode.suppressesUserInteraction else { return nil }
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = tone.alertStyle
        alert.addButton(withTitle: primaryButtonTitle)
        alert.addButton(withTitle: cancelButtonTitle)
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        input.stringValue = initialValue
        input.placeholderString = placeholder
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.window.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }


}

enum MoaModalPanelStyle {
    static let whiteBackplateColor = NSColor(calibratedWhite: 1.0, alpha: 1.0)

    static func applyPopupWindowChrome(to window: NSWindow) {
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    static func makePanel(contentRect: NSRect, title: String) -> NSPanel {
        let panel = MoaModalPanel(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        applyPopupWindowChrome(to: panel)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = {
            NSApp.stopModal(withCode: .cancel)
        }
        return panel
    }

    static func installModalCancelHandler(_ handler: @escaping () -> Void, in panel: NSPanel) {
        (panel as? MoaModalPanel)?.onCancel = handler
    }

    static func installGlassContent(_ content: NSView, in panel: NSPanel, cornerRadius: CGFloat = 24) {
        let container = MoaModalChromeView(cornerRadius: cornerRadius)
        let background = NSView()

        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.backgroundColor = whiteBackplateColor.cgColor
        container.addSubview(background)

        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        panel.contentView = container

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func styleModalButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    static func makeButtonRow(
        leadingButtons: [NSButton] = [],
        trailingButtons: [NSButton]
    ) -> NSStackView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let allButtons = leadingButtons + trailingButtons
        allButtons.forEach { button in
            styleModalButton(button)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 78).isActive = true
        }

        let row = NSStackView(views: leadingButtons + [spacer] + trailingButtons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return row
    }
}

private final class MoaModalPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func close() {
        onCancel = nil
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            close()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
            return
        }
        super.keyDown(with: event)
    }
}

private final class MoaModalChromeView: NSView {
    private let modalCornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.modalCornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateLayerStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = modalCornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerStyle()
    }

    private func updateLayerStyle() {
        layer?.backgroundColor = MoaModalPanelStyle.whiteBackplateColor.cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.08).cgColor
    }
}

enum MoaAlertChoice {
    case primary
    case secondary
    case cancel

    fileprivate var modalResponse: NSApplication.ModalResponse {
        switch self {
        case .primary:
            return .OK
        case .secondary:
            return .continue
        case .cancel:
            return .cancel
        }
    }
}

enum MoaAlertTone {
    case info
    case success
    case warning
    case danger

    var alertStyle: NSAlert.Style {
        switch self {
        case .info, .success:
            return .informational
        case .warning:
            return .warning
        case .danger:
            return .critical
        }
    }

    var accent: Color {
        switch self {
        case .info:
            return MoaTheme.tint
        case .success:
            return MoaTheme.leaf
        case .warning:
            return MoaTheme.amber
        case .danger:
            return MoaTheme.coral
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "sparkles"
        case .success:
            return "checkmark"
        case .warning:
            return "exclamationmark"
        case .danger:
            return "xmark"
        }
    }

    var primaryButtonTone: MoaGlassButtonTone {
        switch self {
        case .warning:
            return .amber
        case .danger:
            return .danger
        case .info, .success:
            return .primary
        }
    }
}
