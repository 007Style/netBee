// ─────────────────────────────────────────────────────────────────────────────
// DashboardView.swift  —  Top-level tabbed dashboard window
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

// MARK: - Tab enum

enum DashboardTab: String, CaseIterable {
    case overview    = "Overview"
    case bandwidth   = "Bandwidth"
    case connections = "Connections"
    case interfaces  = "Interfaces"
    case about       = "About"

    var icon: String {
        switch self {
        case .overview:    return "🐝"
        case .bandwidth:   return "📶"
        case .connections: return "🔗"
        case .interfaces:  return "🔌"
        case .about:       return "ℹ️"
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {
    @StateObject private var monitor    = NetworkMonitor.shared
    @StateObject private var connTracker = ConnectionTracker.shared
    @State private var activeTab: DashboardTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab bar ──────────────────────────────────────────────────────
            tabBar

            Divider().background(DS.border)

            // ── Content ──────────────────────────────────────────────────────
            ScrollView {
                tabContent
                    .padding(16)
            }
            .frame(width: 640)
        }
        .background(DS.bgPrimary)
        .preferredColorScheme(.dark)
        .frame(width: 640, height: 560)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.icon).font(.caption)
                        Text(tab.rawValue).font(DS.fontTitle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundColor(activeTab == tab ? DS.beeYellow : DS.textSecondary)
                    .background(
                        activeTab == tab
                            ? DS.beeYellow.opacity(0.10)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()

            // Live total bandwidth pill
            HStack(spacing: 6) {
                Text("↓ \(formatBps(monitor.totalBandwidth.rxBps))")
                    .foregroundColor(DS.rxGreen)
                Text("↑ \(formatBps(monitor.totalBandwidth.txBps))")
                    .foregroundColor(DS.txBlue)
            }
            .font(DS.fontValue)
            .padding(.trailing, 14)
        }
        .background(DS.bgSecondary)
    }

    // MARK: - Content switcher

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .overview:    OverviewSection()
        case .bandwidth:   BandwidthView()
        case .connections: ConnectionsView()
        case .interfaces:  InterfacesView()
        case .about:       AboutView()
        }
    }
}

// MARK: - OverviewSection

/// Quick-look panel on the Overview tab: top bandwidth interfaces + connection summary.
private struct OverviewSection: View {
    @StateObject private var monitor     = NetworkMonitor.shared
    @StateObject private var connTracker = ConnectionTracker.shared
    @State private var window: TimeWindow = .twoMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Header ───────────────────────────────────────────────────────
            HStack {
                SectionHeader(title: "Network Overview", icon: "🐝")
                Spacer()
                TimeWindowPicker(selected: $window)
            }

            // ── Total bandwidth sparkline ─────────────────────────────────
            MetricCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Total Bandwidth").font(DS.fontLabel).foregroundColor(DS.textSecondary)
                        Spacer()
                        Text("↓ \(formatBps(monitor.totalBandwidth.rxBps))")
                            .font(DS.fontValue).foregroundColor(DS.rxGreen)
                        Text("↑ \(formatBps(monitor.totalBandwidth.txBps))")
                            .font(DS.fontValue).foregroundColor(DS.txBlue)
                    }
                    let history = monitor.combinedHistory(window: window)
                    DualSparklineChart(
                        rxValues: history.map(\.rxBps),
                        txValues: history.map(\.txBps),
                        height: 44
                    )
                }
            }

            // ── Top 3 active interfaces ───────────────────────────────────
            let active = monitor.interfaces
                .filter { $0.isActive }
                .prefix(3)
            if !active.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Interfaces")
                        .font(DS.fontLabel).foregroundColor(DS.textSecondary)
                    ForEach(active) { iface in
                        OverviewInterfaceRow(iface: iface, window: window)
                    }
                }
            }

            // ── Connection summary ────────────────────────────────────────
            MetricCard {
                HStack(spacing: 20) {
                    connStat(label: "Connections",
                             value: "\(connTracker.connections.count)")
                    connStat(label: "Established",
                             value: "\(connTracker.connections.filter { $0.state == .established }.count)")
                    connStat(label: "Listening",
                             value: "\(connTracker.connections.filter { $0.state == .listen }.count)")
                    connStat(label: "Processes",
                             value: "\(Set(connTracker.connections.map(\.pid)).count)")
                }
            }
        }
    }

    private func connStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DS.fontValue).foregroundColor(DS.textPrimary)
            Text(label).font(DS.fontLabel).foregroundColor(DS.textSecondary)
        }
    }
}

// MARK: - OverviewInterfaceRow

private struct OverviewInterfaceRow: View {
    let iface:  InterfaceSnapshot
    let window: TimeWindow

    @StateObject private var monitor = NetworkMonitor.shared

    var body: some View {
        let delta = monitor.bandwidthDeltas.first { $0.id == iface.id }
        let rxBps = delta?.rxBps ?? 0
        let txBps = delta?.txBps ?? 0
        let history = monitor.bandwidthHistory(for: iface.id, window: window)

        MetricCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(iface.friendlyName)
                        .font(DS.fontLabel).foregroundColor(DS.textPrimary)
                    Spacer()
                    Text("↓ \(formatBps(rxBps))").font(DS.fontValue).foregroundColor(DS.rxGreen)
                    Text("↑ \(formatBps(txBps))").font(DS.fontValue).foregroundColor(DS.txBlue)
                }
                DualSparklineChart(
                    rxValues: history.map(\.rxBps),
                    txValues: history.map(\.txBps),
                    height: 28
                )
            }
        }
    }
}
