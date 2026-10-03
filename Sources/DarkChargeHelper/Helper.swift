// The root LaunchDaemon. It holds the LED off while the app's heartbeats say so, and
// hands it back to macOS otherwise. All its inputs (heartbeats, power-source changes,
// sleep and wake, a once-a-second check) arrive on the main run loop, one at a time.

import DarkChargeCore
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import notify
import os

// Message values from IOKit/IOMessage.h (macros not imported into Swift).
private let msgCanSystemSleep: natural_t = 0xE000_0270
private let msgSystemWillSleep: natural_t = 0xE000_0280
private let msgSystemHasPoweredOn: natural_t = 0xE000_0300

@MainActor
final class Helper {
    private let log = Logger(subsystem: "com.darkcharge", category: "helper")
    private var heartbeat: Heartbeat?
    // When the last heartbeat arrived, in awake time: systemUptime stops while the Mac
    // sleeps, so a night's sleep doesn't count as the app having gone away.
    private var heartbeatUptime: TimeInterval = 0
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var sleepNotifier: io_object_t = 0
    private var heartbeatToken: Int32 = 0

    func run() -> Never {
        log.info("Helper \(Heartbeat.currentVersion) starting")
        listenForHeartbeats()
        watchPowerSource()
        watchSleep()
        // Catches the lid, a vanished app, and macOS resetting the LED without a notification.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.enforce() }
        }
        enforce()
        RunLoop.main.run()
        exit(0)
    }

    private func enforce(goingToSleep: Bool = false) {
        let off = LEDPolicy.shouldBeOff(
            heartbeat: heartbeat,
            secondsSinceHeartbeat: ProcessInfo.processInfo.systemUptime - heartbeatUptime,
            lidClosed: Lid.isClosed,
            goingToSleep: goingToSleep)
        do {
            if off {
                try MagSafeLED.set(MagSafeLED.off)
            } else if MagSafeLED.isOff(using: try SMC()) {
                // Only undo our own change; never touch an LED we didn't darken.
                try MagSafeLED.set(MagSafeLED.system)
            }
        } catch {
            log.error("Could not set the LED: \(String(describing: error), privacy: .public)")
        }
    }

    private func listenForHeartbeats() {
        notify_register_dispatch(Heartbeat.notificationName, &heartbeatToken, .main) { token in
            MainActor.assumeIsolated {
                var state: UInt64 = 0
                notify_get_state(token, &state)
                self.received(Heartbeat(state: state))
            }
        }
    }

    private func received(_ beat: Heartbeat) {
        if beat.version > Heartbeat.currentVersion {
            // The app was updated while this older helper kept running. Exit so launchd
            // starts the new helper from the app bundle. (An older app is just ignored.)
            log.notice("App speaks heartbeat version \(beat.version); restarting to update")
            exit(0)
        }
        guard beat.version == Heartbeat.currentVersion else { return }
        if beat != heartbeat {
            log.info("""
                Heartbeat: enabled \(beat.enabled), always \(beat.always), \
                screen dark \(beat.screenDark), quitting \(beat.quitting)
                """)
        }
        heartbeat = beat
        heartbeatUptime = ProcessInfo.processInfo.systemUptime
        enforce()
    }

    // Plugging in, unplugging and charge changes make macOS reset the LED.
    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            let helper = Unmanaged<Helper>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { helper.enforce() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    // Goes dark just before the Mac sleeps; decides afresh on wake, when the screens come back.
    private func watchSleep() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPort, { context, _, message, argument in
            let helper = Unmanaged<Helper>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { helper.powerEvent(message, argument) }
        }, &sleepNotifier)
        if let notifyPort {
            CFRunLoopAddSource(CFRunLoopGetMain(),
                               IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
        }
    }

    private func powerEvent(_ message: natural_t, _ argument: UnsafeMutableRawPointer?) {
        switch message {
        case msgCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case msgSystemWillSleep:
            enforce(goingToSleep: true)
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case msgSystemHasPoweredOn:
            heartbeat?.screenDark = false  // the app reports the real state within a second
            enforce()
        default:
            break
        }
    }
}
