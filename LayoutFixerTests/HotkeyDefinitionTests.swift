import XCTest
import CoreGraphics

final class HotkeyDefinitionTests: XCTestCase {
    func testDefaultDisplayString() {
        XCTAssertEqual(HotkeyDefinition.default.displayString, "⌥ Space")
    }

    func testCodableRoundTrip() {
        let hotkey = HotkeyDefinition.default
        let data = hotkey.encoded()
        let decoded = HotkeyDefinition.decode(from: data)
        XCTAssertEqual(decoded, hotkey)
    }

    func testCommandDisplayString() {
        let hotkey = HotkeyDefinition(
            keyCode: 12, // Q
            modifierFlags: CGEventFlags.maskCommand.rawValue
        )
        XCTAssertEqual(hotkey.displayString, "⌘ Q")
    }

    func testControlShiftDisplayString() {
        let hotkey = HotkeyDefinition(
            keyCode: 14, // E
            modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
        )
        XCTAssertEqual(hotkey.displayString, "⌃ ⇧ E")
    }

    func testDecodeInvalidData() {
        let result = HotkeyDefinition.decode(from: Data())
        XCTAssertNil(result)
    }
}
