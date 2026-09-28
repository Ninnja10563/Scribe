#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class CommentTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testOverlappingMultiParagraphCommentsSurviveProjection() throws {
        var document = ScribeDocument()
        var first = Paragraph("First 👩🏽‍💻"); first.list = .init(kind: .decimal)
        document.sections[0].paragraphs = [first, Paragraph("Second paragraph")]
        let index = DocumentTextIndex(paragraphs: document.paragraphs)
        document.comments = [
            Comment(anchor: index.anchor(for: NSRange(location: 6, length: index.length - 6))!, text: "Across paragraphs", author: "Alex"),
            Comment(anchor: .init(paragraphID: first.id, offset: 0, length: (first.text as NSString).length), text: "First item", author: "Sam")
        ]
        let storage = AttributedDocument.render(document)
        XCTAssertEqual(AttributedDocument.capture(storage, preserving: document).comments, document.comments)
        let range = try XCTUnwrap(CommentProjection.range(for: document.comments[0].anchor, in: storage, document: document))
        XCTAssertTrue((storage.string as NSString).substring(with: range).contains("👩🏽‍💻\nSecond"))
        XCTAssertEqual(CommentProjection.anchor(for: range, in: storage, document: document), document.comments[0].anchor)
    }
    func testCommentFollowsTypingAndReattachesAfterNativeUndo() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs[0] = Paragraph("Before selected after")
        let id = document.model.paragraphs[0].id
        document.model.comments = [Comment(anchor: .init(paragraphID: id, offset: 7, length: 8), text: "Keep this comment", author: "Alex")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 0, length: 0))
        editor.activeTextView.insertText("New ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.snapshot().comments[0].anchor.offset, 11)
        document.undoManager?.removeAllActions()
        editor.select(NSRange(location: 11, length: 8))
        editor.activeTextView.insertText("", replacementRange: NSRange(location: 11, length: 8))
        XCTAssertEqual(document.snapshot().comments[0].isDetached, true)
        XCTAssertEqual(document.model.comments[0].text, "Keep this comment")
        document.undoManager?.undo()
        let restored = document.snapshot()
        XCTAssertNotEqual(restored.comments[0].isDetached, true)
        XCTAssertEqual(restored.comments[0].anchor.offset, 11)
        XCTAssertEqual(restored.comments[0].anchor.length, 8)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(restored)).comments, restored.comments)
    }
    func testSemanticListSplitPreservesCommentAssociation() throws {
        let document = ScribeFileDocument(); var paragraph = Paragraph("FirstSecond"); paragraph.list = .init(kind: .decimal)
        document.model.sections[0].paragraphs = [paragraph]
        document.model.comments = [Comment(anchor: .init(paragraphID: paragraph.id, offset: 0, length: 11), text: "Both parts", author: "Alex")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 9, length: 0)); editor.activeTextView.insertNewline(nil)
        let snapshot = document.snapshot()
        XCTAssertNotEqual(snapshot.comments[0].isDetached, true)
        XCTAssertEqual(snapshot.comments[0].anchor.endParagraphID, snapshot.paragraphs[1].id)
        XCTAssertEqual(snapshot.comments[0].anchor.length, 12)
    }
}
#endif
