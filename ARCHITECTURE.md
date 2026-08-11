# netBee — Architecture

> Deep-dive technical design document for contributors and curious readers.  
> Last updated: v1.0.0

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Process Model](#2-process-model)
3. [Data Collection Layer](#3-data-collection-layer)
   - 3.1 [NetworkMonitor — Interface Sampling](#31-networkmonitor--interface-sampling)
   - 3.2 [ConnectionTracker — Per-Process Sockets](#32-connectiontracker--per-process-sockets)
   - 3.3 [LatencyMonitor — Gateway Ping](#33-latencymonitor--gateway-ping)
   - 3.4 [InterfaceNamer — Friendly Names](#34-interfacenamer--friendly-names)
4. [Threading Model](#4-threading-model)
5. [SwiftUI State Management](#5-swiftui-state-management)
   - 5.1 [Singleton ObservableObjects](#51-singleton-observableobjects)
   - 5.2 [TabRouter — Cross-Boundary Tab Control](#52-tabrouter--cross-boundary-tab-control)
6. [Tray Icon Rendering Pipeline](#6-tray-icon-rendering-pipeline)
7. [Rolling Buffer and History Windowing](#7-rolling-buffer-and-history-windowing)
8. [View Layer](#8-view-layer)
   - 8.1 [DashboardView](#81-dashboardview)
   - 8.2 [BandwidthView](#82-bandwidthview)
   - 8.3 [ConnectionsView](#83-connectionsview)
   - 8.4 [InterfacesView](#84-interfacesview)
   - 8.5 [LatencyView](#85-latencyview)
   - 8.6 [AboutView](#86-aboutview)
9. [Design System](#9-design-system)
10. [Sparkline Charts](#10-sparkline-charts)
11. [Known Constraints and Workarounds](#11-known-constraints-and-workarounds)
12. [Data Flow Diagram](#12-data-flow-diagram)

---

## 1. High-Level Overview

netBee is a macOS menu-bar agent (`LSUIElement = true`) built entirely with Swift and SwiftUI. It has no third-party dependencies and communicates with the kernel exclusively through POSIX/BSD APIs and Apple system utilities.

```
┌─────────────────────────────────────────────────────────────────────┐
│                          macOS Kernel                               │
│   getifaddrs  │  libproc (proc_pidinfo)  │  /sbin/ping  │  route   │
└───────┬───────┴──────────────┬───────────┴──────┬────────┴──────────┘
        │                      │                   │
   NetworkMonitor        ConnectionTracker    LatencyMonitor
   (1 Hz, @MainActor)    (2 Hz, background)  (0.2 Hz, background)
        │                      │                   │
        └──────────────────────┴───────────────────┘
                               │
                        @Published state
                               │
                    ┌──────────▼──────────┐
                    │   SwiftUI Views     │
                    │  (DashboardView     │
                    │   + 6 tab views)    │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │   TrayController    │
                    │  (NSStatusItem +    │
                    │   NSWindow)         │
                    └─────────────────────┘
```

---

## 2. Process Model

netBee launches as a standard macOS application but sets `NSApp.activationPolicy = .accessory` on startup, which:

- Hides the app from the Dock.
- Hides the app from the Command-Tab switcher.
- Keeps the app running in the background.

The `Info.plist` key `LSUIElement = true` reinforces this at the bundle level, preventing a Dock icon from briefly appearing even before the activation policy is set in code.

Entry point: `main.swift` → `AppDelegate.applicationDidFinishLaunching` → `TrayController()`.

`TrayController` is the root owner of both the `NSStatusItem` (tray icon) and the single `NSWindow` (dashboard). It is retained by `AppDelegate`.

---

## 3. Data Collection Layer

All data collection happens in `Sources/netBee/Models/`. None of these files import SwiftUI — they are pure Foundation/Combine and can be tested without a display.

### 3.1 NetworkMonitor — Interface Sampling

**File:** `Sources/netBee/Models/NetworkMonitor.swift`  
**Cadence:** 1 Hz (once per second)  
**Thread:** Main thread (`@MainActor`)

`NetworkMonitor` calls `getifaddrs(3)` on every tick to walk all network interfaces. It collects:

- **AF_LINK** records → `if_data` struct → raw byte, packet, and error counters.
- **AF_INET** records → IPv4 address string via `getnameinfo(3)`.
- **AF_INET6** records → IPv6 address string; link-local (`fe80::`) addresses are skipped if a global address is available.

On each sample it computes delta bytes/second since the previous tick:

```
rxBps = (currentBytesIn  - previousBytesIn)  / elapsedSeconds
txBps = (currentBytesOut - previousBytesOut) / elapsedSeconds
```

Subtraction uses wrapping arithmetic (`&-`) to handle the counter rollover that occurs when `ifi_ibytes` or `ifi_obytes` wraps around `UInt64.max` (rare on modern hardware, but correct).

Results are stored in a `[String: RollingBuffer<BandwidthSample>]` dictionary keyed by BSD interface name. Each buffer holds 600 samples (10 minutes at 1 Hz). A `combinedHistory(window:)` helper aligns samples across all active interfaces and sums them for the "all interfaces" sparkline.

Loopback interfaces (`lo*`) are excluded from all results.

**Published properties:**
- `interfaces: [InterfaceSnapshot]` — current snapshot of all non-loopback interfaces.
- `bandwidthDeltas: [InterfaceBandwidth]` — latest RX/TX bytes-per-second for each interface.
- `totalBandwidth: TotalBandwidth` — summed RX/TX across all interfaces.
- `history: [String: RollingBuffer<BandwidthSample>]` — rolling 10-minute history per interface.

### 3.2 ConnectionTracker — Per-Process Sockets

**File:** `Sources/netBee/Models/ConnectionTracker.swift`  
**Cadence:** 2 Hz (every 2 seconds)  
**Thread:** Background dispatch queue → publishes to main thread

`ConnectionTracker` enumerates all open TCP and UDP sockets across all visible processes using the private-but-stable `libproc` API:

1. `proc_listallpids(nil, 0)` — obtain a count of all PIDs.
2. `proc_listallpids(&pids, bufSize)` — fill a buffer with all PID values.
3. For each PID: `proc_pidinfo(pid, PROC_PIDLISTFDS, ...)` — list all open file descriptors.
4. For each FD where `proc_fdtype == PROX_FDTYPE_SOCKET`: `proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, ...)` — retrieve full socket info as a `socket_fdinfo` struct.
5. From `socket_fdinfo`: extract address family, socket kind, local/remote addresses and ports, TCP state, and socket buffer byte counters.

If `libproc` yields no results (e.g. when the process has no user-space access to other PIDs, or on some sandboxed configurations), the tracker falls back to parsing `netstat -an -p tcp` output. The fallback produces minimal entries (no PID or process name).

**Byte counters** come from `soi_rcv.sbi_mbcnt` and `soi_snd.sbi_mbcnt`, which track socket-level receive and send buffer consumption respectively. These are not cumulative link-layer counters; they reflect per-socket traffic.

**Published properties:**
- `connections: [ConnectionEntry]` — all currently open connections, sorted by total bytes (rx + tx) descending.

### 3.3 LatencyMonitor — Gateway Ping

**File:** `Sources/netBee/Models/LatencyMonitor.swift`  
**Cadence:** 5 s  
**Thread:** `com.beemon.netbee.latency` background queue → publishes to main thread

For each active network interface, `LatencyMonitor`:

1. Discovers the interface's default gateway IP using `/sbin/route -n get default -ifscope <interface>`. The output is parsed for the `gateway:` line; link-layer addresses (containing colons, like `aa:bb:cc:dd:ee:ff`) are skipped.
2. Pings that gateway with `/sbin/ping -c 1 -W 1000 -q <ip>`. The `-q` (quiet) flag suppresses per-packet output; only the summary statistics line is emitted.
3. Parses the `round-trip min/avg/max/stddev = ...` line with a regex to extract the average RTT in milliseconds.
4. If the interface has no default gateway (e.g. a VPN interface), falls back to pinging `8.8.8.8`.

**Dispatch-once safety:** `LatencyMonitor.shared` is a `dispatch_once` singleton (Swift's `static let`). On the first access, `init()` runs inside the `dispatch_once` lock. If `start()` were called directly from `init()`, it would call `probe()`, which dispatches gateway lookup work to `queue.async`. However, `NSTask.waitUntilExit()` internally pumps the run loop, which can re-enter the `dispatch_once` initialiser, triggering a deadlock (`"BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively"`).

The fix: `init()` defers `start()` with `DispatchQueue.main.async`, ensuring `dispatch_once` has fully returned before any `NSTask` work begins.

**Rolling history:** Each interface keeps up to 120 samples (~10 minutes at 5 s cadence). `InterfaceLatency` provides `averageMs`, `minMs`, and `maxMs` computed over the history of successful replies.

**Published properties:**
- `results: [InterfaceLatency]` — one entry per active interface, with current RTT and history.

### 3.4 InterfaceNamer — Friendly Names

**File:** `Sources/netBee/Models/InterfaceNamer.swift`  
**Init:** Once at launch (synchronous, ~50 ms)

BSD network interface names (`en0`, `utun2`, etc.) are not human-readable. `InterfaceNamer` builds a mapping at launch by running `networksetup -listallhardwareports`, which outputs blocks like:

```
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: a4:c3:f0:…
```

This is parsed into a `[String: String]` dictionary (`"en0" → "Wi-Fi"`). The `friendlyName(for:)` method returns `"en0 — Wi-Fi"`.

For interfaces not covered by `networksetup` (VPNs, virtual bridges, AirDrop interfaces), a hardcoded prefix table provides fallbacks:

| Prefix | Label |
|---|---|
| `utun` | VPN Tunnel |
| `ipsec` | IPsec VPN |
| `llw` | Low-Latency WLAN |
| `awdl` | AirDrop |
| `bridge` | Bridge |
| `anpi` | Apple NPI |
| `ap` | Personal Hotspot |
| `ppp` | PPP |

Unknown interfaces fall back to the raw BSD name.

---

## 4. Threading Model

```
Main thread (@MainActor)
├── NetworkMonitor.sample()          — getifaddrs, delta calc, history update
├── ConnectionTracker timer fires    — kicks off queue.async
├── LatencyMonitor timer fires       — kicks off queue.async
├── SwiftUI render loop              — reads @Published state
└── TrayController icon updates      — NSBitmapImageRep draw

com.beemon.netbee.connections (DispatchQueue, .utility)
└── ConnectionTracker.fetchConnections()   — libproc walk, netstat fallback
    └── DispatchQueue.main.async           — publish results

com.beemon.netbee.latency (DispatchQueue, .utility)
└── LatencyMonitor: gateway lookup + ping (per interface, sequential)
    └── DispatchQueue.main.async           — update histories + publish results
```

Key rules:
- No `@Published` property is ever mutated off the main thread.
- Background queues only do blocking I/O (`NSTask.waitUntilExit`) and pass plain value types (`struct`s, tuples) back to the main thread.
- `@MainActor` is applied to both `NetworkMonitor` and `LatencyMonitor` classes to make the Swift concurrency checker enforce this.

---

## 5. SwiftUI State Management

### 5.1 Singleton ObservableObjects

All three data-layer singletons conform to `ObservableObject`. Views observe them via `@StateObject`:

```swift
@StateObject private var monitor = NetworkMonitor.shared
```

Using `@StateObject` (rather than `@ObservedObject`) ensures SwiftUI owns the lifetime of the reference and does not recreate it across view updates. Since all three are singletons, `@StateObject` and `@ObservedObject` behave identically at runtime, but `@StateObject` is the semantically correct choice.

### 5.2 TabRouter — Cross-Boundary Tab Control

The dashboard's active tab is owned by `TabRouter.shared`, a tiny singleton:

```swift
final class TabRouter: ObservableObject {
    static let shared = TabRouter()
    @Published var activeTab: DashboardTab = .overview
}
```

`DashboardView` observes `TabRouter` via `@StateObject`. `TrayController` writes to `TabRouter.shared.activeTab` directly from AppKit code (e.g. when "About netBee" is selected from the right-click menu) before calling `window.makeKeyAndOrderFront`. This works regardless of whether the window is already open or being created for the first time, without any SwiftUI `Binding` passing or delegate callbacks.

---

## 6. Tray Icon Rendering Pipeline

`TrayController.renderIcon(rxBps:txBps:)` runs every second on the main thread.

The rendering pipeline:

1. Allocate an `NSBitmapImageRep` at 72×18 points directly. Using a bitmap rep (rather than `NSImage.lockFocus` or `NSImage(size:flipped:drawingHandler:)`) ensures the drawing context is an explicit offscreen pixel buffer that the status bar cannot tint or recomposite.
2. Set `NSGraphicsContext.current` to a context wrapping the rep.
3. Fill the entire rect with `NSColor.black`.
4. Draw the RX sparkline (green, top 8 rows) and TX sparkline (blue, bottom 8 rows) using `NSBezierPath`. Values are normalised to `[0, 1]` against the rolling maximum.
5. Draw the byte-rate label (`"1.2M 0.4M"`) using `NSFont.monospacedDigitSystemFont(ofSize:8)` aligned to the right edge.
6. Restore the graphics state, wrap the rep in an `NSImage`, set `isTemplate = false`, and assign to `statusItem.button?.image`.

Setting `isTemplate = false` is critical. Template images are rendered by the system in a tinted style that ignores the original pixel colours. Non-template images are composited as-is.

---

## 7. Rolling Buffer and History Windowing

`RollingBuffer<T>` is a value-type FIFO with fixed capacity:

```swift
struct RollingBuffer<T> {
    private(set) var elements: [T] = []
    let capacity: Int
    mutating func append(_ element: T) {
        if elements.count >= capacity { elements.removeFirst() }
        elements.append(element)
    }
    func suffix(_ count: Int) -> ArraySlice<T> { elements.suffix(count) }
}
```

- Capacity is clamped to a minimum of 1.
- `removeFirst()` on an array is O(n), but at capacity 600 this is ~5 μs — negligible at 1 Hz.
- History is keyed by BSD interface name: `[String: RollingBuffer<BandwidthSample>]`.
- The `TimeWindow` enum (`.twoMinutes = 120`, `.tenMinutes = 600`) maps directly to `suffix(rawValue)` calls.

`combinedHistory(window:)` in `NetworkMonitor` aligns all active interface histories to the shortest common length and sums them element-wise. This prevents a newly-active interface with only a few samples from producing a jagged combined view.

---

## 8. View Layer

All views are in `Sources/netBee/Views/`. They import SwiftUI only.

### 8.1 DashboardView

The root view rendered by `NSHostingView`. It owns:
- A `TabRouter` observer.
- The tab bar (`HStack` of `Button` items, each reading `router.activeTab`).
- A live bandwidth pill in the top-right of the tab bar.
- A `ScrollView` wrapping whichever tab content is active.

The window is 760×580 pts, which is the minimum width that fits all six tab labels on one line without wrapping.

### 8.2 BandwidthView

Renders a combined dual-sparkline card followed by one `InterfaceBandwidthCard` per interface that has at least one history sample. Each card shows the interface friendly name, current IPv4, live RX/TX rate, a dual sparkline, and cumulative byte/error/MTU counters.

### 8.3 ConnectionsView

A live table of `ConnectionEntry` values from `ConnectionTracker`. Filtering is computed on every render from the search text and protocol filter state (no debounce needed at 2 Hz refresh). The table is capped at 100 visible rows; a "N more" message is shown when the filter returns more than 100.

### 8.4 InterfacesView

One expandable `InterfaceDetailCard` per interface. The chevron button toggles `@State private var expanded` with a `.easeInOut(duration: 0.15)` animation. Expanded view shows IPv4, IPv6, MTU, packets in/out, bytes in/out, and error counts (shown in amber if non-zero).

### 8.5 LatencyView

One `LatencyCard` per `InterfaceLatency` from `LatencyMonitor.results`. Each card shows:
- The interface friendly name and target host.
- Current RTT as a large monospaced number (coloured by quality band).
- Four stat cells: avg / min / max / last.
- A normalised sparkline of RTT history.
- A reply-count ratio.

When `results` is empty (before the first 5-second probe completes), a `ProgressView` spinner with "Probing gateways…" is shown.

### 8.6 AboutView

Three vertical zones:

1. **`StarNetworkCanvas`** — a `Canvas` view with two `Timer.publish` subscriptions: a 60 fps animation timer that advances the star phase, and a 20 Hz hex-grid timer. Stars are defined as value-type tuples `(angleOffset, orbitR, size, speed)`. Star positions are computed on every frame as trigonometric functions of `phase * speed + angleOffset`. Edges between stars within 200 pts are drawn with opacity proportional to `1 - distance/200`. The hex grid uses a phase-shifted sine on the distance from centre for a pulsing wave effect.

2. **Info row** — fixed 220 pt height. Left column: bee logo with pulsing glow ring, app name, version. Right column: tagline, email, feature grid, tech line.

3. **Live graphics strip** — fixed 130 pt height, three equal-width panels:
   - `LiveBandwidthCard`: maintains its own 60-sample rolling arrays fed by a 1 Hz timer; overlays RX/TX values as text on a `DualSparklineChart`.
   - `ConnectionDonutCard`: draws a segmented arc ring (Established / Listen / Other) using `Canvas` with `Path.addArc`. The total count is drawn in the centre via `ctx.draw(Text(...))`.
   - `LatencyBarsCard`: one `LatencyBarRow` per interface (up to 4). Each row is a `GeometryReader` that scales a filled `RoundedRectangle` to `width * (currentMs / 200)`.

---

## 9. Design System

`Sources/netBee/Views/DesignSystem.swift` defines all visual tokens as static properties of the `DS` enum:

| Token | Value | Usage |
|---|---|---|
| `bgPrimary` | `#1C1E24` | Window / main background |
| `bgSecondary` | `#242730` | Tab bar, cards, secondary areas |
| `bgCard` | `#2B2E38` | MetricCard fill |
| `border` | `white @ 7%` | All dividers and card borders |
| `rxGreen` | `#45B366` | Receive / download |
| `txBlue` | `#4D99E5` | Transmit / upload |
| `beeYellow` | `#F5D42E` | Primary accent, tab highlights |
| `warnAmber` | `#EDA921` | Errors, warnings, fair latency |
| `textPrimary` | `white` | Primary text |
| `textSecondary` | `white @ 55%` | Labels, secondary text |
| `textMuted` | `white @ 30%` | Hints, captions |

Shared components:
- **`MetricCard`** — a generic `View` builder that applies the standard card padding, background, corner radius, and border overlay.
- **`SectionHeader`** — an optional emoji icon + bold title + trailing `Spacer()`.
- **`TimeWindowPicker`** — a pair of pill buttons bound to a `TimeWindow` selection.

Helper functions (`formatBytes`, `formatBps`) are module-level free functions so they can be called from any view without `self`.

---

## 10. Sparkline Charts

`SparklineChart` accepts `[Double]` values (any scale), normalises them against `values.max()`, and draws:
- A filled area path (opacity 0.25) from the baseline up to the value line.
- A stroked line path at the top of the fill.

`DualSparklineChart` overlays two `SparklineChart` instances (RX green, TX blue) in a `ZStack` at shared 20% opacity so the fill regions blend visually.

Both charts use SwiftUI `Canvas`, which avoids UIKit/AppKit view hierarchy overhead and renders the entire chart in a single draw call.

---

## 11. Known Constraints and Workarounds

### libproc access limitations

`proc_pidinfo` and `proc_pidfdinfo` require that the calling process either owns the target PID or has root privileges. Standard user-space apps can enumerate their own sockets and, on macOS, typically can see many (but not all) system processes. Sockets belonging to sandboxed system processes or processes owned by other users may be invisible. The `netstat` fallback covers the case where `libproc` returns nothing at all.

### Ad-hoc code signing

The release DMG is signed with an ad-hoc identity (`codesign --sign -`). This means macOS Gatekeeper will prompt the user on first launch. The app is not notarised. To notarise, a paid Apple Developer account and `xcrun notarytool` are required; that step is intentionally left out of the release script for now.

### Latency measurement accuracy

`/sbin/ping` on macOS adds a minimum overhead of ~1–2 ms due to process launch and ICMP socket setup. The reported RTT is the ICMP round-trip to the gateway, not the application-layer RTT to any service. It is a proxy for local network health, not end-to-end latency.

### Byte counters in ConnectionTracker

`soi_rcv.sbi_mbcnt` and `soi_snd.sbi_mbcnt` track socket memory buffer usage, not total bytes transferred over the lifetime of the connection. Values reset when the socket buffer is drained or the connection is closed. They are useful for relative comparison but not as precise lifetime byte counters.

---

## 12. Data Flow Diagram

```
getifaddrs (1 Hz)
    │
    ▼
NetworkMonitor.sample()
    ├── interfaces:      [InterfaceSnapshot]     ──► Overview, Bandwidth, Interfaces views
    ├── bandwidthDeltas: [InterfaceBandwidth]     ──► Tray icon, Overview, Bandwidth views
    ├── totalBandwidth:  TotalBandwidth           ──► Tab bar pill, About live card
    └── history:         [String: RollingBuffer]  ──► Bandwidth, Overview sparklines


libproc / netstat (2 Hz, background)
    │
    ▼
ConnectionTracker.fetchConnections()
    └── connections: [ConnectionEntry]  ──► Connections view, Overview count, About donut


/sbin/ping + /sbin/route (5 s, background)
    │
    ▼
LatencyMonitor.probe()
    └── results: [InterfaceLatency]  ──► Latency view, About bars


networksetup (once at launch)
    │
    ▼
InterfaceNamer.buildNameMap()
    └── nameMap: [String: String]  ──► friendlyName(for:) called by NetworkMonitor


TabRouter.shared.activeTab: DashboardTab
    │
    ├── Written by: TrayController (right-click menu)
    └── Read by:    DashboardView tab bar + content switcher
```

---

*netBee is built by Daneyand & IBM's Bob 🐝*
