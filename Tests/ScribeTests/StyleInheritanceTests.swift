#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class StyleInheritanceTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testHighlightInheritanceAndExplicitRemovalSurviveStyleChangesAndSaving() throws {
        let document = ScribeFileDocument()
        document.model.title = "Style overrides"
        document.model.styles[0].text.highlight = "#FFFF00"
        document.model.styles[0].text.baseline = 1
        document.model.sections[0].paragraphs = [Paragraph("INHERITED"), Paragraph("NO HIGHLIGHT"), Paragraph("DIRECT")]
        document.model.sections[0].paragraphs[1].runs[0].format.baseline = 0
        document.model.sections[0].paragraphs[2].runs[0].format.highlight = "#FF0000"
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        let range = (editor.storage.string as NSString).range(of: "NO HIGHLIGHT")
        editor.select(range)
        editor.activeTextView.toggleHighlight(nil)
        let captured = document.snapshot()
        XCTAssertNil(captured.paragraphs[0].runs[0].format.highlight, "Inherited colors must not become direct overrides during capture")
        XCTAssertNil(captured.paragraphs[0].runs[0].format.baseline)
        XCTAssertEqual(captured.paragraphs[1].runs[0].format.clearHighlight, true)
        XCTAssertEqual(captured.paragraphs[1].runs[0].format.baseline, 0)
        XCTAssertEqual(captured.paragraphs[2].runs[0].format.highlight, "#FF0000")
        var style = captured.styles[0]; style.text.highlight = "#00FF00"; style.text.baseline = -1
        document.undoManager?.removeAllActions()
        try controller.saveStyleDefinition(style, applying: false)
        func color(_ text: String) -> String? {
            let index = (editor.storage.string as NSString).range(of: text).location
            return (editor.storage.attribute(.backgroundColor, at: index, effectiveRange: nil) as? NSColor)?.hex
        }
        XCTAssertEqual(color("INHERITED"), "#00FF00"); XCTAssertNil(color("NO HIGHLIGHT")); XCTAssertEqual(color("DIRECT"), "#FF0000")
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document.snapshot())).paragraphs[1].runs[0].format.clearHighlight, true)
        document.undoManager?.undo()
        XCTAssertEqual(color("INHERITED"), "#FFFF00"); XCTAssertNil(color("NO HIGHLIGHT"))
        let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        editor.paginate()
        try PrintRenderer(editor: editor).exportPDF(to: directory.appendingPathComponent("StyleOverrides.pdf"), title: "Style overrides", author: "")
    }
}
#endif
