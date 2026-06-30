import XCTest
@testable import GameBridge

final class RFBananaAssistedLaunchTests: XCTestCase {
    @MainActor
    func testLaunchStartsHelperStreamsPrefixedLogsAndStopsHelperWhenWineExits() async throws {
        let root = makeTempRoot()
        let helperStartedMarker = root.appendingPathComponent("helper-started.txt")
        let helperStoppedMarker = root.appendingPathComponent("helper-stopped.txt")
        let wineStartedMarker = root.appendingPathComponent("wine-started.txt")
        let exe = root.appendingPathComponent("bananarfo.exe")
        FileManager.default.createFile(atPath: exe.path, contents: Data())

        let helperScript = root.appendingPathComponent("helper.sh")
        try makeExecutable(
            at: helperScript,
            contents: """
            #!/bin/sh
            echo "helper-started"
            echo "started" > '\(shellQuotedPath(helperStartedMarker))'
            trap 'echo "helper-stopping"; echo "stopped" > '\(shellQuotedPath(helperStoppedMarker))'; exit 0' TERM INT
            while true; do
              sleep 0.1
            done
            """
        )

        let wineScript = root.appendingPathComponent("wine-stub.sh")
        try makeExecutable(
            at: wineScript,
            contents: """
            #!/bin/sh
            echo "wine-started:$1"
            echo "started" > '\(shellQuotedPath(wineStartedMarker))'
            sleep 0.3
            echo "wine-finished"
            """
        )

        let bottle = Bottle(name: "RF Banana", prefixPath: root.appendingPathComponent("Prefix").path)
        let assistedLaunch = RFBananaAssistedLaunchPlan(
            helperExecutableURL: helperScript,
            helperArguments: [],
            helperWorkingDirectory: root,
            captureDirectory: root.appendingPathComponent("Capture", isDirectory: true),
            helperLogPrefix: "[rfbanana-helper]"
        )
        let runner = WineRunner()

        runner.launch(
            exe: exe,
            in: bottle,
            winePath: wineScript.path,
            backend: .wined3d,
            options: LaunchOptions(metalFX: false, showOverlay: false, advertiseAVX: false),
            assistedLaunch: assistedLaunch
        )

        let didStartBothProcesses = await waitUntil(timeout: 5) {
            FileManager.default.fileExists(atPath: helperStartedMarker.path) &&
            FileManager.default.fileExists(atPath: wineStartedMarker.path)
        }
        XCTAssertTrue(didStartBothProcesses, "Expected both helper and wine stubs to start")

        let didStopHelperAfterWineExit = await waitUntil(timeout: 5) {
            !runner.isRunning &&
            FileManager.default.fileExists(atPath: helperStoppedMarker.path)
        }
        XCTAssertTrue(didStopHelperAfterWineExit, "Expected helper cleanup after the wine stub exits")

        let helperLaunchIndex = try XCTUnwrap(
            runner.logLines.firstIndex { $0.hasPrefix("[rfbanana-helper] ▶ ") }
        )
        let wineLaunchIndex = try XCTUnwrap(
            runner.logLines.firstIndex { $0.hasPrefix("[wine] ▶ ") }
        )

        XCTAssertLessThan(helperLaunchIndex, wineLaunchIndex)
        XCTAssertTrue(runner.logLines.contains("[rfbanana-helper] helper-started"))
        XCTAssertTrue(runner.logLines.contains("[wine] wine-started:\(exe.path)"))
        XCTAssertTrue(runner.logLines.contains("[rfbanana-helper] helper-stopping"))
        XCTAssertEqual(runner.statusMessage, "Game exited (code 0)")
    }

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

    private func makeExecutable(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return condition()
    }

    private func shellQuotedPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
