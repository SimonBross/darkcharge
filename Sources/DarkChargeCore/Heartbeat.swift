// The app's message to the helper. The app sends it every few seconds and whenever
// something changes, as the state of a Darwin notification. It carries everything the
// helper needs, so the helper keeps no settings of its own: if the heartbeats stop
// (the app quit, crashed or was deleted), the helper hands the LED back to macOS.

public struct Heartbeat: Equatable, Sendable {
    public static let notificationName = "com.darkcharge.heartbeat"
    // Bumped whenever the app and helper need to change together. A helper that hears a
    // different version exits, so launchd restarts it from the (updated) app bundle.
    public static let currentVersion: UInt16 = 1
    // How long the helper keeps acting on the last heartbeat. The app sends one every
    // few seconds, so this only runs out when the app is gone.
    public static let timeout: Double = 30

    // "Turn Off Charging LED" is checked.
    public var enabled: Bool
    // "Always" is chosen rather than "Whenever the screen is dark".
    public var always: Bool
    // The built-in screen is asleep, fully dimmed, or closed.
    public var screenDark: Bool
    // The app is quitting: hand the LED back right away.
    public var quitting: Bool
    public var version: UInt16

    public init(enabled: Bool, always: Bool, screenDark: Bool, quitting: Bool = false,
                version: UInt16 = Heartbeat.currentVersion) {
        self.enabled = enabled
        self.always = always
        self.screenDark = screenDark
        self.quitting = quitting
        self.version = version
    }

    // Layout of the 64-bit notify state: flags in the low bits, version above them.
    private static let enabledBit: UInt64 = 1 << 0
    private static let alwaysBit: UInt64 = 1 << 1
    private static let screenDarkBit: UInt64 = 1 << 2
    private static let quittingBit: UInt64 = 1 << 3
    private static let versionShift: UInt64 = 16

    public var state: UInt64 {
        var state = UInt64(version) << Self.versionShift
        if enabled { state |= Self.enabledBit }
        if always { state |= Self.alwaysBit }
        if screenDark { state |= Self.screenDarkBit }
        if quitting { state |= Self.quittingBit }
        return state
    }

    public init(state: UInt64) {
        enabled = state & Self.enabledBit != 0
        always = state & Self.alwaysBit != 0
        screenDark = state & Self.screenDarkBit != 0
        quitting = state & Self.quittingBit != 0
        version = UInt16(truncatingIfNeeded: state >> Self.versionShift)
    }
}
