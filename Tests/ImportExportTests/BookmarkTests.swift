import XCTest
import DocumentCore
@testable import ImportExport

final class BookmarkTests: XCTestCase {
    func testNamedBookmarksAndLinksRoundTripAsOfficeAnchors() throws {
        var document = ScribeDocument()
        let target = Paragraph("Target")
        document.sections[0].paragraphs = [Paragraph("Visit notes"), target]
        let id = try XCTUnwrap(document.addParagraphBookmark(name: "Research_notes", paragraphID: target.id))
        _ = document.addParagraphBookmark(name: "Second_location", paragraphID: target.id)
        document.sections[0].paragraphs[0].runs[0].link = DocumentLink.bookmark(id)
        let bytes = try DOCX.encode(document), parts = try ZipArchive.decode(bytes)
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:anchor=\"Research_notes\""))
        XCTAssertTrue(xml.contains("w:name=\"Second_location\""))
        XCTAssertFalse(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("scribe://"))
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.bookmarks.map(\.name), ["Research_notes", "Second_location"])
        XCTAssertEqual(imported.document.destinationParagraphID(for: imported.document.paragraphs[0].runs[0].link!), imported.document.paragraphs[1].id)
        XCTAssertTrue(imported.warnings.isEmpty)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("Bookmarks.docx"))
        }
    }
    func testMissingTargetOmitsBookmarkAndPrivateRelationshipWithoutLosingText() throws {
        var document = ScribeDocument()
        let id = document.addParagraphBookmark(name: "Gone", paragraphID: document.paragraphs[0].id)!
        var replacement = Paragraph("Still readable"); replacement.runs[0].link = DocumentLink.bookmark(id)
        document.sections[0].paragraphs = [replacement]
        let parts = try ZipArchive.decode(DOCX.encode(document))
        XCTAssertFalse(String(decoding: parts["word/document.xml"]!, as: UTF8.self).contains("bookmarkStart"))
        XCTAssertFalse(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("scribe://"))
        XCTAssertEqual(try DOCX.decode(DOCX.encode(document)).document.plainText, "Still readable")
    }
    func testMidParagraphBookmarkImportWarnsAboutParagraphLocation() throws {
        let xml = "<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body><w:p><w:r><w:t>Before</w:t></w:r><w:bookmarkStart w:id=\"0\" w:name=\"Place\"/><w:bookmarkEnd w:id=\"0\"/></w:p></w:body></w:document>"
        let imported = try DOCX.decode(ZipArchive.encode(["word/document.xml": Data(xml.utf8)]))
        XCTAssertEqual(imported.document.bookmarks.first?.name, "Place")
        XCTAssertEqual(imported.document.bookmarks.first?.anchor.offset, 0)
        XCTAssertTrue(imported.warnings.contains { $0.contains("paragraph start") })
    }
}
