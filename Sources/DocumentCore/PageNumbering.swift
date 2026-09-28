import Foundation

public struct PageNumbering: Codable, Equatable, Sendable {
    public enum Position: String, Codable, Sendable, CaseIterable { case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight }
    public enum Format: String, Codable, Sendable, CaseIterable { case decimal, roman, page, pageOfTotal }
    public var position: Position
    public var format: Format
    public var start: Int
    public init(position: Position = .bottomCenter, format: Format = .pageOfTotal, start: Int = 1) {
        self.position = position; self.format = format; self.start = start
    }
    public func label(pageIndex: Int, pageCount: Int) -> String {
        let number = start + pageIndex
        switch format {
        case .decimal: return String(number)
        case .page: return "Page \(number)"
        case .pageOfTotal: return "Page \(number) of \(start + pageCount - 1)"
        case .roman:
            var numbering = ListNumbering()
            return String((numbering.marker(for: ListDescriptor(kind: .lowerRoman, start: number)) ?? "\(number).").dropLast())
        }
    }
}
