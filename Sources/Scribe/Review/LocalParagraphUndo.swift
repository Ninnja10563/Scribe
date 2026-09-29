#if canImport(AppKit)
import AppKit

@MainActor struct LocalParagraphUndoState {
    let location: Int
    let value: NSAttributedString
    let selection: NSRange
    let typingAttributes: [NSAttributedString.Key: Any]
}

@MainActor enum LocalParagraphUndo {
    static func register(before: LocalParagraphUndoState, after: LocalParagraphUndoState,
                         owner: ScribeFileDocument, action: String) {
        owner.undoManager?.registerUndo(withTarget: owner) { target in
            MainActor.assumeIsolated { restore(from: after, to: before, owner: target, action: action) }
        }
        owner.undoManager?.setActionName(action)
    }
    private static func restore(from source: LocalParagraphUndoState, to target: LocalParagraphUndoState,
                                owner: ScribeFileDocument, action: String) {
        guard let editor = owner.editingEditor, editor.owner != nil,
              source.location >= 0, source.location <= editor.storage.length,
              source.value.length <= editor.storage.length - source.location else { return }
        register(before: source, after: target, owner: owner, action: action)
        editor.storage.replaceCharacters(in: NSRange(location: source.location, length: source.value.length), with: target.value)
        editor.activeTextView.typingAttributes = target.typingAttributes
        editor.activeTextView.didChangeText()
        editor.select(target.selection)
        editor.activeTextView.typingAttributes = target.typingAttributes
    }
}
#endif
