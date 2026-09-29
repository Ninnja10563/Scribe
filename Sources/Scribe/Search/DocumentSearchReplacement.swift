#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum DocumentSearchReplacement {
    /// Prepare and validate every note before changing the live document. Applying
    /// reference replacements through NSTextView keeps their contents in native undo.
    static func apply(_ matches: [DocumentSearchMatch], replacement: String, in editor: PaginatedEditor, action: String) throws {
        guard !matches.isEmpty, let owner = editor.owner else { return }
        let model = owner.snapshot()
        var replacements: [(NSRange, NSAttributedString)] = []
        var noteRanges: [UUID: [NSRange]] = [:]
        let bodyRanges = matches.compactMap { match -> NSRange? in
            if case .body(let range) = match { return range }; return nil
        }
        for match in matches {
            if case .note(let id, let range, _) = match { noteRanges[id, default: []].append(range) }
        }
        var references: [UUID: NSRange] = [:]
        editor.storage.enumerateAttribute(.scribeNote, in: NSRange(location: 0, length: editor.storage.length)) { data, range, _ in
            if let data = data as? Data, let note = try? JSONDecoder().decode(DocumentNote.self, from: data), noteRanges[note.id] != nil {
                references[note.id] = range
            }
        }
        for note in model.notes where noteRanges[note.id] != nil {
            var isolated = ScribeDocument(); isolated.styles = model.styles
            isolated.sections[0].paragraphs = note.paragraphs
            let value = NSMutableAttributedString(attributedString: AttributedDocument.render(isolated))
            let snapshot = SemanticTextSnapshot(value)
            for semantic in noteRanges[note.id]!.sorted(by: { $0.location > $1.location }) {
                guard let range = snapshot.sourceRange(forContentRange: semantic) else { throw DocumentError.invalid("the note search result is no longer available") }
                value.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: textAttributes(value.attributes(at: range.location, effectiveRange: nil))))
            }
            var updated = note
            updated.paragraphs = AttributedDocument.capture(value, preserving: isolated).paragraphs
            guard let reference = references[note.id], !bodyRanges.contains(where: { NSIntersectionRange($0, reference).length > 0 }) else { continue }
            let changed = NSMutableAttributedString(attributedString: editor.storage.attributedSubstring(from: reference))
            changed.addAttribute(.scribeNote, value: try JSONEncoder().encode(updated), range: NSRange(location: 0, length: changed.length))
            replacements.append((reference, changed))
        }
        for range in bodyRanges {
            guard range.length > 0, range.location >= 0, NSMaxRange(range) <= editor.storage.length else { throw DocumentError.invalid("the search result is no longer available") }
            replacements.append((range, NSAttributedString(string: replacement, attributes: textAttributes(editor.storage.attributes(at: range.location, effectiveRange: nil)))))
        }
        replacements.sort { $0.0.location > $1.0.location }
        let proposed = NSMutableAttributedString(attributedString: editor.storage)
        for (range, value) in replacements { proposed.replaceCharacters(in: range, with: value) }
        try NativeFormat.validate(AttributedDocument.capture(proposed, preserving: model))
        let view = editor.activeTextView
        view.breakUndoCoalescing(); view.undoManager?.beginUndoGrouping()
        for (range, value) in replacements {
            view.setSelectedRange(range); view.replaceSelection(value, action: action)
        }
        view.undoManager?.endUndoGrouping(); view.undoManager?.setActionName(action)
        editor.paginate()
    }
    private static func textAttributes(_ original: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = original
        for key in [NSAttributedString.Key.attachment, .scribeImage, .scribeEquation, .scribeNote, .scribeNoteNumber] { result.removeValue(forKey: key) }
        return result
    }
}
#endif
