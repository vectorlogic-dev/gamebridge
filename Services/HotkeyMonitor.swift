import Foundation
import Carbon.HIToolbox

/// Wraps Carbon's `RegisterEventHotKey` so the app can listen for system-wide
/// hotkey presses (work from any focused app) and consume them so they don't
/// bleed into whatever's frontmost.
///
/// Carbon's event-handler callback is a C function pointer that can't capture
/// state, so handlers are stored in a `static` dictionary keyed by the hotkey
/// id. The callback looks them up by id and dispatches to the main queue.
final class HotkeyMonitor: @unchecked Sendable {
    static let shared = HotkeyMonitor()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let lock = NSLock()

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let getStatus = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard getStatus == noErr else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            HotkeyMonitor.shared.lock.lock()
            let handler = HotkeyMonitor.shared.handlers[id]
            HotkeyMonitor.shared.lock.unlock()
            if let handler {
                DispatchQueue.main.async(execute: handler)
            }
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, nil, &eventHandler)
    }

    /// Register a global hotkey. Returns the assigned id, or `nil` if another
    /// app has already claimed the combo.
    func register(keyCode: UInt32, modifiers: UInt32 = 0, handler: @escaping () -> Void) -> UInt32? {
        lock.lock()
        let id = nextID
        nextID += 1
        lock.unlock()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x47424B59 /* 'GBKY' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return nil }

        lock.lock()
        refs[id] = hotKeyRef
        handlers[id] = handler
        lock.unlock()
        return id
    }

    func unregister(_ id: UInt32) {
        lock.lock()
        let ref = refs.removeValue(forKey: id)
        handlers.removeValue(forKey: id)
        lock.unlock()
        if let ref { UnregisterEventHotKey(ref) }
    }
}
