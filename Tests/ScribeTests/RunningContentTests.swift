#if canImport(AppKit)
import AppKit
import XCTest
import PDFKit
import DocumentCore
@testable import Scribe

@MainActor final class RunningContentEditorTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testVariantsRenderOnCorrectPagesAndPersistThroughUndoAndSave() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = (0..<3).map { index in
            var paragraph = Paragraph("Running content page \(index + 1)"); paragraph.pageBreakBefore = index > 0; return paragraph
        }
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        let options = RunningContentOptions(section: document.model.sections[0])
        options.header.stringValue = "Default header"; options.footer.stringValue = "Default footer"
        options.differentFirst.state = .on; options.differentEven.state = .on
        options.firstFooter.stringValue = "Cover footer"
        options.evenHeader.stringValue = "Even header"; options.evenFooter.stringValue = "Even footer"
        document.performEdit("Headers and Footers") { value in
            options.apply(to: &value.sections[0]); value.sections[0].runningContent?.startingPageNumber = 2
        }
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(editor.textViews.count, 3)
        XCTAssertEqual(editor.canvas.runningText(isHeader: true, pageIndex: 0), "")
        XCTAssertEqual(editor.canvas.runningText(isHeader: true, pageIndex: 1), "Default header")
        XCTAssertEqual(editor.canvas.runningText(isHeader: true, pageIndex: 2), "Even header")
        let saved = try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName))
        XCTAssertEqual(saved.sections[0].runningContent, document.model.sections[0].runningContent)
        let folder = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("NativeRunningContent.pdf")
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Running content", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url)); XCTAssertEqual(pdf.pageCount, 3)
        let first = pdf.page(at: 0)?.string ?? "", second = pdf.page(at: 1)?.string ?? "", third = pdf.page(at: 2)?.string ?? ""
        XCTAssertTrue(first.contains("Cover footer")); XCTAssertFalse(first.contains("Default header")); XCTAssertFalse(first.contains("Even header"))
        XCTAssertTrue(second.contains("Default header")); XCTAssertTrue(second.contains("Default footer")); XCTAssertFalse(second.contains("Cover footer"))
        XCTAssertTrue(third.contains("Even header")); XCTAssertTrue(third.contains("Even footer")); XCTAssertFalse(third.contains("Default header"))
        document.undoManager?.undo(); XCTAssertNil(document.model.sections[0].runningContent); XCTAssertEqual(editor.canvas.runningText(isHeader: false, pageIndex: 0), "")
        document.undoManager?.redo(); XCTAssertEqual(editor.canvas.runningText(isHeader: false, pageIndex: 0), "Cover footer")
    }
    func testOverflowingRunningTextCannotOverwritePDFAndDormantTextDoesNotBlockOutput() throws {
        let document = ScribeFileDocument(); document.model.sections[0].header = String(repeating: "Long header text. ", count: 40)
        let editor = PaginatedEditor(document: document); defer { editor.prepareForClose() }
        XCTAssertNotNil(editor.outputWarning)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("Keep the previous export".utf8); try original.write(to: url)
        XCTAssertThrowsError(try PrintRenderer(editor: editor).exportPDF(to: url, title: "", author: ""))
        XCTAssertEqual(try Data(contentsOf: url), original)
        editor.canvas.header = "Fits"
        var variants = RunningContentVariants(); variants.firstHeader = String(repeating: "Dormant ", count: 80)
        editor.canvas.runningContent = variants
        XCTAssertNil(editor.outputWarning)
        editor.canvas.runningContent?.differentFirstPage = true
        XCTAssertNotNil(editor.outputWarning)
        editor.canvas.runningContent?.firstHeader = "Two\nlines"
        XCTAssertNotNil(editor.outputWarning)
        editor.canvas.runningContent = nil
        editor.canvas.pageSettings.top = 20
        XCTAssertNotNil(editor.outputWarning)
        editor.canvas.header = ""
        XCTAssertNil(editor.outputWarning)
        editor.canvas.footer = "Footer"; editor.canvas.pageSettings.bottom = 20
        XCTAssertNotNil(editor.outputWarning)
    }
    func testNativeDialogEditsVariantsAndCancelPreservesExistingValues() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView,
                  let tabs = descendants(content).compactMap({ $0 as? NSTabView }).first else { XCTFail("Missing running-content dialog"); NSApp.abortModal(); return }
            tabs.selectTabViewItem(at: 1)
            let views = descendants(content)
            guard let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "First Page Header" }),
                  let toggle = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Different first page" }) else { XCTFail("Missing first-page controls"); NSApp.abortModal(); return }
            field.stringValue = "Cover heading"; toggle.state = .on
            NativeDialogCapture.save(content, name: "RunningContentFirstPage")
            guard let apply = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing Apply button"); NSApp.abortModal(); return }
            apply.performClick(nil)
        }
        controller.editHeaderFooter()
        XCTAssertEqual(document.model.sections[0].runningContent?.firstHeader, "Cover heading")
        XCTAssertEqual(controller.editor.canvas.runningText(isHeader: true, pageIndex: 0), "Cover heading")
        let before = document.snapshot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.abortModal() }
        controller.editHeaderFooter(); XCTAssertEqual(document.snapshot(), before)
    }
}
#endif
