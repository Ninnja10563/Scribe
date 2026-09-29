#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteReviewSessionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testDraftTracksEditsAndRejectsToOriginalForBothNoteKinds() throws {
        for kind in [DocumentNote.Kind.footnote, .endnote] {
            let original = DocumentNote(kind: kind, text: "Original citation")
            let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
            defer { session.close() }
            session.editor.select(NSRange(location: 8, length: 0))
            session.editor.activeTextView.insertText("new ", replacementRange: NSRange(location: NSNotFound, length: 0))
            let edited = try session.note()
            XCTAssertEqual(edited.plainText, "Originalnew  citation")
            XCTAssertTrue(edited.paragraphs[0].runs.contains { $0.review?.insertion != nil })
            var snapshot = session.document.snapshot()
            try snapshot.resolveAllRevisions(accepting: false)
            XCTAssertEqual(snapshot.paragraphs, original.paragraphs)
            session.document.undoManager?.undo()
            XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
            session.document.undoManager?.redo()
            XCTAssertEqual(try session.note(), edited)
        }
    }
    func testTrackingOffRetainsExistingNoteRevisionAndLeavesNewTypingUntracked() throws {
        var original = DocumentNote(kind: .footnote, text: "Draft")
        var review = RunReview(); review.insertion = RevisionIdentity(author: .init(name: "Earlier writer"))
        original.paragraphs[0].runs[0].review = review
        let options = NoteOptions(note: original, styles: ParagraphStyle.defaults, author: nil)
        defer { options.close() }
        XCTAssertNotNil(options.text.editor, "Pending reviews must retain their native drawing and editing engine")
        options.text.setSelectedRange(NSRange(location: 5, length: 0))
        options.text.insertText(" kept", replacementRange: NSRange(location: NSNotFound, length: 0))
        let changed = try options.note()
        XCTAssertEqual(changed.plainText, "Draft kept")
        XCTAssertEqual(changed.paragraphs[0].runs.first?.review, review)
        XCTAssertNil(changed.paragraphs[0].runs.last?.review)
        var isolated = ScribeDocument(); isolated.sections[0].paragraphs = changed.paragraphs
        try isolated.resolveAllRevisions(accepting: false)
        XCTAssertEqual(isolated.paragraphs[0].text, " kept")
        options.text.undoManager?.undo()
        XCTAssertEqual(try options.note(), original)
    }
    func testUntrackedFormattingSurvivesRejectingEarlierTrackedFormatting() throws {
        let original = DocumentNote(kind: .footnote, text: "Citation")
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        defer { session.close() }
        session.editor.select(NSRange(location: 0, length: 8))
        session.editor.activeTextView.toggleBold(nil)
        let tracked = try session.note()
        session.editor.reviewEditing.author = nil
        session.document.undoManager?.removeAllActions()
        session.editor.activeTextView.toggleItalic(nil)
        let changed = try session.note()
        let history = try XCTUnwrap(changed.paragraphs[0].runs[0].review)
        XCTAssertEqual(history.formatting.count, 2)
        XCTAssertFalse(history.formatting[0].accepted)
        XCTAssertTrue(history.formatting[1].accepted)
        session.document.undoManager?.undo()
        XCTAssertEqual(try session.note(), tracked)
        session.document.undoManager?.redo()
        XCTAssertEqual(try session.note(), changed)
        var rejected = session.document.snapshot()
        try rejected.resolveAllRevisions(accepting: false)
        XCTAssertNil(rejected.paragraphs[0].runs[0].format.bold)
        XCTAssertEqual(rejected.paragraphs[0].runs[0].format.italic, true)
        XCTAssertFalse(rejected.hasPendingRevisions)
        try NativeFormat.validate(rejected)
    }
    func testUntrackedParagraphIndentSurvivesRejectingEarlierAlignment() throws {
        let original = DocumentNote(kind: .endnote, text: "Citation")
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        defer { session.close() }
        session.document.performEdit("Alignment") { model in
            var format = (model.paragraphs[0].formatting ?? model.style(for: model.paragraphs[0]).paragraph); format.alignment = .center
            model.sections[0].paragraphs[0].formatting = format
        }
        let tracked = try session.note()
        XCTAssertNotNil(tracked.paragraphs[0].formattingReview)
        session.editor.reviewEditing.author = nil
        session.document.undoManager?.removeAllActions()
        session.document.performEdit("Indent") { model in
            var format = (model.paragraphs[0].formatting ?? model.style(for: model.paragraphs[0]).paragraph); format.headIndent = 18
            model.sections[0].paragraphs[0].formatting = format
        }
        let changed = try session.note()
        XCTAssertEqual(changed.paragraphs[0].formattingReview?.changes.count, 2)
        XCTAssertEqual(changed.paragraphs[0].formattingReview?.changes.last?.accepted, true)
        session.document.undoManager?.undo(); XCTAssertEqual(try session.note(), tracked)
        session.document.undoManager?.redo(); XCTAssertEqual(try session.note(), changed)
        var rejected = session.document.snapshot()
        try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual((rejected.paragraphs[0].formatting ?? rejected.style(for: rejected.paragraphs[0]).paragraph).alignment, .left)
        XCTAssertEqual((rejected.paragraphs[0].formatting ?? rejected.style(for: rejected.paragraphs[0]).paragraph).headIndent, 18)
        XCTAssertFalse(rejected.hasPendingRevisions)
        try NativeFormat.validate(rejected)
    }
    func testLongDraftFlowsAndRetainsCharacterFormattingReview() throws {
        var original = DocumentNote(kind: .endnote)
        original.paragraphs = (1...90).map { Paragraph("Citation \($0). " + String(repeating: "Source details. ", count: 8)) }
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        defer { session.close() }
        XCTAssertGreaterThan(session.editor.textViews.count, 2)
        XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
        let end = session.editor.storage.length
        session.editor.select(NSRange(location: end - 8, length: 7))
        session.editor.activeTextView.toggleBold(nil)
        let formatted = try session.note()
        XCTAssertTrue(formatted.paragraphs.last!.runs.contains { !($0.review?.formatting.isEmpty ?? true) })
        session.document.undoManager?.undo()
        XCTAssertEqual(try session.note().paragraphs, original.paragraphs)
        session.document.undoManager?.redo()
        XCTAssertEqual(try session.note(), formatted)
        var rejected = session.document.snapshot()
        try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.paragraphs, original.paragraphs)
    }
    func testApplyCommitsCompositionButCancelLeavesSourceUntouched() throws {
        let original = DocumentNote(kind: .footnote, text: "Citation")
        let session = NoteReviewSession(note: original, styles: ParagraphStyle.defaults, author: .init(name: "Writer"))
        session.editor.select(NSRange(location: 8, length: 0))
        session.editor.activeTextView.setMarkedText("語", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(session.document.snapshot().paragraphs, original.paragraphs)
        let committed = try session.note()
        XCTAssertEqual(committed.plainText, "Citation語")
        XCTAssertTrue(committed.paragraphs[0].runs.contains { $0.review?.insertion != nil })
        session.close()
        XCTAssertEqual(original.plainText, "Citation")
    }
    func testTrackedModalApplyCancelAndDocumentUndo() throws {
        let document = ScribeFileDocument()
        let original = DocumentNote(kind: .footnote, text: "Citation")
        var reference = TextRun("\u{fffc}"); reference.noteID = original.id
        document.model.notes = [original]; document.model.sections[0].paragraphs[0].runs = [reference]
        document.makeWindowControllers(); defer { document.close() }
        let owner = document.editorController!
        owner.editor.reviewEditing.author = .init(name: "Writer")
        func submit(_ title: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                guard let content = NSApp.modalWindow?.contentView,
                      let text = descendants(content).compactMap({ $0 as? ScribeTextView }).first(where: { $0.identifier?.rawValue == "Note Text" }),
                      let button = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else {
                    XCTFail("Missing tracked note dialog controls"); NSApp.abortModal(); return
                }
                if let editor = text.editor {
                    XCTAssertFalse(editor.scrollView.hasHorizontalScroller)
                    XCTAssertLessThanOrEqual(editor.canvas.frame.width, editor.scrollView.contentView.bounds.width + 1)
                }
                text.setSelectedRange(NSRange(location: 8, length: 0))
                text.insertText(" added", replacementRange: NSRange(location: NSNotFound, length: 0))
                NativeDialogCapture.save(content, name: "TrackedNoteDialog")
                button.performClick(nil)
            }
        }
        let before = document.snapshot()
        submit("Cancel"); owner.editNote()
        XCTAssertEqual(document.snapshot(), before)
        document.undoManager?.removeAllActions()
        submit("Apply"); owner.editNote()
        let applied = document.snapshot()
        XCTAssertEqual(applied.notes.first?.plainText, "Citation added")
        XCTAssertTrue(applied.hasPendingRevisions)
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(applied)), applied)
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try NativeFormat.encode(applied).write(to: folder.appendingPathComponent("TrackedNoteDialog.scribe"))
            for mode in ReviewOutputMode.allCases {
                let output = try ReviewOutputSession(source: applied, mode: mode)
                defer { output.close() }
                let name: String
                switch mode { case .marked: name = "Marked"; case .accepted: name = "Accepted"; case .rejected: name = "Rejected" }
                try output.renderer.exportPDF(to: folder.appendingPathComponent("TrackedNoteDialog-\(name).pdf"), title: "Tracked note", author: "Scribe tests")
            }
            XCTAssertEqual(document.snapshot(), applied)
        }
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().notes, [original])
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().notes, applied.notes)
        var rejected = applied; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.notes, [original])
    }
}
#endif
