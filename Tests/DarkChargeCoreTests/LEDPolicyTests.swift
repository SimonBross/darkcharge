import DarkChargeCore
import Testing

@Suite("When the LED should be off")
struct LEDPolicyTests {
    private let screenLit = Heartbeat(enabled: true, always: false, screenDark: false)

    private func shouldBeOff(_ beat: Heartbeat?, age: Double = 1, lid: Bool = false, sleeping: Bool = false) -> Bool {
        LEDPolicy.shouldBeOff(heartbeat: beat, secondsSinceHeartbeat: age, lidClosed: lid, goingToSleep: sleeping)
    }

    @Test("Left to macOS while the screen is in use")
    func screenInUse() {
        #expect(!shouldBeOff(screenLit))
    }

    @Test("Off when the screen is dark, the lid is closed, or the Mac is going to sleep")
    func darkScreen() {
        var dark = screenLit
        dark.screenDark = true
        #expect(shouldBeOff(dark))
        #expect(shouldBeOff(screenLit, lid: true))
        #expect(shouldBeOff(screenLit, sleeping: true))
    }

    @Test("Always means off even with the screen in use")
    func always() {
        var always = screenLit
        always.always = true
        #expect(shouldBeOff(always))
    }

    @Test("Never off while the feature is switched off")
    func disabled() {
        let disabled = Heartbeat(enabled: false, always: true, screenDark: true)
        #expect(!shouldBeOff(disabled, lid: true, sleeping: true))
    }

    @Test("Back to macOS without a running app", arguments: [
        (nil, 1.0),                                                        // no heartbeat yet
        (Heartbeat(enabled: true, always: true, screenDark: true), 30.0),  // heartbeats stopped
        (Heartbeat(enabled: true, always: true, screenDark: true, quitting: true), 1.0),
    ] as [(Heartbeat?, Double)])
    func noApp(beat: Heartbeat?, age: Double) {
        #expect(!shouldBeOff(beat, age: age, lid: true, sleeping: true))
    }

    @Test("A heartbeat just inside the timeout still counts")
    func justInTime() {
        #expect(shouldBeOff(screenLit, age: Heartbeat.timeout - 0.1, lid: true))
    }
}
