import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus modifiers, stored the way Carbon's hot
/// key API wants them, with the symbols macOS menus use for display.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// The key's label, for example "P".
    var key: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: UInt32(controlKey | optionKey), key: "P")

    /// Symbols in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    /// Spelled out, for sentences and accessibility: "Control-Option-P".
    var spoken: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        return (parts + [key]).joined(separator: "-")
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    /// Builds a shortcut from a key press, or nil if it cannot be a global
    /// shortcut: it needs Control, Option or Command, so plain typing never
    /// triggers it.
    static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> Shortcut? {
        let flags = modifiers.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        guard let label = keyLabel(keyCode: keyCode, characters: characters) else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return Shortcut(keyCode: UInt32(keyCode), carbonModifiers: carbon, key: label)
    }

    /// Option changes the character a key types (⌥P types "π"), so letters and
    /// digits are labelled from the key's position on a US layout, the way
    /// macOS shows shortcuts. Modifier-only and Escape presses are rejected.
    static func keyLabel(keyCode: UInt16, characters: String?) -> String? {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        ]
        let code = Int(keyCode)
        if code == kVK_Escape { return nil }
        if let l = letters[code] ?? named[code] { return l }
        guard let c = characters?.uppercased(), !c.isEmpty,
              c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return c
    }
}
