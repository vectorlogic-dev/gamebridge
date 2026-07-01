import XCTest
import Carbon.HIToolbox
@testable import GameBridge

final class HotkeyComboTests: XCTestCase {
    func testDefaultStartIsControlMinus() {
        XCTAssertEqual(HotkeyCombo.defaultStart.keyCode, UInt32(kVK_ANSI_Minus))
        XCTAssertEqual(HotkeyCombo.defaultStart.modifiers, UInt32(controlKey))
        XCTAssertEqual(HotkeyCombo.defaultStart.label, "⌃-")
    }

    func testDefaultStopIsControlEqual() {
        XCTAssertEqual(HotkeyCombo.defaultStop.keyCode, UInt32(kVK_ANSI_Equal))
        XCTAssertEqual(HotkeyCombo.defaultStop.modifiers, UInt32(controlKey))
        XCTAssertEqual(HotkeyCombo.defaultStop.label, "⌃=")
    }

    func testLabelStacksModifierGlyphsInStandardOrder() {
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_F13),
            modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
        XCTAssertEqual(combo.label, "⌃⌥⇧⌘F13")
    }

    func testLabelFallsBackToKeycodeForUnknownKey() {
        let combo = HotkeyCombo(keyCode: 999, modifiers: 0)
        XCTAssertEqual(combo.label, "keycode 999")
    }

    func testCodableRoundTripPreservesCombo() throws {
        let original = HotkeyCombo(
            keyCode: UInt32(kVK_F19),
            modifiers: UInt32(optionKey) | UInt32(shiftKey)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
