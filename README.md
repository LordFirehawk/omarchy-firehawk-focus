# Firehawk Focus

Firehawk Focus is a cross-platform Pomodoro & Focus block tracker designed for deep work. It runs seamlessly on both **Omarchy Linux** (QML / Wayland bar plugin) and **macOS** (native Swift / SwiftUI menu bar application).

Both editions share the exact same battle-tested core state machine ([`FocusModel.js`](file:///Users/janscodingapple/Projects/Personal/omarchy-firehawk-focus/FocusModel.js)), ensuring identical timer mechanics, 4-cycle long break logic, and local data persistence.

---

## macOS Native App

### Features
- **Native Menu Bar Item**: Dynamic live countdown clock, pause indicator, and flame icon in the macOS menu bar.
- **Locked Tray Window**: The popup tray locks in place directly beneath the menu bar icon when opened so it stays rock-solid while working.
- **App Activity Tracking**: Automatically tracks which frontmost apps you use during focus blocks without needing screen recording permissions. Visualized with native macOS icons and percentage bars in Stats.
- **Audible Across the Room**: Customizable end sounds, featuring a loud **Digital Alarm** for breaks so you never miss when it's time to return to your desk.
- **Auto Startup on Login**: Starts automatically with your Mac.

### Quick Start & Installation

```sh
# Build, install to ~/Applications, create CLI shortcut, and launch:
./platforms/macos/install.sh
```

### Reopening the App if Closed
If you accidentally quit or close the app, you can reopen it anytime using any of these methods:
1. **Spotlight / Raycast**: Press <kbd>⌘</kbd> + <kbd>Space</kbd>, type `Firehawk Focus`, and press <kbd>Return</kbd>.
2. **Terminal**: Run `firehawk-focus`.
3. **Finder**: Go to `Applications` (or `~/Applications`) and open `Firehawk Focus`.

### Launch on Boot
By default, the installer enables launch on login via macOS LaunchAgent (`~/Library/LaunchAgents/org.lordfirehawk.firehawk-focus.plist`). You can also toggle this on or off anytime in the **Settings (⚙️)** tab under **Startup & Reopening**.

---

## Controls

- **Left-click:** open or close the panel
- **Right-click:** start, pause, or resume
- **Middle-click:** reset the timer
- **1 / 2 / 3:** Timer, Stats, and Settings tabs
- **Space:** start or pause
- **E:** add five minutes
- **S:** skip

## Completion behavior

### Non-invasive

Plays the configured alarm and shows a temporary desktop notification. The completed phase waits at zero for you to extend it or start the next phase.

### Invasive

Plays the alarm, opens the full panel, and holds at zero until dismissed. Choose **+5 min** to resume the same phase, **Take a break** after focus, or **Start Focus** after a break.

A running break also provides **Start Focus** so it can be ended early in one click.

## Interruptions and analytics

Leaving a started focus block through **Skip** or **Take a break** records its actual elapsed time as a partial session and advances the round counter. An interrupted fourth focus therefore still earns the configured long break. Paused time is excluded, and skipping a timer that was never started does not create a phantom session.

## Privacy and local data

Timer state, settings, and history are stored locally at:

- Linux: `~/.local/state/omarchy/firehawk-focus.json`
- macOS: `~/Library/Application Support/FirehawkFocus/firehawk-focus.json`

Removing the plugin does not automatically remove this history.

## Script control

```sh
omarchy-shell lordfirehawk.focus open
omarchy-shell lordfirehawk.focus close
omarchy-shell lordfirehawk.focus begin
omarchy-shell lordfirehawk.focus pause
omarchy-shell lordfirehawk.focus extend
omarchy-shell lordfirehawk.focus skip
omarchy-shell lordfirehawk.focus breakNow
omarchy-shell lordfirehawk.focus focusNow
omarchy-shell lordfirehawk.focus reset
omarchy-shell lordfirehawk.focus status
```

## Development

Run the dependency-free state-model test anywhere Node.js is available:

```sh
node test/model.test.js
```

On Omarchy, run the complete plugin validation suite:

```sh
./test/all
```

## License

[MIT](LICENSE) © 2026 LordFirehawk
