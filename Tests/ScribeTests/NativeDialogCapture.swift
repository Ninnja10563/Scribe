#if canImport(AppKit)
import AppKit

@MainActor enum NativeDialogCapture {
    static func save(_ view: NSView, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCRIBE_SCHEMA_OUTPUT"],
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
