// ─────────────────────────────────────────────────────────────────────────────
// LatencyMonitor.swift  —  Ping-based latency per network interface gateway
//
// For each active interface, probes the default gateway (or 8.8.8.8 as
// fallback) using `/sbin/ping -c1 -W500 -b` and records round-trip time.
// Runs on a background queue; publishes results to the main thread at ~5 s.
// ─────────────────────────────────────────────────────────────────────────────
import Foundation
import Combine

// MARK: - LatencySample

struct LatencySample {
    let timestamp: Date
    let ms:        Double   // round-trip in milliseconds; -1 = timeout / unreachable
}

// MARK: - InterfaceLatency

struct InterfaceLatency: Identifiable {
    let id:          String    // interface name, e.g. "en0"
    let friendlyName: String
    let targetHost:  String    // gateway or fallback host we ping
    let current:     Double    // latest RTT in ms (-1 = no reply)
    var history:     [LatencySample]

    var isReachable: Bool { current >= 0 }

    var averageMs: Double {
        let valid = history.compactMap { $0.ms >= 0 ? $0.ms : nil }
        guard !valid.isEmpty else { return -1 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    var minMs: Double {
        history.compactMap { $0.ms >= 0 ? $0.ms : nil }.min() ?? -1
    }

    var maxMs: Double {
        history.compactMap { $0.ms >= 0 ? $0.ms : nil }.max() ?? -1
    }
}

// MARK: - LatencyMonitor

@MainActor
final class LatencyMonitor: ObservableObject {

    static let shared = LatencyMonitor()

    @Published var results: [InterfaceLatency] = []

    private var timer: AnyCancellable?
    private let queue = DispatchQueue(label: "com.beemon.netbee.latency", qos: .utility)

    // Rolling 120-sample history per interface (~10 min at 5 s cadence)
    private var histories: [String: [LatencySample]] = [:]
    private let maxHistory = 120

    private init() {
        // Do NOT call start() here — this runs inside dispatch_once for `shared`.
        // Spawning a Process (via probe→defaultGateway) while dispatch_once holds
        // its lock causes waitUntilExit to pump the run loop, which tries to
        // re-enter the same lock → "BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively".
        // Defer start() until the next run-loop turn so dispatch_once has fully returned.
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func start() {
        guard timer == nil else { return }
        // First probe is also deferred — kick it off after a tiny delay so the
        // timer is installed before any blocking work begins on the background queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.probe() }
        timer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.probe() }
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: - Probe all active interfaces

    private func probe() {
        // Snapshot interface list on the main thread before going to background
        let active = NetworkMonitor.shared.interfaces.filter { $0.isActive }
        guard !active.isEmpty else { return }

        // Capture only lightweight value types — no actor-isolated state crosses into the queue
        let snapshots: [(id: String, friendlyName: String)] = active.map { ($0.id, $0.friendlyName) }

        queue.async { [weak self] in
            // Gateway lookup AND ping both run entirely on the background queue
            var fresh: [(id: String, friendlyName: String, host: String, ms: Double)] = []
            for snap in snapshots {
                let host = LatencyMonitor.defaultGateway(for: snap.id) ?? "8.8.8.8"
                let ms   = LatencyMonitor.ping(host: host)
                fresh.append((snap.id, snap.friendlyName, host, ms))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for item in fresh {
                    var buf = self.histories[item.id, default: []]
                    buf.append(LatencySample(timestamp: Date(), ms: item.ms))
                    if buf.count > self.maxHistory { buf.removeFirst() }
                    self.histories[item.id] = buf
                }
                self.results = fresh.map { item in
                    InterfaceLatency(
                        id:           item.id,
                        friendlyName: item.friendlyName,
                        targetHost:   item.host,
                        current:      item.ms,
                        history:      self.histories[item.id] ?? []
                    )
                }
            }
        }
    }

    // MARK: - /sbin/ping wrapper

    /// Sends one ICMP echo and returns RTT in ms, or -1 on failure/timeout.
    nonisolated private static func ping(host: String) -> Double {
        let task = Process()
        task.launchPath = "/sbin/ping"
        // -c 1 : one packet   -W 1000 : 1 s timeout   -q : quiet
        task.arguments  = ["-c", "1", "-W", "1000", "-q", host]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do { try task.run() } catch { return -1 }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return -1 }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return -1 }

        // Parse "round-trip min/avg/max/stddev = 4.123/4.123/4.123/0.000 ms"
        if let range = out.range(of: #"= [\d.]+/([\d.]+)/"#, options: .regularExpression) {
            let match = String(out[range])
            let parts = match.components(separatedBy: "/")
            if parts.count >= 2, let avg = Double(parts[1]) { return avg }
        }
        return -1
    }

    // MARK: - Default gateway lookup

    /// Returns the default gateway IP for the given interface using `route get default`.
    nonisolated private static func defaultGateway(for iface: String) -> String? {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments  = ["-n", "get", "default", "-ifscope", iface]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }

        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let gw = trimmed.replacingOccurrences(of: "gateway:", with: "")
                                .trimmingCharacters(in: .whitespaces)
                // Skip link-layer addresses (contain colons like aa:bb:cc)
                if !gw.isEmpty && !gw.contains(":") { return gw }
            }
        }
        return nil
    }
}
