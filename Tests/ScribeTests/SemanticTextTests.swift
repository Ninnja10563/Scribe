#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class SemanticTextTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testGeneratedMarkersAreExcludedAndUnicodeMatchesMapToNativeRanges() {
        var document = ScribeDocument()
        var first = Paragraph("First café 👩🏽‍💻"), second = Paragraph("Second 東京")
        first.list = .init(kind: .upperRoman, start: 4); first.pageBreakBefore = true
        second.list = .init(kind: .upperRoman)
        document.sections[0].paragraphs = [first, second, Paragraph("\tIV.\tLiteral text")]
        let rendered = AttributedDocument.render(document), snapshot = SemanticTextSnapshot(rendered)
        XCTAssertEqual(snapshot.text, "First café 👩🏽‍💻\nSecond 東京\n\tIV.\tLiteral text")
        XCTAssertEqual(DocumentStatistics(text: snapshot.text).words, 7)
        XCTAssertEqual(snapshot.matches(query: "IV.").count, 1) // The literal paragraph remains searchable.
        let source = rendered.string as NSString
        for query in ["café", "👩🏽‍💻", "東京", "Literal"] {
            XCTAssertEqual(snapshot.matches(query: query), [source.range(of: query)])
        }
        let crossParagraph = snapshot.matches(query: "👩🏽‍💻\nSecond").first!
        XCTAssertEqual(snapshot.text(inSourceRange: crossParagraph), "👩🏽‍💻\nSecond")
        let marker = source.range(of: "IV.")
        XCTAssertEqual(snapshot.text(inSourceRange: marker), "")
        XCTAssertEqual(snapshot.text(inSourceRange: NSRange(location: 0, length: rendered.length)), snapshot.text)
    }

    func testFindReplaceDoesNotModifyListNumbersAndCacheFollowsUndo() {
        let document = ScribeFileDocument()
        var paragraph = Paragraph("IV. is literal; café is text")
        paragraph.list = .init(kind: .upperRoman, start: 4)
        document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        let search = controller.searchBar
        search.query.stringValue = "IV."; search.replacement.stringValue = "Four"
        XCTAssertEqual(editor.semanticText.matches(query: "IV.").count, 1)
        document.undoManager?.removeAllActions()
        search.replaceAll()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Four is literal; café is text")
        XCTAssertTrue(editor.storage.string.hasPrefix("\tIV.\tFour"))
        XCTAssertEqual(editor.semanticText.matches(query: "IV.").count, 0)
        document.undoManager?.undo()
        XCTAssertEqual(editor.semanticText.matches(query: "IV.").count, 1)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, paragraph.text)
    }
}
#endif
