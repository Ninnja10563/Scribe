#if canImport(AppKit) && canImport(Sparkle)
import AppKit
import Sparkle

@MainActor final class SoftwareUpdates: NSObject, NSMenuItemValidation {
    static let shared = SoftwareUpdates()
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    func start() { controller.startUpdater() }
    func addMenuItems(to menu: NSMenu) {
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = controller; menu.addItem(check)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleChecks), keyEquivalent: "")
        automatic.target = self; menu.addItem(automatic)
        let install = NSMenuItem(title: "Automatically Download and Install Updates", action: #selector(toggleInstallation), keyEquivalent: "")
        install.target = self; menu.addItem(install)
        menu.addItem(.separator())
    }
    @objc private func toggleChecks() { controller.updater.automaticallyChecksForUpdates.toggle() }
    @objc private func toggleInstallation() {
        controller.updater.automaticallyDownloadsUpdates.toggle()
        if controller.updater.automaticallyDownloadsUpdates { controller.updater.automaticallyChecksForUpdates = true }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleChecks) { item.state = controller.updater.automaticallyChecksForUpdates ? .on : .off }
        if item.action == #selector(toggleInstallation) { item.state = controller.updater.automaticallyDownloadsUpdates ? .on : .off }
        return true
    }
}
#endif
