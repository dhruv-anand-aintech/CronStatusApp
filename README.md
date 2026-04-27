# CronStatusApp

A lightweight macOS menu bar app that shows your cron jobs and Launch Agents at a glance — no Dock icon, no clutter.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Menu bar icon** showing live counts: `2a · 3c` (agents running · cron active)
- **Dropdown summary** — top 10 launch agents and cron jobs with green/grey status dots
- **Full dashboard window** (`⌘D`) for the complete list
- **Refresh** (`⌘R`) on demand; also auto-loads on launch and on first menu open
- No Dock icon — runs purely as a menu bar accessory

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ or Swift 5.9 toolchain (for building from source)

## Install

> **Note:** The app is not notarized. After copying to Applications, macOS may show "damaged and can't be opened." Run this once to fix it:
> ```bash
> xattr -c /Applications/CronStatusApp.app
> ```

### Option A — Build from source (recommended)

```bash
git clone https://github.com/dhruv-anand-aintech/CronStatusApp.git
cd CronStatusApp
swift build -c release
cp .build/release/CronStatusApp /usr/local/bin/
```

Then launch it:

```bash
open /usr/local/bin/CronStatusApp
```

Or add it to your Login Items so it starts automatically:  
**System Settings → General → Login Items → +** and select the binary.

### Option B — Run directly (no install)

```bash
swift run
```

## Usage

- **Menu bar icon** — click to see a live summary of your agents and cron jobs
- **Open Dashboard** (`⌘D`) — opens the full monitor window with all entries
- **Refresh** (`⌘R`) — re-reads crontab and launchctl state
- **Quit** (`⌘Q`) — exits the app

## How it works

| Source | What it reads |
|--------|--------------|
| Cron jobs | `crontab -l` — parses your user crontab |
| Launch Agents | `launchctl list` — reads `~/Library/LaunchAgents` plist labels and PID state |

System-level agents (Apple, com.apple.\*, etc.) are filtered out so only your own agents appear.

## Project structure

```
Sources/CronStatusApp/
├── App.swift                # Entry point, menu bar + dashboard window setup
├── MenuBarView.swift        # Dropdown summary UI
├── DashboardView.swift      # Full monitor window
├── CronManager.swift        # Reads and parses crontab -l
├── CronEntry.swift          # Cron job model
├── CronJobsView.swift       # Cron tab in dashboard
├── LaunchAgentManager.swift # Reads launchctl list + plists
├── LaunchAgentEntry.swift   # Launch agent model
├── LaunchAgentsView.swift   # Agents tab in dashboard
├── ShellHelper.swift        # Async shell command runner
└── Resources/Info.plist
```

## License

MIT
