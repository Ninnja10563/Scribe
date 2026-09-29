#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class DocumentPropertiesTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testExplicitCheckSpellingSelectsNextErrorInDocumentLanguage() async throws {
        guard NSSpellChecker.shared.availableLanguages.contains(where: { (try? DocumentMetadata.languageIdentifier($0)) == "en-AU" }) else { throw XCTSkip("English (Australia) dictionary is not installed") }
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("Hello qzxqzxqzxy.")]
        document.makeWindowControllers(); defer { document.close() }
        let editor = document.editorController!.editor
        editor.select(NSRange(location: 0, length: 0))
        editor.activeTextView.checkSpelling(nil)
        let request = editor.activeTextView.spellingTask, done = expectation(description: "Native spelling request completes")
        Task { await request?.value; done.fulfill() }
        await fulfillment(of: [done], timeout: 15)
        XCTAssertEqual((editor.storage.string as NSString).substring(with: editor.activeTextView.selectedRange()), "qzxqzxqzxy")
    }
    func testClosingCancelsBackgroundSpellingBeforeDocumentDetaches() async {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph(String(repeating: "Words qzxqzxqzxy. ", count: 100))]
        document.makeWindowControllers()
        let controller = document.editorController!, view = controller.editor.activeTextView
        view.checkSpelling(nil)
        let request = view.spellingTask
        await Task.yield()
        document.close(); controller.document = nil
        XCTAssertNil(view.spellingTask); XCTAssertNil(view.editor)
        let done = expectation(description: "Closed spelling request returns safely")
        Task { await request?.value; done.fulfill() }
        await fulfillment(of: [done], timeout: 15)
        XCTAssertTrue(controller.isClosing)
    }
    func testSpellingOptionsArePerDocumentAndAutomaticClearsOldOrthography() throws {
        let global = NSSpellChecker.shared.language()
        var french = ScribeDocument(); french.language = "fr"
        var german = ScribeDocument(); german.language = "de"
        var types = NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.orthography.rawValue
        let first = DocumentSpelling.options(document: french, original: [:], types: &types)
        XCTAssertEqual((first[.orthography] as? NSOrthography)?.dominantLanguage, "fr")
        XCTAssertEqual(types & NSTextCheckingResult.CheckingType.orthography.rawValue, 0)
        XCTAssertNotEqual(types & NSTextCheckingResult.CheckingType.spelling.rawValue, 0)
        let second = DocumentSpelling.options(document: german, original: first, types: &types)
        XCTAssertEqual((second[.orthography] as? NSOrthography)?.dominantLanguage, "de")
        german.language = "und"
        let automatic = DocumentSpelling.options(document: german, original: second, types: &types)
        XCTAssertNil(automatic[.orthography])
        XCTAssertNotEqual(types & NSTextCheckingResult.CheckingType.orthography.rawValue, 0)
        XCTAssertEqual(NSSpellChecker.shared.language(), global)
    }
    func testDocumentPropertiesDialogPersistsLanguageAndSupportsUndo() throws {
        let document = ScribeFileDocument()
        document.model.sections[0].paragraphs = [Paragraph("Words for checking.")]
        document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!
        document.undoManager?.removeAllActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            guard let content = NSApp.modalWindow?.contentView else { XCTFail("Missing properties dialog"); NSApp.abortModal(); return }
            let views = descendants(content)
            (views.first { $0.identifier?.rawValue == "document-title" } as? NSTextField)?.stringValue = "Résumé 東京"
            (views.first { $0.identifier?.rawValue == "document-author" } as? NSTextField)?.stringValue = "Zoë"
            let menu = views.compactMap { $0 as? NSPopUpButton }.first
            menu?.selectItem(at: 0)
            NativeDialogCapture.save(content, name: "DocumentPropertiesDialog")
            guard let apply = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Apply" }) else { XCTFail("Missing Apply"); NSApp.abortModal(); return }
            apply.performClick(nil)
        }
        controller.documentProperties()
        let saved = try NativeFormat.decode(document.data(ofType: ScribeFileDocument.typeName))
        XCTAssertEqual(saved.title, "Résumé 東京"); XCTAssertEqual(saved.author, "Zoë"); XCTAssertEqual(saved.language, "und")
        XCTAssertTrue(controller.status.stringValue.contains("Automatic language"))
        document.undoManager?.undo()
        XCTAssertEqual(document.model.language, "en-AU"); XCTAssertEqual(document.model.author, "")
        document.undoManager?.redo(); XCTAssertEqual(document.model.title, "Résumé 東京")
    }
    func testSpellingDelegateUsesCurrentDocumentAfterUndo() throws {
        let document = ScribeFileDocument(); document.makeWindowControllers(); defer { document.close() }
        let controller = document.editorController!, editor = controller.editor
        document.undoManager?.removeAllActions()
        try controller.applyDocumentProperties(title: "French", author: "Writer", language: "fr")
        var types = NSTextCheckingResult.CheckingType.spelling.rawValue
        var options = editor.textView(editor.activeTextView, willCheckTextIn: NSRange(location: 0, length: 0), options: [:], types: &types)
        XCTAssertEqual((options[.orthography] as? NSOrthography)?.dominantLanguage, "fr")
        document.undoManager?.undo()
        options = editor.textView(editor.activeTextView, willCheckTextIn: NSRange(location: 0, length: 0), options: [:], types: &types)
        let orthography = try XCTUnwrap(options[.orthography] as? NSOrthography)
        XCTAssertEqual(try DocumentMetadata.languageIdentifier(orthography.dominantLanguage), "en-AU")
    }
}
#endif
