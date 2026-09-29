import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class RevisionImportTests: XCTestCase {
    private func package(body: String) throws -> Data {
        var files = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        files["word/document.xml"] = Data("<w:document xmlns:w=\"\(DOCX.wordNS)\"><w:body>\(body)</w:body></w:document>".utf8)
        return try ZipArchive.encode(files)
    }
    private let metadata = "w:id=\"1\" w:author=\"Editor\" w:date=\"2026-09-29T12:00:00Z\""

    func testDeletedControlCharactersAndNoteReferencesDoNotLeakIntoCurrentText() throws {
        let data = try package(body: """
        <w:p><w:r><w:t>Before</w:t></w:r>
        <w:del \(metadata)><w:r><w:delText>Removed</w:delText><w:tab/><w:br/><w:br w:type="page"/><w:footnoteReference w:id="99"/></w:r></w:del>
        <w:ins \(metadata)><w:r><w:t>New😀</w:t></w:r></w:ins>
        <w:r><w:t>After</w:t></w:r></w:p>
        """)
        let imported = try DOCX.decode(data)
        XCTAssertEqual(imported.document.paragraphs.map(\.text), ["BeforeNew😀After"])
        XCTAssertTrue(imported.document.notes.isEmpty)
        XCTAssertFalse(imported.document.hasPendingRevisions)
        XCTAssertTrue(imported.warnings.contains { $0.contains("without review history") })
    }

    func testHistoricalFormattingCannotOverwriteCurrentProperties() throws {
        let data = try package(body: """
        <w:p><w:pPr><w:jc w:val="center"/><w:pPrChange \(metadata)><w:pPr><w:jc w:val="right"/><w:ind w:left="1440"/></w:pPr></w:pPrChange></w:pPr>
        <w:r><w:rPr><w:b/><w:rPrChange \(metadata)><w:rPr><w:b w:val="0"/><w:i/><w:color w:val="FF0000"/></w:rPr></w:rPrChange></w:rPr><w:t>Current</w:t></w:r></w:p>
        """)
        let imported = try DOCX.decode(data)
        let paragraph = try XCTUnwrap(imported.document.paragraphs.first)
        XCTAssertEqual(paragraph.formatting?.alignment, .center)
        XCTAssertEqual(paragraph.formatting?.headIndent, 0)
        XCTAssertEqual(paragraph.runs[0].format.bold, true)
        XCTAssertNotEqual(paragraph.runs[0].format.italic, true)
        XCTAssertNotEqual(paragraph.runs[0].format.foreground, "#FF0000")
        XCTAssertFalse(imported.warnings.isEmpty)
    }

    func testMovedAndNestedDeletedContentIsNotDuplicated() throws {
        let data = try package(body: """
        <w:p><w:moveFrom \(metadata)><w:r><w:t>Moved</w:t></w:r></w:moveFrom>
        <w:del \(metadata)><w:ins \(metadata)><w:r><w:t>Also deleted</w:t></w:r></w:ins></w:del>
        <w:moveTo \(metadata)><w:r><w:t>Moved</w:t></w:r></w:moveTo>
        <w:r><w:t> retained</w:t></w:r></w:p>
        """)
        let imported = try DOCX.decode(data)
        XCTAssertEqual(imported.document.paragraphs.map(\.text), ["Moved retained"])
        XCTAssertFalse(imported.warnings.isEmpty)
    }
}
