import Foundation

/// A discovered Wine binary that GameBridge can drive.
struct WineInstall: Identifiable, Hashable {
    var id: String { winePath }
    let name: String
    let winePath: String   // path to wine / wine64 executable
}

/// Probes the common install locations for a Wine binary that ships a
/// DirectX->Metal path (GPTK / CrossOver / community Whisky fork).
enum WineLocator {

    static func detect() -> [WineInstall] {
        let home = NSHomeDirectory()
        let candidates: [(String, String)] = [
            // Apple Game Porting Toolkit via x86_64 Homebrew (/usr/local)
            ("Game Porting Toolkit", "/usr/local/opt/game-porting-toolkit/bin/wine64"),
            ("Game Porting Toolkit", "/usr/local/bin/wine64"),
            // gcenx GPTK cask
            ("GPTK (gcenx)", "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"),
            // CrossOver
            ("CrossOver", "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
            // Whisky community fork bundled wine
            ("Whisky", "\(home)/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"),
            // Mythic / Apple-silicon homebrew
            ("Homebrew wine", "/opt/homebrew/bin/wine64"),
            ("Homebrew wine", "/opt/homebrew/bin/wine"),
        ]

        var seen = Set<String>()
        var found: [WineInstall] = []
        for (name, path) in candidates {
            guard FileManager.default.isExecutableFile(atPath: path),
                  !seen.contains(path) else { continue }
            seen.insert(path)
            found.append(WineInstall(name: name, winePath: path))
        }
        return found
    }
}
