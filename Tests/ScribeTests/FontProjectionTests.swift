#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class FontProjectionTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testConcreteWeightsSurviveCaptureNativeSaveAndReopen() throws {
        for name in ["HelveticaNeue-Medium", "HelveticaNeue-Light", "HelveticaNeue-CondensedBold"] {
            let font = try XCTUnwrap(NSFont(name: name, size: 17))
            var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("Typeface")
            let text = NSMutableAttributedString(attributedString: AttributedDocument.render(document))
            text.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.length))
            let saved = AttributedDocument.capture(text, preserving: document)
            let reopened = try NativeFormat.decode(NativeFormat.encode(saved))
            let projected = AttributedDocument.render(reopened)
            let loaded = try XCTUnwrap(projected.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(loaded.fontName, font.fontName)
            XCTAssertEqual(loaded.pointSize, 17)
        }
    }

    func testStyleFaceRemainsInheritedAndFamilyOverrideReplacesIt() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("Inherited")
        document.styles[0].text.fontFace = "HelveticaNeue-Medium"
        let captured = AttributedDocument.capture(AttributedDocument.render(document), preserving: document)
        XCTAssertNil(captured.paragraphs[0].runs[0].format.fontFace)
        XCTAssertNil(captured.paragraphs[0].runs[0].format.bold)
        var changed = captured; changed.styles[0].text.fontFace = "HelveticaNeue-Light"
        let projected = AttributedDocument.render(changed)
        XCTAssertEqual((projected.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName, "HelveticaNeue-Light")
        var direct = TextFormatting(); direct.fontFamily = "Courier"
        XCTAssertEqual(FontProjection.font(direct, over: document.styles[0].text).familyName, "Courier")
    }

    func testUnavailableFaceIsRetainedUntilFontChanges() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("Fallback")
        let missing = "ScribeTest-UnavailableFace"
        document.sections[0].paragraphs[0].runs[0].format.fontFace = missing
        let projected = NSMutableAttributedString(attributedString: AttributedDocument.render(document))
        XCTAssertEqual(AttributedDocument.capture(projected, preserving: document).paragraphs[0].runs[0].format.fontFace, missing)
        projected.addAttribute(.font, value: try XCTUnwrap(NSFont(name: "Courier", size: 12)), range: NSRange(location: 0, length: projected.length))
        XCTAssertNotEqual(AttributedDocument.capture(projected, preserving: document).paragraphs[0].runs[0].format.fontFace, missing)
    }
}
#endif
