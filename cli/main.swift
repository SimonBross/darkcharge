// darkcharge: turns the MagSafe charging LED off, either always or whenever the built-in
// screen is dark: lid closed, Mac asleep, or (as reported by the app) screen asleep or
// fully dimmed.
// Runs as a root LaunchDaemon (`darkcharge daemon`) and as a command-line tool.

import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import notify

// MARK: - Desired state

// Reported by the app; the daemon can't see the screen itself. Reset on wake, when the
// screen comes back on, and the app reports again within a second anyway.
var screenIsDark = false

func setPaused(_ paused: Bool) throws {
    let fm = FileManager.default
    if paused {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        fm.createFile(atPath: pausedFile, contents: nil)
    } else if fm.fileExists(atPath: pausedFile) {
        try fm.removeItem(atPath: pausedFile)
    }
}

var isPaused: Bool { FileManager.default.fileExists(atPath: pausedFile) }

func setAlwaysOff(_ always: Bool) throws {
    let fm = FileManager.default
    if always {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        fm.createFile(atPath: alwaysFile, contents: nil)
    } else if fm.fileExists(atPath: alwaysFile) {
        try fm.removeItem(atPath: alwaysFile)
    }
}

// Darkens the LED when it should be off; otherwise hands it back to macOS if we had darkened it.
func enforce() throws {
    if !isPaused && (alwaysOff || screenIsDark || lidIsClosed()) {
        try setLED(ledOff)
    } else if try SMC().read(ledKey) == [ledOff] {
        try setLED(ledSystem)
    }
}

func turnOff() throws {
    try setPaused(false)
    try enforce()
}

func turnOn() throws {
    try setPaused(true)
    try enforce()
}

// MARK: - Daemon

func logErrors(_ body: () throws -> Void) {
    do { try body() } catch { fputs("darkcharge: \(error)\n", stderr) }
}

// Message values from IOKit/IOMessage.h (macros not imported into Swift).
private let msgCanSystemSleep: natural_t = 0xE000_0270
private let msgSystemWillSleep: natural_t = 0xE000_0280
private let msgSystemHasPoweredOn: natural_t = 0xE000_0300
private var rootPort: io_connect_t = 0

func runDaemon() -> Never {
    logErrors {
        try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try helperVersion.write(toFile: versionFile, atomically: true, encoding: .utf8)
    }
    logErrors(enforce)

    // Re-apply whenever the power source changes (plug, unplug, charge state).
    if let source = IOPSNotificationCreateRunLoopSource({ _ in logErrors(enforce) }, nil)?.takeRetainedValue() {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    // A sleeping Mac has no lit screen, so go dark just before sleep. On wake the screen
    // comes back on.
    var notifyPort: IONotificationPortRef?
    var notifier: io_object_t = 0
    rootPort = IORegisterForSystemPower(nil, &notifyPort, { _, _, message, arg in
        switch message {
        case msgCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case msgSystemWillSleep:
            if !isPaused { logErrors { try setLED(ledOff) } }
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case msgSystemHasPoweredOn:
            screenIsDark = false
            logErrors(enforce)
        default: break
        }
    }, &notifier)
    if let notifyPort {
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
    }

    // Requests from the menu bar app, which can't write to the SMC itself.
    var token: Int32 = 0
    notify_register_dispatch(notifyOff, &token, .main) { _ in logErrors(turnOff) }
    notify_register_dispatch(notifyOn, &token, .main) { _ in logErrors(turnOn) }
    notify_register_dispatch(notifyMode, &token, .main) { t in
        var state: UInt64 = 0
        notify_get_state(t, &state)
        logErrors {
            try setAlwaysOff(state == 1)
            try enforce()
        }
    }
    notify_register_dispatch(notifyScreen, &token, .main) { t in
        var state: UInt64 = 0
        notify_get_state(t, &state)
        screenIsDark = state == 1
        logErrors(enforce)
    }

    // Watches the lid, and puts the LED back if macOS resets it without a notification.
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in logErrors(enforce) }

    CFRunLoopRun()
    exit(0)
}

// MARK: - Main

let usage = """
usage: darkcharge <command>
  off            turn the charging LED off
  on             give LED control back to macOS
  mode always    keep it off all the time
  mode screen    keep it off whenever the screen is dark
  status         show the current LED setting
  version        print the version
  daemon         run the background helper (used by the LaunchDaemon)
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(1) }

if ["off", "on", "mode", "daemon"].contains(command) && getuid() != 0 {
    fputs("darkcharge: must run as root (try: sudo darkcharge \(command))\n", stderr)
    exit(1)
}

do {
    switch command {
    case "off": try turnOff()
    case "on": try turnOn()
    case "status":
        let value = try SMC().read(ledKey)
        print(value.count == 1 ? describe(value[0]) : "\(value)")
    case "mode" where args.count == 2 && ["always", "screen"].contains(args[1]):
        try setAlwaysOff(args[1] == "always")
        try enforce()
    case "version": print(helperVersion)
    case "daemon": runDaemon()
    default: print(usage); exit(1)
    }
} catch {
    fputs("darkcharge: \(error)\n", stderr)
    exit(1)
}
