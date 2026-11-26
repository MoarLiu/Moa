import AppKit
import Carbon.HIToolbox
import Foundation

enum MoaHotKeyAction: String, CaseIterable, Identifiable, Codable {
    case quickSwitcher
    case openWorkspace
    case openUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickSwitcher: return MoaL10n.text("Open Quick Switcher")
        case .openWorkspace: return MoaL10n.text("Open Workspace Overview")
        case .openUsage: return MoaL10n.text("Open Usage Analysis")
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .quickSwitcher: return 1
        case .openWorkspace: return 2
        case .openUsage: return 3
        }
    }

    var suggestedShortcut: MoaHotKeyShortcut {
        switch self {
        case .quickSwitcher:
            return MoaHotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey))
        case .openWorkspace:
            return MoaHotKeyShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | optionKey))
        case .openUsage:
            return MoaHotKeyShortcut(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: UInt32(cmdKey | optionKey))
        }
    }
}

struct MoaHotKeyShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var isValid: Bool {
        let primaryMask = UInt32(cmdKey | optionKey | controlKey)
        return (carbonModifiers & primaryMask) != 0
    }

    var displayString: String {
        var result = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { result += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        default: return "#\(keyCode)"
        }
    }
}

/// Manages optional Carbon global hotkeys (works on macOS 12+ without Accessibility permission).
/// All hotkeys default to disabled until explicitly configured by the user.
final class MoaGlobalHotkeyManager: ObservableObject {
    static let storageKey = "Moa.globalHotKeys.bindings"
    private static let signature: OSType = 0x4D4F4148 // 'MOAH'

    @Published private(set) var bindings: [MoaHotKeyAction: MoaHotKeyShortcut] = [:]
    var onTrigger: ((MoaHotKeyAction) -> Void)?

    private let defaults: UserDefaults
    private var hotKeyRefs: [MoaHotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadBindings()
    }

    deinit {
        stop()
    }

    func shortcut(for action: MoaHotKeyAction) -> MoaHotKeyShortcut? {
        bindings[action]
    }

    func setShortcut(_ shortcut: MoaHotKeyShortcut?, for action: MoaHotKeyAction) {
        if let shortcut {
            guard shortcut.isValid else { return }
            // Avoid conflicting duplicates across actions.
            for (existingAction, existingShortcut) in bindings where existingAction != action && existingShortcut == shortcut {
                bindings.removeValue(forKey: existingAction)
            }
            bindings[action] = shortcut
        } else {
            bindings.removeValue(forKey: action)
        }
        saveBindings()
        if started {
            reregisterAll()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        guard !MoaRuntimeMode.suppressesUserInteraction,
              !MoaRuntimeMode.isWorkspacePreview else { return }
        installEventHandlerIfNeeded()
        reregisterAll()
    }

    func stop() {
        started = false
        unregisterAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    private func loadBindings() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: MoaHotKeyShortcut].self, from: data) else {
            bindings = [:]
            return
        }
        var result: [MoaHotKeyAction: MoaHotKeyShortcut] = [:]
        for (raw, shortcut) in decoded where shortcut.isValid {
            if let action = MoaHotKeyAction(rawValue: raw) {
                result[action] = shortcut
            }
        }
        bindings = result
    }

    private func saveBindings() {
        let rawMap = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if rawMap.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(rawMap) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == MoaGlobalHotkeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<MoaGlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let action = MoaHotKeyAction.allCases.first(where: { $0.hotKeyID == hotKeyID.id }) {
                    DispatchQueue.main.async {
                        manager.onTrigger?(action)
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func reregisterAll() {
        unregisterAll()
        guard !MoaRuntimeMode.suppressesUserInteraction,
              !MoaRuntimeMode.isWorkspacePreview else { return }
        for (action, shortcut) in bindings where shortcut.isValid {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.hotKeyID)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs[action] = ref
            }
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
}
