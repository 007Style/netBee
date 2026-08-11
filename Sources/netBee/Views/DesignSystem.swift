// ─────────────────────────────────────────────────────────────────────────────
// DesignSystem.swift  —  Design tokens, shared components, and helpers
//
// Mirrors the beeMon DS system so netBee looks and feels like a sibling app.
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

// MARK: - DS Tokens

enum DS {
    // Backgrounds
    static let bgPrimary   = Color(red: 0.11, green: 0.12, blue: 0.14)  // #1C1E24
    static let bgSecondary = Color(red: 0.14, green: 0.15, blue: 0.18)  // #242730
    static let bgCard      = Color(red: 0.17, green: 0.18, blue: 0.22)  // #2B2E38

    // Borders
    static let border      = Color.white.opacity(0.07)
    static let borderBright = Color.white.opacity(0.13)

    // Text
    static let textPrimary  = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textMuted     = Color.white.opacity(0.30)

    // Accent colours
    static let rxGreen  = Color(red: 0.27, green: 0.70, blue: 0.40)   // ↓ receive
    static let txBlue   = Color(red: 0.30, green: 0.60, blue: 0.90)   // ↑ transmit
    static let warnAmber = Color(red: 0.93, green: 0.67, blue: 0.13)
    static let beeYellow = Color(red: 0.96, green: 0.83, blue: 0.18)

    // Typography
    static let fontMono  = Font.system(.caption, design: .monospaced)
    static let fontLabel = Font.system(size: 11, weight: .medium)
    static let fontValue = Font.system(size: 13, weight: .semibold, design: .monospaced)
    static let fontTitle = Font.system(size: 13, weight: .semibold)
}

// MARK: - MetricCard

/// A rounded dark card used throughout the dashboard.
struct MetricCard<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .background(DS.bgCard)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.border, lineWidth: 1)
            )
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var icon:  String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Text(icon).font(.caption) }
            Text(title)
                .font(DS.fontTitle)
                .foregroundColor(DS.textPrimary)
            Spacer()
        }
    }
}

// MARK: - TimeWindowPicker

struct TimeWindowPicker: View {
    @Binding var selected: TimeWindow

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimeWindow.allCases, id: \.self) { window in
                Button(window.label) { selected = window }
                    .font(DS.fontLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selected == window ? DS.beeYellow.opacity(0.22) : Color.clear)
                    .foregroundColor(selected == window ? DS.beeYellow : DS.textSecondary)
                    .cornerRadius(5)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Byte formatting

/// Format a byte count as a human-readable string (B / KB / MB / GB).
func formatBytes(_ bytes: UInt64) -> String {
    switch bytes {
    case ..<1_024:               return "\(bytes) B"
    case ..<1_048_576:           return String(format: "%.1f KB", Double(bytes) / 1_024)
    case ..<1_073_741_824:       return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    default:                     return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }
}

/// Format bytes/sec bandwidth as "X.X KB/s", "X.X MB/s" etc.
func formatBps(_ bps: Double) -> String {
    switch bps {
    case ..<1_024:               return String(format: "%.0f B/s",  bps)
    case ..<1_048_576:           return String(format: "%.1f KB/s", bps / 1_024)
    case ..<1_073_741_824:       return String(format: "%.1f MB/s", bps / 1_048_576)
    default:                     return String(format: "%.2f GB/s", bps / 1_073_741_824)
    }
}

// MARK: - Proto badge

extension ConnProtocol {
    var badgeColor: Color {
        switch self {
        case .tcp, .tcp6: return DS.txBlue
        case .udp, .udp6: return DS.rxGreen
        case .unix:       return DS.warnAmber
        }
    }
}

extension TCPState {
    var color: Color {
        switch self {
        case .established:  return DS.rxGreen
        case .listen:       return DS.txBlue
        case .timeWait,
             .closeWait,
             .finWait1,
             .finWait2,
             .closing,
             .lastAck:      return DS.warnAmber
        default:            return DS.textMuted
        }
    }
}
