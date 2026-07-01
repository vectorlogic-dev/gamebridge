import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A pill-shaped button that shows the current `HotkeyCombo` and lets the
/// user rebind it by clicking and then pressing the desired keystroke.
///
/// While recording, we install a local `NSEvent` monitor for `.keyDown` and
/// swallow the next keystroke (returning `nil`) so it doesn't reach the
/// picker's underlying button or any focused text field. The event's
/// `modifierFlags` are translated into Carbon modifier constants that match
/// what `HotkeyMonitor.register` expects.
struct HotkeyRecorderView: View {
    @Binding var combo: HotkeyCombo
    var onRecorded: () -> Void = {}

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(recording ? "Press a key…" : combo.label)
                .font(.body.monospaced().bold())
                .foregroundStyle(recording ? Color.orange : Color.primary)
                .frame(minWidth: 70)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    (recording ? Color.orange : Color.accentColor).opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            recording ? Color.orange : Color.accentColor.opacity(0.6),
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .help(recording ? "Press the new hotkey combo, or Escape to cancel." : "Click to rebind.")
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopRecording()  // defensive; shouldn't happen
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels without changing the combo.
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            combo = HotkeyCombo(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonModifiers(from: event.modifierFlags)
            )
            stopRecording()
            onRecorded()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }

    /// Translate `NSEvent.ModifierFlags` (Cocoa mask) into Carbon-style
    /// flags. `HotkeyMonitor.register` passes these straight through to
    /// `RegisterEventHotKey`, which wants Carbon values (`controlKey` etc.),
    /// not Cocoa's `.control` bit.
    private func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if nsFlags.contains(.control)  { result |= UInt32(controlKey) }
        if nsFlags.contains(.option)   { result |= UInt32(optionKey) }
        if nsFlags.contains(.shift)    { result |= UInt32(shiftKey) }
        if nsFlags.contains(.command)  { result |= UInt32(cmdKey) }
        return result
    }
}
