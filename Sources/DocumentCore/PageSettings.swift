import Foundation

public struct PageSettings: Codable, Equatable, Sendable {
    public enum Paper: String, CaseIterable, Codable, Sendable { case a4 = "A4", letter = "US Letter", legal = "US Legal" }
    public var width = 595.276
    public var height = 841.89
    public var top = 72.0
    public var bottom = 72.0
    public var left = 72.0
    public var right = 72.0
    public init() {}
    public init(paper: Paper, landscape: Bool = false) {
        switch paper {
        case .a4: width = 595.276; height = 841.89
        case .letter: width = 612; height = 792
        case .legal: width = 612; height = 1008
        }
        if landscape { swap(&width, &height) }
    }
    public var contentWidth: Double { width - left - right }
    public var contentHeight: Double { height - top - bottom }
    public var isValid: Bool {
        [width, height, top, bottom, left, right].allSatisfy { $0.isFinite && $0 >= 0 }
        && width <= 4000 && height <= 4000 && contentWidth >= 72 && contentHeight >= 72
    }
}
