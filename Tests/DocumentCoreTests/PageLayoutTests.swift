import XCTest
@testable import DocumentCore

final class PageLayoutTests: XCTestCase {
    func testNarrowLayoutPreservesMinimumColumnsAndOriginalImageBytes() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 1, columns: 2, after: document.paragraphs[0].id)
        document.tables[0].columnWidths = [12, 400]
        let data = Data([1, 2, 3])
        document.sections[0].paragraphs[0].runs[0] = TextRun("\u{fffc}")
        document.sections[0].paragraphs[0].runs[0].image = InlineImage(data: data, fileExtension: "png", width: 400, height: 200)
        var page = PageSettings(); page.width = 344; page.height = 500; page.top = 72.125
        try document.applyPageLayout(page, sectionID: document.sections[0].id)
        XCTAssertEqual(document.tables[0].columnWidths, [12, 188])
        XCTAssertEqual(document.paragraphs[0].runs[0].image?.width, 200)
        XCTAssertEqual(document.paragraphs[0].runs[0].image?.height, 100)
        XCTAssertEqual(document.paragraphs[0].runs[0].image?.data, data)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)).sections[0].page, page)
    }
    func testRejectedLayoutLeavesModelUnchanged() throws {
        var document = ScribeDocument()
        document.insertTable(rows: 1, columns: 20, after: document.paragraphs[0].id)
        let original = document
        var page = PageSettings(); page.width = 244
        XCTAssertThrowsError(try document.applyPageLayout(page, sectionID: document.sections[0].id))
        XCTAssertEqual(document, original)
        page.width = .infinity
        XCTAssertThrowsError(try document.applyPageLayout(page, sectionID: document.sections[0].id))
        XCTAssertEqual(document, original)
    }
}
