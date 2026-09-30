#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
import ImportExport
@testable import Scribe

@MainActor final class ExpandedFormattingTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testSidebarStaysInDocumentWindowAndFontCommandsPersist() throws {
        let document = ScribeFileDocument(); document.model.sections[0].paragraphs = [Paragraph("Selected type")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = try XCTUnwrap(document.editorController); document.showWindows()
        let editor = controller.editor; editor.select(NSRange(location: 0, length: 8))
        controller.showFonts(); controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(controller.formattingSidebar.isHidden)
        XCTAssertTrue(controller.formattingSidebar.window === controller.window)
        XCTAssertFalse(NSApp.windows.contains { $0 is NSFontPanel && $0.isVisible })
        let sidebar = controller.formattingSidebar
        sidebar.family.selectItem(withTitle: "Menlo")
        XCTAssertEqual(sidebar.family.titleOfSelectedItem, "Menlo")
        sidebar.changeFamily()
        XCTAssertEqual(ScriptProjection.logicalFont(in: editor.activeTextView.currentCharacterAttributes)?.familyName, "Menlo")
        sidebar.size.stringValue = "19.5"; sidebar.changeSize()
        let snapshot = document.snapshot()
        XCTAssertEqual(snapshot.paragraphs[0].runs.first?.format.fontFamily, "Menlo")
        XCTAssertEqual(snapshot.paragraphs[0].runs.first?.format.fontSize, 19.5)
        let reopened = try NativeFormat.decode(NativeFormat.encode(snapshot))
        XCTAssertEqual(reopened.paragraphs, snapshot.paragraphs)
        let office = try DOCX.decode(DOCX.encode(snapshot))
        XCTAssertEqual(office.document.paragraphs[0].runs.first?.format.fontSize, 19.5)
        NativeDialogCapture.save(controller.window!.contentView!, name: "FormattingSidebar")
        if let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"] {
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PrintRenderer(editor: editor).exportPDF(to: folder.appendingPathComponent("FormattingSidebar.pdf"), title: "Formatting", author: "Scribe")
            try DOCX.encode(snapshot).write(to: folder.appendingPathComponent("FormattingSidebar.docx"))
        }
        controller.toggleFocus(); XCTAssertTrue(sidebar.isHidden)
        controller.toggleFocus(); XCTAssertFalse(sidebar.isHidden)
    }
    func testFormatPainterPreservesLinksAndParagraphIdentityAndUndo() throws {
        let document = ScribeFileDocument()
        var source = Paragraph("Source"); source.runs[0].format.bold = true; source.runs[0].format.fontSize = 24
        var target = Paragraph("Target"); target.runs[0].link = "https://example.com"
        document.model.sections[0].paragraphs = [source, target]
        document.makeWindowControllers(); defer { document.close() }
        let controller = try XCTUnwrap(document.editorController); let editor = controller.editor
        editor.select(NSRange(location: 0, length: 6)); controller.copyCharacterFormatting()
        editor.select(NSRange(location: 7, length: 6)); document.undoManager?.removeAllActions()
        controller.pasteCharacterFormatting()
        let after = document.snapshot().paragraphs[1]
        XCTAssertEqual(after.id, target.id); XCTAssertEqual(after.runs[0].link, target.runs[0].link)
        XCTAssertEqual(after.runs[0].format.fontSize, 24); XCTAssertEqual(after.runs[0].format.bold, true)
        document.undoManager?.undo()
        XCTAssertNil(document.snapshot().paragraphs[1].runs[0].format.fontSize)
        document.undoManager?.redo(); XCTAssertEqual(document.snapshot().paragraphs[1].runs[0].format.fontSize, 24)
    }
    func testUnicodeCaseConversionRetainsFormattingAndSelectionLength() throws {
        let document = ScribeFileDocument(); var paragraph = Paragraph("straße 😀")
        paragraph.runs[0].format.italic = true; document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); defer { document.close() }
        let editor = try XCTUnwrap(document.editorController?.editor)
        editor.select(NSRange(location: 0, length: editor.storage.length)); editor.activeTextView.uppercaseSelection(nil)
        XCTAssertEqual(document.snapshot().paragraphs[0].text, "STRASSE 😀")
        XCTAssertEqual(editor.activeTextView.selectedRange().length, ("STRASSE 😀" as NSString).length)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.italic, true)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].text, "straße 😀")
    }
    func testClearCharacterFormattingRestoresStyleWithoutRemovingLink() throws {
        let document = ScribeFileDocument(); var paragraph = Paragraph("Heading", style: "heading1")
        paragraph.runs[0].format.italic = true; paragraph.runs[0].format.baseline = 1; paragraph.runs[0].format.highlight = "#FFF176"
        paragraph.runs[0].link = "https://example.com"; document.model.sections[0].paragraphs = [paragraph]
        document.makeWindowControllers(); defer { document.close() }
        let editor = try XCTUnwrap(document.editorController?.editor)
        editor.select(NSRange(location: 0, length: editor.storage.length)); editor.activeTextView.clearCharacterFormatting(nil)
        let after = document.snapshot().paragraphs[0]
        XCTAssertEqual(after.styleID, "heading1"); XCTAssertEqual(after.runs[0].format, TextFormatting())
        XCTAssertEqual(after.runs[0].link, paragraph.runs[0].link)
    }
    func testParagraphPresetsAndEmptyTypingAreUndoable() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = try XCTUnwrap(document.editorController)
        XCTAssertTrue(controller.editor.activeTextView.setFontSize(18))
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.fontSize, 18)
        XCTAssertFalse(controller.editor.activeTextView.setFontSize(.nan))
        controller.setLineHeightMultiple(2)
        XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.lineHeight, .init(rule: .multiple, value: 2))
        controller.increaseIndent(); XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.headIndent, 24)
        document.undoManager?.removeAllActions()
        controller.togglePageBreakBefore(); XCTAssertTrue(document.snapshot().paragraphs[0].pageBreakBefore)
        document.undoManager?.undo(); XCTAssertFalse(document.snapshot().paragraphs[0].pageBreakBefore)
        document.undoManager?.removeAllActions()
        controller.clearParagraphFormatting(); XCTAssertNil(document.snapshot().paragraphs[0].formatting)
        document.undoManager?.undo(); XCTAssertEqual(document.snapshot().paragraphs[0].formatting?.headIndent, 24)
    }
    func testEmptyUnderlineAndHighlightPersistAndActualButtonActionWorks() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = try XCTUnwrap(document.editorController); controller.showFonts()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let button = try XCTUnwrap(descendants(controller.formattingSidebar).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "underline:" })
        button.performClick(nil)
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.underline, true)
        XCTAssertEqual(button.state, .on)
        controller.editor.activeTextView.setCharacterColour(NSColor(hex: "#FFF176"), highlight: true)
        let reopened = try NativeFormat.decode(NativeFormat.encode(document.snapshot()))
        XCTAssertEqual(reopened.paragraphs[0].runs[0].format.highlight, "#FFF176")
        XCTAssertEqual(reopened.paragraphs[0].runs[0].format.underline, true)
        controller.editor.activeTextView.insertText("Future typing", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(document.snapshot().paragraphs[0].runs[0].format.underline, true)
    }
    func testContextualFontMenuUsesTheInWindowSidebar() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = try XCTUnwrap(document.editorController)
        let menu = NSMenu(), submenu = NSMenu()
        let root = NSMenuItem(title: "Font", action: nil, keyEquivalent: ""); root.submenu = submenu; menu.addItem(root)
        let fonts = NSMenuItem(title: "Show Fonts", action: #selector(NSFontManager.orderFrontFontPanel(_:)), keyEquivalent: "")
        fonts.target = NSFontManager.shared; submenu.addItem(fonts)
        controller.editor.activeTextView.routeFontMenu(menu)
        XCTAssertTrue(fonts.target === controller)
        XCTAssertEqual(fonts.action, #selector(EditorWindowController.showFonts))
        XCTAssertTrue(NSApp.sendAction(fonts.action!, to: fonts.target, from: fonts))
        XCTAssertFalse(controller.formattingSidebar.isHidden)
    }
    func testReducedMotionRevealIsImmediate() {
        let view = NSView(); view.isHidden = true; view.alphaValue = 0
        ChromeAnimation.reveal(view, reduceMotion: true)
        XCTAssertFalse(view.isHidden); XCTAssertEqual(view.alphaValue, 1)
    }
}
#endif
