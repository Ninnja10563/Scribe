import Foundation
import DocumentCore

enum DOCXImageAdjustments {
    static func geometry(_ image: InlineImage) -> (width: Int, height: Int, effects: String, rotation: String, crop: String, opacity: String) {
        let settings = image.adjustments
        let size = settings?.unrotatedSize(frameWidth: image.width, frameHeight: image.height) ?? (width: image.width, height: image.height)
        let width = Int((size.width * 12700).rounded()), height = Int((size.height * 12700).rounded())
        let x = Int(((image.width - size.width) / 2 * 12700).rounded()), y = Int(((image.height - size.height) / 2 * 12700).rounded())
        let effects = settings?.rotation != nil && settings?.rotation != 0 ? "<wp:effectExtent l=\"\(x)\" t=\"\(y)\" r=\"\(x)\" b=\"\(y)\"/>" : ""
        let rotation = settings.map { " rot=\"\(Int(($0.rotation * 60000).rounded()))\"" } ?? ""
        let crop = settings.map { value in
            let c = value.crop
            return "<a:srcRect l=\"\(Int((c.left * 100000).rounded()))\" t=\"\(Int((c.top * 100000).rounded()))\" r=\"\(Int((c.right * 100000).rounded()))\" b=\"\(Int((c.bottom * 100000).rounded()))\"/>"
        } ?? ""
        let opacity = settings.map { "<a:alphaModFix amt=\"\(Int(($0.opacity * 100000).rounded()))\"/>" } ?? ""
        return (width, height, effects, rotation, crop, opacity)
    }
}

final class DOCXImageReader {
    private var target: String?, width = 100.0, height = 100.0, shapeWidth: Double?, shapeHeight: Double?, description = ""
    private var crop = ImageCrop(), rotation = 0.0, opacity = 1.0
    func reset() { target = nil; width = 100; height = 100; shapeWidth = nil; shapeHeight = nil; description = ""; crop = ImageCrop(); rotation = 0; opacity = 1 }
    func start(_ name: String, namespace: String?, attributes a: [String: String], targets: [String: String], warnings: inout Set<String>) {
        if name == "extent", let cx = a["cx"].flatMap(Double.init), let cy = a["cy"].flatMap(Double.init) { width = cx / 12700; height = cy / 12700 }
        if name == "docPr" { description = a["descr"] ?? a["name"] ?? "" }
        if name == "blip", let id = a["r:embed"] ?? a["embed"] { target = targets[id] }
        if name == "anchor" { warnings.insert("Floating images are imported inline with the text.") }
        guard namespace == "http://schemas.openxmlformats.org/drawingml/2006/main" else { return }
        if name == "ext", let cx = a["cx"].flatMap(Double.init), let cy = a["cy"].flatMap(Double.init) { shapeWidth = cx / 12700; shapeHeight = cy / 12700 }
        if name == "xfrm" {
            if let value = a["rot"].flatMap(Double.init) { rotation = value / 60000 }
            if a["flipH"] == "1" || a["flipV"] == "1" || a["flipH"] == "true" || a["flipV"] == "true" { warnings.insert("Image mirroring is not yet imported.") }
        }
        if name == "srcRect" {
            func fraction(_ key: String) -> Double { (a[key].flatMap(Double.init) ?? 0) / 100000 }
            crop = ImageCrop(left: fraction("l"), top: fraction("t"), right: fraction("r"), bottom: fraction("b"))
            if !crop.isValid { crop = ImageCrop(); warnings.insert("An unsupported image crop was omitted; the source image was retained.") }
        }
        if name == "alphaModFix", let amount = a["amt"].flatMap(Double.init) {
            opacity *= amount / 100000
            if !opacity.isFinite || !(0...1).contains(opacity) { opacity = min(1, max(0, opacity.isFinite ? opacity : 1)); warnings.insert("An image alpha effect was limited to the supported opacity range.") }
        }
    }
    func image(files: [String: Data], page: PageSettings, warnings: inout Set<String>) -> InlineImage? {
        guard let target, let data = files["word/" + target], ["png", "jpg", "jpeg", "tiff", "heic"].contains((target as NSString).pathExtension.lowercased()) else {
            warnings.insert("An unsupported or missing image was omitted."); return nil
        }
        let w = max(1, shapeWidth ?? width), h = max(1, shapeHeight ?? height)
        let sourceAspect = w / h * crop.visibleHeight / crop.visibleWidth
        let sourceWidth = w / crop.visibleWidth
        let source = InlineImage(data: data, fileExtension: (target as NSString).pathExtension.lowercased(), width: sourceWidth, height: sourceWidth / sourceAspect, altText: description)
        do { return try source.adjusted(crop: crop, rotation: rotation, opacity: opacity, sourceWidth: sourceWidth, maximumWidth: page.contentWidth, maximumHeight: page.contentHeight - 24) }
        catch {
            warnings.insert("Unsupported image geometry was simplified; the source image was retained.")
            let scale = min(1, page.contentWidth / max(1, width), (page.contentHeight - 24) / max(1, height))
            return InlineImage(data: data, fileExtension: source.fileExtension, width: max(1, width * scale), height: max(1, height * scale), altText: description)
        }
    }
}
