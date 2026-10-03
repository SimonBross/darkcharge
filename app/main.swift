// DarkCharge menu bar app: turns the MagSafe LED off, always or whenever the built-in screen is dark.
// The root daemon (darkcharge daemon) does the SMC writes and watches the lid and system
// sleep; this app installs it, and tells it when the screen is asleep or fully dimmed,
// which only something in the user's session can see. Messages go via Darwin notifications.

import AppKit
import ServiceManagement
import notify

let donateURL = URL(string: "https://ko-fi.com/simonbross")!

let installedBinary = "/usr/local/bin/darkcharge"
let daemonPlist = "/Library/LaunchDaemons/com.darkcharge.daemon.plist"

// Menu bar icon: a MagSafe 3 plug seen from above, cable coming in from the left.
// While the LED is lit, a dot is cut out where the LED sits.
func plugIcon(ledLit: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 3.5, y: 7.6, width: 5, height: 2.8), xRadius: 0.5, yRadius: 0.5).fill()

        // Slightly rounded on the cable side, square on the magnetic face.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 16.5, y: 2))
        body.line(to: NSPoint(x: 16.5, y: 16))
        body.appendArc(from: NSPoint(x: 8, y: 16), to: NSPoint(x: 8, y: 2), radius: 1)
        body.appendArc(from: NSPoint(x: 8, y: 2), to: NSPoint(x: 16.5, y: 2), radius: 1)
        body.close()
        if ledLit {
            body.append(NSBezierPath(ovalIn: NSRect(x: 11.25, y: 8, width: 2, height: 2)))
            body.windingRule = .evenOdd
        }
        body.fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "DarkCharge"
    return image
}

// Watches the built-in screen from the user's session and reports when it stops giving
// off light: asleep, fully dimmed, or gone (lid closed with an external display).
final class ScreenWatcher {
    var onChange: (Bool) -> Void = { _ in }
    private(set) var isDark = false
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    // Private API, but the only way to read the built-in screen's brightness on Apple Silicon.
    private let getBrightness: GetBrightnessFn? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightnessFn.self) }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.check() }
        }
        // Brightness changes have no notification, so poll for those.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        check()
    }

    private var builtInDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func screenIsDark() -> Bool {
        guard let display = builtInDisplay else { return true }
        if CGDisplayIsAsleep(display) != 0 { return true }
        var brightness: Float = 1
        guard let getBrightness, getBrightness(display, &brightness) == 0 else { return false }
        return brightness <= 0.001
    }

    func check() {
        let dark = screenIsDark()
        guard dark != isDark else { return }
        isDark = dark
        onChange(dark)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Turn Off Charging LED", action: #selector(toggle), keyEquivalent: "")
    private let screenDarkItem = NSMenuItem(title: "Whenever the screen is dark", action: #selector(setScreenDark), keyEquivalent: "")
    private let alwaysItem = NSMenuItem(title: "Always", action: #selector(setAlways), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let smc = try? SMC()
    private let screen = ScreenWatcher()

    private var bundledBinary: String { Bundle.main.path(forResource: "darkcharge", ofType: nil)! }
    private var bundledPlist: String { Bundle.main.path(forResource: "com.darkcharge.daemon", ofType: "plist")! }

    private var hidingEnabled: Bool {
        FileManager.default.fileExists(atPath: daemonPlist) && !FileManager.default.fileExists(atPath: pausedFile)
    }

    private var iconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "iconHidden") }
        set { UserDefaults.standard.set(newValue, forKey: "iconHidden") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        for item in [screenDarkItem, alwaysItem] {
            item.target = self
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let donateItem = NSMenuItem(title: "Donate", action: #selector(donate), keyEquivalent: "")
        donateItem.target = self
        let donateTitle = NSMutableAttributedString(string: "♥", attributes: [.foregroundColor: NSColor.systemRed])
        donateTitle.append(NSAttributedString(string: " Donate"))
        donateTitle.addAttribute(.font, value: NSFont.menuFont(ofSize: 0), range: NSRange(location: 0, length: donateTitle.length))
        donateItem.attributedTitle = donateTitle
        menu.addItem(donateItem)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Uninstall DarkCharge…", action: #selector(uninstall), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        // A hidden icon stays hidden across restarts while the app launches at login (macOS
        // gives no reliable sign of a login launch). Opening the app again while it runs
        // shows the icon; without Launch at Login, any launch was by hand, so show it.
        statusItem.isVisible = !(iconHidden && SMAppService.mainApp.status == .enabled)
        if statusItem.isVisible { iconHidden = false }
        refresh()
        // After an app update the installed helper may be older and ignore new settings,
        // so bring it up to date straight away, keeping the user's settings.
        if FileManager.default.fileExists(atPath: daemonPlist) && !helperIsCurrent() {
            DispatchQueue.main.async {
                if self.installHelper(hidingEnabled: self.hidingEnabled, always: alwaysOff) { self.helperStarted() }
            }
        }

        screen.onChange = { [weak self] _ in
            self?.reportScreen()
            self?.refreshSoon()
        }
        reportScreen()
        // Heartbeat; also covers a daemon that restarted and lost the last report.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reportScreen() }
        // Keep the icon in step while the menu is closed.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // Quitting hands the LED back to macOS right away. If the app dies without getting
    // here, the daemon notices the missing heartbeat within half a minute.
    func applicationWillTerminate(_ notification: Notification) {
        send(notifyScreen, state: appQuitting)
    }

    // Also the heartbeat that keeps the daemon active.
    private func reportScreen() { send(notifyScreen, state: screen.isDark ? screenDark : screenLit) }

    // A freshly started daemon doesn't know about the screen yet.
    private func helperStarted() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.reportScreen() }
        refreshSoon()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        toggleItem.state = hidingEnabled ? .on : .off
        screenDarkItem.state = alwaysOff ? .off : .on
        alwaysItem.state = alwaysOff ? .on : .off
        // What the LED is actually doing, straight from the SMC.
        statusItem.button?.image = plugIcon(ledLit: (try? smc?.read(ledKey)) != [ledOff])
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // The daemon applies changes asynchronously; look again once it has.
    private func refreshSoon() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    @objc private func toggle() {
        let turnOff = !hidingEnabled
        if helperIsCurrent() {
            notify_post(turnOff ? notifyOff : notifyOn)
            refreshSoon()
        } else if installHelper(hidingEnabled: turnOff, always: alwaysOff) {
            helperStarted()
        }
    }

    @objc private func setScreenDark() { setMode(always: false) }
    @objc private func setAlways() { setMode(always: true) }

    // Picking a mode also turns the feature on; that's what choosing one implies.
    private func setMode(always: Bool) {
        if helperIsCurrent() {
            send(notifyMode, state: always ? 1 : 0)
            if !hidingEnabled { notify_post(notifyOff) }
            refreshSoon()
        } else if installHelper(hidingEnabled: true, always: always) {
            helperStarted()
        }
    }

    private func send(_ name: String, state: UInt64) {
        var token: Int32 = 0
        notify_register_check(name, &token)
        notify_set_state(token, state)
        notify_post(name)
        notify_cancel(token)
    }

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

    // The LED keeps its setting while hidden; the daemon does the work, not this app.
    // Opening the app again brings the icon back.
    @objc private func hideIcon() {
        statusItem.isVisible = false
        iconHidden = true
    }

    @objc private func donate() { NSWorkspace.shared.open(donateURL) }

    // Opening the app again while it's running brings the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem.isVisible = true
        iconHidden = false
        return false
    }

    private func helperIsCurrent() -> Bool {
        FileManager.default.fileExists(atPath: daemonPlist)
            && (try? String(contentsOfFile: versionFile, encoding: .utf8)) == helperVersion
    }

    // Removes everything DarkCharge put on the Mac and gives the LED back to macOS, then
    // moves the app to the Trash (recoverable) and quits. Cancelling the password prompt
    // leaves everything as it was.
    @objc private func uninstall() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Uninstall DarkCharge?"
        alert.informativeText = "The charging LED goes back to normal, the background helper is removed, "
            + "and DarkCharge moves to the Trash. macOS will ask for your password."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if FileManager.default.fileExists(atPath: daemonPlist) || FileManager.default.fileExists(atPath: installedBinary) {
            // `darkcharge on` after stopping the daemon hands the LED back if it was off.
            let removed = runAsAdmin([
                "launchctl bootout system/com.darkcharge.daemon 2>/dev/null",
                "[ -x \(installedBinary) ] && \(installedBinary) on",
                "rm -f \(installedBinary) \(daemonPlist)",
                "rm -rf '\(supportDir)'",
            ], prompt: "DarkCharge needs to remove its helper.")
            guard removed else { return }
        }
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // Copies the daemon out of the app bundle and starts it with the requested settings.
    // Asks for an admin password; only needed on first use or after an update.
    private func installHelper(hidingEnabled: Bool, always: Bool) -> Bool {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return runAsAdmin([
            "launchctl bootout system/com.darkcharge.daemon 2>/dev/null",
            "mkdir -p /usr/local/bin",
            "install -m 755 \(q(bundledBinary)) \(installedBinary)",
            "install -m 644 \(q(bundledPlist)) \(daemonPlist)",
            "\(installedBinary) mode \(always ? "always" : "screen")",
            "\(installedBinary) \(hidingEnabled ? "off" : "on")",
            "launchctl bootstrap system \(daemonPlist)",
        ], prompt: "DarkCharge needs to install or update its helper to control the charging LED.")
    }

    // Runs shell commands as root behind the standard macOS password prompt. Returns false
    // if the user cancels.
    private func runAsAdmin(_ commands: [String], prompt: String) -> Bool {
        let shell = commands.joined(separator: "; ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
