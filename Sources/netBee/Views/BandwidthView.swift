// ─────────────────────────────────────────────────────────────────────────────
// BandwidthView.swift  —  Per-interface bandwidth sparklines with time window
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

struct BandwidthView: View {
    @StateObject private var monitor = NetworkMonitor.shared
    @State private var window: TimeWindow = .twoMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Header ───────────────────────────────────────────────────────
            HStack {
                SectionHeader(title: "Bandwidth", icon: "📶")
                Spacer()
                TimeWindowPicker(selected: $window)
            }

            // ── Combined chart ────────────────────────────────────────────
            MetricCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All Interfaces — Combined")
                        .font(DS.fontLabel).foregroundColor(DS.textSecondary)
                    let combined = monitor.combinedHistory(window: window)
                    if combined.isEmpty {
                        emptyChart(height: 60)
                    } else {
                        DualSparklineChart(
                            rxValues: combined.map(\.rxBps),
                            txValues: combined.map(\.txBps),
                            height: 60
                        )
                    }
                    legend
                }
            }

            // ── Per-interface cards ───────────────────────────────────────
            let activeIfaces = monitor.interfaces.filter { monitor.history[$0.id] != nil }
            if activeIfaces.isEmpty {
                Text("No interface activity yet — waiting for first samples…")
                    .font(DS.fontLabel)
                    .foregroundColor(DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ForEach(activeIfaces) { iface in
                    InterfaceBandwidthCard(iface: iface, window: window)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(DS.rxGreen, "Receive ↓")
            legendDot(DS.txBlue,  "Transmit ↑")
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(DS.fontLabel).foregroundColor(DS.textSecondary)
        }
    }

    private func emptyChart(height: CGFloat) -> some View {
        Rectangle()
            .fill(DS.bgSecondary)
            .frame(height: height)
            .cornerRadius(4)
            .overlay(
                Text("Collecting data…")
                    .font(DS.fontLabel)
                    .foregroundColor(DS.textMuted)
            )
    }
}

// MARK: - InterfaceBandwidthCard

private struct InterfaceBandwidthCard: View {
    let iface:  InterfaceSnapshot
    let window: TimeWindow

    @StateObject private var monitor = NetworkMonitor.shared

    var body: some View {
        let delta   = monitor.bandwidthDeltas.first { $0.id == iface.id }
        let rxBps   = delta?.rxBps ?? 0
        let txBps   = delta?.txBps ?? 0
        let history = monitor.bandwidthHistory(for: iface.id, window: window)

        MetricCard {
            VStack(alignment: .leading, spacing: 8) {
                // ── Interface name + live rate ────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iface.friendlyName)
                            .font(DS.fontTitle).foregroundColor(DS.textPrimary)
                        if let ip = iface.ipv4 {
                            Text(ip).font(DS.fontMono).foregroundColor(DS.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↓ \(formatBps(rxBps))").font(DS.fontValue).foregroundColor(DS.rxGreen)
                        Text("↑ \(formatBps(txBps))").font(DS.fontValue).foregroundColor(DS.txBlue)
                    }
                }

                // ── Sparkline ─────────────────────────────────────────────
                if history.isEmpty {
                    Rectangle()
                        .fill(DS.bgSecondary)
                        .frame(height: 40)
                        .cornerRadius(4)
                } else {
                    DualSparklineChart(
                        rxValues: history.map(\.rxBps),
                        txValues: history.map(\.txBps),
                        height: 40
                    )
                }

                // ── Cumulative counters ────────────────────────────────────
                HStack(spacing: 16) {
                    counterChip("Total ↓", formatBytes(iface.bytesIn))
                    counterChip("Total ↑", formatBytes(iface.bytesOut))
                    counterChip("Errors", "\(iface.errorsIn + iface.errorsOut)",
                               color: (iface.errorsIn + iface.errorsOut) > 0 ? DS.warnAmber : nil)
                    counterChip("MTU", "\(iface.mtu)")
                }
            }
        }
    }

    private func counterChip(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(DS.fontMono)
                .foregroundColor(color ?? DS.textSecondary)
            Text(label).font(.system(size: 10)).foregroundColor(DS.textMuted)
        }
    }
}
