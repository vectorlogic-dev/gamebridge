import Foundation
import CoreGraphics

/// One of the top-row number keys (not the numpad), what an MMO maps to skill
/// slots 1..10 (where `n0` = the conventional "slot 10").
enum NumberKey: Int, CaseIterable, Identifiable, Codable {
    case n1 = 0x12, n2 = 0x13, n3 = 0x14, n4 = 0x15
    case n5 = 0x17, n6 = 0x16, n7 = 0x1A, n8 = 0x1C
    case n9 = 0x19, n0 = 0x1D

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .n1: return "1"
        case .n2: return "2"
        case .n3: return "3"
        case .n4: return "4"
        case .n5: return "5"
        case .n6: return "6"
        case .n7: return "7"
        case .n8: return "8"
        case .n9: return "9"
        case .n0: return "0"
        }
    }
}

/// Posts synthetic keyboard events. When `toPID` is set, the event is delivered
/// directly to that process's input queue via `CGEvent.postToPid`, which means
/// the keys go to that app whether or not it's frontmost — letting the user
/// switch to other apps without the macro spamming them.
enum KeyPresser {
    // `CGEventSource` isn't `Sendable`; we treat it as effectively immutable
    // after creation. `nonisolated(unsafe)` tells Swift 6 we've audited this.
    nonisolated(unsafe) private static let source = CGEventSource(stateID: .hidSystemState)

    static func down(_ key: NumberKey, toPID pid: pid_t?, autorepeat: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(key.rawValue),
                                  keyDown: true) else { return }
        if autorepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    static func up(_ key: NumberKey, toPID pid: pid_t?) {
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(key.rawValue),
                                  keyDown: false) else { return }
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }
}
