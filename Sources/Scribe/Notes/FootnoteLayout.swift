#if canImport(AppKit)
import AppKit
import DocumentCore

/// Resolves the live editing projection, including note content restored by native undo.
/// Page fitting uses real line fragments and verifies the result after TextKit reflows.
@MainActor final class FootnoteLayout {
    @MainActor struct Page {
        let notes: [NoteTextLayout.Fragment]
        let height: CGFloat
        func draw(at origin: NSPoint, width: CGFloat, showsReviewMarkup: Bool = true) {
            guard !notes.isEmpty else { return }
            NSColor.darkGray.setStroke()
            let rule = NSBezierPath(); rule.lineWidth = 0.5
            rule.move(to: origin); rule.line(to: NSPoint(x: origin.x + min(100, width), y: origin.y)); rule.stroke()
            var y = origin.y + 12
            for note in notes { note.draw(at: NSPoint(x: origin.x, y: y), showsReviewMarkup: showsReviewMarkup); y += note.height + 6 }
        }
    }
    let endnotes: [NumberedNote]
    private let measured: [UUID: NoteTextLayout]
    private struct Continuation { let id: UUID; let start: Int }
    private var pending: [Continuation] = []
    var hasPendingNotes: Bool { !pending.isEmpty }
    private let references: [(range: NSRange, id: UUID)]
    init(storage: NSTextStorage, styles: [ParagraphStyle], width: CGFloat) throws {
        var references: [(range: NSRange, id: UUID)] = [], notes: [DocumentNote] = []
        var failure: Error?
        storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let value else { return }
            do {
                guard let data = value as? Data else { throw DocumentError.invalid("invalid note reference") }
                let note = try JSONDecoder().decode(DocumentNote.self, from: data)
                guard range.length == 1, (storage.string as NSString).substring(with: range) == "\u{fffc}" else {
                    throw DocumentError.invalid("invalid note reference range")
                }
                references.append((range, note.id)); notes.append(note)
            } catch { failure = error }
        }
        if let failure { throw failure }
        let numbered = try NoteNumbering.resolve(referenceIDs: references.map(\.id), notes: notes)
        endnotes = numbered.filter { $0.note.kind == .endnote }
        var measured: [UUID: NoteTextLayout] = [:]
        for note in numbered where note.note.kind == .footnote {
            measured[note.id] = try NoteTextLayout(note: note, styles: styles, width: width)
        }
        self.references = references.filter { measured[$0.id] != nil }; self.measured = measured
    }
    func fit(layout: NSLayoutManager, container: NSTextContainer, pageHeight: CGFloat) throws -> Page {
        container.containerSize.height = pageHeight
        layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
        var lines: [FootnotePagePlan.Line] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, current, glyphs, _ in
            guard current === container else { return }
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append(.init(bottom: rect.maxY, noteIDs: self.ids(in: characters)))
        }
        let heights = measured.mapValues { Double($0.height + 6) }
        if !pending.isEmpty {
            let remaining = pending.map { item in measured[item.id]!.fragment(from: item.start, fitting: 1_000_000)! }
            let reserved = remaining.reduce(CGFloat(12)) { $0 + $1.height + 6 }
            if reserved >= pageHeight || lines.first.map({ $0.bottom + reserved > pageHeight }) == true {
                var fragments: [NoteTextLayout.Fragment] = [], next: [Continuation] = []
                var available = pageHeight - 12
                for item in pending {
                    let note = measured[item.id]!
                    guard let fragment = note.fragment(from: item.start, fitting: available - 6) else { next.append(item); continue }
                    fragments.append(fragment); available -= fragment.height + 6
                    if NSMaxRange(fragment.glyphs) < NSMaxRange(note.glyphRange) { next.append(Continuation(id: item.id, start: NSMaxRange(fragment.glyphs))) }
                }
                guard !fragments.isEmpty else { throw DocumentError.invalid("a footnote line or object is taller than the page writing area") }
                let page = try finish(layout: layout, container: container, bodyHeight: 1, expectedReferences: [], fragments: fragments, pageHeight: pageHeight)
                pending = next; return page
            }
            let plan = try FootnotePagePlan.choose(lines: lines, pageHeight: pageHeight - reserved, noteHeights: heights, separatorHeight: 0)
            let fragments = remaining + plan.noteIDs.map { measured[$0]!.fullFragment }
            let page = try finish(layout: layout, container: container, bodyHeight: max(1, plan.bodyHeight), expectedReferences: plan.noteIDs, fragments: fragments, pageHeight: pageHeight)
            pending = []; return page
        }
        let plan = try FootnotePagePlan.choose(lines: lines, pageHeight: pageHeight, noteHeights: heights)
        if plan.needsContinuation, let first = lines.first {
            let minimums = first.noteIDs.map { measured[$0]!.minimumFragmentHeight(from: 0) + 6 }
            var available = pageHeight - first.bottom - 12
            guard minimums.reduce(0, +) <= available else { throw DocumentError.invalid("the references on one line require more note space than the page provides") }
            var fragments: [NoteTextLayout.Fragment] = [], next: [Continuation] = []
            for (index, id) in first.noteIDs.enumerated() {
                let note = measured[id]!
                let reservedForLater = minimums.dropFirst(index + 1).reduce(0, +)
                guard let fragment = note.fragment(from: 0, fitting: available - reservedForLater - 6) else { throw DocumentError.invalid("a footnote object cannot fit on the reference page") }
                fragments.append(fragment); available -= fragment.height + 6
                if NSMaxRange(fragment.glyphs) < NSMaxRange(note.glyphRange) { next.append(Continuation(id: id, start: NSMaxRange(fragment.glyphs))) }
            }
            let page = try finish(layout: layout, container: container, bodyHeight: first.bottom, expectedReferences: first.noteIDs, fragments: fragments, pageHeight: pageHeight)
            pending = next; return page
        }
        guard plan.lineCount > 0 || lines.isEmpty else { throw DocumentError.invalid("the next body line cannot fit within the page writing area") }
        return try finish(layout: layout, container: container, bodyHeight: max(1, plan.bodyHeight), expectedReferences: plan.noteIDs, fragments: plan.noteIDs.map { measured[$0]!.fullFragment }, pageHeight: pageHeight)
    }
    private func finish(layout: NSLayoutManager, container: NSTextContainer, bodyHeight: CGFloat, expectedReferences: [UUID], fragments: [NoteTextLayout.Fragment], pageHeight: CGFloat) throws -> Page {
        container.containerSize.height = bodyHeight
        layout.textContainerChangedGeometry(container); layout.ensureLayout(for: container)
        let characters = layout.characterRange(forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
        let height = fragments.isEmpty ? 0 : fragments.reduce(CGFloat(12)) { $0 + $1.height + 6 }
        guard ids(in: characters) == expectedReferences,
              layout.usedRect(for: container).maxY + height <= pageHeight + 0.5 else {
            throw DocumentError.invalid("the footnote reference could not be kept with its note on this page")
        }
        return Page(notes: fragments, height: height)
    }
    private func ids(in range: NSRange) -> [UUID] {
        references.filter { NSIntersectionRange($0.range, range).length > 0 }.map(\.id)
    }
}
#endif
