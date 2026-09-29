#if canImport(AppKit)
import AppKit
import CoreText

/// A process-local, pinned font keeps equation geometry independent of installed fonts.
enum MathFont {
    private static let registered: Bool = {
        let url = Bundle.main.url(forResource: "STIXTwoMath-Regular", withExtension: "otf", subdirectory: "MathFont")
            ?? Bundle.module.url(forResource: "STIXTwoMath-Regular", withExtension: "otf", subdirectory: "MathFont")
        guard let url else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // A test host may already have registered the same font.
        return (CTFontCopyPostScriptName(CTFontCreateWithName("STIXTwoMath-Regular" as CFString, 12, nil)) as String) == "STIXTwoMath-Regular"
    }()
    static func font(size: CGFloat) -> CTFont {
        _ = registered
        return CTFontCreateWithName("STIXTwoMath-Regular" as CFString, size, nil)
    }
    static var isAvailable: Bool { registered }
    private static let mathData = CTFontCopyTable(font(size: 20), 0x4D415448, []) as Data? ?? Data()
    private static let unitsPerEm = CGFloat(max(1, CTFontGetUnitsPerEm(font(size: 20))))

    /// OpenType MATH constants are signed big-endian font units, not pixels.
    /// https://learn.microsoft.com/en-us/typography/opentype/spec/math
    struct Metrics {
        let size: CGFloat
        private let data: Data
        private let constants: Int
        private let scale: CGFloat
        init(size: CGFloat) {
            self.size = size
            data = MathFont.mathData
            constants = data.count >= 6 ? Int(data[4]) << 8 | Int(data[5]) : 0
            scale = size / MathFont.unitsPerEm
        }
        private func signed(_ offset: Int) -> Int? {
            guard constants > 0, offset >= 0, offset + 1 < data.count else { return nil }
            return Int(Int16(bitPattern: UInt16(data[offset]) << 8 | UInt16(data[offset + 1])))
        }
        func value(_ index: Int, fallback: CGFloat) -> CGFloat {
            signed(constants + 8 + index * 4).map { CGFloat($0) * scale } ?? fallback * size
        }
        var scriptScale: CGFloat { CGFloat(signed(constants) ?? 80) / 100 }
        var axis: CGFloat { value(1, fallback: 0.25) }
        var rule: CGFloat { max(0.2, value(34, fallback: 0.04)) }
    }

    static func italic(_ string: String) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.map { scalar in
            let value = scalar.value
            if value == 0x68 { return Unicode.Scalar(0x210E)! }
            if (0x41...0x5A).contains(value) { return Unicode.Scalar(value - 0x41 + 0x1D434)! }
            if (0x61...0x7A).contains(value) { return Unicode.Scalar(value - 0x61 + 0x1D44E)! }
            if (0x3B1...0x3C9).contains(value) { return Unicode.Scalar(value - 0x3B1 + 0x1D6FC)! }
            return scalar
        }))
    }
}
#endif
