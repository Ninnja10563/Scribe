#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class BookmarkTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testBookmarkEditingUndoNavigationAndPDF() throws {
        let document = ScribeFileDocument()
        var target = Paragraph("Research notes"); target.pageBreakBefore = true
        document.model.sections[0].paragraphs = [Paragraph("Read more"), target]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        XCTAssertTrue(controller.addBookmark(named: "Notes", paragraphID: target.id))
        let id = try XCTUnwrap(document.snapshot().bookmarks.first?.id)
        document.undoManager?.removeAllActions()
        XCTAssertTrue(controller.applyBookmarkLink(to: id, text: "Visit notes", selection: NSRange(location: 0, length: 9)))
        let link = DocumentLink.bookmark(id)
        XCTAssertTrue(editor.textView(editor.activeTextView, clickedOnLink: link, at: 0))
        XCTAssertEqual(editor.activeTextView.selectedRange().location, (editor.storage.string as NSString).range(of: "Research notes").location)
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("BookmarkLinks.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Bookmarks", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)), annotation = try XCTUnwrap(pdf.page(at: 0)?.annotations.first)
        XCTAssertFalse(pdf.page(at: 0)!.annotations.contains { ($0.action as? PDFActionURL)?.url?.scheme == "scribe" })
        let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
        XCTAssertTrue(try XCTUnwrap(destination?.page) === pdf.page(at: 1))
        document.undoManager?.undo()
        XCTAssertNil(document.snapshot().paragraphs[0].runs[0].link)
        document.undoManager?.removeAllActions()
        document.performEdit("Rename Bookmark") { $0.renameBookmark(id: id, name: "Sources") }
        XCTAssertEqual(document.snapshot().bookmarks.first?.name, "Sources")
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().bookmarks.first?.name, "Notes")
        document.undoManager?.removeAllActions()
        // Exercise actual text deletion, not just model transactions.
        let start = (editor.storage.string as NSString).range(of: "\n").location
        editor.select(NSRange(location: start, length: editor.storage.length - start))
        editor.activeTextView.insertText("", replacementRange: editor.activeTextView.selectedRange())
        XCTAssertNil(document.snapshot().destinationParagraphID(for: link))
        XCTAssertEqual(document.snapshot().bookmarks.count, 1)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().destinationParagraphID(for: link), target.id)
    }
    func testAddAndManageNativeDialogs() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("Destination")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        func respond(_ name: String, actionIndex: Int?, buttonTitle: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing bookmark dialog"); NSApp.abortModal(); return }
                let views = descendants(content)
                guard let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }),
                      let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == buttonTitle }) else { XCTFail("Missing controls"); NSApp.abortModal(); return }
                field.stringValue = name
                if let actionIndex { views.compactMap { $0 as? NSPopUpButton }.first(where: { $0.numberOfItems == 4 })?.selectItem(at: actionIndex) }
                NativeDialogCapture.save(content, name: actionIndex == nil ? "AddBookmarkDialog" : "ManageBookmarksDialog")
                button.performClick(nil)
            }
        }
        respond("Notes", actionIndex: nil, buttonTitle: "Add Bookmark"); controller.insertBookmark()
        XCTAssertEqual(document.snapshot().bookmarks.first?.name, "Notes")
        respond("Sources", actionIndex: 2, buttonTitle: "Apply"); controller.manageBookmarks()
        XCTAssertEqual(document.snapshot().bookmarks.first?.name, "Sources")
        document.undoManager?.removeAllActions() // Separate UI commands normally arrive in separate events.
        respond("", actionIndex: 3, buttonTitle: "Apply"); controller.manageBookmarks()
        XCTAssertTrue(document.snapshot().bookmarks.isEmpty)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().bookmarks.first?.name, "Sources")
    }
}
#endif
