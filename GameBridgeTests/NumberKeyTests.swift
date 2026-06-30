import XCTest
@testable import GameBridge

final class NumberKeyTests: XCTestCase {
    func testAllCasesStayInTopRowOrder() {
        XCTAssertEqual(
            NumberKey.allCases,
            [.n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .n9, .n0]
        )
    }

    func testRawValuesMatchTopRowVirtualKeyCodes() {
        XCTAssertEqual(
            NumberKey.allCases.map(\.rawValue),
            [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        )
    }

    func testLabelsMatchDisplayedDigits() {
        XCTAssertEqual(NumberKey.n1.label, "1")
        XCTAssertEqual(NumberKey.n2.label, "2")
        XCTAssertEqual(NumberKey.n3.label, "3")
        XCTAssertEqual(NumberKey.n4.label, "4")
        XCTAssertEqual(NumberKey.n5.label, "5")
        XCTAssertEqual(NumberKey.n6.label, "6")
        XCTAssertEqual(NumberKey.n7.label, "7")
        XCTAssertEqual(NumberKey.n8.label, "8")
        XCTAssertEqual(NumberKey.n9.label, "9")
        XCTAssertEqual(NumberKey.n0.label, "0")
    }
}
