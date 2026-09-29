#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor struct LocalParagraphReplacement {
    let range: NSRange
    let value: NSAttributedString
    let caret: Int
    let typingAttributes: [NSAttributedString.Key: Any]
    let validatedLength: Int

    static func make(in view: ScribeTextView, replacing range: NSRange) throws -> Self? {
        guard let editor = view.editor, let owner = editor.owner, let author = editor.reviewEditing.author,
              owner.model.comments.isEmpty, owner.model.tables.isEmpty, owner.model.tablesOfContents.isEmpty,
              range.location >= 0, range.length >= 0, range.location <= editor.storage.length,
              range.length <= editor.storage.length - range.location else { return nil }
        let text = editor.storage.string as NSString
        let previous = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: range.location))
        let start = previous.location == NSNotFound ? 0 : NSMaxRange(previous)
        let following = text.range(of: "\n", range: NSRange(location: range.location, length: text.length - range.location))
        let end = following.location == NSNotFound ? text.length : following.location
        guard NSMaxRange(range) <= end else { return nil }
        let hasSeparator = end < text.length
        let extent = NSRange(location: start, length: end - start + (hasSeparator ? 1 : 0))
        guard extent.length <= 8192 else { return nil }
        if extent.length == 0, view.selectedRange().location != range.location { return nil }
        let attributes = extent.length > 0 ? editor.storage.attributes(at: start, effectiveRange: nil) : view.typingAttributes
        guard attributes[.scribeList] == nil, attributes[.scribeCell] == nil, attributes[.scribeTOC] == nil,
              let id = attributes[.scribeParagraphID] as? String, UUID(uuidString: id) != nil else { return nil }
        let source = editor.storage.attributedSubstring(from: extent)
        var unsupported = source.string.contains("\u{fffc}")
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, _, stop in
            if attributes[.attachment] != nil || attributes[.scribeComments] != nil || attributes[.scribeNote] != nil ||
                attributes[.scribeImage] != nil || attributes[.scribeEquation] != nil || attributes[.scribeList] != nil ||
                attributes[.scribeCell] != nil || attributes[.scribeTOC] != nil {
                unsupported = true; stop.pointee = true
            }
        }
        guard !unsupported else { return nil }
        var isolated = ScribeDocument(); isolated.styles = owner.model.styles
        isolated.sections[0].page = owner.model.sections[0].page
        // A trailing empty sentinel represents the existing boundary. Its ID
        // never enters storage; it permits validation of that boundary's review.
        if hasSeparator { isolated.sections[0].paragraphs.append(Paragraph()) }
        isolated = AttributedDocument.capture(source, preserving: isolated, typingAttributes: extent.length == 0 ? attributes : nil)
        let paragraph = isolated.paragraphs[0]
        let prefix = paragraph.pageBreakBefore ? 1 : 0
        guard range.location >= start + prefix else { return nil }
        _ = try isolated.splitTrackedParagraph(id: paragraph.id,
            range: NSRange(location: range.location - start - prefix, length: range.length), author: author)
        let projected = AttributedDocument.render(isolated)
        let boundary = (projected.string as NSString).range(of: "\n")
        guard boundary.location != NSNotFound else { throw DocumentError.invalid("the paragraph split has no separator") }
        let insertion = NSMaxRange(boundary), continuation = isolated.paragraphs[1]
        let typing = continuation.text.isEmpty ? AttributedDocument.editingAttributes(for: continuation, in: isolated) : projected.attributes(at: insertion, effectiveRange: nil)
        return Self(range: extent, value: projected, caret: start + insertion, typingAttributes: typing, validatedLength: source.length)
    }
}
#endif
