import DarkChargeCore
import Testing

@Suite("Heartbeat encoding")
struct HeartbeatTests {
    @Test("Survives the trip through a notify state", arguments: [false, true])
    func roundTrip(flag: Bool) {
        let beat = Heartbeat(enabled: flag, always: !flag, screenDark: flag, quitting: !flag, version: 7)
        #expect(Heartbeat(state: beat.state) == beat)
    }

    @Test("Each flag has its own bit")
    func flagsAreIndependent() {
        let beats = [
            Heartbeat(enabled: true, always: false, screenDark: false, version: 0),
            Heartbeat(enabled: false, always: true, screenDark: false, version: 0),
            Heartbeat(enabled: false, always: false, screenDark: true, version: 0),
            Heartbeat(enabled: false, always: false, screenDark: false, quitting: true, version: 0),
        ]
        let states = beats.map(\.state)
        #expect(Set(states).count == beats.count)
        #expect(states.allSatisfy { $0.nonzeroBitCount == 1 })
    }

    @Test("Carries the current version by default")
    func defaultVersion() {
        let beat = Heartbeat(enabled: true, always: false, screenDark: false)
        #expect(Heartbeat(state: beat.state).version == Heartbeat.currentVersion)
    }

    @Test("An empty state means nothing is asked for")
    func emptyState() {
        let beat = Heartbeat(state: 0)
        #expect(!beat.enabled && !beat.always && !beat.screenDark && !beat.quitting)
        #expect(beat.version == 0)
    }
}
