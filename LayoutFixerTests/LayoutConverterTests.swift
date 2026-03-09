import XCTest

final class LayoutConverterTests: XCTestCase {
    let converter = LayoutConverter()

    func testEnToRuGhbdtn() {
        XCTAssertEqual(converter.convert("ghbdtn", direction: .enToRu), "привет")
    }

    func testRuToEnRuddsch() {
        XCTAssertEqual(converter.convert("руддщ", direction: .ruToEn), "hello")
    }

    func testPassthroughUnmapped() {
        // In Russian layout, "," is produced by shift+"/" → maps back to "?" in English
        let result = converter.convert("тест,", direction: .ruToEn)
        XCTAssertEqual(result, "ntcn?")
    }

    func testUnmappedCharactersPassthrough() {
        // Numbers and spaces are not in the mapping → pass through unchanged
        let result = converter.convert("тест 123", direction: .ruToEn)
        XCTAssertTrue(result.hasSuffix(" 123"))
    }

    func testEmptyString() {
        XCTAssertEqual(converter.convert("", direction: .enToRu), "")
    }

    func testSpacesPassthrough() {
        let result = converter.convert("hello world", direction: .enToRu)
        XCTAssertTrue(result.contains(" "))
    }

    func testNtcn() {
        XCTAssertEqual(converter.convert("тест", direction: .ruToEn), "ntcn")
    }
}
