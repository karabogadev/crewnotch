//
//  GlobalHotkey.swift
//  CrewNotch
//
//  A system-wide shortcut that opens and closes the notch. Uses Carbon's
//  RegisterEventHotKey, which needs no Accessibility permission.
//

import AppKit
import Carbon.HIToolbox

/// A key plus Carbon modifier flags, stored in UserDefaults as JSON.
nonisolated struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// Character shown for the key ("N"), recorded with the shortcut.
    var keyLabel: String

    static let defaultValue = Hotkey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), keyLabel: "N")

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// A shortcut from a key press; it needs ⌘, ⌃ or ⌥ so plain typing never triggers it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mods
        keyLabel = Self.label(for: event.keyCode) ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    private static func label(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Space: return String(localized: "Space")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20:
            let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            return fKeys.firstIndex(of: Int(keyCode)).map { "F\($0 + 1)" }
        default: return nil
        }
    }

    // MARK: Storage

    private static let disabledMarker = "off"

    /// The saved shortcut; nil when the user cleared it.
    static var saved: Hotkey? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: FeatureKeys.hotkey) else { return defaultValue }
            if raw == disabledMarker { return nil }
            return (try? JSONDecoder().decode(Hotkey.self, from: Data(raw.utf8))) ?? defaultValue
        }
        set {
            let raw = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
            UserDefaults.standard.set(raw ?? disabledMarker, forKey: FeatureKeys.hotkey)
        }
    }
}

@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// Runs on the main actor when the shortcut is pressed.
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Registers the saved shortcut (or nothing when it was cleared).
    func registerSaved() {
        register(Hotkey.saved)
    }

    func register(_ hotkey: Hotkey?) {
        unregister()
        guard let hotkey else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x434E_4F54), id: 1)  // "CNOT"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &spec, nil, &handlerRef)
    }
}

private nonisolated func hotkeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in GlobalHotkey.shared.onPress?() }
    return noErr
}
