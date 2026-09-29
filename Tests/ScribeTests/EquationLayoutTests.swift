#if canImport(AppKit)
import AppKit
import CoreText
import PDFKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class EquationLayoutTests: XCTestCase {
    func testBundledMathFontAndNativeVectorLayout() throws {
        XCTAssertTrue(MathFont.isAvailable)
        XCTAssertEqual(CTFontCopyPostScriptName(MathFont.font(size: 18)) as String, "STIXTwoMath-Regular")
        let metrics = MathFont.Metrics(size: 20)
        XCTAssertGreaterThan(metrics.axis, 0); XCTAssertGreaterThan(metrics.rule, 0)
        XCTAssertGreaterThan(metrics.scriptScale, 0.5); XCTAssertLessThan(metrics.scriptScale, 1)
        let sources = [#"x^2+5x+6=0"#, #"x=\frac{-b+\sqrt{b^2-4ac}}{2a}"#, #"\sum_{i=1}^{n}i=\frac{n(n+1)}{2}"#, #"\int_0^1 x^2=\frac{1}{3}"#, #"\sqrt[3]{\frac{x+1}{y-2}}"#, #"\left(\frac{\alpha}{\beta}\right)^2"#, #"\text{Area}=\pi r^2"#]
        let destination = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent("EquationLayout.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        for (index, source) in sources.enumerated() {
            let layout = EquationLayout(equation: try Equation(source: source, pointSize: 24))
            XCTAssertTrue(layout.width.isFinite && layout.height.isFinite)
            XCTAssertGreaterThan(layout.width, 0); XCTAssertGreaterThan(layout.height, 0)
            XCTAssertLessThan(layout.width, 500); XCTAssertLessThan(layout.height, 90)
            layout.draw(in: context, baseline: CGPoint(x: 54, y: 730 - CGFloat(index) * 100))
        }
        context.endPDFPage(); context.closePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Area") == true, "Equation text must remain vector/searchable in the PDF")
        let fraction = EquationLayout(equation: try Equation(source: #"\frac{a}{b}"#))
        let plain = EquationLayout(equation: try Equation(source: "a"))
        XCTAssertGreaterThan(fraction.height, plain.height * 1.5)
        XCTAssertTrue(fraction.marks.contains { if case .rule = $0 { return true }; return false })
        let double = EquationLayout(equation: try Equation(source: #"\frac{a}{b}"#, pointSize: 36))
        XCTAssertEqual(double.width, fraction.width * 2, accuracy: 0.01)
        XCTAssertEqual(double.height, fraction.height * 2, accuracy: 0.01)
    }
}
#endif
