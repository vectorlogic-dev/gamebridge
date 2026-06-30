# KeyPresser AFK Hold Design

Date: 2026-06-30
Status: Draft for review

## Goal

Provide a simple AFK helper for RF Online that repeatedly holds the in-game
macro bound to the top-row `1` key until the user stops it manually.

The user flow is:

1. Bind the RF Online macro to skill slot `1`.
2. Click into RF Online so it is the frontmost app.
3. Press `F11` to start the hold.
4. Leave the game running in the background while the hold continues.
5. Press `F12` to stop the hold and release the key cleanly.

## Scope

This design intentionally covers a small first version only:

- One held key at a time.
- Supported game key range is the existing top-row number set `1` through `0`.
- Default and expected first-use key is `1`.
- Start trigger is `F11`.
- Stop trigger is `F12`.
- The hold targets the captured app process, not the currently focused app.

Out of scope for this version:

- Key sequences or multi-key macros.
- User-configurable trigger keys.
- Per-game presets or saved profiles.
- Numpad support.
- UI for broadcast-mode fallback.

## Recommended Approach

Use targeted event delivery to the currently frontmost app when the user presses
`F11`. This keeps the feature safe for AFK use because synthetic key events are
posted only to RF Online's process and do not leak into whichever macOS app is
focused afterward.

The backup plan is global event broadcast if targeted delivery proves
incompatible with RF Online in practice. That backup should remain dormant
unless real testing shows `CGEvent.postToPid` is insufficient.

## Existing Components To Reuse

- `Services/KeyPresser.swift`
  - Owns synthetic top-row number-key down/up events.
- `Services/HotkeyMonitor.swift`
  - Owns global Carbon hotkey registration for `F11` and `F12`.
- `Services/HoldRunner.swift`
  - Owns the idle/holding state machine and repeat loop.
- `Views/HoldMacroPanel.swift`
  - Owns the user-facing control surface and status text.

The first version should preserve this structure rather than introducing a new
subsystem.

## Behavior Design

### Start

When the runner is idle and the user presses `F11`:

1. Read the frontmost app from `NSWorkspace.shared.frontmostApplication`.
2. Capture its PID and display name.
3. Transition to the holding state.
4. Send an initial `keyDown` for the selected number key.
5. Continue sending autorepeat `keyDown` events at the existing repeat
   interval until stopped.

If there is no frontmost app available, the request is ignored and the runner
remains idle.

### Stop

When the user presses `F12`:

1. Cancel the repeat task.
2. Send a final `keyUp` to the captured PID.
3. Clear the captured PID.
4. Return to idle state.

Stopping should be safe to call repeatedly. If already idle, it should remain a
no-op.

### While Holding

- The selected number key cannot be changed while the runner is active.
- Status text should clearly show that holding is active and which app was
  captured.
- The hold continues even if the user switches focus to another macOS app.

## Failure Handling

### Hotkey registration conflicts

If another app has already claimed `F11` or `F12`, the panel should keep the
existing warning behavior and explain which hotkey failed to register.

### Accessibility permission

The feature should not proactively disable itself when accessibility permission
has not yet been granted. It should continue relying on the normal macOS prompt
when synthetic input is first attempted.

### RF Online incompatibility fallback

If real-world testing shows that PID-targeted delivery does not reliably drive
RF Online, the fallback is global broadcast delivery. That fallback is a backup
engineering path, not part of this first version's default UX.

## Testing Strategy

### Automated

- Confirm the supported number-key set remains the top-row keys `1` through `0`.
- Confirm `HoldRunner.armOnCurrentApp()` transitions from idle to holding only
  once per arming cycle.
- Confirm `HoldRunner.disarm()` returns to idle, clears captured state, and
  releases the held key.
- Confirm UI state disables key selection while holding.

### Manual

1. Launch GameBridge and open a bottle containing RF Online.
2. Set the hold key to `1`.
3. Focus RF Online and press `F11`.
4. Verify the status changes to holding and the in-game macro on slot `1`
   repeats while the game remains active.
5. Switch to another macOS app and verify the hold does not type into that app.
6. Press `F12` and verify the in-game hold stops immediately.

## Acceptance Criteria

- The user can start an AFK hold with `F11` while RF Online is frontmost.
- The feature repeatedly drives the top-row `1` key into RF Online until
  stopped.
- The hold does not leak into unrelated foreground apps after focus changes.
- Pressing `F12` stops the loop and releases the key cleanly.
- Hotkey registration failures remain visible in the UI.
