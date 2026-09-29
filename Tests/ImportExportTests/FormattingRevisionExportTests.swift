import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class FormattingRevisionExportTests: XCTestCase {
    func testPreviousAndCurrentRunPropertiesAreSeparate() throws {
        var document = ScribeDocument(), before = TextFormatting()
        before.italic = true; before.fontSize = 14; before.foreground = "#123456"
        let identity = RevisionIdentity(author: .init(name: "Format reviewer"), date: Date(timeIntervalSince1970: 1_700_000_000))
        var text = RevisionText(runs: [TextRun("Formatting history", format: before)])
        try text.format(NSRange(location: 0, length: 18), identity: identity) { value in
            var result = value; result.bold = true; result.fontSize = 18; result.foreground = "#654321"; return result
        }
        document.sections[0].paragraphs[0].runs = text.runs
        let original = document
        XCTAssertThrowsError(try DOCX.encode(document))
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.paragraphs[0].runs[0].format, text.runs[0].format)
        XCTAssertTrue(imported.warnings.contains { $0.contains("without review history") })
        XCTAssertEqual(document, original)
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("FormattingRevisions.docx"), options: .atomic)
        }
    }

    func testRemovingDirectFormattingPreservesThePreviousProperties() throws {
        var document = ScribeDocument(), before = TextFormatting()
        before.bold = true
        var text = RevisionText(runs: [TextRun("Reset", format: before)])
        try text.format(NSRange(location: 0, length: 5), identity: .init(author: .init(name: "Editor"))) { _ in TextFormatting() }
        document.sections[0].paragraphs[0].runs = text.runs
        let parts = try ZipArchive.decode(DOCXWriter(document, revisions: .runChanges).encode())
        let xml = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:rPr><w:rPrChange"))
        XCTAssertTrue(xml.contains("<w:rPr><w:b w:val=\"1\"/></w:rPr></w:rPrChange>"))
        XCTAssertNil(try DOCX.decode(ZipArchive.encode(parts)).document.paragraphs[0].runs[0].format.bold)
    }
}
