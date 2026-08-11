# netBee Changelog

All notable changes to netBee are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned
- DNS query monitor (per-process recent lookups + latency)
- Latency heatmap (rolling ping to configurable targets)
- New-connection notifications (alert when unknown process opens outbound socket)
- App icon (bee with network cables / signal bars)
- DMG distributable

---

## [0.1.0] — 2026-08-XX (initial scaffold)

### Added
- **Project scaffold** — SPM package, full directory structure, scripts
- **NetworkMonitor** — 1 Hz sampling via `getifaddrs`; per-interface RX/TX bytes,
  packets, errors; `RollingBuffer<BandwidthSample>` (600-sample, 10-minute window)
- **ConnectionTracker** — libproc-based per-process TCP/UDP connection enumeration;
  `netstat -an` fallback when libproc yields no data
- **InterfaceNamer** — `networksetup -listallhardwareports` gold mapping + pattern
  fallback table (matches beeMon strategy)
- **TrayController** — `NSStatusItem` with live dual sparkline icon (RX green / TX blue)
  + byte-rate label; left-click toggles dashboard, right-click shows context menu
- **DashboardView** — 5-tab window (Overview · Bandwidth · Connections · Interfaces · About)
  with live total bandwidth pill in the tab bar
- **BandwidthView** — combined + per-interface sparkline cards with 2m / 10m toggle,
  cumulative counters (total bytes, errors, MTU)
- **ConnectionsView** — searchable / filterable TCP/UDP connection table with
  process name, protocol badge, TCP state, remote endpoint, RX/TX bytes
- **InterfacesView** — expandable interface detail cards (IPv4/IPv6, MTU, counters)
- **AboutView** — animated hex-grid hero, live demo sparkline, feature pills, credits
- **DesignSystem** — DS colour tokens, `MetricCard`, `SectionHeader`,
  `TimeWindowPicker`, `formatBytes`, `formatBps` helpers
- **SparklineChart / DualSparklineChart** — Canvas-based sparklines (matches beeMon)
- **Unit tests** — 46 self-contained tests across 8 suites
  (`RollingBuffer`, `formatBytes`, `formatBps`, `TimeWindow`,
   `ConnProtocol`, `TCPState`, `InterfaceNamerPattern`)
- **Scripts** — `build.sh`, `test.sh`, `release.sh`, `lint.sh` (match beeMon style)

### Technical
- Pure Swift / SwiftUI — no third-party dependencies
- macOS 13 Ventura minimum deployment target
- Data: `getifaddrs` (interfaces), `libproc` / `netstat` (connections)
- `SystemConfiguration` and `Network` frameworks linked

---

*netBee is crafted by Daneyand & IBM's Bob 🐝*
