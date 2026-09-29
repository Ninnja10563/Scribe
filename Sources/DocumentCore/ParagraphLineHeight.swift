import Foundation

/// Explicit height semantics, separate from the legacy extra gap between lines.
public struct ParagraphLineHeight: Codable, Equatable, Sendable {
    public enum Rule: String, Codable, CaseIterable, Sendable { case multiple, minimum, exact }
    public var rule: Rule
    public var value: Double
    public init(rule: Rule, value: Double) { self.rule = rule; self.value = value }
    public func validate() throws {
        let range = rule == .multiple ? 0.1...10.0 : 1.0...4000.0
        guard value.isFinite, range.contains(value) else {
            throw DocumentError.invalid("line-height multiples must be 0.1–10; point heights must be 1–4000")
        }
    }
}
