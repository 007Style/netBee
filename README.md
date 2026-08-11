# 🐝 netBee

> **From the minds of Daneyand & IBM's Bob**
> `daneyand@ibm.com`

A native macOS network-monitoring app that lives in your menu bar.  
Zero dependencies. Pure Swift + SwiftUI. Requires macOS 13 Ventura or later.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Installation](#installation)
- [Building from Source](#building-from-source)
- [Running the Tests](#running-the-tests)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Scripts Reference](#scripts-reference)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

netBee is a lightweight, always-on network monitor that sits in the macOS menu bar and gives you an instant read on everything happening on your network interfaces — bandwidth, connections, latency, and more — without ever sending a single byte of your data anywhere.

The tray icon displays a live dual sparkline (receive ↓ green / transmit ↑ blue) so you can see network activity at a glance without opening the dashboard. Left-click opens the six-tab dashboard; right-click shows a context menu.

---

## Features

| Feature | Detail |
|---|---|
| **Menu bar sparkline** | Live dual RX/TX sparkline icon updated every second. Solid black background, colour-coded green/blue lines, byte-rate label. |
| **Overview tab** | Combined bandwidth sparkline across all interfaces + per-interface mini-cards + connection summary counts. 2 m / 10 m time window toggle. |
| **Bandwidth tab** | Per-interface bandwidth cards showing live RX/TX rates, IPv4 address, dual sparkline history, and cumulative counters (total bytes in/out, errors, MTU). |
| **Connections tab** | Searchable, filterable live table of all open TCP/UDP sockets. Shows process name, protocol badge, TCP state, remote endpoint, and per-socket RX/TX byte counters. Sort by bytes or process name. Filter by TCP / TCP6 / UDP. |
| **Interfaces tab** | Expandable detail cards for every network interface: IPv4, IPv6, MTU, packets in/out, bytes in/out, errors. Expandable chevron reveals the full detail set. |
| **Latency tab** | Per-interface gateway ping (ICMP via `/sbin/ping`) every 5 seconds. Shows current RTT, avg/min/max, reply ratio, and a rolling sparkline. Colour-coded quality bands: green < 20 ms · yellow < 80 ms · amber < 200 ms · red ≥ 200 ms. |
| **About tab** | Animated 60 fps star-network canvas (orbiting stars + connecting edges + hex grid). Live mini-graphs: bandwidth sparkline, connection donut, latency bars. No scrolling. |
| **Zero data exfiltration** | All data comes from local kernel APIs (`getifaddrs`, `libproc`, `netstat`, `ping`). Nothing is sent to any server. |
| **No third-party dependencies** | Only Apple frameworks: Foundation, AppKit, SwiftUI, Combine, SystemConfiguration, Network. |

---

## Screenshots

> _Add your screenshots here after first launch._
>
> Suggested captures:
> - Menu bar icon with sparkline
> - Overview tab
> - Bandwidth tab (with active traffic)
> - Connections tab (filtered by TCP)
> - Interfaces tab (expanded card)
> - Latency tab
> - About tab (animated canvas)

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 13.0 Ventura |
| Swift | 5.9 |
| Xcode | 15 (for IDE use; not required to build) |
| Architecture | Apple Silicon or Intel |

---

## Installation

### Option A — DMG (recommended)

1. Download `netBee-v1.0.0.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **netBee.app** into `/Applications`.
3. Launch netBee from Spotlight or Launchpad.
4. macOS will warn about an unidentified developer on first launch (the app is ad-hoc signed). To allow it:
   - Right-click `netBee.app` → **Open** → **Open** again in the dialog.
   - Or: **System Settings → Privacy & Security → Open Anyway**.

### Option B — Zip archive

Download `netBee-v1.0.0.zip`, unzip, and move `netBee.app` to `/Applications`.

### Option C — Build from source

See [Building from Source](#building-from-source) below.

---

## Building from Source

### Prerequisites

- macOS 13+ with Xcode Command Line Tools  
  ```bash
  xcode-select --install
  ```

### Clone and build

```bash
git clone https://github.com/daneyand/netBee.git
cd netBee

# Debug build (fast, includes symbols)
swift build

# Release build (optimised)
swift build -c release

# Or use the helper script
./scripts/build.sh             # debug
./scripts/build.sh --release   # release
```

The compiled binary lands at `.build/release/netBee` (or `.build/debug/netBee`).

### Run directly

```bash
swift run
```

### Open in Xcode

```bash
open Package.swift
```

Xcode will resolve the package and open the project. Select the `netBee` scheme and press **Run**.

### Build a distributable DMG

```bash
./scripts/release.sh 1.0.0
```

This produces three artefacts in `dist/`:

| File | Description |
|---|---|
| `netBee.app` | Signed `.app` bundle (drag-to-install) |
| `netBee-v1.0.0.zip` | Zipped bundle (~316 KB) |
| `netBee-v1.0.0.dmg` | Drag-to-install DMG with `/Applications` symlink |

---

## Running the Tests

```bash
# Using Swift directly
swift test

# Using the helper script (adds --parallel and a summary line)
./scripts/test.sh
```

The test suite is entirely self-contained — it does not depend on the executable target and runs without any special permissions. It covers:

| Test Suite | What it tests |
|---|---|
| `RollingBufferTests` | FIFO eviction, capacity clamping, suffix slicing, order preservation |
| `FormatBytesTests` | B / KB / MB / GB boundary formatting |
| `FormatBpsTests` | B/s / KB/s / MB/s / GB/s boundary formatting |
| `TimeWindowTests` | Raw values, labels, windowed buffer slicing |
| `ConnProtocolTests` | Raw values, round-trip init, invalid-string nil guard |
| `TCPStateTests` | Raw values, round-trip init, bogus-string nil guard |
| `InterfaceNamerPatternTests` | All prefix-pattern mappings + unknown passthrough |

---

## Project Structure

```
netBee/
├── Package.swift                   SPM manifest — declares targets, platform, linked frameworks
├── Sources/
│   └── netBee/
│       ├── main.swift              App entry point — AppDelegate, NSApplication bootstrap
│       ├── Info.plist              Bundle metadata (excluded from SPM compile target)
│       ├── Assets/
│       │   └── AppIcon.icns        Application icon (bee graphic)
│       │
│       ├── Models/                 Pure data layer — no SwiftUI imports
│       │   ├── NetworkMonitor.swift      1 Hz interface sampler (getifaddrs)
│       │   ├── ConnectionTracker.swift   Per-process socket enumerator (libproc)
│       │   ├── InterfaceNamer.swift      BSD name → friendly name mapper
│       │   └── LatencyMonitor.swift      5 s gateway ping prober (/sbin/ping)
│       │
│       ├── Charts/
│       │   └── SparklineChart.swift      Canvas-based sparklines (single + dual)
│       │
│       ├── Views/                  SwiftUI views — all @MainActor
│       │   ├── DesignSystem.swift        DS colour tokens, MetricCard, helpers
│       │   ├── DashboardView.swift       6-tab window + TabRouter + OverviewSection
│       │   ├── BandwidthView.swift       Per-interface bandwidth sparklines
│       │   ├── ConnectionsView.swift     Searchable connection table
│       │   ├── InterfacesView.swift      Expandable interface detail cards
│       │   ├── LatencyView.swift         Per-interface RTT with sparklines
│       │   └── AboutView.swift           Animated canvas + live mini-graphs
│       │
│       └── Tray/
│           └── TrayController.swift      NSStatusItem, icon rendering, window management
│
├── Tests/
│   └── netBeeTests/
│       └── netBeeTests.swift       46 self-contained unit tests (7 suites)
│
├── scripts/
│   ├── build.sh                    Debug / release build helper
│   ├── test.sh                     Test runner wrapper
│   ├── release.sh                  Full release packager (app + zip + DMG)
│   └── lint.sh                     swift-format + SwiftLint (optional tools)
│
├── dist/                           Build output (gitignored except .gitkeep)
├── README.md                       This file
├── ARCHITECTURE.md                 Deep-dive technical design document
├── CHANGELOG.md                    Version history
├── CONTRIBUTING.md                 Contributor guide
└── LICENSE                         MIT License
```

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a comprehensive technical deep-dive covering:

- Data collection layer and kernel API usage
- Threading model and actor isolation
- SwiftUI state management and the `TabRouter` pattern
- The `LatencyMonitor` dispatch-once safety fix
- Tray icon rendering pipeline
- Rolling buffer design and history windowing

---

## Scripts Reference

| Script | Usage | Description |
|---|---|---|
| `build.sh` | `./scripts/build.sh [--release]` | Builds debug or release binary via `swift build` |
| `test.sh` | `./scripts/test.sh` | Runs `swift test --parallel` with summary output |
| `release.sh` | `./scripts/release.sh [version]` | Full release: compile → bundle → sign → zip → DMG |
| `lint.sh` | `./scripts/lint.sh` | Runs `swift-format` and `swiftlint` if installed |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor guide, including:
- Development environment setup
- Code style conventions
- How to add a new tab / metric
- Pull request process

Quick start:

```bash
git clone https://github.com/daneyand/netBee.git
cd netBee
swift build
swift test
```

---

## License

MIT License — see [LICENSE](LICENSE) for the full text.

---

*netBee v1.0.0 · From the minds of Daneyand & IBM's Bob 🐝*
