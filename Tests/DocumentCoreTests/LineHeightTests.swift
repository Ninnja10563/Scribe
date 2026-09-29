import Foundation
import XCTest
@testable import DocumentCore

final class LineHeightTests: XCTestCase {
    func testLegacyMigrationDoesNotReinterpretAdditionalSpacing() throws {
        var document = ScribeDocument()
        document.styles[0].paragraph.lineSpacing = 7
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: NativeFormat.encode(document)) as? [String: Any])
        data["formatVersion"] = 14
        let original = try JSONSerialization.data(withJSONObject: data)
        let migrated = try NativeFormat.decode(original)
        XCTAssertEqual(migrated.formatVersion, ScribeDocument.currentVersion)
        XCTAssertEqual(migrated.styles[0].paragraph.lineSpacing, 7)
        XCTAssertNil(migrated.styles[0].paragraph.lineHeight)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: original) as? [String: Any])?["formatVersion"] as? Int, 14)
    }
    func testAllHeightRulesRoundTripInStylesBodyAndNotes() throws {
        for rule in ParagraphLineHeight.Rule.allCases {
            let height = ParagraphLineHeight(rule: rule, value: rule == .multiple ? 1.5 : 24)
            var document = ScribeDocument(), formatting = ParagraphFormatting()
            formatting.lineHeight = height; formatting.lineSpacing = 0
            document.styles[0].paragraph = formatting
            document.sections[0].paragraphs[0].formatting = formatting
            var note = DocumentNote(kind: .footnote, text: "Note"); note.paragraphs[0].formatting = formatting
            document.notes = [note]
            var reference = TextRun("\u{fffc}"); reference.noteID = note.id
            document.sections[0].paragraphs[0].runs = [reference]
            XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        }
    }
    func testInvalidHeightsCannotBeSaved() throws {
        for height in [ParagraphLineHeight(rule: .multiple, value: 0), .init(rule: .multiple, value: 11), .init(rule: .exact, value: .infinity), .init(rule: .minimum, value: -1)] {
            var document = ScribeDocument(); document.styles[0].paragraph.lineHeight = height
            XCTAssertThrowsError(try NativeFormat.encode(document))
        }
    }
    func testReviewReplaysHeightIndependentlyOfLaterIndentation() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("Text")
        let first = document, identity = RevisionIdentity(author: .init(name: "Editor"))
        var formatting = document.styles[0].paragraph
        formatting.lineHeight = .init(rule: .exact, value: 24); formatting.lineSpacing = 0
        document.sections[0].paragraphs[0].formatting = formatting
        try document.recordParagraphFormattingChanges(from: first, identity: identity)
        let second = document
        document.sections[0].paragraphs[0].formatting?.headIndent = 18
        try document.recordParagraphFormattingChanges(from: second, identity: .init(author: identity.author))
        try document.resolveRevision(identity.id, accepting: false)
        XCTAssertNil(document.paragraphs[0].formatting?.lineHeight)
        XCTAssertEqual(document.paragraphs[0].formatting?.headIndent, 18)
        XCTAssertEqual(document.paragraphs[0].formatting?.lineSpacing, 3)
    }
}
