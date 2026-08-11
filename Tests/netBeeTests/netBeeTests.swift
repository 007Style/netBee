// ─────────────────────────────────────────────────────────────────────────────
// netBeeTests.swift  —  Unit tests for netBee models and helpers
//
// Self-contained — no dependency on the executable target.
// All tested types are re-implemented or inlined here.
// Run with:  swift test  or  ./scripts/test.sh
// ─────────────────────────────────────────────────────────────────────────────
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Inline copies of tested types (SPM executable can't be a test dep)
// ─────────────────────────────────────────────────────────────────────────────

private struct RollingBuffer<T> {
    private(set) var elements: [T] = []
    let capacity: Int
    init(capacity: Int) { self.capacity = max(1, capacity) }
    mutating func append(_ element: T) {
        if elements.count >= capacity { elements.removeFirst() }
        elements.append(element)
    }
    func suffix(_ count: Int) -> ArraySlice<T> { elements.suffix(count) }
}

private enum TimeWindow: Int, CaseIterable {
    case twoMinutes  = 120
    case tenMinutes  = 600
    var label: String { self == .twoMinutes ? "2m" : "10m" }
}

private func formatBytes(_ bytes: UInt64) -> String {
    switch bytes {
    case ..<1_024:               return "\(bytes) B"
    case ..<1_048_576:           return String(format: "%.1f KB", Double(bytes) / 1_024)
    case ..<1_073_741_824:       return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    default:                     return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }
}

private func formatBps(_ bps: Double) -> String {
    switch bps {
    case ..<1_024:               return String(format: "%.0f B/s",  bps)
    case ..<1_048_576:           return String(format: "%.1f KB/s", bps / 1_024)
    case ..<1_073_741_824:       return String(format: "%.1f MB/s", bps / 1_048_576)
    default:                     return String(format: "%.2f GB/s", bps / 1_073_741_824)
    }
}

private enum ConnProtocol: String {
    case tcp = "TCP", udp = "UDP", tcp6 = "TCP6", udp6 = "UDP6", unix = "UNIX"
}

private enum TCPState: String {
    case established = "ESTABLISHED", listen = "LISTEN", timeWait = "TIME_WAIT"
    case closeWait = "CLOSE_WAIT", synSent = "SYN_SENT", synReceived = "SYN_RCVD"
    case finWait1 = "FIN_WAIT_1", finWait2 = "FIN_WAIT_2"
    case closing = "CLOSING", lastAck = "LAST_ACK", closed = "CLOSED"
    case unknown = "—"
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RollingBufferTests
// ─────────────────────────────────────────────────────────────────────────────

final class RollingBufferTests: XCTestCase {

    func test_appendWithinCapacity() {
        var buf = RollingBuffer<Int>(capacity: 5)
        (1...4).forEach { buf.append($0) }
        XCTAssertEqual(buf.elements, [1, 2, 3, 4])
    }

    func test_evictsOldestWhenFull() {
        var buf = RollingBuffer<Int>(capacity: 3)
        (1...5).forEach { buf.append($0) }
        XCTAssertEqual(buf.elements, [3, 4, 5])
    }

    func test_capacityOne() {
        var buf = RollingBuffer<Int>(capacity: 1)
        buf.append(10); buf.append(20)
        XCTAssertEqual(buf.elements, [20])
    }

    func test_suffixLargerThanSize() {
        var buf = RollingBuffer<Int>(capacity: 10)
        buf.append(1); buf.append(2)
        XCTAssertEqual(Array(buf.suffix(100)), [1, 2])
    }

    func test_suffixExact() {
        var buf = RollingBuffer<Int>(capacity: 5)
        (1...5).forEach { buf.append($0) }
        XCTAssertEqual(Array(buf.suffix(3)), [3, 4, 5])
    }

    func test_emptyBuffer() {
        let buf = RollingBuffer<Int>(capacity: 10)
        XCTAssertTrue(buf.elements.isEmpty)
        XCTAssertEqual(Array(buf.suffix(5)), [])
    }

    func test_capacityZeroClampedToOne() {
        var buf = RollingBuffer<String>(capacity: 0)
        buf.append("a"); buf.append("b")
        XCTAssertEqual(buf.elements, ["b"])
    }

    func test_orderPreserved() {
        var buf = RollingBuffer<Int>(capacity: 600)
        let vals = (1...600).map { $0 }
        vals.forEach { buf.append($0) }
        XCTAssertEqual(buf.elements, vals)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FormatBytesTests
// ─────────────────────────────────────────────────────────────────────────────

final class FormatBytesTests: XCTestCase {

    func test_bytes()     { XCTAssertEqual(formatBytes(512),          "512 B")    }
    func test_kilobytes() { XCTAssertEqual(formatBytes(2_048),        "2.0 KB")   }
    func test_megabytes() { XCTAssertEqual(formatBytes(5_242_880),    "5.0 MB")   }
    func test_gigabytes() { XCTAssertEqual(formatBytes(2_147_483_648),"2.00 GB")  }
    func test_zero()      { XCTAssertEqual(formatBytes(0),            "0 B")      }
    func test_exactKB()   { XCTAssertEqual(formatBytes(1_024),        "1.0 KB")   }
    func test_exactMB()   { XCTAssertEqual(formatBytes(1_048_576),    "1.0 MB")   }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FormatBpsTests
// ─────────────────────────────────────────────────────────────────────────────

final class FormatBpsTests: XCTestCase {

    func test_subKilo()   { XCTAssertEqual(formatBps(512),          "512 B/s")   }
    func test_kilobps()   { XCTAssertEqual(formatBps(2_048),        "2.0 KB/s")  }
    func test_megabps()   { XCTAssertEqual(formatBps(5_242_880),    "5.0 MB/s")  }
    func test_gigabps()   { XCTAssertEqual(formatBps(2_000_000_000),"1.86 GB/s") }
    func test_zero()      { XCTAssertEqual(formatBps(0),            "0 B/s")     }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TimeWindowTests
// ─────────────────────────────────────────────────────────────────────────────

final class TimeWindowTests: XCTestCase {

    func test_twoMinuteRawValue()  { XCTAssertEqual(TimeWindow.twoMinutes.rawValue,  120) }
    func test_tenMinuteRawValue()  { XCTAssertEqual(TimeWindow.tenMinutes.rawValue,  600) }
    func test_twoMinuteLabel()     { XCTAssertEqual(TimeWindow.twoMinutes.label,     "2m") }
    func test_tenMinuteLabel()     { XCTAssertEqual(TimeWindow.tenMinutes.label,     "10m") }
    func test_allCasesCount()      { XCTAssertEqual(TimeWindow.allCases.count,       2) }

    func test_windowedSlicing() {
        var buf = RollingBuffer<Int>(capacity: 600)
        (1...300).forEach { buf.append($0) }
        XCTAssertEqual(Array(buf.suffix(TimeWindow.twoMinutes.rawValue)).count, 120)
        XCTAssertEqual(Array(buf.suffix(TimeWindow.tenMinutes.rawValue)).count, 300) // only 300 available
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ConnProtocolTests
// ─────────────────────────────────────────────────────────────────────────────

final class ConnProtocolTests: XCTestCase {

    func test_tcpRawValue()  { XCTAssertEqual(ConnProtocol.tcp.rawValue,  "TCP")  }
    func test_udpRawValue()  { XCTAssertEqual(ConnProtocol.udp.rawValue,  "UDP")  }
    func test_tcp6RawValue() { XCTAssertEqual(ConnProtocol.tcp6.rawValue, "TCP6") }
    func test_udp6RawValue() { XCTAssertEqual(ConnProtocol.udp6.rawValue, "UDP6") }
    func test_roundTrip()    { XCTAssertEqual(ConnProtocol(rawValue: "TCP"), .tcp) }
    func test_invalidNil()   { XCTAssertNil(ConnProtocol(rawValue: "ICMP"))       }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TCPStateTests
// ─────────────────────────────────────────────────────────────────────────────

final class TCPStateTests: XCTestCase {

    func test_established() { XCTAssertEqual(TCPState.established.rawValue, "ESTABLISHED") }
    func test_listen()      { XCTAssertEqual(TCPState.listen.rawValue,      "LISTEN")      }
    func test_timeWait()    { XCTAssertEqual(TCPState.timeWait.rawValue,    "TIME_WAIT")   }
    func test_roundTrip()   { XCTAssertEqual(TCPState(rawValue: "LISTEN"),  .listen)       }
    func test_unknownNil()  { XCTAssertNil(TCPState(rawValue: "BOGUS"))                   }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - InterfaceNamerPatternTests
// ─────────────────────────────────────────────────────────────────────────────

private struct TestNamer {
    private let patterns: [(prefix: String, label: String)] = [
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

    func friendlyName(for name: String) -> String {
        for (prefix, label) in patterns where name.hasPrefix(prefix) {
            return "\(name) — \(label)"
        }
        return name
    }
}

final class InterfaceNamerPatternTests: XCTestCase {

    private let namer = TestNamer()

    func test_en0()      { XCTAssertEqual(namer.friendlyName(for: "en0"),    "en0 — Ethernet")         }
    func test_utun0()    { XCTAssertEqual(namer.friendlyName(for: "utun0"),  "utun0 — VPN Tunnel")     }
    func test_awdl0()    { XCTAssertEqual(namer.friendlyName(for: "awdl0"),  "awdl0 — AirDrop")        }
    func test_llw0()     { XCTAssertEqual(namer.friendlyName(for: "llw0"),   "llw0 — Low-Latency WLAN")}
    func test_bridge0()  { XCTAssertEqual(namer.friendlyName(for: "bridge0"),"bridge0 — Bridge")       }
    func test_unknown()  { XCTAssertEqual(namer.friendlyName(for: "xyz0"),   "xyz0")                   }
    func test_ipsec0()   { XCTAssertEqual(namer.friendlyName(for: "ipsec0"), "ipsec0 — IPsec VPN")     }
    func test_ppp0()     { XCTAssertEqual(namer.friendlyName(for: "ppp0"),   "ppp0 — PPP")             }
    func test_anpi0()    { XCTAssertEqual(namer.friendlyName(for: "anpi0"),  "anpi0 — Apple NPI")      }
    func test_ap1()      { XCTAssertEqual(namer.friendlyName(for: "ap1"),    "ap1 — Personal Hotspot") }
    func test_en12()     { XCTAssertEqual(namer.friendlyName(for: "en12"),   "en12 — Ethernet")        }
}
