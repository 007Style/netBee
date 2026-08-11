// ─────────────────────────────────────────────────────────────────────────────
// LatencyView.swift  —  Per-interface latency (ping RTT) dashboard tab
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

struct LatencyView: View {
    @StateObject private var latency = LatencyMonitor.shared
    @StateObject private var monitor = NetworkMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Latency", icon: "⏱")

            if latency.results.isEmpty {
                probing
            } else {
                ForEach(latency.results) { item in
                    LatencyCard(item: item)
                }

                // Legend
                HStack(spacing: 16) {
                    legendDot(color: DS.rxGreen,   label: "< 20 ms  excellent")
                    legendDot(color: DS.beeYellow, label: "< 80 ms  good")
                    legendDot(color: DS.warnAmber,  label: "< 200 ms fair")
                    legendDot(color: Color.red.opacity(0.8), label: "≥ 200 ms poor")
                }
                .padding(.top, 4)
            }
        }
    }

    private var probing: some View {
        HStack {
            ProgressView().scaleEffect(0.7)
            Text("Probing gateways…")
                .font(DS.fontLabel).foregroundColor(DS.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundColor(DS.textMuted)
        }
    }
}

// MARK: - LatencyCard

private struct LatencyCard: View {
    let item: InterfaceLatency

    var body: some View {
        MetricCard {
            VStack(alignment: .leading, spacing: 8) {
                // ── Title row ─────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.friendlyName)
                            .font(DS.fontTitle).foregroundColor(DS.textPrimary)
                        Text("→ \(item.targetHost)")
                            .font(DS.fontMono).foregroundColor(DS.textMuted)
                    }
                    Spacer()

                    if item.isReachable {
                        Text(String(format: "%.1f ms", item.current))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(latencyColor(item.current))
                    } else {
                        Text("timeout")
                            .font(DS.fontValue)
                            .foregroundColor(DS.textMuted)
                    }
                }

                // ── Stats row ─────────────────────────────────────────────────
                if item.isReachable || item.averageMs >= 0 {
                    HStack(spacing: 20) {
                        statCell("avg",  item.averageMs)
                        statCell("min",  item.minMs)
                        statCell("max",  item.maxMs)
                        statCell("last", item.current)
                        Spacer()
                        Text("\(item.history.filter { $0.ms >= 0 }.count)/\(item.history.count) replies")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                }

                // ── Sparkline ─────────────────────────────────────────────────
                if item.history.count > 1 {
                    let vals = item.history.map { $0.ms < 0 ? 0.0 : $0.ms }
                    let maxVal = vals.max() ?? 1
                    let norm = vals.map { maxVal > 0 ? $0 / maxVal : 0 }
                    SparklineChart(values: norm, color: latencyColor(item.current))
                        .frame(height: 28)
                }
            }
        }
    }

    private func statCell(_ label: String, _ ms: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ms >= 0 ? String(format: "%.1f ms", ms) : "—")
                .font(DS.fontValue)
                .foregroundColor(ms >= 0 ? latencyColor(ms) : DS.textMuted)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.textMuted)
        }
    }
}

// MARK: - Latency colour helper (global so both views can use it)

func latencyColor(_ ms: Double) -> Color {
    switch ms {
    case ..<0:    return DS.textMuted
    case ..<20:   return DS.rxGreen
    case ..<80:   return DS.beeYellow
    case ..<200:  return DS.warnAmber
    default:      return Color.red.opacity(0.85)
    }
}
