#if canImport(AppKit)
import AppKit
import DocumentCore

@MainActor enum ExternalTextProjection {
    static func render(_ value: NSAttributedString, includeImages: Bool) throws -> NSAttributedString {
        let text = ScriptProjection.external(value)
        if includeImages { return try ExternalEquationProjection.render(ExternalImageProjection.render(text)) }
        let result = NSMutableAttributedString(attributedString: text)
        var replacements: [(NSRange, String)] = []
        text.enumerateAttribute(.scribeEquation, in: NSRange(location: 0, length: text.length)) { data, range, _ in
            if let data = data as? Data, let equation = try? JSONDecoder().decode(Equation.self, from: data) { replacements.append((range, "[Equation: \(equation.source)]")) }
        }
        for (range, source) in replacements.reversed() {
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment); attributes.removeValue(forKey: .scribeEquation)
            result.replaceCharacters(in: range, with: NSAttributedString(string: source, attributes: attributes))
        }
        return result
    }
}
#endif
