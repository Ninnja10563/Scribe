#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class CharacterFormatCaptureCacheTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }
    func testRepeatedAppearancesRetainStyleOverridesScriptsAndMissingFaces() {
        var cache = CharacterFormatCaptureCache()
        for style in ParagraphStyle.defaults {
            let base = AttributedDocument.attributes(style: style)
            var variants = [base]
            for (key, value) in [(NSAttributedString.Key.underlineStyle, 1 as Any),
                                 (.strikethroughStyle, 1 as Any), (.foregroundColor, NSColor.red as Any),
                                 (.backgroundColor, NSColor.yellow as Any),
                                 (.font, NSFont.systemFont(ofSize: 19, weight: .semibold) as Any)] {
                var attributes = base; attributes[key] = value; variants.append(attributes)
            }
            var absentHighlight = base; absentHighlight.removeValue(forKey: .backgroundColor); variants.append(absentHighlight)
            for level in [-1, 1] {
                var attributes = base; ScriptProjection.setLevel(level, in: &attributes); variants.append(attributes)
                // A font-panel change invalidates the old rendered/base pair.
                attributes[.font] = NSFont.systemFont(ofSize: 21); variants.append(attributes)
            }
            var missing = base
            missing[.scribeFontFace] = "Unavailable-Scribe-Test-Face"
            missing[.scribeRenderedFace] = (base[.font] as? NSFont)?.fontName
            variants.append(missing)
            missing[.scribeRenderedFace] = "Different-Face"; variants.append(missing)
            for attributes in variants + variants.reversed() {
                XCTAssertEqual(cache.format(attributes, style: style),
                               AttributedDocument.captureTextFormat(attributes, style: style))
            }
        }
    }
    func testManyDistinctColoursRemainLosslessAfterCacheCapacity() {
        var cache = CharacterFormatCaptureCache()
        for value in 0..<600 {
            var attributes = AttributedDocument.attributes(style: .normal)
            attributes[.foregroundColor] = NSColor(srgbRed: CGFloat(value % 256) / 255,
                                                 green: CGFloat(value / 256) / 255, blue: 0.5, alpha: 1)
            XCTAssertEqual(cache.format(attributes, style: .normal),
                           AttributedDocument.captureTextFormat(attributes, style: .normal))
        }
    }
}
#endif
