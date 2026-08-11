// ─────────────────────────────────────────────────────────────────────────────
// ConnectionsView.swift  —  Live TCP/UDP connection table per process
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

struct ConnectionsView: View {
    @StateObject private var tracker = ConnectionTracker.shared
    @State private var searchText  = ""
    @State private var filterProto: ConnProtocol? = nil
    @State private var sortByBytes = true

    private var filtered: [ConnectionEntry] {
        tracker.connections
            .filter { entry in
                (filterProto == nil || entry.proto == filterProto!) &&
                (searchText.isEmpty ||
                    entry.processName.localizedCaseInsensitiveContains(searchText) ||
                    entry.remoteAddr.localizedCaseInsensitiveContains(searchText))
            }
            .sorted {
                sortByBytes
                    ? ($0.rxBytes + $0.txBytes) > ($1.rxBytes + $1.txBytes)
                    : $0.processName < $1.processName
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Header ───────────────────────────────────────────────────────
            SectionHeader(title: "Connections", icon: "🔗")

            // ── Toolbar ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DS.textMuted)
                TextField("Filter process or address…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.fontLabel)
                    .foregroundColor(DS.textPrimary)

                Spacer()

                // Proto filter pills
                protoFilterButton(nil,   "All")
                protoFilterButton(.tcp,  "TCP")
                protoFilterButton(.tcp6, "TCP6")
                protoFilterButton(.udp,  "UDP")

                // Sort toggle
                Button {
                    sortByBytes.toggle()
                } label: {
                    Text(sortByBytes ? "Sort: Bytes" : "Sort: Name")
                        .font(DS.fontLabel)
                        .foregroundColor(DS.beeYellow)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(DS.bgSecondary)
            .cornerRadius(8)

            // ── Connection count ─────────────────────────────────────────────
            Text("\(filtered.count) connection\(filtered.count == 1 ? "" : "s")")
                .font(DS.fontLabel).foregroundColor(DS.textMuted)

            // ── Table ────────────────────────────────────────────────────────
            if filtered.isEmpty {
                Text("No connections match the current filter.")
                    .font(DS.fontLabel).foregroundColor(DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                VStack(spacing: 2) {
                    // Table header
                    tableHeader

                    ForEach(filtered.prefix(100)) { entry in
                        ConnectionRow(entry: entry)
                    }
                    if filtered.count > 100 {
                        Text("… \(filtered.count - 100) more (refine filter to narrow)")
                            .font(DS.fontLabel).foregroundColor(DS.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Table header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Process").frame(width: 100, alignment: .leading)
            Text("Proto").frame(width: 50, alignment: .leading)
            Text("State").frame(width: 90, alignment: .leading)
            Text("Remote").frame(minWidth: 140, alignment: .leading)
            Spacer()
            Text("RX").frame(width: 70, alignment: .trailing)
            Text("TX").frame(width: 70, alignment: .trailing)
        }
        .font(DS.fontLabel)
        .foregroundColor(DS.textMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Protocol filter pill

    @ViewBuilder
    private func protoFilterButton(_ proto: ConnProtocol?, _ label: String) -> some View {
        let active = filterProto == proto
        Button(label) { filterProto = proto }
            .font(DS.fontLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? DS.beeYellow.opacity(0.22) : Color.clear)
            .foregroundColor(active ? DS.beeYellow : DS.textSecondary)
            .cornerRadius(5)
            .buttonStyle(.plain)
    }
}

// MARK: - ConnectionRow

private struct ConnectionRow: View {
    let entry: ConnectionEntry

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Process name
            Text(entry.processName)
                .font(DS.fontLabel)
                .foregroundColor(DS.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100, alignment: .leading)

            // Protocol badge
            Text(entry.proto.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(entry.proto.badgeColor.opacity(0.18))
                .foregroundColor(entry.proto.badgeColor)
                .cornerRadius(4)
                .frame(width: 50, alignment: .leading)

            // TCP State
            Text(entry.state.rawValue)
                .font(.system(size: 10))
                .foregroundColor(entry.state.color)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            // Remote endpoint
            Text(entry.remoteEndpoint)
                .font(DS.fontMono)
                .foregroundColor(DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(minWidth: 140, alignment: .leading)

            Spacer()

            // Bytes RX
            Text(formatBytes(entry.rxBytes))
                .font(DS.fontMono)
                .foregroundColor(DS.rxGreen)
                .frame(width: 70, alignment: .trailing)

            // Bytes TX
            Text(formatBytes(entry.txBytes))
                .font(DS.fontMono)
                .foregroundColor(DS.txBlue)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovered ? DS.bgSecondary : Color.clear)
        .cornerRadius(6)
        .onHover { hovered = $0 }
    }
}
