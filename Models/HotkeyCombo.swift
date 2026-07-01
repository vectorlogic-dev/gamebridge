import Foundation
import Carbon.HIToolbox

/// A global-hotkey combination: a virtual-key code plus Carbon modifier flags.
/// Persisted on `Bottle` so each bottle can have its own Hold-macro start/stop
/// combo (some games grab certain Ctrl-combos globally, so being able to
/// rebind matters).
struct HotkeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Default start combo: Control + Minus. Matches the historical baked-in
    /// value so bottles without an explicit override behave the same as
    /// before.
    static let defaultStart = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_Minus),
        modifiers: UInt32(controlKey)
    )

    /// Default stop combo: Control + Equal.
    static let defaultStop = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_Equal),
        modifiers: UInt32(controlKey)
    )

    /// Human-readable label — modifier glyphs then the key. Covers F1–F12,
    /// the punctuation keys used by the defaults, and falls back to
    /// "keycode NN" for anything else so a rebound key is at least
    /// identifiable.
    var label: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { prefix += "⌘" }

        let key: String
        switch Int(keyCode) {
        case kVK_F1:         key = "F1"
        case kVK_F2:         key = "F2"
        case kVK_F3:         key = "F3"
        case kVK_F4:         key = "F4"
        case kVK_F5:         key = "F5"
        case kVK_F6:         key = "F6"
        case kVK_F7:         key = "F7"
        case kVK_F8:         key = "F8"
        case kVK_F9:         key = "F9"
        case kVK_F10:        key = "F10"
        case kVK_F11:        key = "F11"
        case kVK_F12:        key = "F12"
        case kVK_F13:        key = "F13"
        case kVK_F14:        key = "F14"
        case kVK_F15:        key = "F15"
        case kVK_F16:        key = "F16"
        case kVK_F17:        key = "F17"
        case kVK_F18:        key = "F18"
        case kVK_F19:        key = "F19"
        case kVK_ANSI_Minus: key = "-"
        case kVK_ANSI_Equal: key = "="
        case kVK_ANSI_A:     key = "A"
        case kVK_ANSI_B:     key = "B"
        case kVK_ANSI_C:     key = "C"
        case kVK_ANSI_D:     key = "D"
        case kVK_ANSI_E:     key = "E"
        case kVK_ANSI_F:     key = "F"
        case kVK_ANSI_G:     key = "G"
        case kVK_ANSI_H:     key = "H"
        case kVK_ANSI_I:     key = "I"
        case kVK_ANSI_J:     key = "J"
        case kVK_ANSI_K:     key = "K"
        case kVK_ANSI_L:     key = "L"
        case kVK_ANSI_M:     key = "M"
        case kVK_ANSI_N:     key = "N"
        case kVK_ANSI_O:     key = "O"
        case kVK_ANSI_P:     key = "P"
        case kVK_ANSI_Q:     key = "Q"
        case kVK_ANSI_R:     key = "R"
        case kVK_ANSI_S:     key = "S"
        case kVK_ANSI_T:     key = "T"
        case kVK_ANSI_U:     key = "U"
        case kVK_ANSI_V:     key = "V"
        case kVK_ANSI_W:     key = "W"
        case kVK_ANSI_X:     key = "X"
        case kVK_ANSI_Y:     key = "Y"
        case kVK_ANSI_Z:     key = "Z"
        case kVK_Tab:        key = "⇥"
        case kVK_Space:      key = "Space"
        case kVK_Return:     key = "↩"
        case kVK_Escape:     key = "⎋"
        default:             key = "keycode \(keyCode)"
        }
        return prefix + key
    }
}
