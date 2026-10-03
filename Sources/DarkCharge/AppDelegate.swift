// The menu bar item and its menu. Keeps the helper informed through heartbeats: the
// user's settings plus whether the built-in screen is dark.

import AppKit
import DarkChargeCore
import ServiceManagement
import notify

private let donateURL = URL(string: "https://ko-fi.com/simonbross")!

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Turn Off Charging LED", action: #selector(toggle), keyEquivalent: "")
    private let screenDarkItem = NSMenuItem(title: "Whenever the screen is dark", action: #selector(chooseScreenDark),
                                            keyEquivalent: "")
    private let alwaysItem = NSMenuItem(title: "Always", action: #selector(chooseAlways), keyEquivalent: "")
    private let approvalItem = NSMenuItem(title: "Allow Helper in System Settings…", action: #selector(openSettings),
                                          keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let smc = try? SMC()
    private let screen = ScreenWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.menu = buildMenu()
        // A hidden icon stays hidden across restarts while the app launches at login (macOS
        // gives no reliable sign of a login launch). Opening the app again while it runs
        // shows the icon; without Launch at Login, any launch was by hand, so show it.
        statusItem.isVisible = !(Settings.iconHidden && SMAppService.mainApp.status == .enabled)
        if statusItem.isVisible { Settings.iconHidden = false }

        if Settings.enabled { HelperService.ensureRunning(askUser: false) }
        screen.onChange = { [weak self] _ in
            self?.sendHeartbeat()
            self?.refreshSoon()
        }
        sendHeartbeat()
        refresh()
        // Heartbeat, well within the helper's timeout. Also refreshes the icon.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sendHeartbeat()
                self?.refresh()
            }
        }
    }

    // Quitting hands the LED back to macOS right away. If the app dies without getting
    // here, the helper notices the missing heartbeats within half a minute.
    func applicationWillTerminate(_ notification: Notification) {
        sendHeartbeat(quitting: true)
    }

    // Opening the app again while it runs brings a hidden icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem.isVisible = true
        Settings.iconHidden = false
        return false
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(toggleItem)
        for item in [screenDarkItem, alwaysItem] {
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(approvalItem)
        menu.addItem(.separator())
        menu.addItem(donateItem())
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        return menu
    }

    private func donateItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Donate", action: #selector(donate), keyEquivalent: "")
        let title = NSMutableAttributedString(string: "♥", attributes: [.foregroundColor: NSColor.systemRed])
        title.append(NSAttributedString(string: " Donate"))
        title.addAttribute(.font, value: NSFont.menuFont(ofSize: 0), range: NSRange(location: 0, length: title.length))
        item.attributedTitle = title
        return item
    }

    private func refresh() {
        toggleItem.state = Settings.enabled ? .on : .off
        screenDarkItem.state = Settings.always ? .off : .on
        alwaysItem.state = Settings.always ? .on : .off
        approvalItem.isHidden = !(Settings.enabled && HelperService.needsApproval)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // What the LED is actually doing, straight from the SMC.
        statusItem.button?.image = plugIcon(ledLit: !(smc.map { MagSafeLED.isOff(using: $0) } ?? false))
    }

    // The helper applies changes asynchronously; look again once it has.
    private func refreshSoon() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    // MARK: - Actions

    @objc private func toggle() {
        Settings.enabled.toggle()
        settingsChanged()
    }

    // Picking a mode also turns the feature on; that's what choosing one implies.
    @objc private func chooseScreenDark() { choose(always: false) }
    @objc private func chooseAlways() { choose(always: true) }

    private func choose(always: Bool) {
        Settings.always = always
        Settings.enabled = true
        settingsChanged()
    }

    private func settingsChanged() {
        if Settings.enabled { HelperService.ensureRunning(askUser: true) }
        sendHeartbeat()
        refreshSoon()
    }

    @objc private func openSettings() { HelperService.openSystemSettings() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    // The LED keeps doing its job while the icon is hidden.
    @objc private func hideIcon() {
        statusItem.isVisible = false
        Settings.iconHidden = true
    }

    @objc private func donate() { NSWorkspace.shared.open(donateURL) }

    // MARK: - Heartbeat

    private func sendHeartbeat(quitting: Bool = false) {
        let beat = Heartbeat(enabled: Settings.enabled, always: Settings.always,
                             screenDark: screen.isDark, quitting: quitting)
        var token: Int32 = 0
        notify_register_check(Heartbeat.notificationName, &token)
        notify_set_state(token, beat.state)
        notify_post(Heartbeat.notificationName)
        notify_cancel(token)
    }
}
