# GameBridge

A minimal native-SwiftUI launcher that runs Windows games on Apple Silicon by
orchestrating an existing Wine + Direct3D-to-Metal translation stack (Apple's
Game Porting Toolkit or CrossOver). It does **not** translate anything itself —
it's the management/launcher layer on top, the same role Whisky and Mythic play.

## Features

- Create and track Wine prefixes ("bottles") — each is a virtual C: drive.
- Initialise a bottle (`wineboot`) and open `winecfg`.
- Pick any Windows `.exe` and launch it inside a bottle.
- **Saved game shortcuts** — save exe paths per bottle for one-click re-launch.
  Launch the saved shortcut from inside GameBridge; directly opening the `.exe`
  in Finder does not apply any bottle-specific launch logic.
- **One-click DXVK install** — downloads and caches DXVK from GitHub, copies DLLs into the bottle. No winetricks needed.
- **One-click D3DMetal install** — auto-detects and copies GPTK D3DMetal redist DLLs into the bottle.
- Toggle graphics backend: **D3DMetal (GPTK)**, **DXVK (Vulkan)**, or **wined3d**.
- Toggle MetalFX upscaling, an FPS overlay, and AVX advertising (some titles need it).
- Stream the game's stdout/stderr as a live, selectable log; stop a running game.

## What it deliberately does NOT do

The hard parts are already solved and shipped — you don't rebuild them:

- **x86 → ARM64 CPU translation** → Rosetta 2 (built into macOS).
- **Win32 API → macOS** → Wine (via GPTK / CrossOver).
- **DirectX → Metal** → Apple's D3DMetal, or DXVK → MoltenVK → Metal.

GameBridge shells out to that stack. The "engine" is GPTK/CrossOver's `wine`.

## Prerequisites

You need a Wine binary with a Metal path. Pick one:

1. **gcenx prebuilt GPTK** (free, fast, recommended). Requires x86_64
   Homebrew at `/usr/local`:
   ```bash
   arch -x86_64 /usr/local/bin/brew install --cask gcenx/wine/game-porting-toolkit
   ```
   Installs `Game Porting Toolkit.app` into `/Applications` and symlinks
   `/usr/local/bin/wine64`. GameBridge auto-detects both.
2. **CrossOver 26** (paid, most polished, best .NET / WPF / anti-cheat
   coverage). GameBridge detects `/Applications/CrossOver.app/.../bin/wine`.
3. **A community Whisky fork / Mythic** — also auto-detected if present.
4. **Apple's official GPTK from source** — historically `brew install
   apple/apple/game-porting-toolkit`. **Broken on macOS 26 Tahoe** due to a
   chain of toolchain issues (openssl@1.1 won't build with modern Xcode). Use
   the gcenx cask instead.

The Wine picker in the app re-scans on demand; you can also point it at any of
the detected binaries.

> **D3DMetal note:** use the **Install D3DMetal** button in the bottle view to
> copy the GPTK redist DLLs automatically. If a D3D11/12 game falls back to
> slow software rendering, switch the toggle to **DXVK**.

## Build

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```bash
xcodegen generate
xcodebuild -scheme GameBridge -configuration Debug build
```

The generated `.xcodeproj` is gitignored — `project.yml` is the source of truth.

- **App Sandbox is OFF** — required for launching Wine processes.
- **Swift 6 language mode** — concurrency is handled cleanly.
- Build target: macOS 14+.

## Use

1. `+` to create a bottle → it appears in the sidebar.
2. Open it → choose your Wine in the picker → **Initialise** (first time only).
3. Install a game by running its installer `.exe` (Steam/Epic/GOG setup, or a
   portable game folder), then **Run .exe…** on the game binary.
4. Start with **D3DMetal**; if a title misbehaves, try **DXVK**.

## Honest limitations

- **Anti-cheat:** kernel-level anti-cheat (Riot Vanguard, much of BattlEye/EAC)
  generally won't run. CrossOver 26 added coverage for some AAA titles; free
  GPTK has less.
- **WPF launchers (.NET Framework):** Wine Mono's WPF implementation is
  incomplete — `GetParent` and related window-manager calls fail. WPF-based
  game launchers crash before showing a window. The workaround is installing
  real Microsoft .NET Framework via winetricks (`dotnet48`), which itself may
  fail on Wine 7.7 (what GPTK ships). CrossOver 26 handles this much better.
- **Fanless MacBook Air (M4):** demanding titles will thermal-throttle without
  active cooling, and 16 GB unified memory is the practical floor for heavy AAA.
  Lighter/older D3D11 games are the sweet spot.
- **This is an MVP:** no per-game profiles, no bottle backup. Those are the
  obvious next steps if you want to grow it toward what Whisky/Mythic offer.

## Game guides

- [RF Banana (RF Online)](docs/rf-banana-setup.md) — setup guide for the RF Banana private server
  Includes the built-in GameBridge assisted-launch path. The one-click flow is
  a saved `bananarfo.exe` shortcut inside the app's bottle view, not a Finder
  shortcut to the `.exe` itself.

## Future ideas

- Launcher integration (Steam/Epic) instead of raw `.exe` picking — see
  [docs/launcher-integration.md](docs/launcher-integration.md) for design notes.
- Per-bottle environment variable editor.
- Bottle backup / export / import.
