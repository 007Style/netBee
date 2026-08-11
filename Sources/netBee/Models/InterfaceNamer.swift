// ─────────────────────────────────────────────────────────────────────────────
// InterfaceNamer.swift  —  Maps BSD interface names to friendly display names
//
// Strategy (same as beeMon):
//   1. Query `networksetup -listallhardwareports` once at launch → gold mapping
//   2. Fall back to a hardcoded pattern table for known VPN / virtual interfaces
//   3. Last resort: return the raw BSD name
// ─────────────────────────────────────────────────────────────────────────────
import Foundation

// MARK: - InterfaceNamer

final class InterfaceNamer {

    static let shared = InterfaceNamer()

    private var nameMap: [String: String] = [:]

    private init() { buildNameMap() }

    // MARK: - Public

    /// Returns a human-readable label for the given BSD interface name.
    func friendlyName(for bsdName: String) -> String {
        if let mapped = nameMap[bsdName] { return "\(bsdName) — \(mapped)" }

        // Pattern fallback
        let patterns: [(prefix: String, label: String)] = [
            ("en",    "Ethernet"),
            ("utun",  "VPN Tunnel"),
            ("ipsec", "IPsec VPN"),
            ("ppp",   "PPP"),
            ("bridge","Bridge"),
            ("llw",   "Low-Latency WLAN"),
            ("awdl",  "AirDrop"),
            ("anpi",  "Apple NPI"),
            ("ap",    "Personal Hotspot"),
        ]
        for (prefix, label) in patterns where bsdName.hasPrefix(prefix) {
            return "\(bsdName) — \(label)"
        }
        return bsdName
    }

    // MARK: - Private

    private func buildNameMap() {
        let task  = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments  = ["-listallhardwareports"]
        let pipe  = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do { try task.run() } catch { return }
        task.waitUntilExit()

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        // Output format (repeated):
        //   Hardware Port: Wi-Fi
        //   Device: en0
        //   Ethernet Address: …
        var currentPort = ""
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("Hardware Port:") {
                currentPort = line
                    .replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), !currentPort.isEmpty {
                let dev = line
                    .replacingOccurrences(of: "Device:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !dev.isEmpty { nameMap[dev] = currentPort }
                currentPort = ""
            }
        }
    }
}
