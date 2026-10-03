import AppKit
import ServiceManagement
import os

// The root helper, bundled in the app (Contents/Library/LaunchDaemons) and registered with
// SMAppService. macOS asks the user to allow it once in System Settings; no password and
// no files outside the app. Deleting the app takes the helper with it.
@MainActor
enum HelperService {
    private static let service = SMAppService.daemon(plistName: "com.darkcharge.daemon.plist")
    private static let log = Logger(subsystem: "com.darkcharge", category: "app")

    static var needsApproval: Bool { service.status == .requiresApproval }

    // Registers the helper if it isn't yet. When `askUser` is set and macOS needs the user's
    // approval, explains that and offers to open System Settings.
    static func ensureRunning(askUser: Bool) {
        if service.status == .enabled { return }
        do {
            try service.register()
        } catch {
            // Registering a helper that still awaits approval reports an error; that's fine.
            if service.status != .requiresApproval {
                log.error("Could not register the helper: \(String(describing: error), privacy: .public)")
                if askUser { showError(error) }
                return
            }
        }
        if askUser && service.status == .requiresApproval { askForApproval() }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    private static func askForApproval() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow DarkCharge in System Settings"
        alert.informativeText = "DarkCharge needs a small background helper to switch the charging LED. "
            + "Turn on DarkCharge under Login Items & Extensions → Allow in the Background."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { openSystemSettings() }
    }

    private static func showError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.messageText = "DarkCharge couldn't start its helper"
        alert.runModal()
    }
}
