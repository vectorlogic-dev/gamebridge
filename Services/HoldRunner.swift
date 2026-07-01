import Foundation
import AppKit
import ApplicationServices
import Combine
import Carbon.HIToolbox

struct FrontmostApp: Equatable {
    let pid: pid_t
    let name: String
}

/// Holds a number key down inside one specific app (captured by PID), like an
/// autobuff for MMOs. The user clicks into the game, presses the start
/// hotkey — `HoldRunner` records the frontmost app's PID, then sends
/// `keyDown` + auto-repeats to that PID until the stop hotkey is pressed.
/// Because events are posted with `CGEvent.postToPid`, they go to the captured
/// app regardless of focus — the user can switch to other apps freely without
/// the macro spamming them.
@MainActor
final class HoldRunner: ObservableObject {
    typealias FrontmostAppProvider = @MainActor () -> FrontmostApp?
    typealias KeyDownHandler = (NumberKey, pid_t, Bool) -> Void
    typealias KeyUpHandler = (NumberKey, pid_t) -> Void
    typealias SleepHandler = (UInt64) async -> Void

    @Published var targetKey: NumberKey = .n1
    @Published private(set) var state: State = .idle
    @Published private(set) var registrationError: String?
    @Published private(set) var permissionError: String?

    /// Start hotkey. Default is ⌃-; per-bottle overrides land here before
    /// `registerHotkeys()` runs.
    var startHotkey: HotkeyCombo = .defaultStart
    /// Stop hotkey. Default is ⌃=.
    var stopHotkey: HotkeyCombo = .defaultStop

    enum State: Equatable {
        case idle
        case holding(targetApp: String, since: Date)
    }

    private var targetPID: pid_t?
    private var armedKey: NumberKey?
    private var holdTask: Task<Void, Never>?
    private var startHotkeyID: UInt32?
    private var stopHotkeyID: UInt32?
    private let frontmostAppProvider: FrontmostAppProvider
    private let keyDownHandler: KeyDownHandler
    private let keyUpHandler: KeyUpHandler
    private let sleepHandler: SleepHandler

    /// Auto-repeat interval, matching macOS's default key-repeat rate.
    private let repeatInterval: UInt64 = 33_000_000  // 33 ms = ~30 Hz

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

    deinit {
        // Carbon resources are process-wide; unregister synchronously.
        if let id = startHotkeyID { HotkeyMonitor.shared.unregister(id) }
        if let id = stopHotkeyID { HotkeyMonitor.shared.unregister(id) }
    }

    func registerHotkeys() {
        registrationError = nil
        unregisterHotkeys()
        requestAccessibilityIfNeeded()

        startHotkeyID = HotkeyMonitor.shared.register(keyCode: startHotkey.keyCode, modifiers: startHotkey.modifiers) { [weak self] in
            Task { @MainActor in self?.armOnCurrentApp() }
        }
        stopHotkeyID = HotkeyMonitor.shared.register(keyCode: stopHotkey.keyCode, modifiers: stopHotkey.modifiers) { [weak self] in
            Task { @MainActor in self?.disarm() }
        }

        var failed: [String] = []
        if startHotkeyID == nil { failed.append("start (\(startHotkey.label))") }
        if stopHotkeyID  == nil { failed.append("stop (\(stopHotkey.label))") }
        if !failed.isEmpty {
            let message = "Hotkey already claimed by another app: " + failed.joined(separator: ", ")
            registrationError = message
            ErrorLogger.shared.log(message, source: "hotkey")
        }
    }

    func unregisterHotkeys() {
        if let id = startHotkeyID { HotkeyMonitor.shared.unregister(id); startHotkeyID = nil }
        if let id = stopHotkeyID  { HotkeyMonitor.shared.unregister(id); stopHotkeyID  = nil }
    }

    /// `CGEvent.postToPid` silently drops synthetic events when the app isn't
    /// in TCC's Accessibility trusted list — and macOS never spontaneously
    /// prompts. Passing `AXTrustedCheckOptionPrompt = true` is the sanctioned
    /// way to trigger the system prompt the first time we need the permission.
    private func requestAccessibilityIfNeeded() {
        // Hardcode the option-key string. `kAXTrustedCheckOptionPrompt` is a
        // `CFStringRef` global that Swift 6 rejects as non-Sendable, but its
        // value is the literal "AXTrustedCheckOptionPrompt".
        let options = ["AXTrustedCheckOptionPrompt": kCFBooleanTrue] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionError = trusted ? nil : "GameBridge needs Accessibility permission to send keys to games. Grant it in System Settings → Privacy & Security → Accessibility, then restart GameBridge."
    }

    /// Capture the currently-frontmost app's PID and start holding the target
    /// key on it. No-op if already holding.
    func armOnCurrentApp() {
        guard case .idle = state else { return }
        guard let frontmost = frontmostAppProvider() else { return }
        targetPID = frontmost.pid
        armedKey = targetKey
        state = .holding(targetApp: frontmost.name, since: Date())
        startHoldLoop(pid: frontmost.pid)
    }

    /// Stop the hold loop and release the captured key immediately. No-op if idle.
    func disarm() {
        holdTask?.cancel()
        holdTask = nil
        if let pid = targetPID, let armedKey {
            keyUpHandler(armedKey, pid)
        }
        targetPID = nil
        armedKey = nil
        state = .idle
    }

    private func startHoldLoop(pid: pid_t) {
        guard let key = armedKey else { return }
        let interval = repeatInterval
        holdTask?.cancel()
        keyDownHandler(key, pid, false)
        holdTask = Task {
            // After the initial press, send tight autorepeat presses until cancelled.
            while !Task.isCancelled {
                await sleepHandler(interval)
                guard !Task.isCancelled else { break }
                keyDownHandler(key, pid, true)
            }
        }
    }

}
