import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class RevisionRoundTripTests: XCTestCase {
    private let author = RevisionAuthor(name: "Reviewer")
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func changed(_ value: String, deleting: Bool = false) -> TextRun {
        var run = TextRun(value), review = RunReview()
        let identity = RevisionIdentity(author: author, date: date)
        if deleting { review.deletion = identity } else { review.insertion = identity }
        run.review = review; return run
    }
    private func roundTrip(_ document: ScribeDocument) throws -> ScribeDocument {
        let result = try DOCX.decodePreservingRevisions(DOCXWriter(document, revisions: .runChanges).encode())
        XCTAssertFalse(result.warnings.contains { $0.contains("without review history") })
        try NativeFormat.validate(result.document)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(result.document)), result.document)
        return result.document
    }
    private func assertDecisions(_ source: ScribeDocument, _ imported: ScribeDocument) throws {
        for accepting in [true, false] {
            var before = source, after = imported
            try before.resolveAllRevisions(accepting: accepting)
            try after.resolveAllRevisions(accepting: accepting)
            XCTAssertEqual(after.plainText, before.plainText)
            XCTAssertEqual(after.notes.map(\.plainText), before.notes.map(\.plainText))
            XCTAssertFalse(after.hasPendingRevisions)
        }
    }
    func testRunDecisionsAndSharedNoteAuthorsSurviveRoundTrip() throws {
        var document = ScribeDocument()
        var inserted = changed(" New😀")
        inserted.link = "https://example.com/review"
        document.sections[0].paragraphs[0].runs = [TextRun("Before"), inserted, changed(" old\tline\u{2028}page\u{c}end", deleting: true), TextRun("After")]
        for kind in DocumentNote.Kind.allCases {
            var note = DocumentNote(kind: kind)
            note.paragraphs[0].runs = [changed("New note"), changed("Old note", deleting: true)]
            document.notes.append(note)
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            document.sections[0].paragraphs[0].runs.append(reference)
        }
        let imported = try roundTrip(document)
        XCTAssertEqual(imported.pendingRevisionIDs.count, 6)
        let identities = (imported.paragraphs + imported.notes.flatMap(\.paragraphs)).flatMap(\.runs).flatMap { [$0.review?.insertion, $0.review?.deletion].compactMap { $0 } }
        XCTAssertEqual(Set(identities.map { $0.author.id }).count, 1)
        XCTAssertTrue(identities.allSatisfy { $0.author.name == author.name && $0.date == date })
        XCTAssertTrue(imported.paragraphs[0].runs.contains { $0.link == inserted.link && $0.review?.insertion != nil })
        try assertDecisions(document, imported)
    }
    func testFormattingCanBeAcceptedOrRejectedAfterImport() throws {
        var document = ScribeDocument(), original = TextFormatting()
        original.italic = true; original.fontSize = 14
        var text = RevisionText(runs: [TextRun("History", format: original)])
        try text.format(NSRange(location: 0, length: 7), identity: .init(author: author, date: date)) { value in
            var value = value; value.bold = true; value.fontSize = 18; return value
        }
        document.sections[0].paragraphs[0].runs = text.runs
        let imported = try roundTrip(document)
        XCTAssertEqual(imported.pendingRevisionIDs.count, 1)
        for accepting in [true, false] {
            var copy = imported; try copy.resolveAllRevisions(accepting: accepting)
            XCTAssertEqual(copy.paragraphs[0].runs[0].format, accepting ? text.runs[0].format : original)
        }
    }
    func testNestedDeletionKeepsIndependentDecisions() throws {
        var document = ScribeDocument(), run = changed("Draft")
        run.review?.deletion = .init(author: .init(name: "Second author"), date: date)
        document.sections[0].paragraphs[0].runs = [run]
        var imported = try roundTrip(document)
        try assertDecisions(document, imported)
        let deletion = try XCTUnwrap(imported.paragraphs[0].runs[0].review?.deletion)
        try imported.resolveRevision(deletion.id, accepting: false)
        XCTAssertEqual(imported.paragraphs[0].text, "Draft")
        XCTAssertEqual(imported.paragraphs[0].runs[0].review?.insertion?.author.name, "Reviewer")
        XCTAssertNil(imported.paragraphs[0].runs[0].review?.deletion)
    }
    func testUnreviewedEquationAfterReviewedTextRemainsImportable() throws {
        var document = ScribeDocument(), equation = TextRun("\u{fffc}")
        equation.equation = try Equation(source: "x+1")
        document.sections[0].paragraphs[0].runs = [changed("New"), equation]
        let imported = try roundTrip(document)
        XCTAssertEqual(imported.paragraphs[0].runs.compactMap(\.equation).count, 1)
    }

    private func package(_ body: String) throws -> Data {
        var parts = try ZipArchive.decode(DOCX.encode(ScribeDocument()))
        parts["word/document.xml"] = Data("<doc:document xmlns:doc=\"\(DOCX.wordNS)\"><doc:body>\(body)</doc:body></doc:document>".utf8)
        return try ZipArchive.encode(parts)
    }
    func testIndependentNamespaceAliasedRevisionUsesSourceAuthorAndFractionalDate() throws {
        let data = try package("""
        <doc:p><doc:ins doc:id="18" doc:author="Independent author" doc:date="2023-11-15T08:13:20.125+10:00"><doc:r><doc:t>Inserted</doc:t></doc:r></doc:ins></doc:p>
        """)
        let imported = try DOCX.decodePreservingRevisions(data).document
        let identity = try XCTUnwrap(imported.paragraphs[0].runs[0].review?.insertion)
        XCTAssertEqual(identity.author.name, "Independent author")
        XCTAssertEqual(identity.date.timeIntervalSince1970, 1_700_000_000.125, accuracy: 0.001)
    }
    func testUnsupportedOrIncompleteRevisionsFailInsteadOfLosingHistory() throws {
        for body in [
            "<doc:p><doc:ins doc:id=\"1\" doc:author=\"Missing date\"><doc:r><doc:t>Text</doc:t></doc:r></doc:ins></doc:p>",
            "<doc:p><doc:pPr><doc:pPrChange doc:id=\"1\" doc:author=\"Editor\" doc:date=\"2023-11-14T22:13:20Z\"><doc:pPr/></doc:pPrChange></doc:pPr></doc:p>",
            "<doc:p><doc:pPr><doc:rPr><doc:del doc:id=\"1\" doc:author=\"Editor\" doc:date=\"2023-11-14T22:13:20Z\"/></doc:rPr></doc:pPr></doc:p>",
        ] {
            XCTAssertThrowsError(try DOCX.decodePreservingRevisions(package(body)))
        }
    }
}
