import Foundation

// The user's choices. They live with the app, which sends them to the helper in every
// heartbeat, so the helper needs no settings of its own.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    // "Turn Off Charging LED".
    static var enabled: Bool {
        get { defaults.bool(forKey: "enabled") }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    // "Always", rather than "Whenever the screen is dark".
    static var always: Bool {
        get { defaults.bool(forKey: "always") }
        set { defaults.set(newValue, forKey: "always") }
    }

    // "Hide Menu Bar Icon"; kept across restarts while the app launches at login.
    static var iconHidden: Bool {
        get { defaults.bool(forKey: "iconHidden") }
        set { defaults.set(newValue, forKey: "iconHidden") }
    }

    static func removeAll() {
        if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
    }
}
