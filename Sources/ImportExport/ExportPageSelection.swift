import Foundation

public enum ExportPageSelection {
    public struct InvalidRange: LocalizedError {
        public let pageCount: Int
        public var errorDescription: String? { "Enter page numbers from 1 to \(pageCount), for example 1, 3–5. Leave Pages blank to export every page." }
    }
    /// User-facing numbers are one based. Output is deduplicated in document order.
    public static func indices(_ expression: String, pageCount: Int) throws -> [Int] {
        guard (1...1_000_000).contains(pageCount) else { throw InvalidRange(pageCount: pageCount) }
        let input = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return Array(0..<pageCount) }
        var pages = Set<Int>()
        for component in input.replacingOccurrences(of: "–", with: "-").components(separatedBy: ",") {
            let bounds = component.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(bounds.count), let start = Int(bounds[0]), (1...pageCount).contains(start),
                  let end = Int(bounds.last!), (start...pageCount).contains(end) else { throw InvalidRange(pageCount: pageCount) }
            pages.formUnion((start...end).map { $0 - 1 })
        }
        return pages.sorted()
    }
}
