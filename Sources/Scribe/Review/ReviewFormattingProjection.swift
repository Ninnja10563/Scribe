#if canImport(AppKit)
import AppKit
import DocumentCore

extension ReviewTextProjection {
    static func formatting(_ original: NSAttributedString, as changed: NSAttributedString,
                           identity: RevisionIdentity, styles: [ParagraphStyle], recordsChange: Bool = true) throws -> NSAttributedString {
        guard original.string == changed.string else { throw DocumentError.invalid("formatting revision changes text") }
        let result = NSMutableAttributedString(attributedString: changed)
        let text = original.string as NSString
        var offset = 0
        while offset < original.length {
            var oldRange = NSRange(), newRange = NSRange()
            let old = original.attributes(at: offset, effectiveRange: &oldRange)
            let new = changed.attributes(at: offset, effectiveRange: &newRange)
            let end = min(NSMaxRange(oldRange), NSMaxRange(newRange))
            let range = NSRange(location: offset, length: end - offset)
            defer { offset = end }
            let review = try (old[.scribeReview] as? Data).map { try JSONDecoder().decode(RunReview.self, from: $0) }
            if review?.deletion != nil { result.setAttributes(old, range: range); continue }
            let style = styles.first { $0.id == (old[.scribeStyle] as? String) } ?? .normal
            let before = AttributedDocument.captureTextFormat(old, style: style), after = AttributedDocument.captureTextFormat(new, style: style)
            let semantic = review?.preservingFormatting(before, inheriting: style.text) ?? before
            let updated = semantic.applyingDifference(from: before, to: after)
            guard updated != semantic else { continue }
            var run = TextRun(text.substring(with: range), format: semantic); run.review = review
            var tracked = RevisionText(runs: [run])
            try tracked.format(NSRange(location: 0, length: range.length), identity: identity) { _ in updated }
            if !recordsChange { tracked.accept(identity.id) }
            let metadata = tracked.runs.first?.review
            // Paragraph marks have a separate insertion/deletion history. Character
            // formatting history belongs only to the actual text between them.
            var start = offset
            while start < end {
                if text.character(at: start) == 10 { start += 1; continue }
                var finish = start + 1
                while finish < end, text.character(at: finish) != 10 { finish += 1 }
                let extent = NSRange(location: start, length: finish - start)
                if let metadata { result.addAttribute(.scribeReview, value: try encoded(metadata), range: extent) }
                else { result.removeAttribute(.scribeReview, range: extent) }
                start = finish
            }
        }
        return result
    }
}
#endif
