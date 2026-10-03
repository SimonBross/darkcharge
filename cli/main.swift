// darkcharge: turns the MagSafe charging LED off, always or only while the room is dark.
// Runs as a root LaunchDaemon (`darkcharge daemon`) and as a command-line tool.

import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import notify

let lightSensor = LightSensor()

// MARK: - Desired state

var threshold = readThreshold()
var onlyWhenDark = readOnlyWhenDark()
var roomIsDark = false

func readThreshold() -> Double {
    (try? String(contentsOfFile: thresholdFile, encoding: .utf8))
        .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? defaultThreshold
}

func setThreshold(_ lux: Double) throws {
    threshold = lux
    try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
    try String(lux).write(toFile: thresholdFile, atomically: true, encoding: .utf8)
}

func setOnlyWhenDark(_ value: Bool) throws {
    onlyWhenDark = value
    let fm = FileManager.default
    if value {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try "dark".write(toFile: modeFile, atomically: true, encoding: .utf8)
    } else if fm.fileExists(atPath: modeFile) {
        try fm.removeItem(atPath: modeFile)
    }
}

func setPaused(_ paused: Bool) throws {
    let fm = FileManager.default
    if paused {
        try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        fm.createFile(atPath: pausedFile, contents: nil)
    } else if fm.fileExists(atPath: pausedFile) {
        try fm.removeItem(atPath: pausedFile)
    }
}

// Darkens the LED when it should be hidden; otherwise hands it back to macOS if we had darkened it.
func enforce() throws {
    let dark = !FileManager.default.fileExists(atPath: pausedFile) && (!onlyWhenDark || roomIsDark)
    if dark {
        try setLED(ledOff)
    } else if try SMC().read(ledKey) == [ledOff] {
        try setLED(ledSystem)
    }
}

// Takes a single reading and trusts it, for one-shot commands, setting changes and sleep/wake.
func sampleRoomNow() {
    if let lux = lightSensor?.lux { roomIsDark = lux <= threshold }
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

private let lightPollSeconds = 1.0

func pollLight() {
    guard onlyWhenDark, let lux = lightSensor?.lux else { return }
    if (lux <= threshold) != roomIsDark {
        roomIsDark.toggle()
        logErrors(enforce)
    }
}

func runDaemon() -> Never {
    if lightSensor == nil { fputs("darkcharge: no ambient light sensor found\n", stderr) }
    logErrors {
        try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try helperVersion.write(toFile: versionFile, atomically: true, encoding: .utf8)
    }
    sampleRoomNow()
    logErrors(enforce)

    // Re-apply whenever the power source changes (plug, unplug, charge state).
    if let source = IOPSNotificationCreateRunLoopSource({ _ in logErrors(enforce) }, nil)?.takeRetainedValue() {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    // The daemon can't watch the room while the Mac sleeps, so decide just before sleep
    // (a closing lid reads as dark) and look again on wake.
    var notifyPort: IONotificationPortRef?
    var notifier: io_object_t = 0
    rootPort = IORegisterForSystemPower(nil, &notifyPort, { _, _, message, arg in
        switch message {
        case msgCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case msgSystemWillSleep:
            sampleRoomNow()
            logErrors(enforce)
            IOAllowPowerChange(rootPort, Int(bitPattern: arg))
        case msgSystemHasPoweredOn:
            sampleRoomNow()
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
    notify_register_dispatch(notifyThreshold, &token, .main) { t in
        var state: UInt64 = 0
        notify_get_state(t, &state)
        logErrors {
            try setThreshold(Double(state) / 10)
            sampleRoomNow()
            try enforce()
        }
    }

    notify_register_dispatch(notifyMode, &token, .main) { t in
        var state: UInt64 = 0
        notify_get_state(t, &state)
        logErrors {
            try setOnlyWhenDark(state == 1)
            sampleRoomNow()
            try enforce()
        }
    }

    Timer.scheduledTimer(withTimeInterval: lightPollSeconds, repeats: true) { _ in pollLight() }
    // Fallback in case macOS resets the LED without a notification.
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in logErrors(enforce) }

    CFRunLoopRun()
    exit(0)
}

// MARK: - Main

let usage = """
usage: darkcharge <command>
  off              hide the charging LED
  mode always      hide it all the time
  mode dark        hide it only while the room is dark
  on               give LED control back to macOS
  status           show the current LED setting
  light            show the ambient light level
  threshold <lux>  room counts as dark at or below this (default 10)
  version          print the version
  daemon           keep the LED off (used by the LaunchDaemon)
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(1) }

if ["off", "on", "mode", "threshold", "daemon"].contains(command) && getuid() != 0 {
    fputs("darkcharge: must run as root (try: sudo darkcharge \(command))\n", stderr)
    exit(1)
}

do {
    sampleRoomNow()
    switch command {
    case "off": try turnOff()
    case "on": try turnOn()
    case "status":
        let value = try SMC().read(ledKey)
        print(value.count == 1 ? describe(value[0]) : "\(value)")
    case "light":
        guard let lux = lightSensor?.lux else { throw SMCError(description: "no ambient light sensor found") }
        print(String(format: "%.1f lux (%@)", lux, lux <= threshold ? "dark" : "lit"))
    case "mode" where args.count == 2 && ["always", "dark"].contains(args[1]):
        try setOnlyWhenDark(args[1] == "dark")
        try enforce()
    case "threshold" where args.count == 2:
        guard let lux = Double(args[1]), lux > 0 else { print(usage); exit(1) }
        try setThreshold(lux)
        sampleRoomNow()
        try enforce()
    case "version": print(helperVersion)
    case "daemon": runDaemon()
    default: print(usage); exit(1)
    }
} catch {
    fputs("darkcharge: \(error)\n", stderr)
    exit(1)
}
