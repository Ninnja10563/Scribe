#if canImport(AppKit)
import AppKit

/// View state only: zoom never changes document geometry or exported output.
enum DocumentZoomMode: Equatable {
    case factor(CGFloat), fitWidth, fitPage
}
extension PaginatedEditor {
    var zoom: CGFloat {
        get { scrollView.magnification }
        set { selectZoom(.factor(newValue)) }
    }
    func selectZoom(_ mode: DocumentZoomMode) {
        zoomMode = mode; refreshZoom()
    }
    func refreshZoom() {
        guard !isUpdatingZoom else { return }
        let viewport = scrollView.contentView.frame.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        isUpdatingZoom = true; defer { isUpdatingZoom = false }
        let page = canvas.pageSettings, value: CGFloat
        switch zoomMode {
        case .factor(let factor): value = factor
        case .fitWidth: value = viewport.width / (page.width + 2 * canvas.gap)
        case .fitPage: value = min(viewport.width / (page.width + 2 * canvas.gap), viewport.height / (page.height + 2 * canvas.gap))
        }
        let bounded = max(scrollView.minMagnification, min(scrollView.maxMagnification, value))
        if bounded.isFinite, abs(scrollView.magnification - bounded) > 0.0001 {
            scrollView.setMagnification(bounded, centeredAt: scrollView.documentVisibleRect.origin)
        }
        resizeCanvas(); onSelection?()
    }
    @objc func userMagnificationChanged() {
        zoomMode = .factor(scrollView.magnification)
        resizeCanvas(); onSelection?()
    }
}
#endif
