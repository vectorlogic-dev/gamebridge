import Foundation

/// A saved game shortcut: a name + path to a Windows .exe inside a bottle.
struct GameShortcut: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var exePath: String

    var exeURL: URL { URL(fileURLWithPath: exePath) }
}

/// A Wine prefix ("bottle"): a self-contained virtual C: drive that holds a
/// game's install + registry. Each bottle is just a directory on disk.
struct Bottle: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var prefixPath: String              // absolute path to the WINEPREFIX dir
    var windowsVersion: String = "win10"
    var defaultBackend: GraphicsBackend = .d3dmetal
    var createdAt: Date = Date()
    var shortcuts: [GameShortcut] = []
    /// Preferred key for the Hold-macro (autobuff) feature. Persisted per
    /// bottle so switching between games remembers each one's skill slot.
    /// `nil` means "use `HoldRunner`'s default" — the first bottle the user
    /// creates hasn't picked one yet.
    var holdTargetKey: NumberKey?

    /// Custom Hold-macro start hotkey for this bottle. `nil` = use the
    /// baked-in default (⌃-). Rebinding matters because Wine games commonly
    /// grab Ctrl-based combos globally while running.
    var holdStartHotkey: HotkeyCombo?

    /// Custom Hold-macro stop hotkey. `nil` = use the default (⌃=).
    var holdStopHotkey: HotkeyCombo?

    /// drive_c inside the prefix — where Windows programs live.
    var driveCURL: URL {
        URL(fileURLWithPath: prefixPath).appendingPathComponent("drive_c")
    }

    var prefixURL: URL { URL(fileURLWithPath: prefixPath) }

    /// True if the prefix has actually been initialised by wineboot.
    var isInitialised: Bool {
        FileManager.default.fileExists(atPath: driveCURL.path)
    }
}
