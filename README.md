# Power Mode Status Bar

**A macOS menu bar app for MacBook sleep control, lid-close behavior, auto-lock, clamshell workflows, and battery-safe standby modes.**

<p align="center">
  <a href="https://github.com/zhulijin1991/power-mode-status-bar/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/zhulijin1991/power-mode-status-bar?style=social"></a>
  <a href="https://github.com/zhulijin1991/power-mode-status-bar/blob/main/LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-brightgreen.svg"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-0b7285.svg">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange.svg">
</p>

![Power Mode Status Bar hero](Docs/assets/hero.svg)

## Why This Exists

Power Mode Status Bar gives you three practical Mac power modes from the menu bar:

- **Extreme Mode**: keep your Mac awake no matter whether it is plugged in, unplugged, open, or closed.
- **Office Mode**: keep the system awake, let the display sleep on idle, then lock immediately when you close the lid without sleeping the Mac.
- **Standby Mode**: lock immediately and sleep immediately when you close the lid.

Normal mode switching is password-free. The app uses runtime IOPM assertions for everyday changes, so you do not get an `osascript` password prompt every time you switch modes. A separate manual menu item is available only when you intentionally want to apply system-level `pmset` settings.

If this saves your Mac from unexpected sleep during builds, downloads, remote sessions, or clamshell workflows, please star the repo so other people can find it.

## Core Selling Points

![Power mode matrix](Docs/assets/mode-matrix.svg)

| Mode | Best For | Lid Close | Unplugged |
| --- | --- | --- | --- |
| Extreme | Long builds, downloads, remote sessions | Sleep off, auto-lock off | Sleep off, auto-lock off |
| Office | Desk work, meetings, moving around | Sleep off, auto-lock on | Sleep off, auto-lock off |
| Standby | Battery-safe standby | Sleep on, auto-lock on | Sleep follows the standby rule |

## What You See In The Menu

![Menu anatomy](Docs/assets/menu-anatomy.svg)

The menu is intentionally small:

- three mutually exclusive modes
- one rule summary for lid-close behavior
- one rule summary for unplugged behavior
- startup toggle
- thermal auto cool-down toggle (on by default)
- a cool-down status row and tooltip while a thermal cool-down is active
- optional system-level settings action
- quit

The mode rows include the core behavior directly in the menu:

```text
Extreme Mode    Never sleeps or auto-locks
Office Mode     Display sleeps on idle; locks on lid close
Standby Mode    Lid close locks and sleeps
```

Office keeps preventing **system** idle sleep with the lid open or closed. It does not prevent **display** sleep, so the screen can turn off on idle. Closing the lid in Office still locks the screen and still does not sleep the system.

## Thermal Auto Cool-Down

**Thermal Auto Cool-Down** is on by default and stored in UserDefaults. Turn it off from the menu at any time.

The app checks `ProcessInfo.processInfo.thermalState` at launch, whenever macOS posts a thermal-state change, and every 30 minutes. It does not use `powermetrics`, sudo, or a launchd job. The timer lives next to the existing one-second power monitor.

If the state is **serious** or **critical** and the current mode is Office or Extreme, the app:

1. Remembers that mode.
2. Releases its IOPM sleep assertions so the Mac is actually allowed to sleep. Selecting Standby is not enough: Standby with the lid open on AC power still prevents sleep.
3. Sleeps immediately through the existing `pmset sleepnow` path so the machine can cool.
4. Restores the remembered mode 15 minutes later and reapplies its assertions, if cool-down is still enabled.

Choosing any mode during cool-down cancels the pending restore and keeps the mode you picked. Turning the toggle off also cancels cool-down and returns to the selected mode. While cool-down is active, the menu and status-item tooltip show that it is active and the clock time when the mode will be restored.

The optional **Apply System Settings (Admin Required)** action still writes a global `pmset` profile, including `displaysleep 0`. That system setting can keep the display awake even when Office is no longer holding a display-sleep assertion.

## How It Works

![How Power Mode Status Bar works](Docs/assets/how-it-works.svg)

Power Mode Status Bar combines:

- **AppKit status bar UI** for a lightweight native menu bar experience
- **IOPM assertions** to prevent idle system sleep, and display sleep in the modes that require it, without administrator prompts
- **power/lid state monitoring** to update behavior when AC power, battery power, or lid state changes
- **thermal cool-down** that reads `ProcessInfo.thermalState` and temporarily releases sleep assertions when Office or Extreme is overheating
- **optional `pmset` commands** for users who explicitly choose system-level settings

This keeps the common path fast and quiet while still leaving a manual advanced path for users who want persistent global power settings.

## Installation From Source

Requirements:

- macOS 26 or newer
- Swift toolchain / Command Line Tools
- `git`

Clone and install:

```bash
git clone https://github.com/zhulijin1991/power-mode-status-bar.git
cd power-mode-status-bar
./scripts/install_app.sh
```

The installed app appears as:

```text
~/Applications/Power Mode.app
```

The app runs as a normal macOS application bundle, so it is visible in the Applications list and can be launched by name.

## Development

Build:

```bash
swift build
```

Run as a real `.app` bundle:

```bash
./scripts/build_and_run.sh
```

Run verification:

```bash
./scripts/test_power_mode_status_bar.sh
```

Regenerate the app icon from SVG:

```bash
./scripts/generate_app_icon.sh
```

## Permissions And Safety

Everyday mode switching does **not** require an administrator password.

The menu item **Apply System Settings (Admin Required)** intentionally uses administrator authorization because it applies global `pmset` settings. You can ignore that item if you only want runtime mode switching.

The app does not try to block manual user actions. If you explicitly lock the screen, sleep the Mac, quit the app, or shut down, the app respects that.

## App Icon

![Power Mode Status Bar app icon](Resources/AppIcon-1024.png)

The icon uses a macOS 26-style glass tile and a clean power symbol for active wake control.

## Search Keywords

This project is meant for people searching for:

- Mac prevent sleep
- MacBook lid close prevent sleep
- macOS menu bar sleep control
- Mac clamshell mode sleep
- Mac auto lock on lid close
- keep Mac awake on battery
- caffeinate alternative for macOS
- Amphetamine alternative menu bar app
- macOS power mode switcher
- MacBook keep awake utility
- Mac lid close sleep control
- Mac menu bar sleep prevention tool
- macOS auto-lock control
- MacBook plugged-in no sleep mode
- MacBook lid close lock and sleep

## Roadmap Ideas

- signed and notarized release builds
- Sparkle auto-update support
- localized English/Chinese menu labels
- menu screenshot automation for release notes
- optional custom user-defined modes

## Contributing

Issues and pull requests are welcome. Good contributions include:

- bug reports with macOS version, Mac model, and selected mode
- improved handling for different MacBook lid/power edge cases
- better menu copy and localization
- signed release packaging help
- clearer diagrams or documentation

## License

MIT. See [LICENSE](LICENSE).

<!--
SEO: macOS sleep prevention, MacBook lid close sleep, clamshell mode, menu bar app, no sleep Mac, prevent display sleep, IOPM assertion, pmset, caffeinate alternative, Amphetamine alternative, Mac auto lock, Mac power management, Swift AppKit menu bar utility.
-->
