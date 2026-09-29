import Foundation

extension ScribeDocument {
    /// A pasted paragraph's formatting belongs to its insertion group. When
    /// its draft boundary disappears, original text must not acquire frozen
    /// copies of that temporary formatting and lose its style inheritance.
    mutating func prepareGroupedDraftJoin(section: Int, index: Int, insertion: RevisionIdentity) throws {
        guard let group = insertion.groupID else { return }
        let previous = sections[section].paragraphs[index]
        var next = sections[section].paragraphs[index + 1]
        let previousChanges = Set(previous.formattingReview?.changes.map { $0.identity.id } ?? [])
        let independent = next.formattingReview?.changes.filter {
            !previousChanges.contains($0.identity.id) && $0.identity.groupID != group
        } ?? []
        guard independent.allSatisfy({ !$0.accepted && $0.identity.author.id == insertion.author.id && $0.identity.date >= insertion.date }) else {
            throw DocumentError.invalid("resolve this paragraph’s independent formatting before joining it")
        }
        if next.formattingReview == nil {
            var baseline = previous.formattingReview?.changes.first(where: { $0.identity.groupID == group })?.before ?? ParagraphRevisionState(previous)
            baseline.pageBreakBefore = false; baseline.list?.restart = nil
            guard ParagraphRevisionState(next) == baseline else {
                throw DocumentError.invalid("resolve the pasted paragraph’s formatting before joining it")
            }
        }
        let appearance = style(for: next).text
        next.runs = next.runs.map { run in
            run.review?.insertion?.groupID == group ? run.materializingReviewFormatting(over: appearance) : run
        }
        // The surviving paragraph owns paragraph properties after a join.
        // Keep its history, and keep original runs inheriting that history.
        ParagraphRevisionState(previous).apply(to: &next)
        next.formattingReview = previous.formattingReview
        sections[section].paragraphs[index + 1] = next
    }
}
