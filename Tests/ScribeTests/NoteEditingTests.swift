#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class NoteEditingTests: XCTestCase {
    func testLongEndnoteCanBeInsertedAndEditedWithoutFlatteningBodyText() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        var note = DocumentNote(kind: .endnote)
        note.paragraphs = (1...50).map { Paragraph("Source \($0). " + String(repeating: "Endnote detail. ", count: 10)) }
        try controller.applyNote(note, replacing: NSRange(location: 0, length: 0), action: "Insert Endnote")
        XCTAssertEqual(document.snapshot().notes, [note])
        XCTAssertGreaterThan(controller.editor.canvas.pageCount, 2)
        XCTAssertEqual(document.snapshot().paragraphs.count, 1)
        document.undoManager?.undo(); controller.editor.paginate()
        XCTAssertTrue(document.snapshot().notes.isEmpty)
        XCTAssertEqual(controller.editor.canvas.pageCount, 1)
    }
    func testNativeNoteDialogInsertEditCancelAndUndo() throws {
        _ = NSApplication.shared
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        func submit(_ content: String, button title: String, capture: Bool = false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                guard let view = NSApp.modalWindow?.contentView,
                      let text = descendants(view).compactMap({ $0 as? NSTextView }).first(where: { $0.identifier?.rawValue == "Note Text" }),
                      let button = descendants(view).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else {
                    XCTFail("Missing native note controls"); NSApp.abortModal(); return
                }
                text.string = content
                if capture { NativeDialogCapture.save(view, name: "NoteDialog") }
                button.performClick(nil)
            }
        }
        submit("A citation with résumé and Unicode.\nA second paragraph.", button: "Insert", capture: true)
        controller.insertFootnote()
        let inserted = document.snapshot()
        XCTAssertEqual(inserted.notes.count, 1)
        XCTAssertEqual(inserted.notes.first?.paragraphs.count, 2)
        XCTAssertNil(controller.editor.layoutWarning)
        document.undoManager?.undo(); XCTAssertTrue(document.snapshot().notes.isEmpty)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().notes, inserted.notes)
        controller.editor.select(NSRange(location: 0, length: 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.abortModal() }
        controller.editNote(); XCTAssertEqual(document.snapshot(), inserted)
        submit("Revised citation.", button: "Apply")
        controller.editNote()
        XCTAssertEqual(document.snapshot().notes.first?.id, inserted.notes.first?.id)
        XCTAssertEqual(document.snapshot().notes.first?.plainText, "Revised citation.")
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().notes, inserted.notes)
        let encoded = try document.data(ofType: "org.scribe.document")
        XCTAssertEqual(try NativeFormat.decode(encoded).notes, inserted.notes)
        let tooLong = DocumentNote(kind: .footnote, text: String(repeating: "Too much text. ", count: 1000))
        XCTAssertThrowsError(try controller.applyNote(tooLong, replacing: NSRange(location: 0, length: 1), action: "Edit Note"))
        XCTAssertEqual(document.snapshot().notes, inserted.notes)
    }
}
#endif
