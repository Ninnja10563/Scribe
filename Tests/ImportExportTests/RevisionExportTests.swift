import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class RevisionExportTests: XCTestCase {
    private let identity = RevisionIdentity(author: .init(name: "A & B <Review>"), date: Date(timeIntervalSince1970: 1_700_000_000))

    private func changed(_ text: String, deleting: Bool = false) -> TextRun {
        var run = TextRun(text), review = RunReview()
        if deleting { review.deletion = .init(author: identity.author, date: identity.date) } else { review.insertion = identity }
        run.review = review
        return run
    }

    func testRealTextRevisionPackageAndPublicGate() throws {
        var document = ScribeDocument()
        var inserted = changed(" New 👩🏽‍💻 & <text>")
        inserted.format.bold = true
        inserted.link = "https://example.com/review?a=1&b=2"
        document.sections[0].paragraphs[0].runs = [TextRun("Before"), inserted, changed("Old\tline\u{2028}page\u{c}end", deleting: true), TextRun("After")]
        let original = document
        XCTAssertThrowsError(try DOCX.encode(document))
        XCTAssertThrowsError(try DOCXWriter(document).encode())
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let parts = try ZipArchive.decode(bytes)
        let xml = try XCTUnwrap(parts["word/document.xml"]).string
        XCTAssertTrue(xml.contains("<w:ins w:id=\"0\""))
        XCTAssertTrue(xml.contains("<w:del w:id=\"1\""))
        XCTAssertTrue(xml.contains("w:author=\"A &amp; B &lt;Review&gt;\""))
        XCTAssertTrue(xml.contains("w:date=\"2023-11-14T22:13:20Z\""))
        XCTAssertTrue(xml.contains("<w:delText xml:space=\"preserve\">Old</w:delText><w:tab/>"))
        XCTAssertTrue(xml.contains("<w:br w:type=\"page\"/><w:delText"))
        XCTAssertTrue(xml.contains("<w:hyperlink r:id="))
        XCTAssertEqual(document, original)
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.paragraphs[0].text, "Before New 👩🏽‍💻 & <text>After")
        XCTAssertTrue(imported.warnings.contains { $0.contains("without review history") })
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("TextRevisions.docx"), options: .atomic)
        }
    }

    func testTextRevisionsInBothNoteParts() throws {
        var document = ScribeDocument()
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            var note = DocumentNote(kind: kind, text: "")
            note.paragraphs[0].runs = [TextRun(kind.rawValue), changed(" new"), changed(" old", deleting: true)]
            document.notes.append(note)
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            document.sections[0].paragraphs[0].runs.append(reference)
        }
        XCTAssertThrowsError(try DOCX.encode(document))
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let parts = try ZipArchive.decode(bytes)
        let imported = try DOCX.decode(bytes)
        XCTAssertEqual(imported.document.notes.map(\.plainText), ["footnote new", "endnote new"])
        XCTAssertTrue(imported.warnings.contains { $0.contains("without review history") })
        for name in ["footnotes", "endnotes"] {
            let xml = try XCTUnwrap(parts["word/\(name).xml"]).string
            XCTAssertTrue(xml.contains("<w:ins")); XCTAssertTrue(xml.contains("<w:del"))
            XCTAssertTrue(xml.contains("<w:delText xml:space=\"preserve\"> old"))
        }
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("NoteTextRevisions.docx"), options: .atomic)
        }
    }

    func testCommentBoundariesSplitAnnotationsWithoutDuplicatingTheirIDs() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs[0].runs = [changed("A😀BC")]
        document.comments = [Comment(anchor: .init(paragraphID: document.paragraphs[0].id, offset: 1, length: 2), text: "Emoji", author: "Editor")]
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let xml = try XCTUnwrap(ZipArchive.decode(bytes)["word/document.xml"]).string
        for id in 0..<3 { XCTAssertTrue(xml.contains("<w:ins w:id=\"\(id)\"")) }
        XCTAssertTrue(xml.contains("</w:ins><w:commentRangeStart"))
        XCTAssertTrue(xml.contains("😀"))
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent("CommentTextRevisions.docx"), options: .atomic)
        }
    }

    func testLayeredFormattingAndObjectPropertiesRemainGuarded() throws {
        var document = ScribeDocument()
        var text = RevisionText(runs: [TextRun("Bold")])
        try text.format(NSRange(location: 0, length: 4), identity: identity) { original in
            var result = original; result.bold = true; return result
        }
        try text.format(NSRange(location: 0, length: 4), identity: .init(author: identity.author)) { original in
            var result = original; result.italic = true; return result
        }
        document.sections[0].paragraphs[0].runs = text.runs
        try NativeFormat.validate(document)
        XCTAssertThrowsError(try DOCXWriter(document, revisions: .runChanges).encode())
        var equation = changed("\u{fffc}")
        equation.equation = try Equation(source: "x+1")
        var objectText = RevisionText(runs: [equation])
        try objectText.format(NSRange(location: 0, length: 1), identity: .init(author: identity.author)) { original in
            var result = original; result.bold = true; return result
        }
        equation = objectText.runs[0]
        document.sections[0].paragraphs = [Paragraph("")]
        document.sections[0].paragraphs[0].runs = [equation]
        try NativeFormat.validate(document)
        XCTAssertThrowsError(try DOCXWriter(document, revisions: .runChanges).encode())
    }

    func testInvalidXMLAuthorAndOutOfRangeDateFailBeforeWritingPackage() throws {
        for identity in [RevisionIdentity(author: .init(name: "Bad\u{1}author")),
                         RevisionIdentity(author: .init(name: "Author"), date: Date(timeIntervalSince1970: 1e15))] {
            var document = ScribeDocument(), run = TextRun("Text"), review = RunReview()
            review.insertion = identity; run.review = review
            document.sections[0].paragraphs[0].runs = [run]
            XCTAssertThrowsError(try DOCXWriter(document, revisions: .runChanges).encode())
        }
    }

    func testAnotherAuthorsDeletionKeepsTheOriginalInsertion() throws {
        var document = ScribeDocument(), run = changed("temporary")
        run.review?.deletion = .init(author: .init(name: "Second reviewer"), date: identity.date)
        document.sections[0].paragraphs[0].runs = [TextRun("Before"), run, TextRun("After")]
        let bytes = try DOCXWriter(document, revisions: .runChanges).encode()
        let parts = try ZipArchive.decode(bytes)
        let xml = try XCTUnwrap(parts["word/document.xml"]).string
        XCTAssertTrue(xml.contains("<w:ins")); XCTAssertTrue(xml.contains("<w:del"))
        XCTAssertTrue(xml.contains("</w:del></w:ins>"))
        XCTAssertTrue(xml.contains("<w:delText xml:space=\"preserve\">temporary"))
        XCTAssertEqual(try DOCX.decode(bytes).document.paragraphs[0].text, "BeforeAfter")
        var rejectDeletion = document
        try rejectDeletion.resolveRevision(run.review!.deletion!.id, accepting: false)
        XCTAssertEqual(rejectDeletion.paragraphs[0].text, "BeforetemporaryAfter")
        XCTAssertTrue(rejectDeletion.hasPendingRevisions)
        var rejectInsertion = document
        try rejectInsertion.resolveRevision(identity.id, accepting: false)
        XCTAssertEqual(rejectInsertion.paragraphs[0].text, "BeforeAfter")
        if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent("OverlappingTextRevisions.docx"), options: .atomic)
        }
    }

    func testUnsupportedReviewCannotSilentlyFlatten() throws {
        var document = ScribeDocument()
        document.sections[0].paragraphs[0].runs = [TextRun("Heading")]
        let before = document
        document.sections[0].paragraphs[0].styleID = "heading1"
        try document.recordParagraphFormattingChanges(from: before, identity: identity)
        try NativeFormat.validate(document)
        XCTAssertThrowsError(try DOCXWriter(document, revisions: .runChanges).encode())
    }
}

private extension Data {
    var string: String { String(decoding: self, as: UTF8.self) }
}
