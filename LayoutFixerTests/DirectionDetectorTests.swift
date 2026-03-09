import XCTest

final class DirectionDetectorTests: XCTestCase {
    let detector = DirectionDetector()

    func testPureLatin() {
        XCTAssertEqual(detector.detectDirection("ghbdtn"), .enToRu)
        XCTAssertEqual(detector.detectDirection("hello"), .enToRu)
    }

    func testPureCyrillic() {
        XCTAssertEqual(detector.detectDirection("привет"), .ruToEn)
        XCTAssertEqual(detector.detectDirection("тест"), .ruToEn)
    }

    func testEmpty() {
        XCTAssertNil(detector.detectDirection(""))
    }

    func testNonAlphabetic() {
        XCTAssertNil(detector.detectDirection("123 !@#"))
        XCTAssertNil(detector.detectDirection("   "))
    }

    func testMixedDominantLatin() {
        XCTAssertEqual(detector.detectDirection("hello а"), .enToRu)
    }

    func testMixedDominantCyrillic() {
        XCTAssertEqual(detector.detectDirection("привет a"), .ruToEn)
    }

    func testEqualCounts() {
        XCTAssertEqual(detector.detectDirection("aя"), .enToRu)
    }
}
