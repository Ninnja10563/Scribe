import Foundation

public extension ScribeDocument {
    var pendingRevisionIDs: [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for paragraph in paragraphs + notes.flatMap(\.paragraphs) {
            var ids = paragraph.runs.flatMap { $0.review?.pendingIDs ?? [] }
            ids += paragraph.breakReview?.pendingIDs ?? []
            ids += paragraph.formattingReview?.pendingIDs ?? []
            result += ids.filter { seen.insert($0).inserted }
        }
        return result
    }
    mutating func resolveRevision(_ id: UUID, accepting: Bool) throws {
        try resolveRevisions(revisionGroup(containing: id), accepting: accepting)
    }
    mutating func resolveAllRevisions(accepting: Bool) throws {
        try resolveRevisions(Set(pendingRevisionIDs), accepting: accepting)
    }
    private mutating func resolveRevisions(_ ids: Set<UUID>, accepting: Bool) throws {
        try NativeFormat.validate(self)
        guard !ids.isDisjoint(with: pendingRevisionIDs) else { return }
        var candidate = self, removed: [NSRange] = [], offset = 0
        var mergedParagraphs: [UUID: UUID] = [:]
        func resolve(_ paragraph: inout Paragraph, body: Bool) {
            if var review = paragraph.formattingReview {
                for id in review.pendingIDs where ids.contains(id) { review.resolve(id, accepting: accepting) }
                review.state.apply(to: &paragraph)
                paragraph.formattingReview = review.pendingIDs.isEmpty ? nil : review
            }
            for run in paragraph.runs {
                let length = (run.text as NSString).length
                let discarded = accepting ? run.review?.deletion?.id : run.review?.insertion?.id
                if body, let discarded, ids.contains(discarded), length > 0 { removed.append(NSRange(location: offset, length: length)) }
                if body { offset += length }
            }
            var text = RevisionText(runs: paragraph.runs)
            let order = text.pendingIDs.filter { ids.contains($0) }
            for id in accepting ? order : Array(order.reversed()) {
                if accepting { text.accept(id) } else { text.reject(id) }
            }
            paragraph.runs = text.runs.isEmpty ? [TextRun("", format: paragraph.runs.first?.format ?? TextFormatting())] : text.runs
            if body { offset += 1 } // Paragraph separators are outside this run operation.
        }
        func resolveFlow(_ source: [Paragraph], body: Bool) throws -> [Paragraph] {
            var result: [Paragraph] = [], mergeNext = false
            for var paragraph in source {
                let originalBreak = paragraph.breakReview
                resolve(&paragraph, body: body)
                var mark = TextRun("\n"); mark.review = originalBreak
                var separator = RevisionText(runs: [mark])
                let order = separator.pendingIDs.filter { ids.contains($0) }
                for id in accepting ? order : Array(order.reversed()) {
                    if accepting { separator.accept(id) } else { separator.reject(id) }
                }
                let removedBreak = separator.runs.isEmpty
                paragraph.breakReview = separator.runs.first?.review
                if removedBreak, body { removed.append(NSRange(location: offset - 1, length: 1)) }
                if mergeNext, let previous = result.indices.last {
                    guard Set(paragraph.formattingReview?.pendingIDs ?? []).isSubset(of: Set(result[previous].formattingReview?.pendingIDs ?? [])) else {
                        throw DocumentError.invalid("resolve this paragraph’s formatting changes before joining it to the previous paragraph")
                    }
                    if body { mergedParagraphs[paragraph.id] = result[previous].id }
                    var incoming = paragraph.runs
                    if paragraph.styleID != result[previous].styleID {
                        let inherited = style(for: paragraph).text
                        incoming = incoming.map { $0.materializingReviewFormatting(over: inherited) }
                    }
                    // Do not assemble the growing paragraph merely to test emptiness,
                    // or retain a copy of it while appending (which forces COW).
                    if result[previous].runs.allSatisfy({ $0.text.isEmpty }) { result[previous].runs = [] }
                    result[previous].runs += incoming
                    result[previous].breakReview = paragraph.breakReview
                } else { result.append(paragraph) }
                mergeNext = removedBreak
            }
            for index in result.indices { result[index].runs = RevisionText.coalescing(result[index].runs) }
            return result
        }
        for section in candidate.sections.indices {
            candidate.sections[section].paragraphs = try resolveFlow(candidate.sections[section].paragraphs, body: true)
        }
        for note in candidate.notes.indices {
            candidate.notes[note].paragraphs = try resolveFlow(candidate.notes[note].paragraphs, body: false)
        }
        for index in candidate.bookmarks.indices {
            if let destination = mergedParagraphs[candidate.bookmarks[index].anchor.paragraphID] {
                candidate.bookmarks[index].anchor = TextAnchor(paragraphID: destination, offset: 0, length: 0)
            }
        }
        candidate.rebaseReviewComments(from: paragraphs, removing: removed)
        candidate.reconcileNotes()
        try NativeFormat.validate(candidate)
        self = candidate
    }
}

extension ScribeDocument {
    mutating func rebaseReviewComments(from original: [Paragraph], removing ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }
        let before = DocumentTextIndex(paragraphs: original), after = DocumentTextIndex(paragraphs: paragraphs)
        // Removed runs arrive in document order. Prefix sums avoid scanning every
        // removal for each annotation in documents with many review decisions.
        var ends: [Int] = [], totals: [Int] = [0]
        for range in ranges { ends.append(NSMaxRange(range)); totals.append(totals.last! + range.length) }
        func position(_ value: Int) -> Int {
            var low = 0, high = ends.count
            while low < high {
                let middle = (low + high) / 2
                if ends[middle] <= value { low = middle + 1 } else { high = middle }
            }
            let partial = low < ranges.count ? max(0, value - ranges[low].location) : 0
            return value - totals[low] - partial
        }
        for index in comments.indices where comments[index].isDetached != true {
            guard let range = before.range(for: comments[index].anchor) else { comments[index].isDetached = true; continue }
            let start = position(range.location), end = position(NSMaxRange(range))
            guard !(range.length > 0 && end == start), let anchor = after.anchor(for: NSRange(location: start, length: end - start)) else {
                comments[index].isDetached = true; continue
            }
            comments[index].anchor = anchor
        }
    }
}
