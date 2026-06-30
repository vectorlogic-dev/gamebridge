# RF Banana Assisted Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an RF Banana-assisted launch flow that bundles the existing Python capture helper, starts it automatically for `bananarfo.exe`, and streams its output into GameBridge while saving `.tmp` snapshots to a predictable per-bottle diagnostics folder.

**Architecture:** Keep `WineRunner` as the single owner of launch lifecycle, but let it orchestrate one optional sidecar helper process before the main Wine launch. Put RF Banana detection, capture-directory construction, and helper command building into a small dedicated service so `BottleDetailView` only decides whether to do a normal launch, an assisted launch, or abort with a logged preflight error.

**Tech Stack:** SwiftUI, Foundation `Process`, XcodeGen, XCTest, bundled Python script resource

---

### Task 1: Add project scaffolding for bundled helper and tests

**Files:**
- Modify: `project.yml`
- Create: `GameBridgeTests/`

- [ ] **Step 1: Add the bundled helper resource and a unit-test target in `project.yml`**

```yaml
name: GameBridge
options:
  deploymentTarget:
    macOS: "14.0"
  bundleIdPrefix: com.argie
settings:
  base:
    SWIFT_VERSION: "6.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Automatic
targets:
  GameBridge:
    type: application
    platform: macOS
    sources:
      - path: GameBridgeApp.swift
      - path: Models
      - path: Services
      - path: Views
    resources:
      - path: scripts/rfbanana_handoff_patcher.py
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.argie.gamebridge
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_ENTITLEMENTS: ""
  GameBridgeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: GameBridgeTests
    dependencies:
      - target: GameBridge
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Automatic
```

- [ ] **Step 2: Generate the Xcode project from the updated spec**

Run:

```bash
xcodegen generate
```

Expected: `Generated project at /Users/argie/repos/gamebridge/GameBridge.xcodeproj`

- [ ] **Step 3: Run a clean build before adding new behavior**

Run:

```bash
xcodebuild -scheme GameBridge -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit the scaffolding change**

```bash
git add project.yml
git commit -m "test: add GameBridge test target"
```

### Task 2: Add failing tests and implement the RF Banana launch-plan builder

**Files:**
- Create: `GameBridgeTests/RFBananaAssistedLaunchTests.swift`
- Create: `Services/RFBananaAssistedLaunch.swift`

- [ ] **Step 1: Write failing tests for RF Banana detection and helper command construction**

```swift
import XCTest
@testable import GameBridge

final class RFBananaAssistedLaunchTests: XCTestCase {
    func testDecisionIsNotApplicableForNonLauncherExecutable() throws {
        let root = makeTempRoot()
        let exe = root.appendingPathComponent("SomethingElse.exe")
        FileManager.default.createFile(atPath: exe.path, contents: Data())

        let bottle = Bottle(name: "Test Bottle", prefixPath: root.appendingPathComponent("Prefix").path)
        let decision = RFBananaAssistedLaunch.decide(
            for: exe,
            in: bottle,
            scriptURL: root.appendingPathComponent("rfbanana_handoff_patcher.py"),
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(decision, .notApplicable)
    }

    func testDecisionBuildsCaptureOnlyPlanForKnownLayout() throws {
        let root = makeTempRoot()
        let installRoot = root.appendingPathComponent("RF_Banana", isDirectory: true)
        let systemDir = installRoot.appendingPathComponent("System", isDirectory: true)
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)
        try Data().write(to: installRoot.appendingPathComponent("RF_Online.bin"))
        try Data().write(to: installRoot.appendingPathComponent("bananarfo.exe"))
        try Data().write(to: systemDir.appendingPathComponent("DefaultSet.tmp"))
        let scriptURL = root.appendingPathComponent("rfbanana_handoff_patcher.py")
        try Data("#!/usr/bin/env python3\n".utf8).write(to: scriptURL)

        let bottle = Bottle(name: "RF Banana", prefixPath: root.appendingPathComponent("Prefix").path)
        let decision = RFBananaAssistedLaunch.decide(
            for: installRoot.appendingPathComponent("bananarfo.exe"),
            in: bottle,
            scriptURL: scriptURL,
            now: Date(timeIntervalSince1970: 0)
        )

        guard case let .ready(plan) = decision else {
            return XCTFail("Expected an assisted-launch plan")
        }

        XCTAssertEqual(plan.helperExecutableURL.path, "/usr/bin/python3")
        XCTAssertEqual(plan.helperArguments, [
            scriptURL.path,
            "--game-dir", installRoot.path,
            "--no-patch",
            "--out-dir", plan.captureDirectory.path
        ])
        XCTAssertEqual(plan.helperWorkingDirectory, installRoot)
        XCTAssertEqual(plan.helperLogPrefix, "[rfbanana-helper]")
        XCTAssertEqual(plan.captureDirectory.lastPathComponent, "1970-01-01T00-00-00")
        XCTAssertTrue(plan.captureDirectory.path.contains("/Diagnostics/RFBanana/"))
    }

    func testDecisionBlocksWhenLauncherLooksLikeRFBananaButScriptIsMissing() throws {
        let root = makeTempRoot()
        let installRoot = root.appendingPathComponent("RF_Banana", isDirectory: true)
        let systemDir = installRoot.appendingPathComponent("System", isDirectory: true)
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)
        try Data().write(to: installRoot.appendingPathComponent("RF_Online.bin"))
        try Data().write(to: installRoot.appendingPathComponent("bananarfo.exe"))
        try Data().write(to: systemDir.appendingPathComponent("DefaultSet.tmp"))

        let bottle = Bottle(name: "RF Banana", prefixPath: root.appendingPathComponent("Prefix").path)
        let decision = RFBananaAssistedLaunch.decide(
            for: installRoot.appendingPathComponent("bananarfo.exe"),
            in: bottle,
            scriptURL: nil,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            decision,
            .blocked("[rfbanana] Bundled assisted-launch helper is missing.")
        )
    }

    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail before implementation**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -destination 'platform=macOS' \
  -only-testing:GameBridgeTests/RFBananaAssistedLaunchTests test
```

Expected: FAIL with compile errors such as `Cannot find 'RFBananaAssistedLaunch' in scope`

- [ ] **Step 3: Implement the launch-plan builder in `Services/RFBananaAssistedLaunch.swift`**

```swift
import Foundation

struct RFBananaAssistedLaunchPlan: Equatable {
    let helperExecutableURL: URL
    let helperArguments: [String]
    let helperWorkingDirectory: URL
    let captureDirectory: URL
    let helperLogPrefix: String
}

enum RFBananaAssistedLaunchDecision: Equatable {
    case notApplicable
    case blocked(String)
    case ready(RFBananaAssistedLaunchPlan)
}

enum RFBananaAssistedLaunch {
    static func decide(
        for exeURL: URL,
        in bottle: Bottle,
        scriptURL: URL? = Bundle.main.url(forResource: "rfbanana_handoff_patcher", withExtension: "py"),
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> RFBananaAssistedLaunchDecision {
        guard exeURL.lastPathComponent.caseInsensitiveCompare("bananarfo.exe") == .orderedSame else {
            return .notApplicable
        }

        let installRoot = exeURL.deletingLastPathComponent()
        let gameBinary = installRoot.appendingPathComponent("RF_Online.bin")
        let defaultSet = installRoot.appendingPathComponent("System/DefaultSet.tmp")

        guard fileManager.fileExists(atPath: gameBinary.path),
              fileManager.fileExists(atPath: defaultSet.path) else {
            return .notApplicable
        }

        guard let scriptURL else {
            return .blocked("[rfbanana] Bundled assisted-launch helper is missing.")
        }

        let captureDirectory = diagnosticsRoot(for: bottle)
            .appendingPathComponent(timestampString(from: now), isDirectory: true)

        return .ready(
            RFBananaAssistedLaunchPlan(
                helperExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                helperArguments: [
                    scriptURL.path,
                    "--game-dir", installRoot.path,
                    "--no-patch",
                    "--out-dir", captureDirectory.path
                ],
                helperWorkingDirectory: installRoot,
                captureDirectory: captureDirectory,
                helperLogPrefix: "[rfbanana-helper]"
            )
        )
    }

    private static func diagnosticsRoot(for bottle: Bottle) -> URL {
        bottle.prefixURL
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("RFBanana", isDirectory: true)
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run the targeted tests again and confirm they pass**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -destination 'platform=macOS' \
  -only-testing:GameBridgeTests/RFBananaAssistedLaunchTests test
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit the tested launch-plan helper**

```bash
git add project.yml Services/RFBananaAssistedLaunch.swift GameBridgeTests/RFBananaAssistedLaunchTests.swift
git commit -m "feat: add RF Banana assisted launch planning"
```

### Task 3: Teach `WineRunner` to manage an optional helper sidecar

**Files:**
- Modify: `Services/WineRunner.swift`

- [ ] **Step 1: Add helper-process state and a public log helper**

```swift
@MainActor
final class WineRunner: ObservableObject {
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Idle"

    private var currentProcess: Process?
    private var helperProcess: Process?

    func logExternal(_ line: String) {
        appendLine(line)
    }
}
```

- [ ] **Step 2: Extend `launch(...)` so it can start the helper before Wine**

```swift
func launch(
    exe: URL,
    in bottle: Bottle,
    winePath: String,
    backend: GraphicsBackend,
    options: LaunchOptions,
    assistedLaunch: RFBananaAssistedLaunchPlan? = nil
) {
    var env = baseEnv(for: bottle, winePath: winePath)
    for (k, v) in backend.environment(options: options) { env[k] = v }
    if options.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
    if options.showOverlay { env["MTL_HUD_ENABLED"] = "1" }

    if let assistedLaunch {
        do {
            try FileManager.default.createDirectory(
                at: assistedLaunch.captureDirectory,
                withIntermediateDirectories: true
            )
            appendLine("[rfbanana] capture dir: \(assistedLaunch.captureDirectory.path)")
            helperProcess = try startHelper(assistedLaunch)
        } catch {
            appendLine("[rfbanana] Failed to start assisted launch: \(error.localizedDescription)")
            statusMessage = "Assisted launch failed"
            return
        }
    }

    statusMessage = "Launching \(exe.lastPathComponent) [\(backend.label)]"
    do {
        currentProcess = try startProcess(
            executableURL: URL(fileURLWithPath: winePath),
            arguments: [exe.path],
            workingDir: exe.deletingLastPathComponent(),
            env: env,
            logPrefix: "[wine]",
            onFinish: { [weak self] code in
                self?.stopHelperIfRunning()
                self?.statusMessage = "Game exited (code \(code))"
            }
        )
        isRunning = true
    } catch {
        stopHelperIfRunning()
        statusMessage = "Launch failed"
    }
}
```

- [ ] **Step 3: Add a reusable `startProcess(...)` helper that throws if startup fails and streams prefixed output**

```swift
private func startProcess(
    executableURL: URL,
    arguments: [String],
    workingDir: URL,
    env: [String: String],
    logPrefix: String,
    onFinish: @MainActor @escaping @Sendable (Int32) -> Void
) throws -> Process {
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
        throw CocoaError(.fileNoSuchFile)
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = env
    process.currentDirectoryURL = workingDir

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in
            self?.appendChunk(text, prefix: logPrefix)
        }
    }

    process.terminationHandler = { proc in
        Task { @MainActor in
            pipe.fileHandleForReading.readabilityHandler = nil
            onFinish(proc.terminationStatus)
        }
    }

    do {
        appendLine("\(logPrefix) ▶ \(executableURL.path) \(arguments.joined(separator: " "))")
        try process.run()
        return process
    } catch {
        appendLine("\(logPrefix) Failed to start: \(error.localizedDescription)")
        throw error
    }
}
```

- [ ] **Step 4: Add helper-start and helper-stop methods plus prefixed chunk handling**

```swift
private func startHelper(_ plan: RFBananaAssistedLaunchPlan) throws -> Process {
    appendLine("[rfbanana] assisted launch started")
    return try startProcess(
        executableURL: plan.helperExecutableURL,
        arguments: plan.helperArguments,
        workingDir: plan.helperWorkingDirectory,
        env: ProcessInfo.processInfo.environment,
        logPrefix: plan.helperLogPrefix,
        onFinish: { [weak self] code in
            self?.helperProcess = nil
            self?.appendLine("[rfbanana-helper] exited with code \(code)")
        }
    )
}

private func stopHelperIfRunning() {
    helperProcess?.terminate()
    helperProcess = nil
}

func terminate() {
    stopHelperIfRunning()
    currentProcess?.terminate()
}

private func appendChunk(_ text: String, prefix: String) {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines where !line.isEmpty {
        appendLine("\(prefix) \(line)")
    }
}
```

- [ ] **Step 5: Run the app test target and a full build**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -destination 'platform=macOS' test
xcodebuild -scheme GameBridge -configuration Debug build
```

Expected:
- `** TEST SUCCEEDED **`
- `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit the sidecar lifecycle support**

```bash
git add Services/WineRunner.swift
git commit -m "feat: add assisted launch helper lifecycle"
```

### Task 4: Integrate assisted-launch decisions into `BottleDetailView`

**Files:**
- Modify: `Views/BottleDetailView.swift`

- [ ] **Step 1: Decide assisted vs normal launch in `launchExe(_:)`**

```swift
private func launchExe(_ url: URL) {
    switch RFBananaAssistedLaunch.decide(for: url, in: bottle) {
    case .notApplicable:
        runner.launch(
            exe: url,
            in: bottle,
            winePath: store.selectedWinePath,
            backend: backend,
            options: options
        )

    case .blocked(let message):
        runner.logExternal(message)
        runner.logExternal("[rfbanana] Assisted launch aborted before Wine startup.")

    case .ready(let assistedLaunch):
        runner.launch(
            exe: url,
            in: bottle,
            winePath: store.selectedWinePath,
            backend: backend,
            options: options,
            assistedLaunch: assistedLaunch
        )
    }
}
```

- [ ] **Step 2: Build and run the targeted tests to catch integration regressions**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -destination 'platform=macOS' \
  -only-testing:GameBridgeTests/RFBananaAssistedLaunchTests test
xcodebuild -scheme GameBridge -configuration Debug build
```

Expected:
- `** TEST SUCCEEDED **`
- `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit the UI integration**

```bash
git add Views/BottleDetailView.swift
git commit -m "feat: wire RF Banana assisted launch into UI"
```

### Task 5: Verify the end-to-end RF Banana capture workflow

**Files:**
- Modify: `docs/rf-banana-setup.md`

- [ ] **Step 1: Document the new assisted-launch flow in `docs/rf-banana-setup.md`**

```md
## GameBridge assisted launch capture mode

If you save `bananarfo.exe` as a shortcut and launch it from GameBridge,
GameBridge now detects the RF Banana layout and starts its bundled
`rfbanana_handoff_patcher.py` helper in capture-only mode before Wine starts
the launcher.

What this does:

- writes `DefaultSet.tmp` snapshots into the bottle's
  `Diagnostics/RFBanana/<timestamp>/` directory
- streams helper output into the GameBridge log alongside Wine output
- makes failed launcher-to-game handoff runs easier to compare later

What this does not do:

- it does not fix `Diff Nation Code`
- it does not replace the native Sirin session handoff
```

- [ ] **Step 2: Run the full automated verification pass**

Run:

```bash
xcodegen generate
xcodebuild -scheme GameBridge -destination 'platform=macOS' test
xcodebuild -scheme GameBridge -configuration Debug build
```

Expected:
- `** TEST SUCCEEDED **`
- `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the manual assisted-launch validation**

Run and verify:

```text
1. Open GameBridge and select the RF Banana bottle.
2. Launch a non-RF executable and confirm no [rfbanana] log lines appear.
3. Launch bananarfo.exe and confirm these log patterns:
   [rfbanana] assisted launch started
   [rfbanana] capture dir: <.../Diagnostics/RFBanana/<timestamp>>
   [rfbanana-helper] Watching: <.../System/DefaultSet.tmp>
   [wine] ▶ <wine-path> <.../bananarfo.exe>
4. Log in, select a server, and click Start Game.
5. Confirm raw DefaultSet snapshot files appear in the printed capture directory.
6. Click Stop or let the run exit; confirm the helper exits too.
```

Expected: The helper starts automatically, snapshots are saved, and the app log makes the artifact path obvious even if the game still fails with `Diff Nation Code`.

- [ ] **Step 4: Commit the docs and verified feature**

```bash
git add docs/rf-banana-setup.md
git commit -m "docs: document RF Banana assisted launch capture"
```

- [ ] **Step 5: Create the final feature commit if the branch still has uncommitted code**

```bash
git status --short
git add project.yml Services/RFBananaAssistedLaunch.swift Services/WineRunner.swift \
  Views/BottleDetailView.swift GameBridgeTests/RFBananaAssistedLaunchTests.swift \
  docs/rf-banana-setup.md
git commit -m "feat: add RF Banana assisted launch capture"
```

Expected: `nothing to commit, working tree clean` or a final successful feature commit if earlier task commits were intentionally skipped
