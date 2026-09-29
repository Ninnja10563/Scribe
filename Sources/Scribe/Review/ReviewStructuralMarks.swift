#if canImport(AppKit)
import AppKit
import DocumentCore

/// Margin labels expose structural revisions without inserting display glyphs
/// into the document's text, changing pagination, or moving the native caret.
@MainActor enum ReviewStructuralMarks {
    enum Kind: Int { case insertedBreak, deletedBreak, paragraphFormatting }
    struct Mark {
        let kind: Kind
        let y: CGFloat
        var label: String {
            switch kind { case .insertedBreak: return "¶+"; case .deletedBreak: return "¶−"; case .paragraphFormatting: return "¶~" }
        }
    }
    static func marks(storage: NSAttributedString, layout: NSLayoutManager, container: NSTextContainer,
                      glyphs: NSRange, trailingReview: ParagraphFormattingReview? = nil) -> [Mark] {
        var result: [Mark] = [], seen = Set<String>(), paragraphs = Set<String>()
        func append(_ kind: Kind, y: CGFloat) {
            let key = "\(kind.rawValue):\(Int((y * 100).rounded()))"
            if seen.insert(key).inserted { result.append(Mark(kind: kind, y: y)) }
        }
        if glyphs.length > 0 {
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                guard attributes[.scribeNoteLabelID] == nil else { return }
                let glyph = layout.glyphIndexForCharacter(at: range.location)
                guard NSLocationInRange(glyph, glyphs) else { return }
                let y = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                if let data = attributes[.scribeBreakReview] as? Data, data.count <= NativeFormat.maximumBytes,
                   let review = try? JSONDecoder().decode(RunReview.self, from: data) {
                    if review.insertion != nil { append(.insertedBreak, y: y) }
                    if review.deletion != nil { append(.deletedBreak, y: y) }
                }
                if let id = attributes[.scribeParagraphID] as? String, paragraphs.insert(id).inserted,
                   let data = attributes[.scribeParagraphReview] as? Data, data.count <= NativeFormat.maximumBytes,
                   let review = try? JSONDecoder().decode(ParagraphFormattingReview.self, from: data), !review.pendingIDs.isEmpty {
                    append(.paragraphFormatting, y: y)
                }
            }
        }
        if let trailingReview, !trailingReview.pendingIDs.isEmpty,
           NSMaxRange(glyphs) == layout.numberOfGlyphs, layout.extraLineFragmentTextContainer === container {
            append(.paragraphFormatting, y: layout.extraLineFragmentRect.minY)
        }
        return result
    }
    static func requiredLeftMargin(for marks: [Mark]) -> CGFloat {
        var counts: [Int: Int] = [:]
        for mark in marks { counts[Int((mark.y * 100).rounded()), default: 0] += 1 }
        return counts.values.map { 22 + CGFloat($0 - 1) * 19 }.max() ?? 0
    }
    static func draw(_ marks: [Mark], at origin: NSPoint) {
        var occupied: [Int: Int] = [:]
        for mark in marks {
            let line = Int((mark.y * 100).rounded()), slot = occupied[line, default: 0]
            occupied[line] = slot + 1
            let color: NSColor
            switch mark.kind {
            case .insertedBreak: color = NSColor(srgbRed: 0.08, green: 0.40, blue: 0.23, alpha: 1)
            case .deletedBreak: color = NSColor(srgbRed: 0.68, green: 0.16, blue: 0.16, alpha: 1)
            case .paragraphFormatting: color = NSColor(srgbRed: 0.16, green: 0.32, blue: 0.64, alpha: 1)
            }
            // Grow away from text when multiple kinds share a line.
            (mark.label as NSString).draw(at: NSPoint(x: origin.x - 22 - CGFloat(slot) * 19, y: origin.y + mark.y + 1),
                withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: color])
        }
    }
}
#endif

#if canImport(AppKit)
extension PaginatedEditor {
    func drawStructuralReview(on page: Int, at origin: NSPoint) { ReviewStructuralMarks.draw(structuralReviewMarks(on: page), at: origin) }
    func structuralReviewMarks(on page: Int) -> [ReviewStructuralMarks.Mark] {
        guard layout.textContainers.indices.contains(page) else { return [] }
        let container = layout.textContainers[page]
        let trailing = owner?.model.paragraphs.last.flatMap { $0.text.isEmpty ? $0.formattingReview : nil }
        return ReviewStructuralMarks.marks(storage: storage, layout: layout, container: container,
            glyphs: layout.glyphRange(for: container), trailingReview: trailing)
    }
}
#endif
