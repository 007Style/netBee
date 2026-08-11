// ─────────────────────────────────────────────────────────────────────────────
// ConnectionTracker.swift  —  Active TCP/UDP connection enumeration
//
// Uses libproc (proc_pidinfo / PROC_PIDLISTFDS / proc_pidfdinfo) to walk every
// process's open file descriptors and extract socket connections.
//
// The result is a list of ConnectionEntry values sorted by bytes transferred.
// Sampling runs on a background queue to avoid blocking the main thread.
// ─────────────────────────────────────────────────────────────────────────────
import Foundation
import Combine

// MARK: - Types

/// Protocol / address family for a connection.
enum ConnProtocol: String {
    case tcp  = "TCP"
    case udp  = "UDP"
    case tcp6 = "TCP6"
    case udp6 = "UDP6"
    case unix = "UNIX"
}

/// State of a TCP connection (mirrors TCP_* states from <netinet/tcp_fsm.h>).
enum TCPState: String {
    case established = "ESTABLISHED"
    case listen      = "LISTEN"
    case timeWait    = "TIME_WAIT"
    case closeWait   = "CLOSE_WAIT"
    case synSent     = "SYN_SENT"
    case synReceived = "SYN_RCVD"
    case finWait1    = "FIN_WAIT_1"
    case finWait2    = "FIN_WAIT_2"
    case closing     = "CLOSING"
    case lastAck     = "LAST_ACK"
    case closed      = "CLOSED"
    case unknown     = "—"
}

/// One active socket / connection.
struct ConnectionEntry: Identifiable, Equatable {
    let id:          UUID          = UUID()
    let pid:         pid_t
    let processName: String
    let proto:       ConnProtocol
    let state:       TCPState
    let localAddr:   String
    let localPort:   UInt16
    let remoteAddr:  String
    let remotePort:  UInt16
    let rxBytes:     UInt64
    let txBytes:     UInt64

    /// Human-readable remote endpoint string.
    var remoteEndpoint: String {
        remoteAddr.isEmpty ? "—" : "\(remoteAddr):\(remotePort)"
    }

    static func == (lhs: ConnectionEntry, rhs: ConnectionEntry) -> Bool {
        lhs.pid == rhs.pid &&
        lhs.localAddr == rhs.localAddr && lhs.localPort == rhs.localPort &&
        lhs.remoteAddr == rhs.remoteAddr && lhs.remotePort == rhs.remotePort
    }
}

// MARK: - ConnectionTracker

@MainActor
final class ConnectionTracker: ObservableObject {

    static let shared = ConnectionTracker()

    @Published var connections: [ConnectionEntry] = []

    private var timer: AnyCancellable?
    private let queue = DispatchQueue(label: "com.beemon.netbee.connections",
                                      qos: .utility)

    private init() { start() }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: - Refresh

    private func refresh() {
        queue.async { [weak self] in
            let entries = ConnectionTracker.fetchConnections()
            DispatchQueue.main.async {
                self?.connections = entries
            }
        }
    }

    // MARK: - libproc-based connection enumeration

    /// Walks all visible PIDs and collects their open sockets.
    /// Falls back to `netstat -an` parsing if libproc returns no data
    /// (can happen when the process has no user-space access to other PIDs).
    nonisolated private static func fetchConnections() -> [ConnectionEntry] {
        var results: [ConnectionEntry] = []

        // ── Get PID list ─────────────────────────────────────────────────────
        let bufSize = proc_listallpids(nil, 0)
        guard bufSize > 0 else { return fallbackNetstat() }

        var pids = [Int32](repeating: 0, count: Int(bufSize))
        let count = proc_listallpids(&pids, Int32(pids.count) * 4)
        guard count > 0 else { return fallbackNetstat() }

        // ── Walk each PID ────────────────────────────────────────────────────
        for pid in pids.prefix(Int(count)) where pid > 0 {
            let name = processName(pid: pid)

            // Get file descriptor count
            let fdBufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard fdBufSize > 0 else { continue }

            let fdCount = Int(fdBufSize) / MemoryLayout<proc_fdinfo>.stride
            var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
            let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos,
                                   Int32(fdCount * MemoryLayout<proc_fdinfo>.stride))
            guard got > 0 else { continue }

            let validFDs = got / Int32(MemoryLayout<proc_fdinfo>.stride)
            for i in 0..<Int(validFDs) {
                guard fdInfos[i].proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }
                var sockInfo = socket_fdinfo()
                let r = proc_pidfdinfo(pid, fdInfos[i].proc_fd, PROC_PIDFDSOCKETINFO,
                                       &sockInfo, Int32(MemoryLayout<socket_fdinfo>.stride))
                guard r == MemoryLayout<socket_fdinfo>.stride else { continue }

                if let entry = connectionEntry(pid: pid, name: name, info: sockInfo) {
                    results.append(entry)
                }
            }
        }

        if results.isEmpty { return fallbackNetstat() }
        return results.sorted { $0.rxBytes + $0.txBytes > $1.rxBytes + $1.txBytes }
    }

    // MARK: - socket_fdinfo → ConnectionEntry

    nonisolated private static func connectionEntry(pid: pid_t,
                                        name: String,
                                        info: socket_fdinfo) -> ConnectionEntry? {
        let si = info.psi
        let family = Int32(si.soi_family)
        let kind   = Int32(si.soi_kind)

        // We only care about INET (IPv4/IPv6) TCP and UDP
        guard family == AF_INET || family == AF_INET6 else { return nil }
        guard kind == SOCK_STREAM || kind == SOCK_DGRAM  else { return nil }

        let isTCP = (kind == SOCK_STREAM)
        let isV6  = (family == AF_INET6)

        let proto: ConnProtocol
        switch (isTCP, isV6) {
        case (true, false):  proto = .tcp
        case (true, true):   proto = .tcp6
        case (false, false): proto = .udp
        case (false, true):  proto = .udp6
        }

        // Extract addresses
        var localAddr = "", remoteAddr = ""
        var localPort: UInt16 = 0, remotePort: UInt16 = 0

        if family == AF_INET {
            let inPcb = si.soi_proto.pri_tcp.tcpsi_ini  // in_sockinfo
            localPort  = UInt16(bigEndian: UInt16(inPcb.insi_lport))
            remotePort = UInt16(bigEndian: UInt16(inPcb.insi_fport))
            localAddr  = inetString4(inPcb.insi_laddr.ina_46.i46a_addr4.s_addr)
            remoteAddr = inetString4(inPcb.insi_faddr.ina_46.i46a_addr4.s_addr)
        } else {
            let inPcb = si.soi_proto.pri_tcp.tcpsi_ini
            localPort  = UInt16(bigEndian: UInt16(inPcb.insi_lport))
            remotePort = UInt16(bigEndian: UInt16(inPcb.insi_fport))
            localAddr  = inetString6(inPcb.insi_laddr.ina_6.__u6_addr.__u6_addr8)
            remoteAddr = inetString6(inPcb.insi_faddr.ina_6.__u6_addr.__u6_addr8)
        }

        // TCP state
        var tcpState = TCPState.unknown
        if isTCP {
            let rawState = Int32(si.soi_proto.pri_tcp.tcpsi_state)
            tcpState = tcpStateFrom(rawState)
        }

        // Byte counters from socket stats
        let rxBytes = UInt64(si.soi_rcv.sbi_mbcnt)
        let txBytes = UInt64(si.soi_snd.sbi_mbcnt)

        return ConnectionEntry(
            pid:         pid,
            processName: name,
            proto:       proto,
            state:       tcpState,
            localAddr:   localAddr,
            localPort:   localPort,
            remoteAddr:  remoteAddr,
            remotePort:  remotePort,
            rxBytes:     rxBytes,
            txBytes:     txBytes
        )
    }

    // MARK: - Helpers

    nonisolated private static func processName(pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        proc_name(pid, &buf, UInt32(buf.count))
        let full = String(cString: buf)
        return full.components(separatedBy: "/").last ?? full
    }

    nonisolated private static func inetString4(_ addr: in_addr_t) -> String {
        var a = addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }

    nonisolated private static func inetString6(_ bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )) -> String {
        var arr: [UInt8] = [
            bytes.0,  bytes.1,  bytes.2,  bytes.3,
            bytes.4,  bytes.5,  bytes.6,  bytes.7,
            bytes.8,  bytes.9,  bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ]
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &arr, &buf, socklen_t(INET6_ADDRSTRLEN))
        return String(cString: buf)
    }

    nonisolated private static func tcpStateFrom(_ state: Int32) -> TCPState {
        // <netinet/tcp_fsm.h> constants
        switch state {
        case 0:  return .closed
        case 1:  return .listen
        case 2:  return .synSent
        case 3:  return .synReceived
        case 4:  return .established
        case 5:  return .closeWait
        case 6:  return .finWait1
        case 7:  return .closing
        case 8:  return .lastAck
        case 9:  return .finWait2
        case 10: return .timeWait
        default: return .unknown
        }
    }

    // MARK: - Fallback: netstat -an parsing

    /// Parses `netstat -an` output when libproc yields nothing.
    /// Returns minimal entries (no PID / process name available).
    nonisolated private static func fallbackNetstat() -> [ConnectionEntry] {
        let task = Process()
        task.launchPath = "/usr/sbin/netstat"
        task.arguments  = ["-an", "-p", "tcp"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        do { try task.run() } catch { return [] }
        task.waitUntilExit()

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var entries: [ConnectionEntry] = []
        for line in output.components(separatedBy: "\n").dropFirst(2) {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 6 else { continue }
            let protoStr = String(cols[0])
            let local    = parseEndpoint(String(cols[3]))
            let remote   = parseEndpoint(String(cols[4]))
            let stateStr = String(cols[5])

            let proto: ConnProtocol
            switch protoStr {
            case "tcp4":   proto = .tcp
            case "tcp6":   proto = .tcp6
            default:       continue
            }

            let state = TCPState(rawValue: stateStr) ?? .unknown

            entries.append(ConnectionEntry(
                pid:         0,
                processName: "—",
                proto:       proto,
                state:       state,
                localAddr:   local.addr,
                localPort:   local.port,
                remoteAddr:  remote.addr,
                remotePort:  remote.port,
                rxBytes:     0,
                txBytes:     0
            ))
        }
        return entries
    }

    nonisolated private static func parseEndpoint(_ s: String) -> (addr: String, port: UInt16) {
        // Handles "1.2.3.4.8080" (netstat dot-notation) and "[::1].443"
        if s == "*.*" || s == "*" { return ("*", 0) }
        if let dot = s.lastIndex(of: ".") {
            let addr = String(s[s.startIndex..<dot])
            let port = UInt16(s[s.index(after: dot)...]) ?? 0
            // Convert IPv4 dot-notation (a.b.c.d) — already fine; strip brackets for IPv6
            let cleanAddr = addr.replacingOccurrences(of: "[", with: "")
                               .replacingOccurrences(of: "]", with: "")
            return (cleanAddr, port)
        }
        return (s, 0)
    }
}
