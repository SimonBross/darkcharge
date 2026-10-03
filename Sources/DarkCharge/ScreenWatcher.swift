import AppKit

// Watches the built-in screen from the user's session, the only place it can be seen, and
// reports when it stops giving off light: asleep, fully dimmed, or gone (lid closed with an
// external display). External displays are deliberately ignored.
@MainActor
final class ScreenWatcher {
    var onChange: (Bool) -> Void = { _ in }
    private(set) var isDark = false

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    // Private API, but the only way to read the built-in screen's brightness on Apple Silicon.
    // If it's ever missing, a dimmed screen just stops counting as dark.
    private let getBrightness: GetBrightnessFn? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetBrightnessFn.self) }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }
        // Brightness changes have no notification, so poll for those.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        isDark = builtInScreenIsDark()
    }

    private func check() {
        let dark = builtInScreenIsDark()
        guard dark != isDark else { return }
        isDark = dark
        onChange(dark)
    }

    private func builtInScreenIsDark() -> Bool {
        guard let display = builtInDisplay else { return true }  // lid closed
        if CGDisplayIsAsleep(display) != 0 { return true }
        var brightness: Float = 1
        guard let getBrightness, getBrightness(display, &brightness) == 0 else { return false }
        return brightness <= 0.001
    }

    private var builtInDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}
