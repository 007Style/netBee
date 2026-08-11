# Contributing to netBee

Thank you for your interest in contributing! netBee is a native macOS app written in pure Swift / SwiftUI with zero third-party dependencies. This guide covers everything you need to get started, understand the codebase, add new features, and submit a pull request.

---

## Table of Contents

- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Project Layout](#project-layout)
- [Development Workflow](#development-workflow)
- [Adding a New Tab / Metric](#adding-a-new-tab--metric)
- [Code Style](#code-style)
- [Running the Tests](#running-the-tests)
- [Writing Tests](#writing-tests)
- [Submitting a Pull Request](#submitting-a-pull-request)

---

## Requirements

| Tool | Minimum version |
|---|---|
| macOS | 13.0 Ventura |
| Xcode Command Line Tools | 15 |
| Swift | 5.9 |
| Xcode (optional, IDE) | 15 |

Install the command line tools if you haven't already:

```bash
xcode-select --install
```

---

## Getting Started

```bash
# Clone the repo
git clone https://github.com/daneyand/netBee.git
cd netBee

# Debug build and run
swift run

# Or open in Xcode
open Package.swift
```

The app will appear in your menu bar as a dual-sparkline icon. Left-click to open the dashboard.

---

## Project Layout

```
Sources/netBee/
├── main.swift                    App entry point — AppDelegate, NSApplication bootstrap
├── Info.plist                    Bundle metadata (excluded from SPM compile target)
├── Assets/
│   └── AppIcon.icns              Application icon
│
├── Models/                       Pure data layer — no SwiftUI imports
│   ├── NetworkMonitor.swift      1 Hz getifaddrs sampler, RollingBuffer, history
│   ├── ConnectionTracker.swift   Per-process TCP/UDP socket enumeration (libproc)
│   ├── InterfaceNamer.swift      BSD name → friendly display name
│   └── LatencyMonitor.swift      5 s gateway ping, RTT history
│
├── Charts/
│   └── SparklineChart.swift      Canvas-based sparklines (SparklineChart + DualSparklineChart)
│
├── Views/                        SwiftUI views — all @MainActor
│   ├── DesignSystem.swift        DS colour tokens, MetricCard, SectionHeader, helpers
│   ├── DashboardView.swift       6-tab window + TabRouter + OverviewSection
│   ├── BandwidthView.swift       Per-interface bandwidth sparkline cards
│   ├── ConnectionsView.swift     Searchable / filterable connection table
│   ├── InterfacesView.swift      Expandable interface detail cards
│   ├── LatencyView.swift         Per-interface RTT cards with sparklines
│   └── AboutView.swift           Animated canvas about panel + live mini-graphs
│
└── Tray/
    └── TrayController.swift      NSStatusItem icon rendering + NSWindow management

Tests/netBeeTests/
└── netBeeTests.swift             46 self-contained unit tests (7 suites)

scripts/
├── build.sh                      Debug / release build helper
├── test.sh                       Test runner wrapper
├── release.sh                    Full release: compile → bundle → sign → zip → DMG
└── lint.sh                       swift-format + SwiftLint (if installed)
```

For a full architectural deep-dive, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Development Workflow

### Build

```bash
./scripts/build.sh              # debug (fast, with symbols)
./scripts/build.sh --release    # optimised release
```

### Run

```bash
swift run                       # build + launch
.build/debug/netBee             # run an already-built debug binary
```

### Test

```bash
./scripts/test.sh               # runs swift test --parallel
swift test                      # equivalent, with full XCTest output
```

### Lint (optional — requires tools)

```bash
./scripts/lint.sh
# install via: brew install swift-format swiftlint
```

### Package for distribution

```bash
./scripts/release.sh 1.0.0
# Produces: dist/netBee.app, dist/netBee-v1.0.0.zip, dist/netBee-v1.0.0.dmg
```

---

## Adding a New Tab / Metric

netBee is intentionally structured to make adding a new data source + tab straightforward. Here is the full checklist:

### 1. Add a data model (if needed)

Create `Sources/netBee/Models/YourMonitor.swift`. Follow the existing pattern:

```swift
@MainActor
final class YourMonitor: ObservableObject {
    static let shared = YourMonitor()
    @Published var results: [YourType] = []
    private var timer: AnyCancellable?

    private init() {
        // IMPORTANT: defer start() out of dispatch_once (see LatencyMonitor for why)
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        // Snapshot lightweight values on main thread
        let snapshot = ...
        // Dispatch heavy work to background
        DispatchQueue(label: "com.beemon.netbee.yourmonitor").async { [weak self] in
            let results = heavyWork(snapshot)
            DispatchQueue.main.async { self?.results = results }
        }
    }
}
```

### 2. Add a view

Create `Sources/netBee/Views/YourView.swift`. Use `@StateObject` to observe your monitor:

```swift
struct YourView: View {
    @StateObject private var monitor = YourMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your Tab", icon: "🎯")
            // ... your content using DS tokens
        }
    }
}
```

### 3. Add the tab enum case

In `Sources/netBee/Views/DashboardView.swift`, add to `DashboardTab`:

```swift
case yourTab = "Your Tab"
```

Add the icon:

```swift
case .yourTab: return "🎯"
```

Add the content case:

```swift
case .yourTab: YourView()
```

### 4. Write tests

Add at least one test suite in `Tests/netBeeTests/netBeeTests.swift` for any new model logic (formatting, data types, parsing).

### 5. Update documentation

- Add your tab/feature to the feature table in `README.md`.
- Add a section under [View Layer](ARCHITECTURE.md#8-view-layer) in `ARCHITECTURE.md`.
- Add an entry to `CHANGELOG.md` under `[Unreleased]`.

---

## Code Style

- Follow the existing `// MARK: -` section structure within each file.
- No third-party dependencies — Apple frameworks only.
- All UI must compile for macOS 13+. Do not use APIs that require macOS 14+.
- Use `DS.*` tokens for all colours, fonts, and spacing — never hard-code colours.
- Model files must not import SwiftUI.
- View files must not do blocking I/O.
- All `@Published` mutations must happen on the main thread.
- Prefer `struct` over `class` for value types. Use `final class` for singletons and ObservableObjects.
- New model logic must have a corresponding unit test.

---

## Running the Tests

```bash
swift test
# or
./scripts/test.sh
```

The test suite is entirely self-contained — it does not link against the executable target. Tested types are inlined as private copies inside the test file. This is a necessary workaround for Swift Package Manager's limitation that executable targets cannot be linked as library dependencies.

All tests must pass before a PR will be merged:

```
Test Suite 'All tests' passed.
  Executed 46 tests, with 0 failures (0 unexpected) in X.XXX seconds
```

---

## Writing Tests

Add new test suites to `Tests/netBeeTests/netBeeTests.swift`. Follow the existing naming convention:

```swift
final class YourTypeTests: XCTestCase {
    func test_someExpectedBehaviour() {
        // Arrange
        let input = ...
        // Act
        let result = yourFunction(input)
        // Assert
        XCTAssertEqual(result, expectedValue)
    }
}
```

If the type you are testing lives in the main target, inline a copy of the relevant struct/function/enum into the test file as a `private` definition (see existing examples in the test file).

---

## Submitting a Pull Request

1. **Fork** the repository and create a feature branch:
   ```bash
   git checkout -b feat/my-feature
   ```

2. **Make your changes** with clear, focused commits. Each commit should represent one logical change.

3. **Run the tests** and confirm everything passes:
   ```bash
   ./scripts/test.sh
   ```

4. **Build a release** to confirm no regressions:
   ```bash
   ./scripts/build.sh --release
   ```

5. **Update the docs** — add your feature to `README.md` and `CHANGELOG.md`.

6. **Open a PR** against `main` with:
   - A clear title (`feat: add DNS query monitor tab`)
   - A description of what you changed and why
   - Screenshots if the change affects any UI

---

*netBee is crafted by Daneyand & IBM's Bob 🐝*
