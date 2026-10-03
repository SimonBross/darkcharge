<p align="center">
  <img src="icon/icon_1024.png" width="160" alt="DarkCharge icon">
</p>

<h1 align="center">DarkCharge</h1>

<p align="center"><b>Turn off the MagSafe charging light on your Mac.</b></p>

That little green or amber light on the MagSafe plug is bright enough to light up a
dark bedroom. DarkCharge is a tiny menu bar app that switches it off, either all the
time or only when the room is dark, using your Mac's ambient light sensor.

- **One click** to turn the charging LED off
- **Light-aware:** a slider sets how dark the room must be (or "Always off")
- **Stays off** after plugging in, unplugging, sleep and restarts
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
- **Slider:** `Always off` at 0, or `Turn off at ≤ N lux` to hide the LED only when the
  room is that dark or darker. The current light level is shown next to it.
- **Launch at Login**, **Hide Menu Bar Icon** (open the app again to bring it back).

## How it works

The LED is controlled by the Mac's System Management Controller (SMC), key `ACLC`.
Writing to it needs root, so the app installs a small helper as a LaunchDaemon. The
helper sets the LED, and puts it back whenever macOS resets it: on every power change,
after wake, and every 30 seconds as a fallback. It reads the light sensor once a second.

While the Mac is asleep the helper can't watch the room, so it decides just before
sleep. Closing the lid covers the sensor, which counts as dark.

The light sensor is read through a private macOS API (there's no public one on Apple
Silicon). If a future macOS update breaks that, the LED simply stays on.

## Uninstall

Quit DarkCharge, delete it from Applications, then remove the helper:

```sh
sudo launchctl bootout system/com.darkcharge.daemon
sudo /usr/local/bin/darkcharge on
sudo rm -rf /usr/local/bin/darkcharge /Library/LaunchDaemons/com.darkcharge.daemon.plist "/Library/Application Support/DarkCharge"
```

## Build from source

```sh
make app            # builds build/DarkCharge.app
make                # also builds the darkcharge command-line tool
sudo make install   # install just the helper, without the app
sudo make uninstall # remove the helper and give the LED back to macOS
```

Command-line control (once the helper is installed):

```sh
sudo darkcharge off            # turn the LED off
sudo darkcharge on             # give the LED back to macOS
sudo darkcharge mode always    # off all the time
sudo darkcharge mode dark      # off only while the room is dark
sudo darkcharge threshold 5    # room counts as dark at 5 lux or less
darkcharge light               # current light level
darkcharge status              # current LED state
```

## Support

DarkCharge is free and open source. If it helps you sleep, you can
[buy me a coffee on Ko-fi](https://ko-fi.com/simonbross) ♥

## License

[MIT](LICENSE)
