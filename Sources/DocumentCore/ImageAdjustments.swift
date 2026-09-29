import Foundation

/// Fractions removed from the original image, measured from its unrotated edges.
public struct ImageCrop: Codable, Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double
    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public var visibleWidth: Double { 1 - left - right }
    public var visibleHeight: Double { 1 - top - bottom }
    public var isValid: Bool {
        [left, top, right, bottom].allSatisfy { $0.isFinite && (0...1).contains($0) } && visibleWidth >= 0.0001 && visibleHeight >= 0.0001
    }
}

/// Source bytes remain unchanged. Width/height on InlineImage describe the
/// resulting rotated frame; sourceAspectRatio retains the original proportions.
public struct ImageAdjustments: Codable, Equatable, Sendable {
    public var crop: ImageCrop
    public var rotation: Double // Clockwise degrees in [0, 360).
    public var opacity: Double
    public var sourceAspectRatio: Double
    public init(crop: ImageCrop = ImageCrop(), rotation: Double = 0, opacity: Double = 1, sourceAspectRatio: Double) {
        self.crop = crop; self.rotation = rotation; self.opacity = opacity; self.sourceAspectRatio = sourceAspectRatio
    }
    public var isValid: Bool {
        crop.isValid && rotation.isFinite && (0..<360).contains(rotation) && opacity.isFinite && (0...1).contains(opacity) && sourceAspectRatio.isFinite && sourceAspectRatio > 0 && sourceAspectRatio <= 1_000_000_000
    }
    public var croppedAspectRatio: Double { sourceAspectRatio * crop.visibleWidth / crop.visibleHeight }
    public var frameAspectRatio: Double {
        let angle = rotation * .pi / 180, c = abs(cos(angle)), s = abs(sin(angle)), ratio = croppedAspectRatio
        return (c * ratio + s) / (s * ratio + c)
    }
    public func unrotatedSize(frameWidth: Double, frameHeight: Double) -> (width: Double, height: Double) {
        let angle = rotation * .pi / 180, c = abs(cos(angle)), s = abs(sin(angle)), ratio = croppedAspectRatio
        let scale = min(frameWidth / (c * ratio + s), frameHeight / (s * ratio + c))
        return (ratio * scale, scale)
    }
}

extension InlineImage {
    public var sourceDisplayWidth: Double {
        guard let settings = adjustments else { return width }
        return settings.unrotatedSize(frameWidth: width, frameHeight: height).width / settings.crop.visibleWidth
    }
    public func adjusted(crop: ImageCrop, rotation: Double, opacity: Double, sourceWidth: Double, maximumWidth: Double, maximumHeight: Double) throws -> InlineImage {
        guard rotation.isFinite, sourceWidth.isFinite, sourceWidth > 0, maximumWidth.isFinite, maximumHeight.isFinite, maximumWidth >= 1, maximumHeight >= 1 else { throw DocumentError.invalid("invalid image dimensions or rotation") }
        let normalized = rotation.truncatingRemainder(dividingBy: 360)
        let settings = ImageAdjustments(crop: crop, rotation: normalized < 0 ? normalized + 360 : normalized, opacity: opacity, sourceAspectRatio: adjustments?.sourceAspectRatio ?? self.width / self.height)
        guard settings.isValid else { throw DocumentError.invalid("crop edges must leave some image visible and opacity must be 0–100%") }
        let angle = settings.rotation * .pi / 180, c = abs(cos(angle)), s = abs(sin(angle))
        let croppedWidth = sourceWidth * crop.visibleWidth, croppedHeight = sourceWidth / settings.sourceAspectRatio * crop.visibleHeight
        let width = c * croppedWidth + s * croppedHeight, height = s * croppedWidth + c * croppedHeight
        let scale = min(1, maximumWidth / width, maximumHeight / height)
        var result = self; result.width = width * scale; result.height = height * scale
        guard result.width >= 1, result.height >= 1, result.width <= 4000, result.height <= 4000 else { throw DocumentError.invalid("the adjusted image is too narrow or tall for this page") }
        result.adjustments = settings.crop == ImageCrop() && settings.rotation == 0 && settings.opacity == 1 ? nil : settings
        return result
    }
}
