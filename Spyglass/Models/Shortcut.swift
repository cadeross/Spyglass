import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: one key plus at least one modifier.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt
    /// The key as typed, for display ("L", "1", "Space").
    var key: String

    static let toggleDefault = Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "L")
    static let discardDefault = Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "D")

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Reads a shortcut from a key press, or nil if it has no command, option or control modifier.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let key: String = switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        default: Self.functionKeys[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        }
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, key: key)
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }
}
