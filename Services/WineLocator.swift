import Foundation

/// Probes the common install locations for a Wine binary that ships a
/// DirectX->Metal path (GPTK / CrossOver / community Whisky fork).
enum WineLocator {
    static func detect(
        candidatePaths: [(String, String)] = defaultCandidates(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        canonicalPath: (String) -> String = {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardized.path
        }
    ) -> [GameRuntimeInstall] {
        var seen = Set<String>()
        var found: [GameRuntimeInstall] = []
        for (name, path) in candidatePaths {
            let resolvedPath = canonicalPath(path)
            guard isExecutable(path), seen.insert(resolvedPath).inserted else { continue }

            let family = classify(path: path, canonicalPath: resolvedPath)
            found.append(
                GameRuntimeInstall(
                    name: name,
                    winePath: path,
                    family: family,
                    capabilities: capabilities(for: family)
                )
            )
        }
        return found
    }

    private static func defaultCandidates() -> [(String, String)] {
        let home = NSHomeDirectory()
        return [
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
            // Homebrew (x86_64) — `brew install --cask wine-stable` on Intel
            ("Homebrew wine", "/usr/local/bin/wine"),
        ]
    }

    private static func classify(path: String, canonicalPath: String) -> RuntimeFamily {
        let rawPath = path.lowercased()
        let resolvedPath = canonicalPath.lowercased()
        let pathEvidence = "\(rawPath) \(resolvedPath)"

        if pathEvidence.contains("game porting toolkit.app") || pathEvidence.contains("game-porting-toolkit") {
            return .gptk
        }
        if pathEvidence.contains("crossover.app") || pathEvidence.contains("/crossover/") {
            return .crossover
        }
        if pathEvidence.contains("com.isaacmarovitz.whisky") || pathEvidence.contains("/whisky/") {
            return .whisky
        }
        if resolvedPath.contains("/cellar/wine")
            || resolvedPath.hasPrefix("/opt/homebrew/bin/")
            || resolvedPath.hasPrefix("/usr/local/bin/wine")
            || resolvedPath.contains("wine-stable") {
            return .homebrewWine
        }

        return .unknown
    }

    private static func capabilities(for family: RuntimeFamily) -> RuntimeCapabilities {
        switch family {
        case .gptk, .crossover, .whisky:
            return RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: true,
                supportsDXVK: true
            )
        case .homebrewWine, .unknown:
            return RuntimeCapabilities(
                supportsGenericWineLaunch: true,
                supportsD3DMetal: false,
                supportsDXVK: true
            )
        }
    }
}
