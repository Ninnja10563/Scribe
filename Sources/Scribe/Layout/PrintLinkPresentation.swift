#if canImport(AppKit)
import AppKit

extension PrintRenderer {
    /// NSTextView decorates links while drawing. Direct layout-manager output needs
    /// the same attributes explicitly; restore its temporary state after each page.
    func withLinkPresentation(on index: Int, draw: () -> Void) {
        let layout = editor.layout
        let glyphs = layout.glyphRange(for: layout.textContainers[index])
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var saved: [(NSRange, [NSAttributedString.Key: Any])] = []
        let presentation = editor.textViews[index].linkTextAttributes ?? [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        editor.storage.enumerateAttribute(.link, in: characters) { value, range, _ in
            guard value != nil else { return }
            var position = range.location
            while position < NSMaxRange(range) {
                var effective = NSRange()
                let attributes = layout.temporaryAttributes(atCharacterIndex: position, effectiveRange: &effective)
                let overlap = NSIntersectionRange(effective, range)
                guard overlap.length > 0 else { break }
                saved.append((overlap, attributes)); position = NSMaxRange(overlap)
            }
            layout.addTemporaryAttributes(presentation, forCharacterRange: range)
        }
        let wasDrawingPrintLinks = editor.drawingPrintLinks
        editor.drawingPrintLinks = true
        defer {
            editor.drawingPrintLinks = wasDrawingPrintLinks
            for (range, attributes) in saved { layout.setTemporaryAttributes(attributes, forCharacterRange: range) }
        }
        // Document pages are light in both application appearances.
        if let appearance = NSAppearance(named: .aqua) { appearance.performAsCurrentDrawingAppearance(draw) }
        else { draw() }
    }
}
#endif
