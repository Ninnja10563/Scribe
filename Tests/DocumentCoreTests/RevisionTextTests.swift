import Foundation
import XCTest
@testable import DocumentCore

final class RevisionTextTests: XCTestCase {
    private let alice = RevisionAuthor(name: "Alice")
    private let bob = RevisionAuthor(name: "Bob")
    private func identity(_ author: RevisionAuthor) -> RevisionIdentity { .init(author: author) }
    func testReplacementCanAcceptOrRejectInsertionAndDeletionIndependently() throws {
        var value = RevisionText(runs: [TextRun("Hello world")])
        let insertion = identity(alice), deletion = identity(alice)
        let caret = try value.replace(NSRange(location: 6, length: 5), with: [TextRun("reader")], insertion: insertion, deletion: deletion)
        XCTAssertEqual(value.markupText, "Hello worldreader"); XCTAssertEqual(value.finalText, "Hello reader")
        XCTAssertEqual(caret, 17)
        var rejected = value; rejected.rejectAll(); XCTAssertEqual(rejected.markupText, "Hello world")
        XCTAssertTrue(rejected.pendingIDs.isEmpty)
        value.accept(insertion.id); value.reject(deletion.id)
        XCTAssertEqual(value.finalText, "Hello worldreader"); XCTAssertTrue(value.pendingIDs.isEmpty)
    }
    func testOwnPendingInsertionCanBeEditedWithoutLeavingDeletedDraftText() throws {
        let insertion = identity(alice)
        var value = RevisionText(runs: [TextRun("Start ")])
        try value.replace(NSRange(location: 6, length: 0), with: [TextRun("draft")], insertion: insertion, deletion: identity(alice))
        try value.replace(NSRange(location: 6, length: 5), with: [TextRun("final")], insertion: identity(alice), deletion: identity(alice))
        XCTAssertEqual(value.markupText, "Start final")
        value.rejectAll(); XCTAssertEqual(value.markupText, "Start ")
    }
    func testAnotherAuthorCanReviewAnInsertionWithoutLosingItsOrigin() throws {
        let insertion = identity(alice), deletion = identity(bob)
        var value = RevisionText(runs: [])
        try value.replace(NSRange(location: 0, length: 0), with: [TextRun("draft")], insertion: insertion, deletion: identity(alice))
        try value.replace(NSRange(location: 0, length: 5), with: [], insertion: identity(bob), deletion: deletion)
        XCTAssertEqual(Set(value.pendingIDs), Set([insertion.id, deletion.id]))
        XCTAssertEqual(value.markupText, "draft"); XCTAssertEqual(value.finalText, "")
        value.reject(deletion.id); XCTAssertEqual(value.finalText, "draft")
        value.accept(insertion.id); XCTAssertNil(value.runs[0].review)
    }
    func testRejectingOlderFormatPreservesLaterIndependentOrAcceptedChanges() throws {
        for acceptLater in [false, true] {
            var value = RevisionText(runs: [TextRun("Text")])
            let bold = identity(alice), size = identity(bob)
            try value.format(NSRange(location: 0, length: 4), identity: bold) { var f = $0; f.bold = true; return f }
            try value.format(NSRange(location: 0, length: 4), identity: size) { var f = $0; f.fontSize = 24; return f }
            if acceptLater { value.accept(size.id) }
            value.reject(bold.id)
            XCTAssertNil(value.runs[0].format.bold); XCTAssertEqual(value.runs[0].format.fontSize, 24)
            if !acceptLater { value.reject(size.id); XCTAssertEqual(value.runs[0].format, TextFormatting()) }
            XCTAssertNil(value.runs[0].review)
        }
    }
    func testLaterOverlappingFormatWinsWhenEarlierChangeIsRejected() throws {
        var value = RevisionText(runs: [TextRun("Text")])
        let first = identity(alice), second = identity(bob)
        try value.format(NSRange(location: 0, length: 4), identity: first) { var f = $0; f.foreground = "#FF0000"; return f }
        try value.format(NSRange(location: 0, length: 4), identity: second) { var f = $0; f.foreground = "#0000FF"; return f }
        value.accept(second.id); value.reject(first.id)
        XCTAssertEqual(value.runs[0].format.foreground, "#0000FF"); XCTAssertNil(value.runs[0].review)
    }
    func testPartialFormattingAndUnicodeBoundariesAreNonDestructive() throws {
        var value = RevisionText(runs: [TextRun("A😀B")])
        let original = value
        XCTAssertThrowsError(try value.replace(NSRange(location: 2, length: 1), with: [], insertion: identity(alice), deletion: identity(alice)))
        XCTAssertEqual(value, original)
        let change = identity(alice)
        try value.format(NSRange(location: 1, length: 2), identity: change) { var f = $0; f.italic = true; return f }
        XCTAssertEqual(value.runs.map(\.text), ["A", "😀", "B"])
        XCTAssertEqual(value.runs[1].format.italic, true); XCTAssertNil(value.runs[0].review)
        value.reject(change.id); XCTAssertEqual(value.markupText, original.markupText)
        XCTAssertTrue(value.runs.allSatisfy { $0.format == TextFormatting() && $0.review == nil })
    }
    func testCoalescedTypingKeepsOneReviewIdentityWithoutFragmentingRuns() throws {
        var value = RevisionText(runs: [TextRun("Body ")])
        let insertion = identity(alice), deletion = identity(alice)
        for _ in 0..<200 {
            try value.replace(NSRange(location: (value.markupText as NSString).length, length: 0), with: [TextRun("x")], insertion: insertion, deletion: deletion)
        }
        XCTAssertEqual(value.runs.count, 2); XCTAssertEqual(value.pendingIDs, [insertion.id])
        value.acceptAll(); XCTAssertEqual(value.runs.count, 1)
        XCTAssertEqual(value.markupText, "Body " + String(repeating: "x", count: 200))
    }
    func testNativeReviewRoundTripAndVersion13Migration() throws {
        var value = RevisionText(runs: [TextRun("Original")])
        try value.replace(NSRange(location: 0, length: 8), with: [TextRun("Replacement")], insertion: identity(alice), deletion: identity(alice))
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs = value.runs
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(ScribeDocument())) as? [String: Any])
        json["formatVersion"] = 13
        let earlier = try JSONSerialization.data(withJSONObject: json)
        let migrated = try NativeFormat.decode(earlier)
        XCTAssertEqual(migrated.formatVersion, 14); XCTAssertNil(migrated.paragraphs[0].runs[0].review)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: earlier) as? [String: Any])?["formatVersion"] as? Int, 13)
    }
    func testInvalidRevisionIdentityAndFormattingHistoryAreRejected() throws {
        var value = RevisionText(runs: [TextRun("Text")])
        let change = identity(alice)
        try value.format(NSRange(location: 0, length: 4), identity: change) { var f = $0; f.bold = true; return f }
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs = value.runs
        try NativeFormat.validate(document)
        document.sections[0].paragraphs[0].runs[0].format.bold = false
        XCTAssertThrowsError(try NativeFormat.validate(document))
        document.sections[0].paragraphs[0].runs = value.runs
        document.sections[0].paragraphs[0].runs[0].review?.insertion = change
        XCTAssertThrowsError(try NativeFormat.validate(document), "One identity cannot be both a formatting and insertion revision")
    }
}
