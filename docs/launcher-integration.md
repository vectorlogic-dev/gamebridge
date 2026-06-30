# Launcher Integration (Steam / Epic) — Design Notes

## Goal

Let users browse and launch games from their Steam or Epic library directly
inside GameBridge, instead of manually picking `.exe` files.

## Steam

### How it works on Windows
Steam installs games under `steamapps/common/` and tracks them in
`steamapps/libraryfolders.vdf` (Valve Data Format). Each game has an
`appmanifest_<appid>.acf` file with metadata.

### Approach for GameBridge

1. **Install Steam inside a bottle** — run the Steam installer `.exe` via
   GameBridge like any other game. Steam installs into `drive_c/Program Files
   (x86)/Steam/`.

2. **Scan for installed games** — parse `steamapps/libraryfolders.vdf` and the
   `appmanifest_*.acf` files to build a game list with names, app IDs, and
   install paths.

3. **Launch via Steam protocol** — instead of running the game `.exe` directly,
   launch `steam.exe -applaunch <appid>`. This lets Steam handle runtime setup
   (redistributables, overlays, cloud saves).

4. **Alternative: direct exe launch** — parse the game's ACF for the
   `installdir`, find the exe in that folder, and run it directly. Skips Steam
   overlay but avoids Steam needing to be running.

### Key files to parse
- `steamapps/libraryfolders.vdf` — lists library folders
- `steamapps/appmanifest_<id>.acf` — per-game metadata (name, install dir, size)
- VDF is a simple key-value format with nested braces, easy to parse

### Implementation sketch
```swift
struct SteamGame: Identifiable {
    let appID: String
    let name: String
    let installDir: URL
}

enum SteamScanner {
    static func scan(in bottle: Bottle) -> [SteamGame] {
        // 1. Find steamapps/ under drive_c
        // 2. Parse libraryfolders.vdf for library paths
        // 3. For each library, parse appmanifest_*.acf
        // 4. Return game list
    }
}
```

## Epic Games Store

### How it works on Windows
Epic installs games under a configurable directory and tracks them in
`%LOCALAPPDATA%/EpicGamesLauncher/Saved/Config/Windows/GameUserSettings.ini`
and `.item` manifest files under
`%PROGRAMDATA%/Epic/EpicGamesLauncher/Data/Manifests/`.

### Approach for GameBridge

1. **Install Epic launcher in a bottle** — same as Steam.

2. **Scan manifests** — the `.item` files are JSON with fields like
   `DisplayName`, `InstallLocation`, `LaunchExecutable`, `LaunchCommand`.

3. **Launch directly** — Epic games don't usually require the launcher to be
   running (unlike Steam). Parse the manifest for the exe path and launch it.

### Key files to parse
- `ProgramData/Epic/EpicGamesLauncher/Data/Manifests/*.item` — JSON manifests
- Each has `DisplayName`, `InstallLocation`, `LaunchExecutable`

### Implementation sketch
```swift
struct EpicGame: Identifiable {
    let id: String
    let name: String
    let exePath: URL
}

enum EpicScanner {
    static func scan(in bottle: Bottle) -> [EpicGame] {
        // 1. Find ProgramData/Epic/.../Manifests/ under drive_c
        // 2. Parse each .item JSON file
        // 3. Return game list
    }
}
```

## UI approach

Add a "Library" tab or section to the bottle detail view that shows detected
games from Steam/Epic. Each entry gets a launch button that creates a
GameShortcut automatically. The manual "Run .exe…" picker remains for games
outside these launchers.

## Effort estimate

- VDF parser for Steam: ~100 lines
- Epic JSON manifest scanner: ~50 lines
- UI for library view: ~100 lines
- Testing with actual installs: the hard part — need Steam/Epic actually
  installed and games downloaded inside a bottle

## Open questions

- Should we support GOG Galaxy as well? (Similar manifest-based approach)
- Should GameBridge manage Steam/Epic installation itself, or just detect
  existing installs?
- How to handle Steam games that require the Steam overlay / DRM?
