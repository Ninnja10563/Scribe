#if canImport(AppKit)
import AppKit

/// Proportional corner resizing follows the dominant normalized pointer movement.
/// Either axis can drive a resize; page bounds constrain both dimensions.
enum ImageResizeGeometry {
    static func scale(width: CGFloat, height: CGFloat, horizontalChange: CGFloat, verticalChange: CGFloat,
                      maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        let x = horizontalChange / width, y = verticalChange / height
        let change = abs(x) >= abs(y) ? x : y
        let limit = min(maximumWidth / width, maximumHeight / height)
        return max(0.001, min(limit, max(min(12 / width, 12 / height), 1 + change)))
    }
}
#endif
