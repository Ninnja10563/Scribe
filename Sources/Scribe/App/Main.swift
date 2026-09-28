#if canImport(AppKit)
import AppKit
import DocumentCore

@main struct ScribeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents = ScribeDocumentController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        MainMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--smoke-test") { smokeTest(); return }
        Task {
            let snapshots = (try? await ScribeFileDocument.recovery.snapshots()) ?? []
            for snapshot in snapshots {
                let alert = NSAlert(); alert.messageText = "Recover \(snapshot.document.title)?"
                alert.informativeText = "Scribe found a recovery copy from \(snapshot.savedAt.formatted()). It opens as an unsaved document; the original is kept intact."
                alert.addButton(withTitle: "Recover Copy"); alert.addButton(withTitle: "Keep for Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    let document = ScribeFileDocument(); document.model = snapshot.document
                    document.model.title += " — Recovered"
                    documents.addDocument(document); document.makeWindowControllers(); document.showWindows(); document.updateChangeCount(.changeDone)
                }
            }
            if documents.documents.isEmpty { _ = try? documents.openUntitledDocumentAndDisplay(true) }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            let url = URL(fileURLWithPath: file)
            if url.pathExtension == "scribe" {
                documents.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
            } else { documents.importDocument(url) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Scribe", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "A native document workspace for macOS.\nEarly development release.")])
    }
    private func smokeTest() {
        do {
            let document = ScribeFileDocument()
            document.model.sections[0].paragraphs = [Paragraph("Scribe", style: "title"), Paragraph("A native document workspace", style: "subtitle"), Paragraph("A considered place to write", style: "heading1"), Paragraph("Scribe brings named styles, an outline, flowing pages and familiar macOS editing together. This document exercises the same layout used for PDF and printing.")]
            for i in 1...80 { document.model.sections[0].paragraphs.append(Paragraph("Paragraph \(i). " + String(repeating: "Professional documents need clear structure and dependable editing. ", count: 6))) }
            documents.addDocument(document); document.makeWindowControllers(); document.showWindows()
            guard let controller = document.editorController else { fatalError("Missing editor") }
            controller.editor.paginate()
            let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCRIBE_SMOKE_OUTPUT"] ?? NSTemporaryDirectory())
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try NativeFormat.save(document.snapshot(), to: folder.appendingPathComponent("Smoke.scribe"))
            try PrintRenderer(editor: controller.editor).exportPDF(to: folder.appendingPathComponent("Smoke.pdf"), title: "Scribe Smoke Test", author: "Scribe")
            let pages = controller.editor.textViews.count
            guard pages > 1 else { fatalError("Text did not paginate") }
            controller.window?.displayIfNeeded()
            if let view = controller.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: folder.appendingPathComponent("Scribe.png")) }
            }
            print("Scribe launch smoke test passed: \(pages) pages, native save, PDF and window rendering")
            NSApp.terminate(nil)
        } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
    }
}
#else
import Foundation
@main struct ScribeMain {
    static func main() {
        print("Scribe is a native macOS application. Build on macOS 14 or later. The document core and import/export tests run on Linux with swift test.")
    }
}
#endif
