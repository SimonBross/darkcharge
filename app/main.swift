// DarkCharge menu bar app: hides the MagSafe LED, always or only when the room is dark.
// The root daemon (darkcharge daemon) watches the light sensor and does the actual SMC
// writes; this app installs it on first use and sends it settings via Darwin notifications.
// It reads the sensor and LED itself (no root needed) using shared/Hardware.swift.

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

// Menu row with a slider in whole lux, matching the sensor, which reports whole numbers.
// 0 keeps the LED dark all the time; 1–20 hides it while the room is at or below that level.
final class ThresholdRow: NSView {
    static let minLux = 0.0
    static let maxLux = 20.0
    private let slider = NSSlider(value: 10, minValue: minLux, maxValue: maxLux, target: nil, action: nil)
    private let thresholdLabel = NSTextField(labelWithString: "")
    private let roomLabel = NSTextField(labelWithString: "")
    private var lastSent: Double?
    var onChange: (Double) -> Void = { _ in }

    var threshold: Double {
        get { slider.doubleValue.rounded() }
        set {
            slider.doubleValue = max(Self.minLux, min(Self.maxLux, newValue.rounded()))
            lastSent = threshold
            updateLabel()
        }
    }

    var roomLux: Double? {
        didSet { roomLabel.stringValue = roomLux.map { "Current: \(Self.format($0))" } ?? "" }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        for label in [thresholdLabel, roomLabel] {
            label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }
        thresholdLabel.frame = NSRect(x: 14, y: 28, width: 130, height: 16)
        roomLabel.frame = NSRect(x: 136, y: 28, width: 100, height: 16)
        roomLabel.alignment = .right
        slider.frame = NSRect(x: 12, y: 6, width: 226, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        addSubview(slider)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    static func format(_ lux: Double) -> String { String(format: "%.0f lux", lux) }

    private func updateLabel() {
        thresholdLabel.stringValue = threshold == 0 ? "Always off" : "Turn off at ≤ \(Self.format(threshold))"
    }

    // Snap to whole numbers, and only pass on actual changes.
    @objc private func sliderMoved() {
        updateLabel()
        guard threshold != lastSent else { return }
        lastSent = threshold
        onChange(threshold)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "Turn Off Charging LED", action: #selector(toggle), keyEquivalent: "")
    private let thresholdRow = ThresholdRow()
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var helperCurrent = false
    private var lightTimer: Timer?
    private let lightSensor = LightSensor()
    private let smc = try? SMC()

    private var bundledBinary: String { Bundle.main.path(forResource: "darkcharge", ofType: nil)! }
    private var bundledPlist: String { Bundle.main.path(forResource: "com.darkcharge.daemon", ofType: "plist")! }

    private var hidingEnabled: Bool {
        FileManager.default.fileExists(atPath: daemonPlist) && !FileManager.default.fileExists(atPath: pausedFile)
    }

    // The slider's position: 0 for always dark, otherwise the lux threshold. It's the source
    // of truth; it reaches the daemon right away, or with the next helper install. Without
    // a saved position, it's worked out from the daemon's own settings.
    private var savedLevel: Double {
        if let level = UserDefaults.standard.object(forKey: "level") as? Double { return level }
        guard readOnlyWhenDark() else { return 0 }
        let lux = (try? String(contentsOfFile: thresholdFile, encoding: .utf8))
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? defaultThreshold
        return max(1, min(ThresholdRow.maxLux, lux.rounded()))  // older versions allowed fractions
    }

    private func installHelper(hidingEnabled: Bool, level: Double) -> Bool {
        installHelper(hidingEnabled: hidingEnabled, onlyWhenDark: level > 0,
                      threshold: level > 0 ? level : defaultThreshold)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        let thresholdItem = NSMenuItem()
        thresholdItem.view = thresholdRow
        thresholdRow.onChange = { [weak self] level in self?.setLevel(level) }
        menu.addItem(thresholdItem)
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
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.isVisible = true  // macOS remembers a hidden status item; opening the app always shows it
        refresh()
        // After an app update the installed helper may be older and ignore new settings,
        // so bring it up to date straight away, keeping the user's settings.
        if FileManager.default.fileExists(atPath: daemonPlist) && !helperIsCurrent() {
            DispatchQueue.main.async {
                if self.installHelper(hidingEnabled: self.hidingEnabled, level: self.savedLevel) { self.refreshSoon() }
            }
        }
        // Keep the icon in step with the room while the menu is closed.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        helperCurrent = helperIsCurrent()
        refresh()
        thresholdRow.threshold = savedLevel
        // Show the live light level while the menu is open, so the slider is easy to set.
        thresholdRow.roomLux = readLux()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.thresholdRow.roomLux = self?.readLux()
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        lightTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        lightTimer?.invalidate()
        lightTimer = nil
    }

    private func readLux() -> Double? { lightSensor?.lux }

    private func refresh() {
        toggleItem.state = hidingEnabled ? .on : .off
        // What the LED is actually doing, straight from the SMC; only the daemon knows
        // whether it currently considers the room dark.
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
        } else if !installHelper(hidingEnabled: turnOff, level: savedLevel) {
            return
        }
        refreshSoon()
    }

    private func setLevel(_ level: Double) {
        UserDefaults.standard.set(level, forKey: "level")
        guard helperCurrent else { return }  // passed along when the helper gets installed
        if level > 0 { send(notifyThreshold, state: UInt64(level * 10)) }
        send(notifyMode, state: level > 0 ? 1 : 0)
        refreshSoon()
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
    @objc private func hideIcon() { statusItem.isVisible = false }

    @objc private func donate() { NSWorkspace.shared.open(donateURL) }

    // Opening the app again while it's running brings the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem.isVisible = true
        return false
    }

    private func helperIsCurrent() -> Bool {
        FileManager.default.fileExists(atPath: daemonPlist)
            && (try? String(contentsOfFile: versionFile, encoding: .utf8)) == helperVersion
    }

    // Copies the daemon out of the app bundle and starts it with the requested settings.
    // Asks for an admin password; only needed on first use or after an update.
    private func installHelper(hidingEnabled: Bool, onlyWhenDark: Bool, threshold: Double) -> Bool {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = [
            "launchctl bootout system/com.darkcharge.daemon 2>/dev/null",
            "mkdir -p /usr/local/bin",
            "install -m 755 \(q(bundledBinary)) \(installedBinary)",
            "install -m 644 \(q(bundledPlist)) \(daemonPlist)",
            "\(installedBinary) threshold \(threshold)",
            "\(installedBinary) mode \(onlyWhenDark ? "dark" : "always")",
            "\(installedBinary) \(hidingEnabled ? "off" : "on")",
            "launchctl bootstrap system \(daemonPlist)",
        ].joined(separator: "; ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges " +
            "with prompt \"DarkCharge needs to install or update its helper to control the charging LED.\""
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
