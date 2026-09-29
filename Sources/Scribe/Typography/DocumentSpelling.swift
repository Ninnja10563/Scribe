#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum DocumentSpelling {
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
