// The one decision DarkCharge makes, kept free of hardware access so it can be tested.

public enum LEDPolicy {
    // Whether the LED should be held off right now.
    // - heartbeat: the app's latest heartbeat, nil if none has arrived yet.
    // - secondsSinceHeartbeat: awake time since it arrived.
    // - lidClosed: the lid is shut.
    // - goingToSleep: the Mac is about to sleep; a sleeping Mac lights no screen.
    public static func shouldBeOff(heartbeat: Heartbeat?, secondsSinceHeartbeat: Double,
                                   lidClosed: Bool, goingToSleep: Bool = false) -> Bool {
        // Without a running app the LED belongs to macOS.
        guard let heartbeat, !heartbeat.quitting, secondsSinceHeartbeat < Heartbeat.timeout,
              heartbeat.enabled else { return false }
        return heartbeat.always || heartbeat.screenDark || lidClosed || goingToSleep
    }
}
