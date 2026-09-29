#if canImport(AppKit)
import AppKit
import CoreText
import DocumentCore

/// Baseline-relative vector layout. Coordinates increase upward, as in Core Text.
/// TextKit attachments and PDF output can draw the same immutable display list.
struct EquationLayout {
    enum Mark {
        case text(CTLine, CGPoint)
        case rule(CGPoint, CGPoint, CGFloat)
        func translated(x: CGFloat, y: CGFloat) -> Mark {
            switch self {
            case .text(let line, let point): return .text(line, CGPoint(x: point.x + x, y: point.y + y))
            case .rule(let a, let b, let width): return .rule(CGPoint(x: a.x + x, y: a.y + y), CGPoint(x: b.x + x, y: b.y + y), width)
            }
        }
    }
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var marks: [Mark] = []
    var height: CGFloat { ascent + descent }
    var size: CGSize { CGSize(width: width, height: height) }

    init(equation: Equation) {
        self = Self.layout(equation.expression, size: CGFloat(equation.pointSize))
    }
    private init(width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0, marks: [Mark] = []) {
        self.width = width; self.ascent = ascent; self.descent = descent; self.marks = marks
    }
    mutating func place(_ box: EquationLayout, x: CGFloat, y: CGFloat = 0) {
        width = max(width, x + box.width)
        ascent = max(ascent, y + box.ascent); descent = max(descent, box.descent - y)
        marks += box.marks.map { $0.translated(x: x, y: y) }
    }
    func draw(in context: CGContext, baseline: CGPoint) {
        context.saveGState()
        context.translateBy(x: baseline.x, y: baseline.y)
        context.setFillColor(NSColor.black.cgColor); context.setStrokeColor(NSColor.black.cgColor)
        context.textMatrix = .identity
        for mark in marks {
            switch mark {
            case .text(let line, let point): context.textPosition = point; CTLineDraw(line, context)
            case .rule(let a, let b, let thickness):
                context.setLineWidth(thickness); context.move(to: a); context.addLine(to: b); context.strokePath()
            }
        }
        context.restoreGState()
    }
    private static func text(_ source: String, size: CGFloat, italic: Bool = false) -> EquationLayout {
        let content = italic ? MathFont.italic(source) : source.replacingOccurrences(of: "-", with: "−")
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): MathFont.font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: content, attributes: attributes) as CFAttributedString)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let inset = max(0, -ink.minX)
        return EquationLayout(width: max(advance, ink.maxX) + inset, ascent: max(0, ink.maxY), descent: max(0, -ink.minY), marks: [.text(line, CGPoint(x: inset, y: 0))])
    }
    private static func layout(_ expression: MathExpression, size: CGFloat) -> EquationLayout {
        let m = MathFont.Metrics(size: size)
        let small = max(4, size * m.scriptScale)
        switch expression {
        case .token(let value, let italic): return text(value, size: size, italic: italic)
        case .largeOperator(let value): return text(value, size: size * 1.4)
        case .space(let em): return EquationLayout(width: CGFloat(em) * size)
        case .row(let values):
            var result = EquationLayout()
            for (index, value) in values.enumerated() {
                let gap: CGFloat
                if case .token(let symbol, _) = value, ["=", "+", "-", "×", "÷", "≤", "≥", "≠", "≈", "→"].contains(symbol), index > 0 {
                    gap = size * 0.16
                } else { gap = 0 }
                result.place(layout(value, size: size), x: result.width + gap)
                result.width += gap
            }
            return result
        case .fraction(let numerator, let denominator):
            let top = layout(numerator, size: small), bottom = layout(denominator, size: small)
            let width = max(top.width, bottom.width) + size * 0.3
            let topY = max(m.value(28, fallback: 0.65), m.axis + m.rule / 2 + m.value(32, fallback: 0.12) + top.descent)
            let bottomY = min(-m.value(30, fallback: 0.65), m.axis - m.rule / 2 - m.value(35, fallback: 0.12) - bottom.ascent)
            var result = EquationLayout(width: width)
            result.place(top, x: (width - top.width) / 2, y: topY)
            result.place(bottom, x: (width - bottom.width) / 2, y: bottomY)
            result.marks.append(.rule(CGPoint(x: 0, y: m.axis), CGPoint(x: width, y: m.axis), m.rule))
            return result
        case .scripts(let base, let lower, let upper):
            let body = layout(base, size: size)
            let sub = lower.map { layout($0, size: small) }, sup = upper.map { layout($0, size: small) }
            var result = body
            if case .largeOperator(let symbol) = base, symbol != "∫" {
                let width = max(body.width, max(sub?.width ?? 0, sup?.width ?? 0))
                result = EquationLayout(width: width)
                result.place(body, x: (width - body.width) / 2)
                if let sup { result.place(sup, x: (width - sup.width) / 2, y: body.ascent + m.value(14, fallback: 0.12) + sup.descent) }
                if let sub { result.place(sub, x: (width - sub.width) / 2, y: -body.descent - m.value(16, fallback: 0.12) - sub.ascent) }
            } else {
                let upperY = max(m.value(7, fallback: 0.45), body.ascent - m.value(10, fallback: 0.2), (sup?.descent ?? 0) + m.value(9, fallback: 0.1))
                var lowerY = -max(m.value(4, fallback: 0.25), (sub?.ascent ?? 0) - m.value(5, fallback: 0.3), body.descent + m.value(6, fallback: 0.1))
                if let sup, let sub { lowerY = min(lowerY, upperY - sup.descent - sub.ascent - m.value(11, fallback: 0.16)) }
                if let sup { result.place(sup, x: body.width + size * 0.04, y: upperY) }
                if let sub { result.place(sub, x: body.width, y: lowerY) }
                result.width += m.value(13, fallback: 0.04)
            }
            return result
        case .radical(let radicand, let degree):
            let body = layout(radicand, size: size)
            let rootDegree = degree.map { layout($0, size: max(4, size * 0.6)) }
            let inset = max(0, (rootDegree?.width ?? 0) - size * 0.25)
            let thickness = max(0.2, m.value(47, fallback: 0.04))
            let top = body.ascent + m.value(45, fallback: 0.12) + thickness
            let bottom = -body.descent
            let rootWidth = size * 0.65
            var result = EquationLayout(width: inset + rootWidth + body.width + size * 0.1, ascent: top + thickness, descent: body.descent)
            result.place(body, x: inset + rootWidth)
            // Constructed radical and vinculum remain vector paths at any zoom.
            let points = [CGPoint(x: inset, y: bottom + (top - bottom) * 0.35), CGPoint(x: inset + rootWidth * 0.23, y: bottom + (top - bottom) * 0.43), CGPoint(x: inset + rootWidth * 0.48, y: bottom), CGPoint(x: inset + rootWidth * 0.86, y: top), CGPoint(x: result.width, y: top)]
            for index in 1..<points.count { result.marks.append(.rule(points[index - 1], points[index], thickness)) }
            if let rootDegree { result.place(rootDegree, x: 0, y: bottom + (top - bottom) * 0.62) }
            return result
        case .delimited(let left, let body, let right):
            let center = layout(body, size: size)
            func delimiter(_ value: String) -> EquationLayout {
                guard !value.isEmpty else { return EquationLayout() }
                let normal = text(value, size: size)
                let target = max(normal.height, center.height + size * 0.15)
                return text(value, size: size * target / max(1, normal.height))
            }
            let leading = delimiter(left), trailing = delimiter(right)
            var result = EquationLayout()
            result.place(leading, x: 0, y: m.axis - (leading.ascent - leading.descent) / 2)
            result.place(center, x: result.width + size * 0.04)
            result.place(trailing, x: result.width + size * 0.04, y: m.axis - (trailing.ascent - trailing.descent) / 2)
            return result
        }
    }
}
#endif
