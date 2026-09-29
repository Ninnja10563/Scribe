import Foundation
import XCTest
import DocumentCore
@testable import ImportExport

final class ParagraphRevisionInterchangeTests: XCTestCase {
    private let author = RevisionAuthor(name: "Paragraph reviewer")
    private func paragraphs(deleting: Bool) -> [Paragraph] {
        var first = Paragraph("First"), review = RunReview()
        let identity = RevisionIdentity(author: author, date: Date(timeIntervalSince1970: 1_700_000_000))
        if deleting { review.deletion = identity } else { review.insertion = identity }
        first.breakReview = review
        return [first, Paragraph("Second")]
    }
    func testParagraphMarksUseOfficePropertiesAndKeepDecisions() throws {
        for deleting in [false, true] {
            var source = ScribeDocument(); source.sections[0].paragraphs = paragraphs(deleting: deleting)
            let bytes = try DOCXWriter(source, revisions: .runChanges).encode()
            let imported = try DOCX.decodePreservingRevisions(bytes).document
            XCTAssertEqual(imported.paragraphs.map(\.text), ["First", "Second"])
            let review = try XCTUnwrap(imported.paragraphs[0].breakReview)
            XCTAssertEqual((deleting ? review.deletion : review.insertion)?.author.name, author.name)
            XCTAssertTrue(imported.paragraphs.flatMap(\.runs).allSatisfy { $0.review == nil })
            for accepting in [false, true] {
                var copy = imported; try copy.resolveAllRevisions(accepting: accepting)
                XCTAssertEqual(copy.paragraphs.map(\.text), accepting == deleting ? ["FirstSecond"] : ["First", "Second"])
                XCTAssertFalse(copy.hasPendingRevisions)
            }
            if let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
                let name = deleting ? "ParagraphDeletionRevisions" : "ParagraphInsertionRevisions"
                try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".docx"), options: .atomic)
            }
        }
    }
    func testBothNoteKindsRetainParagraphBoundaryReview() throws {
        for kind in DocumentNote.Kind.allCases {
            var source = ScribeDocument(), note = DocumentNote(kind: kind)
            note.paragraphs = paragraphs(deleting: true); source.notes = [note]
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            source.sections[0].paragraphs[0].runs = [reference]
            let bytes = try DOCXWriter(source, revisions: .runChanges).encode()
            var imported = try DOCX.decodePreservingRevisions(bytes).document
            XCTAssertNotNil(imported.notes[0].paragraphs[0].breakReview?.deletion)
            try imported.resolveAllRevisions(accepting: true)
            XCTAssertEqual(imported.notes[0].paragraphs.map(\.text), ["FirstSecond"])
        }
    }
    func testOverlappingParagraphMarkDecisionsRetainBothAuthors() throws {
        var source = ScribeDocument(); source.sections[0].paragraphs = paragraphs(deleting: false)
        source.sections[0].paragraphs[0].breakReview?.deletion = .init(author: .init(name: "Second reviewer"))
        let bytes = try DOCXWriter(source, revisions: .runChanges).encode()
        var imported = try DOCX.decodePreservingRevisions(bytes).document
        let review = try XCTUnwrap(imported.paragraphs[0].breakReview)
        XCTAssertEqual(review.insertion?.author.name, author.name)
        XCTAssertEqual(review.deletion?.author.name, "Second reviewer")
        try imported.resolveRevision(try XCTUnwrap(review.deletion?.id), accepting: false)
        XCTAssertEqual(imported.paragraphs.count, 2)
        XCTAssertNotNil(imported.paragraphs[0].breakReview?.insertion)
        try imported.resolveRevision(try XCTUnwrap(review.insertion?.id), accepting: false)
        XCTAssertEqual(imported.paragraphs.map(\.text), ["FirstSecond"])
    }
}
