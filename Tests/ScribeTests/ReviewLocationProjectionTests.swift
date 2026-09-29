#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ReviewLocationProjectionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testListTextAndSeparatorExcludeGeneratedPrefixes() throws {
        var document = ScribeDocument(), paragraph = Paragraph("A🙂B")
        paragraph.list = .init(kind: .decimal, start: 12); paragraph.pageBreakBefore = true
        var review = RunReview(); review.insertion = RevisionIdentity(author: .init(name: "Writer"))
        paragraph.runs[0].review = review; paragraph.breakReview = review
        var next = Paragraph("next"); next.list = .init(kind: .decimal)
        document.sections[0].paragraphs = [paragraph, next]
        let storage = AttributedDocument.render(document)
        let locations = RevisionIndex(document: document).changes[0].locations
        XCTAssertEqual(locations.count, 2)
        guard case .body(let text) = ReviewLocationProjection.match(for: locations[0], in: storage, document: document),
              case .body(let separator) = ReviewLocationProjection.match(for: locations[1], in: storage, document: document) else {
            return XCTFail("Missing native review extent")
        }
        XCTAssertEqual((storage.string as NSString).substring(with: text), "A🙂B")
        XCTAssertGreaterThan(text.location, 0)
        XCTAssertEqual((storage.string as NSString).substring(with: separator), "\n")
        XCTAssertEqual(separator.length, 1)
        let changed = NSMutableAttributedString(attributedString: storage)
        changed.replaceCharacters(in: text, with: "stale")
        XCTAssertNil(ReviewLocationProjection.match(for: locations[0], in: changed, document: document))
    }

    func testNoteLocationsUseNoteParagraphOffsetsAndReference() throws {
        var document = ScribeDocument(), note = DocumentNote(kind: .endnote, text: "first")
        var paragraph = Paragraph("🙂 second")
        var review = RunReview(); review.deletion = RevisionIdentity(author: .init(name: "Reviewer"))
        paragraph.runs[0].review = review; note.paragraphs.append(paragraph)
        document.notes = [note]
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        document.sections[0].paragraphs[0].runs = [TextRun("body"), reference]
        let storage = AttributedDocument.render(document)
        let location = try XCTUnwrap(RevisionIndex(document: document).changes.first?.locations.first)
        guard case .note(let id, let range, let nativeReference) = ReviewLocationProjection.match(for: location, in: storage, document: document) else {
            return XCTFail("Missing note review extent")
        }
        XCTAssertEqual(id, note.id)
        XCTAssertEqual(range, NSRange(location: 6, length: 9))
        XCTAssertEqual(nativeReference, NSRange(location: 4, length: 1))
        XCTAssertNil(ReviewLocationProjection.match(for: location, in: NSAttributedString(string: "body"), document: document))
    }
}
#endif
