# netBee Changelog

All notable changes to netBee are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned
- DNS query monitor (per-process recent lookups + latency)
- New-connection notifications (alert when unknown process opens outbound socket)

---

## [1.0.0] — 2026-08-11

### Added
- **LatencyView** — new ⏱ Latency tab with per-interface gateway ping (ICMP via
  `/sbin/ping`). Shows current RTT as a large colour-coded number, avg/min/max stats,
  rolling 120-sample sparkline, and reply-count ratio.
  Quality bands: green < 20 ms · yellow < 80 ms · amber < 200 ms · red ≥ 200 ms.
- **LatencyMonitor** — background 5 s probe pipeline. Gateway is discovered via
  `/sbin/route -n get default -ifscope <iface>`; falls back to `8.8.8.8`. Rolling
  120-sample history (~10 min at 5 s cadence). Defers `start()` out of `dispatch_once`
  init path to prevent libdispatch recursive-lock crash.
- **TabRouter** — tiny `ObservableObject` singleton that owns `activeTab: DashboardTab`.
  Allows `TrayController` to drive the active tab from AppKit code at any time,
  including when the dashboard window is already open. Fixes "About" menu item not
  switching to the About tab.
- **AboutView redesign** — no-scroll layout with three zones:
  1. `StarNetworkCanvas` — 60 fps animated orbiting stars with connecting network edges
     and a drifting hex grid background.
  2. Info row — bee logo + version (left), tagline + email + feature grid (right).
  3. Live graphics strip — `LiveBandwidthCard` (dual sparkline), `ConnectionDonutCard`
     (arc-ring by state), `LatencyBarsCard` (per-interface RTT bars).
- **Wider dashboard** — window widened from 640 → 760 px so all 6 tabs fit on one line.
- **Black tray icon background** — rewrote `renderIcon` to use `NSBitmapImageRep`
  drawn via `NSGraphicsContext`, bypassing the status bar's lazy compositing that
  was overriding the fill colour with a system tint.
- **Version 1.0.0** — `CFBundleShortVersionString` bumped in `Info.plist`.

### Fixed
- Clicking the Latency tab crashed with
  `"BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively"`. Root cause: SwiftUI
  initialising `@StateObject var latency = LatencyMonitor.shared` triggered
  `dispatch_once` for the singleton on the main thread; `init()` called `start()` →
  `probe()` → `defaultGateway()` → `NSTask.waitUntilExit()`, which pumped the run
  loop and re-entered the `dispatch_once` lock. Fixed by deferring `start()` (and the
  first `probe()`) to the next run-loop turn via `DispatchQueue.main.async`.
- "About netBee" right-click menu item opened the dashboard but did not switch to
  the About tab when the window was already open. Fixed with `TabRouter`.
- Tray icon appeared with a transparent / system-tinted background instead of solid
  black. Fixed by using `NSBitmapImageRep` instead of `NSImage.lockFocus` /
  `NSImage(size:flipped:drawingHandler:)`.

---

## [0.1.0] — 2026-08-01 (initial scaffold)

### Added
- **Project scaffold** — SPM package, full directory structure, helper scripts
- **NetworkMonitor** — 1 Hz sampling via `getifaddrs`; per-interface RX/TX bytes,
  packets, errors; `RollingBuffer<BandwidthSample>` (600-sample, 10-minute window)
- **ConnectionTracker** — libproc-based per-process TCP/UDP connection enumeration;
  `netstat -an` fallback when libproc yields no data
- **InterfaceNamer** — `networksetup -listallhardwareports` gold mapping + pattern
  fallback table (en / utun / ipsec / ppp / bridge / llw / awdl / anpi / ap)
- **TrayController** — `NSStatusItem` with live dual sparkline icon (RX green / TX blue)
  + byte-rate label; left-click toggles dashboard, right-click shows context menu
- **DashboardView** — 5-tab window (Overview · Bandwidth · Connections · Interfaces · About)
  with live total bandwidth pill in the tab bar
- **BandwidthView** — combined + per-interface sparkline cards with 2 m / 10 m toggle,
  cumulative counters (total bytes, errors, MTU)
- **ConnectionsView** — searchable / filterable TCP/UDP connection table with
  process name, protocol badge, TCP state, remote endpoint, RX/TX bytes
- **InterfacesView** — expandable interface detail cards (IPv4/IPv6, MTU, counters)
- **AboutView** — animated hex-grid hero, live demo sparkline, feature pills, credits
- **DesignSystem** — DS colour tokens, `MetricCard`, `SectionHeader`,
  `TimeWindowPicker`, `formatBytes`, `formatBps` helpers
- **SparklineChart / DualSparklineChart** — Canvas-based sparklines
- **Unit tests** — 46 self-contained tests across 7 suites
  (`RollingBuffer`, `formatBytes`, `formatBps`, `TimeWindow`,
   `ConnProtocol`, `TCPState`, `InterfaceNamerPattern`)
- **Scripts** — `build.sh`, `test.sh`, `release.sh`, `lint.sh`

### Technical
- Pure Swift / SwiftUI — no third-party dependencies
- macOS 13 Ventura minimum deployment target
- Data: `getifaddrs` (interfaces), `libproc` / `netstat` (connections)
- `SystemConfiguration` and `Network` frameworks linked

---

*netBee is crafted by Daneyand & IBM's Bob 🐝*
