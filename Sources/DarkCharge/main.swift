// DarkCharge: a menu bar app that turns the MagSafe charging LED off whenever the built-in
// screen is dark, or always. A root helper (DarkChargeHelper) does the actual LED writes.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
