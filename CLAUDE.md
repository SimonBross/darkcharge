# DarkCharge

macOS menu bar app that turns the MagSafe charging LED off whenever the built-in screen is
dark (lid closed, Mac asleep, screen asleep, brightness at zero), or always. Meant to be
published: open source (MIT), signed and notarized. See README.md for the user-facing side.

## Layout

Swift package, Swift 6 language mode, macOS 14+.

- `Sources/DarkChargeCore`: shared code. SMC access (`SMC.swift`, LED key `ACLC`), lid
  state, the `Heartbeat` message format, and `LEDPolicy`, the one decision whether the
  LED should be off. Keep `LEDPolicy` free of hardware access so it stays testable.
- `Sources/DarkChargeHelper`: root LaunchDaemon. Registered by the app with
  `SMAppService.daemon`; launchd runs it as `DarkChargeHelper daemon`. Stateless: acts
  only on the app's heartbeats and hands the LED back to macOS when they stop.
- `Sources/DarkCharge`: the menu bar app (AppKit). Owns the user's settings and watches
  the built-in screen, which only the user session can see.
- `Bundle/`: Info.plist and the helper's LaunchDaemon plist (goes into
  `Contents/Library/LaunchDaemons`).
- `Tests/DarkChargeCoreTests`: Swift Testing tests for `Heartbeat` and `LEDPolicy`.

## Commands

- `make app`: build `build.noindex/DarkCharge.app` (ad hoc signed; `SIGN=` for a real identity)
- `make test`: run the tests
- `make install`: update /Applications/DarkCharge.app in place and start it
- Logs: `/usr/bin/log stream --info --predicate 'subsystem == "com.darkcharge"'`
  (plain `log` is a zsh builtin)

## Rules

- App and helper talk only through `Heartbeat`. If its meaning changes, bump
  `Heartbeat.currentVersion`; a newer app makes an older running helper restart.
- When in doubt, give the LED back to macOS: never leave it off without a running app.
- Update /Applications in place (`make install` uses rsync); deleting and re-copying the
  app breaks its login item.
- External monitors are deliberately ignored (DDC/CI proved unreliable on real hardware).
- Private APIs in use: SMC writes and DisplayServices brightness. Keep them isolated and
  fail safe if they're missing.
- Run `make test` before committing.
