import Foundation

/// Expected page-end offsets after plain-text insertions. A matching boundary beyond
/// every insertion permits unchanged following pages to retain their containers.
struct PaginationStability {
    private(set) var expectedEnds: [Int]?
    private(set) var editedEnd = 0
    mutating func invalidate() { expectedEnds = nil; editedEnd = 0 }
    mutating func insert(at location: Int, length: Int, previousEnds: [Int], startingClean: Bool) {
        if startingClean { expectedEnds = previousEnds; editedEnd = 0 }
        guard expectedEnds != nil else { return }
        for index in expectedEnds!.indices where expectedEnds![index] >= location { expectedEnds![index] += length }
        if editedEnd >= location { editedEnd += length }
        editedEnd = max(editedEnd, location + length)
    }
    func canStop(after index: Int, characterEnd: Int, documentLength: Int) -> Bool {
        guard let ends = expectedEnds, index + 1 < ends.count, ends.last == documentLength else { return false }
        return characterEnd < documentLength && characterEnd >= editedEnd && ends[index] == characterEnd
    }
    func remainingRanges(after index: Int) -> [NSRange] {
        guard let ends = expectedEnds, index + 1 < ends.count else { return [] }
        return ((index + 1)..<ends.count).map { NSRange(location: ends[$0 - 1], length: ends[$0] - ends[$0 - 1]) }
    }
}
