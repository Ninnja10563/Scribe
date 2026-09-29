#if canImport(AppKit)
import AppKit

@MainActor enum NativeDialogCapture {
    static func save(_ view: NSView, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size, flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill(); rect.fill()
            if let cgImage = bitmap.cgImage {
                NSImage(cgImage: cgImage, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let composited = NSBitmapImageRep(data: tiff),
              let png = composited.representation(using: .png, properties: [:]) else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
