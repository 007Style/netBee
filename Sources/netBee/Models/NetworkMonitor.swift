// ─────────────────────────────────────────────────────────────────────────────
// NetworkMonitor.swift  —  Core data collection engine
//
// Samples all network metrics at 1 Hz and publishes them as @Published state
// for SwiftUI views to consume.
//
// Data sources:
//   • getifaddrs          — per-interface byte / packet / error counters
//   • libproc             — per-process socket / file-descriptor info
//   • sysctl              — routing tables, interface config
// ─────────────────────────────────────────────────────────────────────────────
import Foundation
import Combine
import Darwin

// MARK: - Types

/// One sample of per-interface network statistics.
struct InterfaceSnapshot: Identifiable, Equatable {
    let id:           String     // interface name, e.g. "en0"
    let friendlyName: String     // e.g. "en0 — Wi-Fi"
    let ipv4:         String?    // primary IPv4 address
    let ipv6:         String?    // primary IPv6 address (link-local stripped)
    let mtu:          Int
    let bytesIn:      UInt64
    let bytesOut:     UInt64
    let packetsIn:    UInt64
    let packetsOut:   UInt64
    let errorsIn:     UInt64
    let errorsOut:    UInt64
    var isActive:     Bool { bytesIn > 0 || bytesOut > 0 }
}

/// Delta bandwidth between two consecutive interface samples (bytes / second).
struct InterfaceBandwidth: Identifiable {
    let id:       String   // interface name
    let rxBps:    Double   // receive bytes / sec
    let txBps:    Double   // transmit bytes / sec
}

/// A rolling-window sample: one interface's bandwidth at a point in time.
struct BandwidthSample {
    let timestamp: Date
    let rxBps:     Double
    let txBps:     Double
}

/// Summary totals across all interfaces.
struct TotalBandwidth {
    let rxBps: Double
    let txBps: Double
}

// MARK: - RollingBuffer

/// Fixed-capacity FIFO buffer — oldest element is evicted when capacity is exceeded.
struct RollingBuffer<T> {
    private(set) var elements: [T] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    mutating func append(_ element: T) {
        if elements.count >= capacity { elements.removeFirst() }
        elements.append(element)
    }

    /// Returns the last `count` elements (or all if fewer are available).
    func suffix(_ count: Int) -> ArraySlice<T> { elements.suffix(count) }
}

// MARK: - TimeWindow

enum TimeWindow: Int, CaseIterable {
    case twoMinutes  = 120
    case tenMinutes  = 600

    var label: String {
        switch self {
        case .twoMinutes:  return "2m"
        case .tenMinutes:  return "10m"
        }
    }
}

// MARK: - NetworkMonitor

@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    // ── Published state ──────────────────────────────────────────────────────
    @Published var interfaces:      [InterfaceSnapshot]   = []
    @Published var bandwidthDeltas: [InterfaceBandwidth]  = []
    @Published var totalBandwidth:  TotalBandwidth        = TotalBandwidth(rxBps: 0, txBps: 0)

    /// Per-interface rolling history (600 samples = 10 min at 1 Hz).
    @Published var history: [String: RollingBuffer<BandwidthSample>] = [:]

    // ── Private state ────────────────────────────────────────────────────────
    private var timer: AnyCancellable?
    private var previousSnapshots: [String: InterfaceSnapshot] = [:]
    private var previousTimestamp: Date?

    // ── Lifecycle ────────────────────────────────────────────────────────────

    private init() { start() }

    func start() {
        guard timer == nil else { return }
        sample()   // immediate first read
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Sampling

    private func sample() {
        let now       = Date()
        let snapshots = readInterfaces()
        let elapsed   = previousTimestamp.map { now.timeIntervalSince($0) } ?? 1.0
        let dt        = max(elapsed, 0.1)

        // ── Compute deltas ───────────────────────────────────────────────────
        var deltas: [InterfaceBandwidth] = []
        var totalRx = 0.0, totalTx = 0.0

        for snap in snapshots {
            if let prev = previousSnapshots[snap.id] {
                let rxBps = Double(snap.bytesIn  &- prev.bytesIn)  / dt
                let txBps = Double(snap.bytesOut &- prev.bytesOut) / dt
                deltas.append(InterfaceBandwidth(id: snap.id, rxBps: rxBps, txBps: txBps))
                totalRx += rxBps
                totalTx += txBps

                // ── Update rolling history ───────────────────────────────────
                var buf = history[snap.id, default: RollingBuffer(capacity: 600)]
                buf.append(BandwidthSample(timestamp: now, rxBps: rxBps, txBps: txBps))
                history[snap.id] = buf
            }
        }

        // ── Publish ──────────────────────────────────────────────────────────
        interfaces      = snapshots
        bandwidthDeltas = deltas
        totalBandwidth  = TotalBandwidth(rxBps: totalRx, txBps: totalTx)

        previousSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        previousTimestamp = now
    }

    // MARK: - getifaddrs reader

    private func readInterfaces() -> [InterfaceSnapshot] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let base = ifap else { return [] }
        defer { freeifaddrs(base) }

        // First pass: collect data links (AF_LINK) for byte / packet counters.
        var linkData:  [String: if_data]   = [:]
        var mtuData:   [String: Int]       = [:]
        // Second pass: collect AF_INET / AF_INET6 addresses.
        var ipv4Addrs: [String: String]    = [:]
        var ipv6Addrs: [String: String]    = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = base
        while let ifa = cursor {
            let name   = String(cString: ifa.pointee.ifa_name)
            let family = Int32(ifa.pointee.ifa_addr.pointee.sa_family)

            switch family {
            case AF_LINK:
                if let data = ifa.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    linkData[name] = d
                    mtuData[name]  = Int(d.ifi_mtu)
                }
            case AF_INET:
                if let sa = ifa.pointee.ifa_addr {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sa, socklen_t(ifa.pointee.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    ipv4Addrs[name] = String(cString: host)
                }
            case AF_INET6:
                if let sa = ifa.pointee.ifa_addr, ipv6Addrs[name] == nil {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(sa, socklen_t(ifa.pointee.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    let addr = String(cString: host)
                    // Skip link-local addresses (fe80::) unless there's nothing else
                    if !addr.hasPrefix("fe80") { ipv6Addrs[name] = addr }
                }
            default:
                break
            }
            cursor = ifa.pointee.ifa_next
        }

        let namer = InterfaceNamer.shared
        return linkData
            .filter { !$0.key.hasPrefix("lo") }       // skip loopback
            .map { (name, d) in
                InterfaceSnapshot(
                    id:           name,
                    friendlyName: namer.friendlyName(for: name),
                    ipv4:         ipv4Addrs[name],
                    ipv6:         ipv6Addrs[name],
                    mtu:          mtuData[name] ?? 0,
                    bytesIn:      UInt64(d.ifi_ibytes),
                    bytesOut:     UInt64(d.ifi_obytes),
                    packetsIn:    UInt64(d.ifi_ipackets),
                    packetsOut:   UInt64(d.ifi_opackets),
                    errorsIn:     UInt64(d.ifi_ierrors),
                    errorsOut:    UInt64(d.ifi_oerrors)
                )
            }
            .sorted { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut }
    }

    // MARK: - History helpers

    /// Returns windowed history for a given interface.
    func bandwidthHistory(for interfaceID: String, window: TimeWindow) -> [BandwidthSample] {
        Array(history[interfaceID]?.suffix(window.rawValue) ?? ArraySlice([]))
    }

    /// Combined RX+TX across all interfaces for the given window.
    func combinedHistory(window: TimeWindow) -> [BandwidthSample] {
        guard !history.isEmpty else { return [] }

        // Align to the shortest available history among active interfaces
        let activeIDs = bandwidthDeltas.filter { $0.rxBps + $0.txBps > 0 }.map(\.id)
        guard !activeIDs.isEmpty else { return [] }

        let slices = activeIDs.compactMap { history[$0]?.suffix(window.rawValue) }
        guard let shortest = slices.map(\.count).min() else { return [] }

        return (0..<shortest).map { i in
            let totalRx = slices.map { Double($0[$0.startIndex + i].rxBps) }.reduce(0, +)
            let totalTx = slices.map { Double($0[$0.startIndex + i].txBps) }.reduce(0, +)
            let ts      = slices[0][slices[0].startIndex + i].timestamp
            return BandwidthSample(timestamp: ts, rxBps: totalRx, txBps: totalTx)
        }
    }
}
