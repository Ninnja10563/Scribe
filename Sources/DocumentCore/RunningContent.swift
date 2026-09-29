import Foundation

/// Alternate running text is retained when its display option is switched off.
public struct RunningContentVariants: Codable, Equatable, Sendable {
    /// Retains imported numbering parity even when no page-number field is displayed.
    public var startingPageNumber: Int?
    public var differentFirstPage = false
    public var differentOddEvenPages = false
    public var firstHeader = ""
    public var firstFooter = ""
    public var evenHeader = ""
    public var evenFooter = ""
    public init() {}
    public func text(defaultText: String, isHeader: Bool, pageIndex: Int, startingNumber: Int) -> String {
        if pageIndex == 0 && differentFirstPage { return isHeader ? firstHeader : firstFooter }
        if differentOddEvenPages && (startingNumber + pageIndex).isMultiple(of: 2) { return isHeader ? evenHeader : evenFooter }
        return defaultText
    }
}

public extension Section {
    /// Numbered-page parity follows the section's starting page number.
    func runningText(isHeader: Bool, pageIndex: Int) -> String {
        let fallback = isHeader ? header : footer
        return runningContent?.text(defaultText: fallback, isHeader: isHeader, pageIndex: pageIndex, startingNumber: pageNumbering?.start ?? runningContent?.startingPageNumber ?? 1) ?? fallback
    }
}
