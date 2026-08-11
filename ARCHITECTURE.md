# netBee — Architecture

## Overview

netBee is a native macOS menu bar app that gives you deep, real-time visibility
into your machine's network activity: per-interface bandwidth, per-process TCP/UDP
connections, and interface details — all with rolling history sparklines and zero
data leaving your Mac.

It is the network-focused sibling of [beeMon](https://github.com/007Style/beeMon)
and [nBeeMon](https://github.com/007Style/nBeeMon) in the Bee tool suite.

---

## Problem Space

macOS has no built-in tool that shows **who is using the network and how much**
in real time. Activity Monitor only shows totals; Wireshark is heavy; `netstat`
and `lsof -i` are CLI-only and require mental assembly. netBee fills that gap:
a lightweight, always-on, native UI that answers "what's on my network right now?"

---

## Core Concepts

| Concept | Description |
|---|---|
| **Interface snapshot** | One sample of a BSD network interface's cumulative byte/packet/error counters |
| **Bandwidth delta** | Bytes-per-second computed between two consecutive snapshots (Δbytes / Δt) |
| **Rolling buffer** | Fixed-capacity FIFO that discards oldest sample when full (600 samples = 10 min at 1 Hz) |
| **Connection entry** | One active TCP or UDP socket: process → local:port → remote:port + state + bytes |
| **Time window** | User-selectable history slice: 2 minutes (120 samples) or 10 minutes (600 samples) |

---

## Tech Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift 5.9 | No Objective-C, no bridging header |
| UI | SwiftUI (AppKit shell) | `NSHostingView` in an `NSWindow`; menu bar via `NSStatusItem` |
| Styling | Custom DS tokens | Dark glass, matches beeMon / nBeeMon palette |
| Data — interfaces | `getifaddrs` (Darwin libc) | Per-interface byte/packet/error counters |
| Data — connections | `libproc` (`proc_pidinfo`, `PROC_PIDLISTFDS`, `proc_pidfdinfo`) | Per-process open sockets; `netstat -an` fallback |
| Data — names | `networksetup -listallhardwareports` | Friendly interface names; pattern-table fallback |
| Concurrency | Combine `Timer.publish` + `DispatchQueue` | 1 Hz main-thread publish; 2 Hz background connection scan |
| Build | Swift Package Manager | No Xcode project file required |
| Distribution | Ad-hoc codesigned `.app` + DMG | No notarisation (same as beeMon) |
| Dependencies | **Zero** | Pure Apple frameworks only |

---

## High-Level Structure

```
netBee/
├── Sources/netBee/
│   ├── main.swift                  NSApplication + AppDelegate entry point
│   ├── Info.plist                  Bundle metadata
│   │
│   ├── Models/
│   │   ├── NetworkMonitor.swift    Interface sampling + rolling history
│   │   ├── ConnectionTracker.swift libproc connection enumeration
│   │   └── InterfaceNamer.swift    BSD name → friendly label
│   │
│   ├── Charts/
│   │   └── SparklineChart.swift    Canvas sparkline (single + dual)
│   │
│   ├── Views/
│   │   ├── DesignSystem.swift      DS tokens, shared components, formatters
│   │   ├── DashboardView.swift     5-tab main window + Overview section
│   │   ├── BandwidthView.swift     Per-interface bandwidth + sparklines
│   │   ├── ConnectionsView.swift   Searchable connection table
│   │   ├── InterfacesView.swift    Interface detail cards
│   │   └── AboutView.swift         About panel + animated hex grid
│   │
│   └── Tray/
│       └── TrayController.swift    NSStatusItem icon + window management
│
├── Tests/netBeeTests/
│   └── netBeeTests.swift           46 unit tests (8 suites)
│
└── scripts/
    ├── build.sh                    Debug / release compile
    ├── test.sh                     Run test suite
    ├── release.sh                  Package .app + DMG + zip
    └── lint.sh                     swift-format + SwiftLint
```

---

## Data Flow

```
1 Hz Timer (main thread)
    │
    └─ NetworkMonitor.sample()
         ├─ getifaddrs  →  [InterfaceSnapshot]
         │                       │
         │    Δ vs previous  ──→ [InterfaceBandwidth]  (bytes/sec)
         │                       │
         │                  RollingBuffer<BandwidthSample> per interface (cap 600)
         │                       │
         └─ @Published ──────────┴──────────────→  SwiftUI re-render

2 Hz Timer (background DispatchQueue.utility)
    │
    └─ ConnectionTracker.fetchConnections()
         ├─ proc_listallpids  →  [pid_t]
         │   └─ proc_pidinfo(PROC_PIDLISTFDS) per PID
         │       └─ proc_pidfdinfo(PROC_PIDFDSOCKETINFO) per socket FD
         │           └─ [ConnectionEntry]   (or netstat fallback)
         │                   │
         └─ DispatchQueue.main.async  →  @Published connections  →  SwiftUI
```

---

## Key Design Principles

1. **Bee family consistency** — same DS tokens, same sparkline component, same
   tray icon style, same build / release scripts as beeMon and nBeeMon.
2. **Zero dependencies** — every data source is a public Apple API; no SPM deps.
3. **Minimal permissions** — reads only public counters and your own-user processes.
   No root, no kernel extension, no entitlements beyond what SPM gives by default.
4. **Degrade gracefully** — if `libproc` returns no data (e.g. SIP context),
   `ConnectionTracker` falls back to `netstat -an` parsing automatically.
5. **1-second updates** — all metrics at 1 Hz; connection scan at 2-second
   intervals (heavier libproc walk runs on a background queue).

---

## Privacy

netBee reads only system network counters via public macOS APIs:

- `getifaddrs`   — per-interface byte / packet / error counters (no payload)
- `libproc`      — open socket metadata for your user's processes (no payload)
- `networksetup` — interface friendly names (once at launch)

No packet contents are read. No data leaves your machine. No network requests.
No analytics.

---

## Open Questions / Roadmap

- [ ] DNS monitor — intercept / log per-process DNS lookups + latency
- [ ] Latency heatmap — rolling ping to gateway, 8.8.8.8, and custom targets
- [ ] New-connection alert — notify when unknown process opens outbound socket
- [ ] App icon — bee with network cables / signal bars
- [ ] `nextBee` integration — post metrics to Firestore for multi-Mac dashboard

---

## Decision Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-08 | SPM over Xcode project | Same as beeMon; simpler CI, no `.xcodeproj` merge conflicts |
| 2026-08 | `getifaddrs` not `NetworkExtension` | No entitlements / provisioning needed |
| 2026-08 | `libproc` with `netstat` fallback | `libproc` gives process names; `netstat` is the safety net |
| 2026-08 | 2-second connection poll | `libproc` walk is O(n×FDs); 1 Hz was measurable CPU; 2s is imperceptible |

---

*netBee is crafted by Daneyand & IBM's Bob 🐝*
