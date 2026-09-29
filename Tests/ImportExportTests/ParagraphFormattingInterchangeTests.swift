import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class ParagraphFormattingInterchangeTests: XCTestCase {
    func testSpacingIndentStyleAndPageBreakHistoryRoundTrip() throws {
        var source = ScribeDocument(), before = ParagraphFormatting()
        before.lineHeight = .init(rule: .multiple, value: 1.5); before.lineSpacing = 0
        before.headIndent = 18; before.firstLineIndent = 18
        source.sections[0].paragraphs = [Paragraph("First line\u{2028}Second line\u{2028}Third line")]
        source.sections[0].paragraphs[0].formatting = before
        let original = source
        var after = before; after.lineHeight = .init(rule: .exact, value: 28)
        after.headIndent = 36; after.firstLineIndent = 48; after.alignment = .right
        source.sections[0].paragraphs[0].formatting = after
        source.sections[0].paragraphs[0].styleID = "heading2"
        source.sections[0].paragraphs[0].pageBreakBefore = true
        try source.recordParagraphFormattingChanges(from: original, identity: .init(author: .init(name: "Paragraph editor"), date: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertThrowsError(try DOCX.encode(source))
        let bytes = try DOCXWriter(source, revisions: .runChanges).encode()
        let imported = try DOCX.decodePreservingRevisions(bytes).document
        let history = try XCTUnwrap(imported.paragraphs[0].formattingReview)
        XCTAssertEqual(history.changes.count, 1)
        XCTAssertEqual(history.changes[0].identity.author.name, "Paragraph editor")
        XCTAssertEqual(history.base.formatting, before)
        XCTAssertEqual(imported.paragraphs[0].formatting, after)
        var rejected = imported; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs[0].formatting, before)
        XCTAssertEqual(rejected.paragraphs[0].styleID, "normal")
        XCTAssertFalse(rejected.paragraphs[0].pageBreakBefore)
        var accepted = imported; try accepted.resolveAllRevisions(accepting: true)
        XCTAssertEqual(accepted.paragraphs[0].formatting, after)
        XCTAssertEqual(accepted.paragraphs[0].styleID, "heading2")
        XCTAssertTrue(accepted.paragraphs[0].pageBreakBefore)
        let flattened = try DOCX.decode(bytes)
        XCTAssertEqual(flattened.document.paragraphs[0].formatting, after)
        XCTAssertFalse(flattened.document.hasPendingRevisions)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("ParagraphFormattingRevisions.docx"), options: .atomic)
        }
    }
    func testIndependentSnapshotAndUnsupportedProperties() throws {
        func package(current: String, previous: String) throws -> Data {
            var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
            parts["word/document.xml"] = Data("""
            <w:document xmlns:w="\(DOCX.wordNS)"><w:body><w:p><w:pPr>\(current)<w:pPrChange w:id="19" w:author="Independent" w:date="2023-11-14T22:13:20Z"><w:pPr>\(previous)</w:pPr></w:pPrChange></w:pPr><w:r><w:t>Unchanged text</w:t></w:r></w:p></w:body></w:document>
            """.utf8)
            return try ZipArchive.encode(parts)
        }
        var imported = try DOCX.decodePreservingRevisions(package(current: "<w:jc w:val=\"center\"/>", previous: "")).document
        XCTAssertEqual(imported.paragraphs[0].formatting?.alignment, .center)
        try imported.resolveAllRevisions(accepting: false)
        XCTAssertNil(imported.paragraphs[0].formatting)
        XCTAssertEqual(imported.paragraphs[0].text, "Unchanged text")
        for (current, previous) in [("<w:rPr><w:b/></w:rPr>", "<w:jc w:val=\"right\"/>"), ("<w:jc w:val=\"distribute\"/>", "<w:jc w:val=\"right\"/>"), ("<w:tabs/>", "<w:jc w:val=\"right\"/>"), ("<w:jc w:val=\"center\"/>", "<w:spacing w:beforeLines=\"200\"/>"), ("<w:jc w:val=\"center\"/>", "<w:keepNext/>")] {
            XCTAssertThrowsError(try DOCX.decodePreservingRevisions(package(current: current, previous: previous)))
        }
    }
    func testStyleDefinitionHistoryNeverOverwritesCurrentProperties() throws {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        parts["word/styles.xml"] = Data("""
        <w:styles xmlns:w="\(DOCX.wordNS)"><w:style w:type="paragraph" w:styleId="normal"><w:pPr><w:jc w:val="center"/><w:pPrChange w:id="1" w:author="Editor" w:date="2023-11-14T22:13:20Z"><w:pPr><w:jc w:val="right"/></w:pPr></w:pPrChange></w:pPr></w:style></w:styles>
        """.utf8)
        let bytes = try ZipArchive.encode(parts), imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.styles.first { $0.id == "normal" }?.paragraph.alignment, .center)
        XCTAssertTrue(imported.warnings.contains { $0.contains("Style-definition revisions") })
        XCTAssertThrowsError(try DOCX.decodePreservingRevisions(bytes))
    }
    func testInheritedPreviousStyleRestoresItsLiveDefinition() throws {
        var source = ScribeDocument()
        source.sections[0].paragraphs = [Paragraph("Style history", style: "heading1")]
        let before = source
        source.sections[0].paragraphs[0].styleID = "normal"
        try source.recordParagraphFormattingChanges(from: before, identity: .init(author: .init(name: "Editor")))
        var imported = try DOCX.decodePreservingRevisions(DOCXWriter(source, revisions: .runChanges).encode()).document
        try imported.resolveAllRevisions(accepting: false)
        XCTAssertEqual(imported.paragraphs[0].styleID, "heading1")
        XCTAssertNil(imported.paragraphs[0].formatting)
    }
}
