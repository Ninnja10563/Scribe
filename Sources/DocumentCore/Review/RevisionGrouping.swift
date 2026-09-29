import Foundation

extension ScribeDocument {
    /// Kind-specific identities remain distinct. Grouping only expands the
    /// requested decision; it never conflates an insertion with a deletion or
    /// discards independent formatting history on the same paragraph.
    func revisionGroup(containing id: UUID) -> Set<UUID> {
        var identities: [RevisionIdentity] = []
        func append(_ review: RunReview?) {
            guard let review else { return }
            if let identity = review.insertion { identities.append(identity) }
            if let identity = review.deletion { identities.append(identity) }
            identities += review.formatting.map(\.identity)
        }
        for paragraph in paragraphs + notes.flatMap(\.paragraphs) {
            append(paragraph.breakReview)
            identities += paragraph.formattingReview?.changes.map(\.identity) ?? []
            for run in paragraph.runs { append(run.review) }
        }
        guard let group = identities.first(where: { $0.id == id })?.groupID else { return [id] }
        return Set(identities.filter { $0.groupID == group }.map(\.id))
    }
}
