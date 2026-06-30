# KeyPresser AFK Hold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the RF Online AFK hold-key flow so pressing `F11` captures the frontmost app, repeatedly drives top-row key `1` into that app, and `F12` stops and releases it cleanly.

**Architecture:** Keep the existing `KeyPresser` + `HotkeyMonitor` + `HoldRunner` + `HoldMacroPanel` split. Add small injection seams to `HoldRunner` so its state machine can be tested without real global hotkeys or real synthetic key events, then add focused tests for number-key coverage and hold/release behavior.

**Tech Stack:** Swift 6, SwiftUI, Combine, XCTest, Carbon, CoreGraphics, AppKit

---

## File Structure

- Modify: `Services/HoldRunner.swift`
  - Add injectable frontmost-app and key-event hooks so the hold lifecycle is testable without relying on `NSWorkspace.shared` or real `CGEvent` delivery.
- Modify: `Services/KeyPresser.swift`
  - Keep the top-row `1` through `0` mapping stable; only touch this file if a small visibility adjustment is needed for tests.
- Create: `GameBridgeTests/HoldRunnerTests.swift`
  - Cover start, repeat, stop, and idle no-op behavior with fakes.
- Create: `GameBridgeTests/NumberKeyTests.swift`
  - Lock the supported key set to top-row `1` through `0`.

### Task 1: Make `HoldRunner` Testable

**Files:**
- Modify: `Services/HoldRunner.swift`
- Create: `GameBridgeTests/HoldRunnerTests.swift`
- Test: `GameBridgeTests/HoldRunnerTests.swift`

- [ ] **Step 1: Write the failing `HoldRunner` tests**

```swift
import XCTest
@testable import GameBridge

@MainActor
final class HoldRunnerTests: XCTestCase {
    func testArmOnCurrentAppCapturesFrontmostAppAndSendsInitialKeyDown() async throws {
        var events: [RecordedKeyEvent] = []
        let repeatStarted = expectation(description: "repeat loop started")

        let runner = HoldRunner(
            frontmostAppProvider: { FrontmostApp(pid: 4242, name: "RF Online") },
            keyDownHandler: { key, pid, autorepeat in
                events.append(.down(key: key, pid: pid, autorepeat: autorepeat))
                if events.count == 2 { repeatStarted.fulfill() }
            },
            keyUpHandler: { key, pid in
                events.append(.up(key: key, pid: pid))
            },
            sleepHandler: { _ in
                await Task.yield()
            }
        )

        runner.armOnCurrentApp()
        await fulfillment(of: [repeatStarted], timeout: 1.0)
        runner.disarm()

        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(events.first, .down(key: .n1, pid: 4242, autorepeat: false))
        XCTAssertTrue(events.contains(.down(key: .n1, pid: 4242, autorepeat: true)))
        XCTAssertEqual(events.filter(\.isKeyUp).count, 1)
        XCTAssertEqual(events.last, .up(key: .n1, pid: 4242))
    }

    func testArmOnCurrentAppDoesNothingWhenAlreadyHolding() async {
        var frontmostAppCalls = 0
        var keyDownCount = 0

        let runner = HoldRunner(
            frontmostAppProvider: {
                frontmostAppCalls += 1
                return FrontmostApp(pid: 4242, name: "RF Online")
            },
            keyDownHandler: { _, _, _ in keyDownCount += 1 },
            keyUpHandler: { _, _ in },
            sleepHandler: { _ in await Task.yield() }
        )

        runner.armOnCurrentApp()
        runner.armOnCurrentApp()
        runner.disarm()

        XCTAssertEqual(frontmostAppCalls, 1)
        XCTAssertGreaterThanOrEqual(keyDownCount, 1)
    }

    func testDisarmIsSafeWhileIdle() {
        let runner = HoldRunner(
            frontmostAppProvider: { nil },
            keyDownHandler: { _, _, _ in XCTFail("Unexpected keyDown") },
            keyUpHandler: { _, _ in XCTFail("Unexpected keyUp") },
            sleepHandler: { _ in await Task.yield() }
        )

        runner.disarm()

        XCTAssertEqual(runner.state, .idle)
    }
}

private enum RecordedKeyEvent: Equatable {
    case down(key: NumberKey, pid: pid_t, autorepeat: Bool)
    case up(key: NumberKey, pid: pid_t)

    var isKeyUp: Bool {
        if case .up = self {
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: Run the test target to verify it fails**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug test \
  -only-testing:GameBridgeTests/HoldRunnerTests
```

Expected: FAIL with compiler errors because `HoldRunner` does not yet expose
`FrontmostApp`, `frontmostAppProvider`, `keyDownHandler`, `keyUpHandler`, or
`sleepHandler`.

- [ ] **Step 3: Add injection seams to `HoldRunner` with minimal behavior change**

```swift
import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

struct FrontmostApp: Equatable {
    let pid: pid_t
    let name: String
}

@MainActor
final class HoldRunner: ObservableObject {
    typealias FrontmostAppProvider = @MainActor () -> FrontmostApp?
    typealias KeyDownHandler = (NumberKey, pid_t, Bool) -> Void
    typealias KeyUpHandler = (NumberKey, pid_t) -> Void
    typealias SleepHandler = (UInt64) async -> Void

    private let frontmostAppProvider: FrontmostAppProvider
    private let keyDownHandler: KeyDownHandler
    private let keyUpHandler: KeyUpHandler
    private let sleepHandler: SleepHandler

    init(
        frontmostAppProvider: @escaping FrontmostAppProvider = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return FrontmostApp(
                pid: app.processIdentifier,
                name: app.localizedName ?? "Unknown app"
            )
        },
        keyDownHandler: @escaping KeyDownHandler = { key, pid, autorepeat in
            KeyPresser.down(key, toPID: pid, autorepeat: autorepeat)
        },
        keyUpHandler: @escaping KeyUpHandler = { key, pid in
            KeyPresser.up(key, toPID: pid)
        },
        sleepHandler: @escaping SleepHandler = { interval in
            try? await Task.sleep(nanoseconds: interval)
        }
    ) {
        self.frontmostAppProvider = frontmostAppProvider
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.sleepHandler = sleepHandler
    }

    func armOnCurrentApp() {
        guard case .idle = state else { return }
        guard let frontmost = frontmostAppProvider() else { return }
        targetPID = frontmost.pid
        state = .holding(targetApp: frontmost.name, since: Date())
        startHoldLoop(pid: frontmost.pid)
    }

    func disarm() {
        holdTask?.cancel()
        holdTask = nil
        if let pid = targetPID {
            keyUpHandler(targetKey, pid)
        }
        targetPID = nil
        state = .idle
    }

    private func startHoldLoop(pid: pid_t) {
        let key = targetKey
        let interval = repeatInterval
        holdTask?.cancel()
        holdTask = Task {
            keyDownHandler(key, pid, false)
            while !Task.isCancelled {
                await sleepHandler(interval)
                guard !Task.isCancelled else { break }
                keyDownHandler(key, pid, true)
            }
            keyUpHandler(key, pid)
        }
    }
}
```

Note: after this step, remove the extra `keyUpHandler` call from either
`disarm()` or the task teardown so only one final key-up is emitted. Prefer
keeping the release in the task teardown and letting `disarm()` just cancel and
clear state.

- [ ] **Step 4: Run the targeted tests until they pass**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug test \
  -only-testing:GameBridgeTests/HoldRunnerTests
```

Expected: PASS with three tests passing.

- [ ] **Step 5: Commit the testability refactor**

```bash
git add Services/HoldRunner.swift GameBridgeTests/HoldRunnerTests.swift
git commit -m "test: cover hold runner lifecycle"
```

### Task 2: Lock the Supported Key Range to Top-Row `1` Through `0`

**Files:**
- Create: `GameBridgeTests/NumberKeyTests.swift`
- Modify: `Services/KeyPresser.swift` (only if test visibility requires it)
- Test: `GameBridgeTests/NumberKeyTests.swift`

- [ ] **Step 1: Write the failing key-range tests**

```swift
import XCTest
@testable import GameBridge

final class NumberKeyTests: XCTestCase {
    func testAllCasesStayInTopRowOrder() {
        XCTAssertEqual(
            NumberKey.allCases,
            [.n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .n9, .n0]
        )
    }

    func testLabelsMatchDisplayedDigits() {
        XCTAssertEqual(NumberKey.n1.label, "1")
        XCTAssertEqual(NumberKey.n2.label, "2")
        XCTAssertEqual(NumberKey.n3.label, "3")
        XCTAssertEqual(NumberKey.n4.label, "4")
        XCTAssertEqual(NumberKey.n5.label, "5")
        XCTAssertEqual(NumberKey.n6.label, "6")
        XCTAssertEqual(NumberKey.n7.label, "7")
        XCTAssertEqual(NumberKey.n8.label, "8")
        XCTAssertEqual(NumberKey.n9.label, "9")
        XCTAssertEqual(NumberKey.n0.label, "0")
    }
}
```

- [ ] **Step 2: Run the key-range tests to verify the baseline**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug test \
  -only-testing:GameBridgeTests/NumberKeyTests
```

Expected: PASS immediately if the current `NumberKey` enum already matches the
spec. If it fails, fix `NumberKey` before moving on.

- [ ] **Step 3: Keep `NumberKey` constrained to the top row**

```swift
enum NumberKey: Int, CaseIterable, Identifiable, Codable {
    case n1 = 0x12, n2 = 0x13, n3 = 0x14, n4 = 0x15
    case n5 = 0x17, n6 = 0x16, n7 = 0x1A, n8 = 0x1C
    case n9 = 0x19, n0 = 0x1D
}
```

If the enum already matches this, leave `Services/KeyPresser.swift` unchanged
and rely on the new test as the enforcement mechanism.

- [ ] **Step 4: Re-run the key-range tests**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug test \
  -only-testing:GameBridgeTests/NumberKeyTests
```

Expected: PASS with both tests passing.

- [ ] **Step 5: Commit the key-range coverage**

```bash
git add GameBridgeTests/NumberKeyTests.swift Services/KeyPresser.swift
git commit -m "test: lock keypresser top-row key set"
```

### Task 3: Verify the Whole AFK Hold Flow

**Files:**
- Modify: `Views/HoldMacroPanel.swift` (only if manual testing reveals a UI wording gap)
- Test: `GameBridgeTests/HoldRunnerTests.swift`

- [ ] **Step 1: Run the full automated test suite**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug test
```

Expected: PASS with `RFBananaAssistedLaunchTests`, `HoldRunnerTests`, and
`NumberKeyTests` all green.

- [ ] **Step 2: Build the app for manual verification**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -configuration Debug build
```

Expected: PASS with a successful `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manually verify the RF Online AFK flow**

Use this checklist:

```text
1. Launch GameBridge and open the RF Online bottle.
2. Leave the hold key set to 1.
3. Focus the RF Online window.
4. Press F11.
5. Confirm the panel shows Holding 1 -> RF Online.
6. Switch to another macOS app and confirm 1 is not typed there.
7. Press F12.
8. Confirm the hold stops immediately and the status returns to Idle.
```

- [ ] **Step 4: If manual verification exposes only wording issues, tighten the panel copy**

```swift
Text("Click into the game, press **F11** to start holding **1** in that app. Press **F12** to stop. Keys go only to the captured app, so you can use other apps while it runs.")
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
```

Only make this change if the existing copy is unclear during testing. Do not
add new controls for broadcast-mode fallback in this first version.

- [ ] **Step 5: Commit the verified AFK hold behavior**

```bash
git add Views/HoldMacroPanel.swift GameBridgeTests/HoldRunnerTests.swift GameBridgeTests/NumberKeyTests.swift Services/HoldRunner.swift Services/KeyPresser.swift
git commit -m "feat: finalize afk hold key flow"
```

## Self-Review

- Spec coverage: the plan covers targeted PID delivery, `F11`/`F12` triggers,
  top-row `1` through `0` support, stop/release semantics, and RF Online manual
  verification. The global-broadcast fallback is intentionally excluded from
  implementation unless targeted delivery fails in practice.
- Placeholder scan: no `TODO`, `TBD`, or "appropriate handling" placeholders
  remain; each task lists exact files, code, and commands.
- Type consistency: the plan uses `FrontmostApp`, `frontmostAppProvider`,
  `keyDownHandler`, `keyUpHandler`, and `sleepHandler` consistently across the
  test and implementation tasks.
