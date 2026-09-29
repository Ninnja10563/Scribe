import Foundation

/// Position on the physical page containing the image's semantic text anchor.
/// Coordinates are points from that page's left and top writing margins.
public struct FloatingImagePlacement: Codable, Equatable, Sendable {
    public enum Wrapping: String, Codable, CaseIterable, Sendable {
        case square, behindText, inFrontOfText
    }
    public var x: Double
    public var y: Double
    public var wrapping: Wrapping
    public var textDistance: Double
    public var zOrder: Int
    public init(x: Double, y: Double, wrapping: Wrapping = .square, textDistance: Double = 8, zOrder: Int = 0) {
        self.x = x; self.y = y; self.wrapping = wrapping
        self.textDistance = textDistance; self.zOrder = zOrder
    }
    public func validate() throws {
        guard x.isFinite, y.isFinite, (0...4000).contains(x), (0...4000).contains(y),
              textDistance.isFinite, (0...200).contains(textDistance), (0...1_000_000).contains(zOrder) else {
            throw DocumentError.invalid("invalid floating image position or wrapping distance")
        }
    }
}

public extension ScribeDocument {
    var hasFloatingImages: Bool {
        (paragraphs + notes.flatMap(\.paragraphs)).contains { $0.runs.contains { $0.image?.placement != nil } }
    }
}
