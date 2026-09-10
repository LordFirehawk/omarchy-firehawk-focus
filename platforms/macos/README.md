# Firehawk Focus for macOS (Menu Bar)

A native macOS menu bar focus companion app for **Firehawk Focus**, styled with the fluid feel of Kofe Flow and sharing 100% of the core Pomodoro state machine, analytics, and transition logic from the Omarchy Linux edition.

---

## Highlights & Features

- **100% Shared Domain Logic**: Bridges [`FocusModel.js`](../../FocusModel.js) natively via Apple's `JavaScriptCore` (`JSContext`). All phase calculations, cycle intervals, interrupted session tracking, streaks, and 7-day analytics run through the identical engine used in the Linux / QML build.
- **Kofe Flow Style Circular Countdown**:
  - Smooth animated circular progress ring with custom phase color gradients (Flame Orange for Focus, Emerald for Short Break, Cyan for Long Break).
  - Prominent monospaced digital clock and active phase badge with SF Symbols.
  - Cycle indicator dots showing progress toward your next long break.
- **Menu Bar Integration**:
  - Runs as an accessory (`LSUIElement = true`) with zero Dock clutter.
  - Menu bar icon updates dynamically with phase symbols and live countdown countdowns (` 24:59`, ` Done`, or ` ⏸`).
  - Left-click opens the sleek translucent popover panel.
  - Right-click opens a quick action context menu (Start/Pause, +5m, Skip, Reset, Open Panel, Quit).
- **Comprehensive Analytics (Stats View)**:
  - Daily focus time and session counter.
  - Consecutive day streak counter (`🔥 X days`).
  - 7-day activity bar chart with day-of-week labels and peak-scaled bars.
  - Recent sessions log with completion badges and timestamps.
- **Customizable Preferences (Settings View)**:
  - Configurable focus, short break, and long break durations (stepper controls).
  - Rounds per long break (cycle limit).
  - Completion alert modes: Non-invasive (notification) vs. Invasive (auto-reveals popover on timer expiry).
  - Sound chime alerts (`NSSound`) and macOS native desktop notifications (`UNUserNotificationCenter`).
- **Persistence**:
  - Persists state to `~/Library/Application Support/FirehawkFocus/firehawk-focus.json`.
  - Automatically recognizes existing Omarchy configs (`~/.local/state/omarchy/firehawk-focus.json`) when available.

---

## Installation & Build

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Swift 5.9+ / Xcode Command Line Tools (`xcode-select --install`)

### One-Command Build & Install
From the repository root or inside `platforms/macos`:

```bash
cd platforms/macos
./install.sh
```

This compiles the release binary with whole-module optimization, creates `~/Applications/Firehawk Focus.app`, ad-hoc signs it, and launches the app directly into your menu bar.

### Launch at Login (Optional)
To launch Firehawk Focus automatically upon user login:
1. Open **System Settings** > **General** > **Login Items**.
2. Under "Open at Login", click `+` and select `~/Applications/Firehawk Focus.app`.
