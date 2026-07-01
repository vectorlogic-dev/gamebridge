import SwiftUI
import AppKit

@main
struct GameBridgeApp: App {
    @StateObject private var store = BottleStore()

    init() {
        // If another GameBridge process is already running, activate it and
        // bail out. Prevents the second instance's `RegisterEventHotKey` from
        // failing with "hotkey already claimed" against the first — see the
        // errors.log entries in ai/2026-07-01-hold-presser-issue.md.
        let me = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != me
        }
        if let existing = others.first {
            existing.activate()
            // NSApp isn't fully initialised in App.init — raw exit is the only
            // reliable way to leave without touching a half-built AppKit.
            exit(EXIT_SUCCESS)
        }

        // Now that we know we're the only GameBridge process, kill any
        // helper subprocesses left over from prior crashes / force-quits.
        WineRunner.reapOrphanHelpers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}
