#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum DocumentSpelling {
    static func findNext(in view: ScribeTextView) {
        guard let editor = view.editor, let document = editor.owner, editor.storage.length > 0 else { return }
        let checker = NSSpellChecker.shared
        if document.model.language != "und" {
            let installed = checker.availableLanguages.compactMap { try? DocumentMetadata.languageIdentifier($0) }
            guard installed.contains(document.model.language) else {
                document.editorController?.showStatus("The spelling dictionary for \(label(for: document.model.language)) is unavailable on this Mac."); return
            }
        }
        var types = NSTextCheckingResult.CheckingType.spelling.rawValue
        let options = options(document: document.model, original: [:], types: &types)
        let results = checker.check(editor.storage.string, range: NSRange(location: 0, length: editor.storage.length), types: types, options: options, inSpellDocumentWithTag: view.spellCheckerDocumentTag, orthography: nil, wordCount: nil)
            .filter { $0.resultType == .spelling }.sorted { $0.range.location < $1.range.location }
        let end = NSMaxRange(view.selectedRange())
        guard let next = results.first(where: { $0.range.location >= end }) ?? results.first else {
            document.editorController?.showStatus("No spelling errors found."); return
        }
        editor.select(next.range)
    }
    static func label(for identifier: String) -> String {
        if identifier == "und" { return "Automatic language" }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
    static func options(document: ScribeDocument, original: [NSSpellChecker.OptionKey: Any], types: UnsafeMutablePointer<NSTextCheckingTypes>) -> [NSSpellChecker.OptionKey: Any] {
        var options = original
        options[.documentTitle] = document.title; options[.documentAuthor] = document.author
        if document.language != "und" {
            // Disable automatic orthography detection for this request only.
            // Other open documents and the system spell-checker preference are untouched.
            types.pointee &= ~NSTextCheckingResult.CheckingType.orthography.rawValue
            options[.orthography] = NSOrthography.defaultOrthography(forLanguage: document.language)
        } else {
            types.pointee |= NSTextCheckingResult.CheckingType.orthography.rawValue
            options.removeValue(forKey: .orthography)
        }
        return options
    }
}

extension PaginatedEditor {
    func textView(_ view: NSTextView, willCheckTextIn range: NSRange, options: [NSSpellChecker.OptionKey: Any], types checkingTypes: UnsafeMutablePointer<NSTextCheckingTypes>) -> [NSSpellChecker.OptionKey: Any] {
        guard let owner else { return options }
        return DocumentSpelling.options(document: owner.model, original: options, types: checkingTypes)
    }
}
#endif
