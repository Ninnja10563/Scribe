#if canImport(AppKit)
import AppKit
import DocumentCore

/// Decisions apply to an isolated output copy, never the user's live document.
enum ReviewOutputMode: String, CaseIterable {
    case marked = "Show tracked changes"
    case accepted = "Accept pending changes"
    case rejected = "Reject pending changes"
}

@MainActor final class ReviewOutputSession {
    private let document: ScribeFileDocument
    let editor: PaginatedEditor
    let renderer: PrintRenderer
    init(source: ScribeDocument, mode: ReviewOutputMode) throws {
        var projected = source
        switch mode {
        case .marked: try NativeFormat.validate(projected)
        case .accepted: try projected.resolveAllRevisions(accepting: true)
        case .rejected: try projected.resolveAllRevisions(accepting: false)
        }
        guard projected.sections.count == 1 else { throw DocumentError.invalid("review output currently requires one section") }
        // This transient NSDocument must never address the source recovery slot.
        projected.id = UUID()
        document = ScribeFileDocument(); document.model = projected
        editor = PaginatedEditor(document: document)
        renderer = PrintRenderer(editor: editor, showsReviewMarkup: mode == .marked)
        do {
            if let warning = editor.outputWarning { throw DocumentError.invalid(warning) }
        } catch { editor.prepareForClose(); throw error }
    }
    func close() { editor.prepareForClose() }
}
#endif
