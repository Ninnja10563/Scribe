import Foundation

/// Editing operations over semantic runs in one flow fragment. Coordinates are
/// UTF-16 in the review projection, which retains pending deletions. Paragraph
/// boundary editing is handled by the document transaction layer, not this type.
public struct RevisionText: Equatable, Sendable {
    public private(set) var runs: [TextRun]
    public init(runs: [TextRun]) { self.runs = runs }
    public var markupText: String { runs.map(\.text).joined() }
    public var finalText: String { runs.filter { $0.review?.deletion == nil }.map(\.text).joined() }
    public var pendingIDs: [UUID] {
        var seen = Set<UUID>()
        return runs.flatMap { $0.review?.pendingIDs ?? [] }.filter { seen.insert($0).inserted }
    }

    /// Replacement retains original deleted runs and inserts independently
    /// reviewable content. Editing one's own pending insertion simply revises it.
    @discardableResult public mutating func replace(_ range: NSRange, with inserted: [TextRun],
                                                     insertion: RevisionIdentity, deletion: RevisionIdentity) throws -> Int {
        let parts = try split(range)
        var removed: [TextRun] = []
        for var run in parts.selected {
            if run.review?.insertion?.author.id == deletion.author.id, run.review?.deletion == nil { continue }
            var review = run.review ?? RunReview()
            if review.deletion == nil { review.deletion = deletion }
            run.review = review; removed.append(run)
        }
        let additions = inserted.filter { !$0.text.isEmpty }.map { run -> TextRun in
            var value = run, review = RunReview(); review.insertion = insertion
            value.review = review; return value
        }
        runs = Self.coalescing(parts.before + removed + additions + parts.after)
        return range.location + (removed + additions).reduce(0) { $0 + ($1.text as NSString).length }
    }

    public mutating func format(_ range: NSRange, identity: RevisionIdentity,
                                 transform: (TextFormatting) -> TextFormatting) throws {
        let parts = try split(range)
        let changed = parts.selected.map { run -> TextRun in
            guard run.review?.deletion == nil else { return run }
            var value = run
            let result = transform(run.format)
            guard result != run.format else { return run }
            var review = run.review ?? RunReview()
            if review.formatting.isEmpty { review.formattingBase = run.format }
            review.formatting.append(FormattingRevision(identity: identity, before: run.format, after: result))
            value.format = result; value.review = review; return value
        }
        runs = Self.coalescing(parts.before + changed + parts.after)
    }

    public mutating func accept(_ id: UUID) { resolve(id, accepting: true) }
    public mutating func reject(_ id: UUID) { resolve(id, accepting: false) }
    public mutating func acceptAll() { for id in pendingIDs { accept(id) } }
    public mutating func rejectAll() { for id in pendingIDs.reversed() { reject(id) } }

    private mutating func resolve(_ id: UUID, accepting: Bool) {
        runs = Self.coalescing(runs.compactMap { original in
            guard var review = original.review else { return original }
            var run = original
            if review.insertion?.id == id {
                if !accepting { return nil }; review.insertion = nil
            }
            if review.deletion?.id == id {
                if accepting { return nil }; review.deletion = nil
            }
            if let index = review.formatting.firstIndex(where: { $0.identity.id == id && !$0.accepted }) {
                let base = review.formattingBase ?? review.formatting[0].before
                if accepting { review.formatting[index].accepted = true }
                else { review.formatting.remove(at: index) }
                run.format = review.formatting.reduce(base) { $0.applyingDifference(from: $1.before, to: $1.after) }
                if review.formatting.allSatisfy(\.accepted) { review.formatting = []; review.formattingBase = nil }
            }
            run.review = review.isEmpty ? nil : review
            return run
        })
    }

    private static func coalescing(_ source: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in source {
            if let previous = result.last, previous.format == run.format, previous.link == run.link,
               previous.review == run.review, previous.image == nil, run.image == nil,
               previous.equation == nil, run.equation == nil, previous.noteID == nil, run.noteID == nil {
                result[result.count - 1].text += run.text
            } else { result.append(run) }
        }
        return result
    }

    private func split(_ range: NSRange) throws -> (before: [TextRun], selected: [TextRun], after: [TextRun]) {
        let string = markupText as NSString
        guard range.location >= 0, range.length >= 0, range.location <= string.length,
              range.length <= string.length - range.location else { throw DocumentError.invalid("revision range is outside the text") }
        for offset in [range.location, NSMaxRange(range)] where offset > 0 && offset < string.length {
            guard !(0xD800...0xDBFF).contains(string.character(at: offset - 1)) || !(0xDC00...0xDFFF).contains(string.character(at: offset)) else {
                throw DocumentError.invalid("revision range splits a Unicode scalar")
            }
        }
        var before: [TextRun] = [], selected: [TextRun] = [], after: [TextRun] = [], offset = 0
        for run in runs {
            let text = run.text as NSString, end = offset + text.length
            for (start, finish, region) in [(offset, min(end, range.location), 0), (max(offset, range.location), min(end, NSMaxRange(range)), 1), (max(offset, NSMaxRange(range)), end, 2)] where finish > start {
                var part = run; part.text = text.substring(with: NSRange(location: start - offset, length: finish - start))
                switch region { case 0: before.append(part); case 1: selected.append(part); default: after.append(part) }
            }
            offset = end
        }
        return (before, selected, after)
    }
}
