import XCTest
@testable import DocumentCore

final class ParagraphIndentTests: XCTestCase {
    func testChangesOnlyChosenIndentAndRetainsDistinctParagraphGeometry() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs = [Paragraph("One"), Paragraph("Two"), Paragraph("Untouched")]
        var first = ParagraphFormatting(); first.alignment = .right; first.spaceBefore = 18; first.firstLineIndent = 12
        var second = ParagraphFormatting(); second.lineSpacing = 7; second.firstLineIndent = 36
        document.sections[0].paragraphs[0].formatting = first; document.sections[0].paragraphs[1].formatting = second
        let ids = Set(document.paragraphs.prefix(2).map(\.id))
        try document.setParagraphIndent(.left, to: 48, paragraphIDs: ids)
        let paragraphs = document.paragraphs
        XCTAssertEqual(paragraphs[0].formatting?.firstLineIndent, 12)
        XCTAssertEqual(paragraphs[1].formatting?.firstLineIndent, 36)
        XCTAssertEqual(paragraphs[0].formatting?.alignment, .right)
        XCTAssertEqual(paragraphs[0].formatting?.spaceBefore, 18)
        XCTAssertEqual(paragraphs[1].formatting?.lineSpacing, 7)
        XCTAssertEqual(paragraphs[0].formatting?.headIndent, 48)
        XCTAssertEqual(paragraphs[1].formatting?.headIndent, 48)
        XCTAssertNil(paragraphs[2].formatting)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
    }
    func testWholeSelectionValidationIsAtomicAndUnchangedIndentPreservesInheritance() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("One"), Paragraph("Two")]
        let ids = Set(document.paragraphs.map(\.id)), original = document
        try document.setParagraphIndent(.left, to: 0, paragraphIDs: ids)
        XCTAssertEqual(document, original)
        for value in [Double.nan, .infinity, -1, 4001, document.sections[0].page.contentWidth] {
            XCTAssertThrowsError(try document.setParagraphIndent(.right, to: value, paragraphIDs: ids))
            XCTAssertEqual(document, original)
        }
        XCTAssertThrowsError(try document.setParagraphIndent(.left, to: 12, paragraphIDs: ids.union([UUID()])))
        XCTAssertEqual(document, original)
        document.sections[0].paragraphs[1].list = ListDescriptor()
        let withList = document
        XCTAssertThrowsError(try document.setParagraphIndent(.left, to: 12, paragraphIDs: ids))
        XCTAssertEqual(document, withList)
    }
}
