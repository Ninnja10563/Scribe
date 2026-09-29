import Foundation
import DocumentCore

/// Development-only anchored drawing export; public interchange remains gated.
/// Office positions are EMUs relative to the physical page's writing margins.
enum DOCXFloatingImages {
    static func validate(_ document: ScribeDocument) throws {
        for section in document.sections {
            for image in section.paragraphs.flatMap(\.runs).compactMap(\.image) {
                guard let placement = image.placement else { continue }
                guard (image.adjustments?.rotation ?? 0) == 0 else {
                    throw DocumentError.invalid("rotated floating-image DOCX geometry is still being implemented")
                }
                guard placement.x + image.width <= section.page.contentWidth,
                      placement.y + image.height <= section.page.contentHeight else {
                    throw DocumentError.invalid("a floating image extends beyond the page's writing area")
                }
            }
        }
    }
    static func container(_ placement: FloatingImagePlacement?) -> (open: String, wrap: String, close: String) {
        guard let placement else {
            return ("<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">", "", "</wp:inline>")
        }
        let distance = Int((placement.textDistance * 12700).rounded())
        let x = Int((placement.x * 12700).rounded()), y = Int((placement.y * 12700).rounded())
        let behind = placement.wrapping == .behindText ? "1" : "0"
        let open = "<wp:anchor distT=\"\(distance)\" distB=\"\(distance)\" distL=\"\(distance)\" distR=\"\(distance)\" simplePos=\"0\" relativeHeight=\"\(placement.zOrder)\" behindDoc=\"\(behind)\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"margin\"><wp:posOffset>\(x)</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"margin\"><wp:posOffset>\(y)</wp:posOffset></wp:positionV>"
        let wrap = placement.wrapping == .square ? "<wp:wrapSquare wrapText=\"bothSides\"/>" : "<wp:wrapNone/>"
        return (open, wrap, "</wp:anchor>")
    }
}
