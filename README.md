# GameBridge

A minimal native-SwiftUI launcher that runs Windows games on Apple Silicon by
orchestrating an existing Wine + Direct3D-to-Metal translation stack (Apple's
Game Porting Toolkit, CrossOver, Whisky, or Homebrew Wine). It does **not**
translate anything itself — it's the management/launcher layer on top, the
same role Whisky and Mythic play.

Requires **macOS 14 Sonoma** or newer. Universal binary (Apple Silicon + Intel).

---

## Install

1. Grab the latest DMG from the [latest release](https://github.com/vectorlogic-dev/gamebridge/releases/latest) (or browse [all releases](https://github.com/vectorlogic-dev/gamebridge/releases)).
2. Open the DMG → drag **GameBridge** into your **Applications** folder.
3. **First-launch gotcha (self-signed builds).** Because GameBridge isn't yet
   notarised by Apple, Gatekeeper will refuse a normal double-click and say
   "GameBridge is damaged and can't be opened" or "unidentified developer."
   Bypass it once:
   - **Right-click** GameBridge in Applications → **Open** → confirm.
   - Or from Terminal: `xattr -dr com.apple.quarantine /Applications/GameBridge.app`
   - Every launch after the first works normally.

You will also need a Wine runtime — see [Prerequisites](#prerequisites).

---

## Features

- Auto-detect supported Wine-family runtimes and probe their real
  capabilities (GPTK, CrossOver, Whisky, Homebrew Wine).
- Create and track Wine prefixes ("bottles") — each is a virtual C: drive.
- Point a bottle at an existing `WINEPREFIX` from the **New Bottle** sheet
  when you want to reuse someone else's install.
- Initialise a bottle (`wineboot`) and open `winecfg`.
- Pick any Windows `.exe` and launch it inside a bottle. Save game shortcuts
  per bottle for one-click re-launch.
- **Colour-coded readiness banner** shows Ready / Warning / Blocked before
  you hit Run, so you know when D3DMetal/DXVK support files are missing.
- **One-click DXVK install** — downloads and caches DXVK from GitHub, copies
  DLLs into the bottle. No winetricks needed.
- **One-click D3DMetal install** — auto-detects and copies GPTK D3DMetal
  redist DLLs into the bottle.
- Toggle graphics backend: **D3DMetal (GPTK)**, **DXVK (Vulkan)**, or **wined3d**.
- Toggle MetalFX upscaling, an FPS overlay, and AVX advertising (some titles
  need it).
- **Hold-macro / autobuff** with configurable per-bottle start / stop
  hotkeys and a manual Start/Stop button. Sends synthetic key events only
  to the captured app, so you can alt-tab freely while the macro runs.
- **Single-instance guard** — a second launch activates the existing
  window instead of racing over hotkey registration.
- Stream the game's stdout/stderr as a live, selectable log; stop a
  running game.

## What it deliberately does NOT do

The hard parts are already solved and shipped — you don't rebuild them:

- **x86 → ARM64 CPU translation** → Rosetta 2 (built into macOS).
- **Win32 API → macOS** → Wine (via GPTK / CrossOver / Whisky / Homebrew).
- **DirectX → Metal** → Apple's D3DMetal, or DXVK → MoltenVK → Metal.

GameBridge shells out to that stack. The "engine" is the wine binary you
point at.

---

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
3. **Whisky / Mythic** — auto-detected if present.
4. **Homebrew Wine** (`brew install --cask wine-stable`). GameBridge detects
   `/opt/homebrew/bin/wine` (Apple silicon) and `/usr/local/bin/wine`
   (Intel).
5. **Apple's official GPTK from source** — historically `brew install
   apple/apple/game-porting-toolkit`. **Broken on macOS 26 Tahoe** due to a
   chain of toolchain issues (openssl@1.1 won't build with modern Xcode).
   Use the gcenx cask instead.

The Wine picker in the app re-scans on demand; you can point it at any of
the detected binaries.

> **D3DMetal note:** click **Install D3DMetal** in the bottle view to copy
> the GPTK redist DLLs automatically. If a D3D11/12 game falls back to slow
> software rendering, switch the toggle to **DXVK**.

---

## Getting started

1. Click `+` in the sidebar to create a bottle → it appears in the list.
2. Open the bottle → choose your Wine in the picker → click **Initialise**
   (first time only).
3. Install a game by running its installer `.exe` (Steam/Epic/GOG setup, or
   a portable game folder), then **Run .exe…** on the game binary.
4. Save the launched `.exe` as a shortcut when prompted so you don't have to
   re-pick it next time.
5. Start with **D3DMetal**; if a title misbehaves, switch to **DXVK** or
   **wined3d**.

### Using the hold-macro / autobuff

Autobuff holds a chosen number key inside a specific app — useful for MMO
buff rotations.

1. Open the bottle's Hold panel and pick a key (1–0).
2. **First use** — macOS will prompt for Accessibility permission. Grant it
   in System Settings → Privacy & Security → Accessibility, then quit and
   relaunch GameBridge so the process picks up the grant. This is a one-time
   step per install.
3. Click into your game so it's the frontmost app.
4. Press the start hotkey (default `⌃-`) *or* click the **Start** button in
   the Hold panel.
5. Press the stop hotkey (default `⌃=`) *or* click **Stop**.

If a hotkey shows as "already claimed" (some Wine games grab Ctrl-combos
globally), click the pill to rebind to something like `F13` and hit the
Reset arrow to restore defaults.

---

## Honest limitations

- **Anti-cheat:** kernel-level anti-cheat (Riot Vanguard, much of
  BattlEye/EAC) generally won't run. CrossOver 26 added coverage for some
  AAA titles; free GPTK has less.
- **WPF launchers (.NET Framework):** Wine Mono's WPF implementation is
  incomplete — `GetParent` and related window-manager calls fail. WPF-based
  game launchers crash before showing a window. The workaround is installing
  real Microsoft .NET Framework via winetricks (`dotnet48`), which itself
  may fail on Wine 7.7 (what GPTK ships). CrossOver 26 handles this much
  better.
- **Fanless MacBook Air:** demanding titles thermal-throttle without active
  cooling, and 16 GB unified memory is the practical floor for heavy AAA.
  Lighter/older D3D11 games are the sweet spot.
- **Not yet notarised.** Distribution DMGs are self-signed, so first launch
  needs the right-click → Open dance. Once an Apple Developer Program
  membership is set up, the release pipeline (`scripts/release.sh`) is
  already wired for notarisation via `GAMEBRIDGE_NOTARIZE=1` +
  `GAMEBRIDGE_NOTARIZE_PROFILE`.
- **This is an early release (0.1.0):** no per-game profiles, no bottle
  backup, no auto-updates. Those are on the roadmap.

## Game guides

- [RF Banana (RF Online)](docs/rf-banana-setup.md) — setup guide for the RF
  Banana private server. Includes the built-in GameBridge assisted-launch
  path. The one-click flow is a saved `bananarfo.exe` shortcut inside the
  app's bottle view, not a Finder shortcut to the `.exe` itself.

## Future ideas

- Launcher integration (Steam/Epic) instead of raw `.exe` picking — see
  [docs/launcher-integration.md](docs/launcher-integration.md) for design
  notes.
- Per-bottle environment variable editor.
- Bottle backup / export / import.
- Auto-update (Sparkle) once we're notarised.

---

## Build from source

Contributors and anyone who wants the bleeding edge.

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) and Xcode 16+.

### One-time setup

Provision the local self-signed identity Debug builds sign with:

```bash
./scripts/create-signing-identity.sh
```

This creates a `GameBridge Dev` code-signing cert in your login keychain
(idempotent — safe to re-run). Debug builds reference it in `project.yml`.
Ad-hoc signing (`-`) is *not* used because it changes `cdhash` on every
rebuild and silently invalidates TCC grants like Accessibility — see
[ai/2026-07-01-hold-presser-issue.md](ai/2026-07-01-hold-presser-issue.md)
for the incident that motivated this.

### Debug build (day-to-day)

```bash
./scripts/build.sh          # builds into ./build/GameBridge.app
./scripts/build.sh --run    # ... and launches it
```

Or the raw form:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -configuration Debug \
    -derivedDataPath build/dd \
    CONFIGURATION_BUILD_DIR="$(pwd)/build" build
```

Run tests:

```bash
xcodebuild -scheme GameBridge -configuration Debug \
    -derivedDataPath build/dd test
```

### Release build + DMG

```bash
./scripts/release.sh
# Produces dist/GameBridge-<version>.dmg
```

Signs with the same self-signed `GameBridge Dev` identity by default.
To sign + notarise with a real Apple identity:

```bash
GAMEBRIDGE_RELEASE_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
GAMEBRIDGE_DEVELOPMENT_TEAM="TEAMID" \
GAMEBRIDGE_NOTARIZE=1 \
GAMEBRIDGE_NOTARIZE_PROFILE="notary-profile-name" \
./scripts/release.sh
```

(`GAMEBRIDGE_NOTARIZE_PROFILE` is a `xcrun notarytool store-credentials`
keychain profile name.)

### Notes

- The generated `.xcodeproj` is gitignored — `project.yml` is the source of
  truth.
- **App Sandbox is OFF** — required for launching Wine processes.
- **Swift 6 language mode** — concurrency is handled cleanly.
- Bump `MARKETING_VERSION` in `project.yml` for each user-visible release.
