#if canImport(AppKit)
import AppKit
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class InternalLinkTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testHeadingLinkDialogDistinguishesDuplicateTitles() {
        let document = ScribeFileDocument()
        let first = Paragraph("Same title", style: "heading1"), second = Paragraph("Same title", style: "heading1")
        document.model.sections[0].paragraphs = [Paragraph("Link"), first, second]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        controller.editor.select(NSRange(location: 0, length: 4))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing link dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            guard let target = views.compactMap({ $0 as? NSPopUpButton }).first,
                  let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Insert Link" }) else {
                XCTFail("Missing link controls"); NSApp.abortModal(); return
            }
            XCTAssertEqual(target.numberOfItems, 2); target.selectItem(at: 1)
            if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"],
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    let folder = URL(fileURLWithPath: directory, isDirectory: true)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? png.write(to: folder.appendingPathComponent("HeadingLinkDialog.png"))
                }
            }
            button.performClick(nil)
        }
        controller.insertHeadingLink()
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].link, DocumentLink.paragraph(second.id))
    }

    func testEmptyFinalHeadingHasPDFDestination() throws {
        let document = ScribeFileDocument()
        let heading = Paragraph("", style: "heading1")
        var link = Paragraph("Future section"); link.runs[0].link = DocumentLink.paragraph(heading.id)
        document.model.sections[0].paragraphs = [link, heading]
        let editor = PaginatedEditor(document: document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrintRenderer(editor: editor).exportPDF(to: url, title: "Empty destination", author: "")
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        let annotation = try XCTUnwrap(pdf.page(at: 0)?.annotations.first)
        let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
        XCTAssertTrue(try XCTUnwrap(destination?.page) === pdf.page(at: 0))
    }

    func testHeadingLinkInsertionNavigationUndoAndPDFDestination() throws {
        let document = ScribeFileDocument()
        var heading = Paragraph("Destination", style: "heading1"); heading.pageBreakBefore = true
        document.model.sections[0].paragraphs = [Paragraph("Go here"), heading]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        document.undoManager?.removeAllActions()
        controller.applyHeadingLink(to: heading.id, text: "Read more", selection: NSRange(location: 0, length: 7))
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].link, DocumentLink.paragraph(heading.id))
        XCTAssertTrue(editor.textView(editor.activeTextView, clickedOnLink: DocumentLink.paragraph(heading.id), at: 0))
        XCTAssertEqual(editor.activeTextView.selectedRange().location, (editor.storage.string as NSString).range(of: "Destination").location)
        let diagnostics = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"]
        let directory = diagnostics.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fullURL = directory.appendingPathComponent("HeadingLinks.pdf")
        let partialURL = directory.appendingPathComponent("HeadingLinks-partial.pdf")
        defer { if diagnostics == nil { try? FileManager.default.removeItem(at: fullURL); try? FileManager.default.removeItem(at: partialURL) } }
        let renderer = PrintRenderer(editor: editor)
        let range = NSRange(location: 0, length: 9)
        editor.layout.addTemporaryAttribute(.foregroundColor, value: NSColor.red, forCharacterRange: range)
        let originalAttributes = editor.storage.attributes(at: 0, effectiveRange: nil) as NSDictionary
        try renderer.exportPDF(to: fullURL, title: "Links", author: "")
        XCTAssertEqual(editor.storage.attributes(at: 0, effectiveRange: nil) as NSDictionary, originalAttributes)
        XCTAssertEqual(editor.layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor, NSColor.red)
        let pdf = try XCTUnwrap(PDFDocument(url: fullURL))
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Links")
        XCTAssertFalse(pdf.page(at: 0)?.annotations.contains(where: { ($0.action as? PDFActionURL)?.url?.scheme == "scribe" }) == true)
        let annotation = try XCTUnwrap(pdf.page(at: 0)?.annotations.first)
        let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
        XCTAssertTrue(try XCTUnwrap(destination?.page) === pdf.page(at: 1))
        try renderer.exportPDF(to: partialURL, title: "Links", author: "", pages: [0])
        XCTAssertTrue(PDFDocument(url: partialURL)?.page(at: 0)?.annotations.isEmpty == true)
        document.undoManager?.undo()
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "Go here")
        XCTAssertNil(document.snapshot().paragraphs[0].runs[0].link)
    }
}
#endif
