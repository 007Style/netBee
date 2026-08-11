# 🐝 netBee

**A native macOS network monitor** — per-interface bandwidth sparklines, per-process
TCP/UDP connections, interface details, and rolling history — displayed in a sleek
dark dashboard with a live menu bar bandwidth indicator.

Built with pure Swift / SwiftUI. No third-party dependencies. macOS 13+ required.

---

## Features

| Category | What you get |
|---|---|
| **Bandwidth** | Per-interface ↓↑ sparklines with 2-minute and 10-minute rolling history |
| **Combined view** | Total bandwidth across all interfaces on the Overview tab |
| **Connections** | Live table: process name · protocol · TCP state · remote endpoint · RX/TX bytes |
| **Connection filter** | Search by process name or IP; filter by TCP / TCP6 / UDP; sort by bytes or name |
| **Interfaces** | All BSD interfaces with IPv4/IPv6 addresses, MTU, packet counters, error counts |
| **Menu bar** | Live dual sparkline (↓ green / ↑ blue) + byte-rate label — always at a glance |
| **Time windows** | Toggle between **2m** and **10m** rolling history on every chart |
| **1-second updates** | Interface sampling at 1 Hz; connection table refreshed every 2 seconds |

---

## Quick start

```bash
git clone https://github.com/007Style/netBee.git
cd netBee
swift run
```

Look for the dual sparkline in your menu bar. Left-click to open the dashboard.

---

## Installation

### Option A — Build from source

```bash
./scripts/build.sh --release
open .build/release/netBee
```

### Option B — Download the app bundle

Grab the latest `netBee-v*.dmg` from the [Releases](https://github.com/007Style/netBee/releases)
page, open the DMG, and drag `netBee.app` to `/Applications`.

### Option C — Open in Xcode

```bash
open Package.swift
```

Then **Product → Run** (`⌘R`).

---

## Usage

| Action | Result |
|---|---|
| **Left-click** tray icon | Toggle dashboard open / closed |
| **Right-click** tray icon | Context menu: Open · About · Quit |
| **Overview tab** | Combined bandwidth sparkline + top interfaces + connection summary |
| **Bandwidth tab** | Per-interface sparkline cards, cumulative bytes, error counts |
| **Connections tab** | Searchable/filterable TCP/UDP table sorted by bytes |
| **Interfaces tab** | Expandable cards: IPs, MTU, packet in/out, errors |
| **2m / 10m pill** | Switch sparkline time window on any tab |

---

## Scripts

```bash
./scripts/build.sh              # debug build
./scripts/build.sh --release    # optimised release build
./scripts/test.sh               # run 46-test unit suite
./scripts/release.sh 1.0.0      # create dist/netBee.app + zip + DMG
./scripts/lint.sh               # swift-format + SwiftLint (optional)
```

---

## Architecture

```
Sources/netBee/
├── main.swift                    AppDelegate + NSApplication entry point
├── Info.plist                    Bundle metadata
│
├── Models/
│   ├── NetworkMonitor.swift       Interface sampling (getifaddrs) + rolling history
│   ├── ConnectionTracker.swift    Per-process TCP/UDP connections (libproc)
│   └── InterfaceNamer.swift       BSD name → friendly label (networksetup + patterns)
│
├── Charts/
│   └── SparklineChart.swift       SwiftUI Canvas sparklines (single + dual)
│
├── Views/
│   ├── DesignSystem.swift         DS colour tokens · MetricCard · helpers
│   ├── DashboardView.swift        5-tab main window + Overview section
│   ├── BandwidthView.swift        Per-interface bandwidth + sparklines
│   ├── ConnectionsView.swift      Searchable connection table
│   ├── InterfacesView.swift       Interface detail cards
│   └── AboutView.swift            About panel + animated hex-grid background
│
└── Tray/
    └── TrayController.swift       NSStatusItem dual sparkline icon + window mgmt

Tests/netBeeTests/
└── netBeeTests.swift              46 self-contained unit tests
```

### Data flow

```
1 Hz Timer (NetworkMonitor)
    │
    └─ getifaddrs  →  InterfaceSnapshot[]  →  Δ bytes/sec  →  RollingBuffer (600 cap)
           │
           └─ @Published  →  SwiftUI views re-render

2 s Timer (ConnectionTracker — background queue)
    │
    └─ libproc / netstat  →  ConnectionEntry[]
           │
           └─ DispatchQueue.main  →  @Published  →  SwiftUI re-render
```

---

## Testing

```bash
swift test
```

**46 tests · 0 failures** across 8 test suites:

| Suite | Tests | Covers |
|---|---|---|
| `RollingBufferTests` | 8 | Eviction, capacity, ordering, edge cases |
| `FormatBytesTests` | 7 | B / KB / MB / GB formatting |
| `FormatBpsTests` | 5 | Bandwidth rate string formatting |
| `TimeWindowTests` | 6 | Raw values, labels, window slicing |
| `ConnProtocolTests` | 6 | Raw values, round-trips, invalid |
| `TCPStateTests` | 5 | Raw values, round-trips, invalid |
| `InterfaceNamerPatternTests` | 11 | en / utun / awdl / llw / bridge / ppp patterns |

---

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel)
- Xcode 15+ / Swift 5.9+ (to build from source)

---

## Privacy

netBee reads only system network counters via public macOS APIs:

- `getifaddrs`        — per-interface byte / packet / error counters
- `libproc`           — open socket metadata for your user's processes (no packet contents)
- `networksetup`      — interface friendly names (once at launch)

No packet contents are inspected. No data leaves your machine.
No network requests. No analytics.

---

## License

MIT License — see [`LICENSE`](LICENSE) for full text.

---

## Credits

<p align="center">
  <strong>From the minds of Daneyand &amp; IBM's Bob 🐝</strong>
</p>

---

*netBee v0.1.0*
