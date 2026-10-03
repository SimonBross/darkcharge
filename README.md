<p align="center">
  <img src="icon/icon_1024.png" width="160" alt="DarkCharge icon">
</p>

<h1 align="center">DarkCharge</h1>

<p align="center"><b>Turn off the MagSafe charging light on your Mac.</b></p>

That little green or amber light on the MagSafe plug is bright enough to light up a
dark bedroom. DarkCharge is a tiny menu bar app that switches it off whenever your
MacBook's screen is dark, and lets it shine normally while you're using the Mac.

- **Automatic:** the LED goes dark when the lid is closed, the Mac is asleep, or the
  screen is off or dimmed all the way down. Or keep it off all the time.
- **Stays put** after plugging in, unplugging, sleep and restarts
- **Tiny and private:** no network access, no tracking, almost no CPU

## Requirements

- A MacBook with **MagSafe 3** (Apple Silicon MacBook Air and MacBook Pro, 2021 and later)
- macOS 14 Sonoma or later

Tested on a 16" MacBook Pro (M4 Pro). Reports from other models are welcome.

## Install

1. Download `DarkCharge.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move **DarkCharge** to your Applications folder and open it.
3. Click the plug icon in the menu bar and check **Turn Off Charging LED**.
   macOS asks for your password once, to install the small helper that controls the LED.

### Using it

- **Turn Off Charging LED:** the main switch.
- **Whenever the screen is dark** (default): the LED is dark while
  - the lid is closed (also when you use the Mac closed with an external display),
  - the Mac is asleep,
  - the screen has gone to sleep, or
  - the brightness is turned all the way down,

  and shines normally while you're using the Mac.
- **Always:** the LED stays off all the time.
- **Launch at Login** (recommended), **Hide Menu Bar Icon** (open the app again to bring
  it back).

DarkCharge only controls the LED while the app is running. Quit it and the LED is back
to normal right away; that's also why **Launch at Login** is recommended.

## How it works

The LED is controlled by the Mac's System Management Controller (SMC), key `ACLC`.
Writing to it needs root, so the app installs a small helper as a LaunchDaemon. The
helper turns the LED off just before the Mac sleeps and whenever the lid is closed, and
gives it back to macOS when the screen is in use. It also puts it back whenever macOS
resets it, for example on plugging in.

The helper only acts while the app is running: the app checks in every few seconds, and
if it quits, crashes or is deleted, the helper hands the LED back to macOS (at once on
quit, otherwise within half a minute).

Whether the screen is asleep or fully dimmed can only be seen from your login session,
so the menu bar app watches that and tells the helper. Reading the brightness uses a
private macOS API (there's no public one on Apple Silicon); if a future macOS update
breaks it, "dimmed all the way down" simply stops counting as dark.

## Uninstall

Choose **Uninstall DarkCharge…** from its menu. It gives the LED back to macOS, removes
the helper (asking for your password), and moves the app to the Trash.

If the app is already gone, remove the helper from Terminal:

```sh
sudo launchctl bootout system/com.darkcharge.daemon
sudo /usr/local/bin/darkcharge on
sudo rm -rf /usr/local/bin/darkcharge /Library/LaunchDaemons/com.darkcharge.daemon.plist "/Library/Application Support/DarkCharge"
```

## Build from source

```sh
make app            # builds build/DarkCharge.app
make                # also builds the darkcharge command-line tool
sudo make uninstall # remove the helper and give the LED back to macOS
```

Command-line control (settings take effect while the app is running):

```sh
sudo darkcharge off           # turn the LED off
sudo darkcharge on            # give the LED back to macOS
sudo darkcharge mode screen   # off whenever the screen is dark (default)
sudo darkcharge mode always   # off all the time
darkcharge status             # current LED state
```

## Support

DarkCharge is free and open source. If it helps you sleep, you can
[buy me a coffee on Ko-fi](https://ko-fi.com/simonbross) ♥

## License

[MIT](LICENSE)
