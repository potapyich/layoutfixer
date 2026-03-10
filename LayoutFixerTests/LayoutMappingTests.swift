import XCTest

final class LayoutMappingTests: XCTestCase {
    func testAllEnToRuMappings() {
        XCTAssertFalse(LayoutMapping.qwertyToRu.isEmpty)
        XCTAssertEqual(LayoutMapping.qwertyToRu["q"], "й")
        XCTAssertEqual(LayoutMapping.qwertyToRu["h"], "р")
        XCTAssertEqual(LayoutMapping.qwertyToRu["g"], "п")
        XCTAssertEqual(LayoutMapping.qwertyToRu["b"], "и")
        XCTAssertEqual(LayoutMapping.qwertyToRu["d"], "в")
        XCTAssertEqual(LayoutMapping.qwertyToRu["t"], "е")
        XCTAssertEqual(LayoutMapping.qwertyToRu["n"], "т")
    }

    func testAllRuToEnMappings() {
        for (en, ru) in LayoutMapping.qwertyToRu {
            XCTAssertEqual(LayoutMapping.ruToQwerty[ru], en, "RU→EN mismatch for \(ru)")
        }
    }

    func testRoundTrip() {
        let converter = LayoutConverter()
        let detector = DirectionDetector()
        let testWords = ["ghbdtn", "руддщ"]
        for word in testWords {
            guard let dir = detector.detectDirection(word) else {
                XCTFail("Could not detect direction for \(word)")
                continue
            }
            let converted = converter.convert(word, direction: dir)
            let back = converter.convert(converted, direction: dir == .enToRu ? .ruToEn : .enToRu)
            XCTAssertEqual(back, word, "Round-trip failed for \(word)")
        }
    }
}
