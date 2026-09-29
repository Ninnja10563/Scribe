import XCTest
@testable import DocumentCore

final class EquationTests: XCTestCase {
    func testFractionsRootsScriptsAndOperatorsHaveSemanticStructure() throws {
        let equation = try Equation(source: #"\frac{-b+\sqrt{b^2-4ac}}{2a}"#)
        guard case .fraction(let numerator, let denominator) = equation.expression else { return XCTFail("Missing fraction") }
        guard case .row(let top) = numerator, case .radical(let value, nil) = top.last else { return XCTFail("Missing root") }
        guard case .row(let radicand) = value, case .scripts(.token("b", true), nil, .some(.token("2", false))) = radicand.first else { return XCTFail("Missing power") }
        XCTAssertTrue(equation.expression.accessibilityText.contains("numerator"))
        XCTAssertEqual(try MathParser.parse("12+3").accessibilityText, "12 plus 3")
        XCTAssertEqual(denominator, .row([.token("2", italic: false), .token("a", italic: true)]))
        XCTAssertEqual(try MathParser.parse(#"\sum_{i=1}^{n}"#), .scripts(base: .largeOperator("∑"), lower: .row([.token("i", italic: true), .token("=", italic: false), .token("1", italic: false)]), upper: .token("n", italic: true)))
        XCTAssertEqual(try MathParser.parse(#"\sqrt[3]{x}"#), .radical(radicand: .token("x", italic: true), degree: .token("3", italic: false)))
    }
    func testUnicodeTextAndStretchingDelimitersRoundTrip() throws {
        let equation = try Equation(source: #"\left[\frac{\alpha}{2}\right]+\text{résumé 👩🏽‍💻}"#, pointSize: 24)
        XCTAssertEqual(try JSONDecoder().decode(Equation.self, from: JSONEncoder().encode(equation)), equation)
        XCTAssertEqual(try MathParser.parse(#"\text{a \{b\}}"#), .token("a {b}", italic: false))
    }
    func testInvalidIncompleteAndExcessivelyNestedInputIsRejected() {
        for source in ["", "x^", "x_}", #"\frac{1}"#, #"\frac{}{2}"#, #"\sqrt{x"#, #"\unknown{x}"#, "x^2^3", "(x]", #"\left(x"#, "x)"] {
            XCTAssertThrowsError(try Equation(source: source), source)
        }
        XCTAssertThrowsError(try Equation(source: String(repeating: "{", count: 40) + "x" + String(repeating: "}", count: 40)))
        XCTAssertThrowsError(try Equation(source: String(repeating: "x", count: 3000)))
        XCTAssertThrowsError(try Equation(source: String(repeating: "x", count: 9000)))
        XCTAssertThrowsError(try Equation(source: "x", pointSize: .infinity))
        XCTAssertThrowsError(try Equation(source: "\\text{bad\u{0}text}"))
    }
}
