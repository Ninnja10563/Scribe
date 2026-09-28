import XCTest
@testable import ImportExport

final class ExportPageSelectionTests: XCTestCase {
    func testPageRangesAreSortedAndDeduplicated() throws {
        XCTAssertEqual(try ExportPageSelection.indices("", pageCount: 4), [0, 1, 2, 3])
        XCTAssertEqual(try ExportPageSelection.indices(" 5, 1, 3–5, 1 ", pageCount: 8), [0, 2, 3, 4])
        XCTAssertEqual(try ExportPageSelection.indices("2-2", pageCount: 2), [1])
    }
    func testInvalidRangesCannotSilentlyOmitPages() {
        for input in ["0", "-1", "1,", "1,,2", "5-3", "1-9", "1-2-3", "two", "99999999999999999999"] {
            XCTAssertThrowsError(try ExportPageSelection.indices(input, pageCount: 8), input)
        }
        XCTAssertThrowsError(try ExportPageSelection.indices("", pageCount: 0))
    }
}
