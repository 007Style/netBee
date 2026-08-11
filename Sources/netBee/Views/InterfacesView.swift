// ─────────────────────────────────────────────────────────────────────────────
// InterfacesView.swift  —  Full interface details table
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

struct InterfacesView: View {
    @StateObject private var monitor = NetworkMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Network Interfaces", icon: "🔌")

            if monitor.interfaces.isEmpty {
                Text("Discovering interfaces…")
                    .font(DS.fontLabel).foregroundColor(DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ForEach(monitor.interfaces) { iface in
                    InterfaceDetailCard(iface: iface)
                }
            }
        }
    }
}

// MARK: - InterfaceDetailCard

private struct InterfaceDetailCard: View {
    let iface: InterfaceSnapshot

    @StateObject private var monitor = NetworkMonitor.shared
    @State private var expanded = false

    var body: some View {
        let delta = monitor.bandwidthDeltas.first { $0.id == iface.id }
        let rxBps = delta?.rxBps ?? 0
        let txBps = delta?.txBps ?? 0

        MetricCard {
            VStack(alignment: .leading, spacing: 8) {
                // ── Title row ─────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iface.friendlyName)
                            .font(DS.fontTitle).foregroundColor(DS.textPrimary)
                    }
                    Spacer()

                    // Active indicator
                    Circle()
                        .fill(iface.isActive ? DS.rxGreen : DS.textMuted)
                        .frame(width: 7, height: 7)
                    Text(iface.isActive ? "Active" : "Idle")
                        .font(DS.fontLabel)
                        .foregroundColor(iface.isActive ? DS.rxGreen : DS.textMuted)

                    // Expand toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                // ── Live rate ─────────────────────────────────────────────
                HStack(spacing: 16) {
                    Text("↓ \(formatBps(rxBps))").font(DS.fontValue).foregroundColor(DS.rxGreen)
                    Text("↑ \(formatBps(txBps))").font(DS.fontValue).foregroundColor(DS.txBlue)
                    Spacer()
                }

                // ── Expanded details ──────────────────────────────────────
                if expanded {
                    Divider().background(DS.border)
                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("IPv4",          iface.ipv4 ?? "—")
                        detailRow("IPv6",          iface.ipv6 ?? "—")
                        detailRow("MTU",           "\(iface.mtu)")
                        detailRow("Packets In",    "\(iface.packetsIn)")
                        detailRow("Packets Out",   "\(iface.packetsOut)")
                        detailRow("Bytes In",      formatBytes(iface.bytesIn))
                        detailRow("Bytes Out",     formatBytes(iface.bytesOut))
                        if iface.errorsIn + iface.errorsOut > 0 {
                            detailRow("Errors",    "\(iface.errorsIn + iface.errorsOut)",
                                      valueColor: DS.warnAmber)
                        }
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String,
                            valueColor: Color = DS.textSecondary) -> some View {
        HStack {
            Text(label).font(DS.fontLabel).foregroundColor(DS.textMuted).frame(width: 100, alignment: .leading)
            Text(value).font(DS.fontMono).foregroundColor(valueColor)
        }
    }
}
