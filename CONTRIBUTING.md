# Contributing to netBee

Thank you for your interest in contributing! netBee is a native macOS app
written in pure Swift / SwiftUI with no third-party dependencies.

---

## Requirements

| Tool   | Version         |
|--------|-----------------|
| macOS  | 13 Ventura or later |
| Xcode  | 15+             |
| Swift  | 5.9+            |

---

## Getting started

```bash
git clone https://github.com/007Style/netBee.git
cd netBee
swift build          # debug build
swift run            # build and launch
```

Or open in Xcode:

```bash
open Package.swift
```

---

## Project layout

```
Sources/netBee/
├── main.swift                    AppDelegate + NSApplication entry point
├── Info.plist                    Bundle metadata (excluded from SPM compile)
│
├── Models/
│   ├── NetworkMonitor.swift      Interface sampling (getifaddrs) + RollingBuffer
│   ├── ConnectionTracker.swift   Per-process TCP/UDP connections (libproc)
│   └── InterfaceNamer.swift      Friendly names via networksetup + pattern table
│
├── Charts/
│   └── SparklineChart.swift      SwiftUI Canvas sparklines (single + dual)
│
├── Views/
│   ├── DesignSystem.swift        DS tokens · MetricCard · TimeWindowPicker · helpers
│   ├── DashboardView.swift       5-tab main window + OverviewSection
│   ├── BandwidthView.swift       Per-interface bandwidth sparklines
│   ├── ConnectionsView.swift     Searchable connection table
│   ├── InterfacesView.swift      Interface detail cards
│   └── AboutView.swift           About panel + HexGridBackground
│
└── Tray/
    └── TrayController.swift      NSStatusItem dual sparkline icon + window mgmt

Tests/netBeeTests/
└── netBeeTests.swift             46 self-contained unit tests

scripts/
├── build.sh                      Debug / release build
├── test.sh                       Run test suite
├── release.sh                    Build .app bundle + DMG + zip
└── lint.sh                       swift-format + SwiftLint (optional)
```

---

## Scripts

```bash
./scripts/build.sh              # debug build
./scripts/build.sh --release    # release build
./scripts/test.sh               # run unit tests
./scripts/release.sh 1.0.0      # package dist/netBee.app + zip + DMG
./scripts/lint.sh               # lint (requires swift-format / swiftlint)
```

---

## Running tests

```bash
swift test
# or
./scripts/test.sh
```

---

## Code style

- Follow existing file and `// MARK: -` section structure
- No third-party dependencies — use only Apple frameworks
- All UI must compile for macOS 13+
- New data-layer changes should include a corresponding unit test

---

## Submitting a pull request

1. Fork the repo and create a branch: `git checkout -b feat/my-feature`
2. Make your changes with clear, focused commits
3. Run `./scripts/test.sh` and confirm all tests pass
4. Open a PR against `main` with a clear description

---

*netBee is crafted by Daneyand & IBM's Bob 🐝*
