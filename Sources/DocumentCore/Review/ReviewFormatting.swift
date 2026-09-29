import Foundation

extension TextFormatting {
    /// Freeze the old paragraph's character appearance before merging it into a
    /// differently styled paragraph. Explicit family also suppresses a new face.
    func materialized(over inherited: TextFormatting) -> TextFormatting {
        var value = self
        value.fontFamily = fontFamily ?? inherited.fontFamily ?? "Helvetica Neue"
        value.fontFace = fontFace ?? (fontFamily == nil ? inherited.fontFace : nil)
        value.fontSize = fontSize ?? inherited.fontSize ?? 12
        value.bold = bold ?? inherited.bold ?? false
        value.italic = italic ?? inherited.italic ?? false
        value.underline = underline ?? inherited.underline ?? false
        value.strikethrough = strikethrough ?? inherited.strikethrough ?? false
        value.baseline = baseline ?? inherited.baseline ?? 0
        value.foreground = foreground ?? inherited.foreground ?? "#1D1D1F"
        value.highlight = clearHighlight == true ? nil : highlight ?? (inherited.clearHighlight == true ? nil : inherited.highlight)
        value.clearHighlight = value.highlight == nil ? true : nil
        return value
    }
}

extension TextRun {
    func materializingReviewFormatting(over inherited: TextFormatting) -> TextRun {
        var run = self
        run.format = format.materialized(over: inherited)
        if var review {
            review.formattingBase = review.formattingBase?.materialized(over: inherited)
            review.formatting = review.formatting.map {
                var revision = $0
                revision.before = revision.before.materialized(over: inherited)
                revision.after = revision.after.materialized(over: inherited)
                return revision
            }
            run.review = review
        }
        return run
    }
}
