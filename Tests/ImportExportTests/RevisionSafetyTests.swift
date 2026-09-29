import Foundation
import XCTest
import DocumentCore
import ImportExport

final class RevisionSafetyTests: XCTestCase {
    func testPendingRevisionsCannotBeSilentlyFlattenedIntoDOCX() throws {
        let author = RevisionAuthor(name: "Reviewer")
        var text = RevisionText(runs: [TextRun("Original")])
        try text.replace(NSRange(location: 0, length: 8), with: [TextRun("Replacement")], insertion: .init(author: author), deletion: .init(author: author))
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs = text.runs
        XCTAssertThrowsError(try DOCX.encode(document))
        text.acceptAll(); document.sections[0].paragraphs[0].runs = text.runs
        XCTAssertEqual(try DOCX.decode(DOCX.encode(document)).document.paragraphs[0].text, "Replacement")
    }
}
