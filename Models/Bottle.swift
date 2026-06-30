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
