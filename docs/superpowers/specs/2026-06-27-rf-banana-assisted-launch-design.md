# RF Banana Assisted Launch Design

Date: 2026-06-27
Status: Draft approved in chat, pending written-spec review

## Goal

Add a first-pass RF Banana-assisted launch flow to GameBridge that makes the
current launcher-to-game handoff failure reproducible and inspectable from
inside the app.

This milestone does not promise a gameplay fix. It packages the repo's current
diagnostic workflow into a one-click app flow so we can keep iterating without
manual shell setup.

## Problem Summary

RF Banana now launches farther than before under Homebrew Wine Stable 11: the
user can log in, select a server, open the settings/start screen, and spawn
`RF_Online.bin`.

The remaining failure happens after `Start Game`. Current findings in
`docs/rf-banana-setup.md` and `scripts/rfbanana_handoff_patcher.py` show:

- `System/DefaultSet.tmp` is real and worth capturing, but it is not the full
  session handoff.
- The real session data path likely involves native Sirin behavior around the
  bundled `d3d9.dll`.
- The existing Python patcher is still useful as a capture tool because it can
  snapshot each `DefaultSet.tmp` write at the exact moment the launcher updates
  it.

Right now that workflow lives outside the app. The user has to run a script by
hand, manage output files manually, and correlate those artifacts with the app
launch afterward.

## Milestone Outcome

When launching RF Banana from GameBridge in assisted mode, the app will:

1. Detect that the selected executable is the RF Banana launcher.
2. Start `scripts/rfbanana_handoff_patcher.py` in capture-only mode
   (`--no-patch`).
3. Point the patcher at the game's install directory.
4. Store capture artifacts in a stable, per-bottle diagnostics folder.
5. Launch `bananarfo.exe` through the existing Wine path as usual.
6. Stream helper output into the same log view the user already watches for
   Wine output.
7. Log the artifact directory path clearly so the user can inspect saved blobs
   later.

## Non-Goals

This milestone will not:

- Rewrite the RF Banana patcher in Swift.
- Attempt to force a nation/server/session fix inside `DefaultSet.tmp`.
- Implement a fully generic hook/plugin system for every game.
- Claim to resolve `Diff Nation Code` or make the game playable yet.
- Change the existing Wine process ownership model away from `WineRunner`.

## Recommended Approach

Implement an RF Banana-specific assisted launch path instead of a generic hook
framework.

Why this approach:

- It is the smallest change that matches what the repo already proved.
- It reuses the existing patcher script instead of duplicating fragile logic.
- It keeps the app honest: this is a diagnostic aid, not a speculative fix.
- It preserves room to generalize later if the pattern proves useful.

Alternatives considered:

1. Generic pre-launch hook framework
   Cleaner long-term abstraction, but it introduces architecture before the RF
   Banana workflow is proven and adds extra surface area to debug.
2. Native Swift replacement for the patcher
   Better integration on paper, but higher risk and lower value for a milestone
   whose purpose is capture and observability, not handoff replacement.

## Proposed Product Behavior

### Detection

GameBridge will treat a launch as RF Banana-assisted eligible when the selected
executable is `bananarfo.exe` and the surrounding install looks like the known
layout:

- sibling `RF_Online.bin`
- `System/DefaultSet.tmp`
- supporting folders such as `Launcher/` or `NetLog/` may be used as extra
  confidence checks, but they are not required

Detection should be conservative. If the layout does not match, GameBridge
falls back to a normal Wine launch with no helper.

### Assisted Launch Flow

1. User launches `bananarfo.exe` from an existing shortcut or via `Run .exe...`.
2. GameBridge detects RF Banana eligibility.
3. GameBridge creates a timestamped capture directory under a stable
   per-bottle diagnostics root.
4. GameBridge starts the Python helper:

   ```text
   scripts/rfbanana_handoff_patcher.py
     --game-dir <rf-banana-dir>
     --no-patch
     --out-dir <capture-dir>
   ```

5. Once the helper is running, GameBridge launches `bananarfo.exe` with the
   current Wine path, backend, and launch options.
6. Both helper output and Wine output appear in the existing log stream.
7. When the Wine process exits or the user stops it, GameBridge also terminates
   the helper if it is still running.

### User-Facing Copy

This feature should be described as assisted launch or capture mode, not as a
fix. The UI and log output should set expectations clearly:

- assisted launch started
- capture artifacts are being written to `<path>`
- helper is in capture-only mode

Avoid any text that suggests the app solved the Sirin IPC issue.

## Architecture Changes

### `Services/WineRunner.swift`

`WineRunner` remains the owner of process lifecycle. It gains a narrow ability
to orchestrate one optional sidecar helper process for assisted launches.

Responsibilities to add:

- start a helper process before the main Wine launch
- stream helper stdout/stderr into the same published log
- track the helper process separately from the Wine process
- terminate the helper when the launch ends or is manually stopped
- emit clear log lines around helper start, artifact directory, and helper exit

This should stay RF Banana-aware through a small assisted-launch configuration
value rather than turning `WineRunner` into a generic plugin system.

### Detection / Configuration Helper

Add a small helper type or function set that:

- detects whether a chosen executable is the RF Banana launcher
- derives the game root directory from the executable path
- derives a diagnostics root for the current bottle
- builds the helper command arguments

This logic should live outside `BottleDetailView` so the view remains focused
on presentation and button actions.

### `Views/BottleDetailView.swift`

The view needs only minimal change:

- when launching an executable, ask the helper/detection layer whether this is
  an RF Banana-assisted launch
- call into `WineRunner` with either a normal launch request or an assisted
  launch request

No new complex UI is required for this milestone. Reusing the existing launch
entry points keeps the change easy to validate.

## Artifact Layout

Artifacts should be easy to find and grouped by bottle and run.

Recommended layout:

```text
<bottle-prefix-or-app-support>/Diagnostics/RFBanana/
  2026-06-27T11-05-22/
    DefaultSet-20260627-110523-01-raw.bin
    DefaultSet-20260627-110523-02-raw.bin
```

Exact root location may follow whatever path is simplest inside the existing
app model, but it must be:

- stable per bottle
- writable by the app
- easy to print in logs

For this milestone, streaming helper output to the UI is required. A separate
persisted helper text log file is out of scope.

## Error Handling

Expected failure cases and behavior:

- Python unavailable
  Log a clear error and abort the assisted launch. Do not silently fall back to
  a normal launch because that would make the capture workflow unreliable.
- Script missing
  Log a clear error and abort the assisted launch.
- RF Banana layout incomplete
  Skip assisted mode and launch normally.
- Helper fails to start
  Log the failure and do not pretend capture is active.
- Helper exits early
  Log that capture stopped unexpectedly, but keep the Wine launch running.

The app should favor transparency over silent fallback.

## Logging

Log lines should distinguish their source. A simple prefix is enough:

- `[wine] ...`
- `[rfbanana-helper] ...`
- `[rfbanana] capture dir: ...`

This keeps the existing single log view usable without adding a separate pane.

## Testing Strategy

This milestone is mostly integration behavior, so testing will combine focused
code checks with manual verification.

### Code-Level Validation

- Verify RF Banana detection returns true for the known launcher layout and
  false for unrelated executables.
- Verify helper command construction points to the expected script, game dir,
  and capture dir.
- Verify stop/termination code cleans up both the Wine process and helper.

If there is no current unit-test harness around this area, lightweight coverage
may be deferred in favor of careful manual validation, but detection and helper
argument construction should still be kept in code that is easy to test later.

### Manual Validation

1. Launch a non-RF executable and confirm GameBridge performs a normal launch.
2. Launch `bananarfo.exe` and confirm the log shows assisted mode activation.
3. Confirm the helper starts before the Wine launch.
4. Click `Start Game` in the launcher and confirm raw `DefaultSet` snapshots are
   written to the run directory.
5. Stop the launch and confirm the helper process is also terminated.
6. Confirm the capture directory path shown in logs matches real saved files.

## Risks

- The repo's current Python helper becomes a runtime dependency for this flow.
- Process cleanup may be easy to get wrong if helper and Wine exits race.
- Assisted mode could confuse users if the UI implies a fix instead of a
  capture workflow.

These risks are acceptable for this milestone because the goal is observability
and repeatability, not a full compatibility solution.

## Success Criteria

This milestone is successful when:

- GameBridge can launch RF Banana in assisted capture mode from the app.
- The helper starts automatically with no manual shell step.
- Capture artifacts are saved into a predictable per-bottle location.
- The log makes it obvious where artifacts were written.
- The code remains explicit that this is a diagnostic workflow, not the final
  gameplay fix.

## Follow-On Work

If this milestone works well, the next design/implementation cycle can choose
among:

- optional account-field patch mode using the same helper
- a reusable assisted-launch abstraction for other problematic launchers
- deeper investigation of the native Sirin handoff path in `d3d9.dll`
- eventual replacement of the Python helper with a native Swift tool if the
  workflow proves permanent
