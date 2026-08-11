// ─────────────────────────────────────────────────────────────────────────────
// AboutView.swift  —  About panel with animated hex grid (matches beeMon style)
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

struct AboutView: View {
    @State private var glowPulse  = false
    @State private var demoValues: [Double] = (0..<60).map { _ in Double.random(in: 0...1) }
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Hero band ────────────────────────────────────────────────────
            ZStack {
                HexGridBackground()
                    .frame(height: 180)
                    .clipped()

                VStack(spacing: 10) {
                    // Glow ring + bee emoji
                    ZStack {
                        Circle()
                            .stroke(DS.beeYellow.opacity(glowPulse ? 0.35 : 0.10), lineWidth: 18)
                            .frame(width: 72, height: 72)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                       value: glowPulse)
                        Text("🐝").font(.system(size: 40))
                    }

                    Text("netBee")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DS.textPrimary)

                    Text("v\(version)  —  native macOS network monitor")
                        .font(DS.fontLabel)
                        .foregroundColor(DS.textSecondary)
                }
            }
            .onAppear { glowPulse = true }

            Divider().background(DS.border)

            // ── Feature pills ────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureGrid

                    // Live demo sparkline
                    MetricCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Live demo — bandwidth sparkline")
                                .font(DS.fontLabel).foregroundColor(DS.textSecondary)
                            SparklineChart(values: demoValues, color: DS.rxGreen)
                                .frame(height: 32)
                                .onReceive(timer) { _ in
                                    demoValues.removeFirst()
                                    demoValues.append(Double.random(in: 0.1...1.0))
                                }
                        }
                    }

                    // Credits
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("crafted by Daneyand & IBM's Bob 🐝")
                                .font(DS.fontLabel).foregroundColor(DS.textMuted)
                            Text("Pure Swift · SwiftUI · Zero dependencies · macOS 13+")
                                .font(.system(size: 10)).foregroundColor(DS.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
        }
        .background(DS.bgPrimary)
    }

    // MARK: - Feature grid

    private var featureGrid: some View {
        let features: [(icon: String, label: String)] = [
            ("📶", "Bandwidth per interface"),
            ("🔗", "Per-process connections"),
            ("🔌", "Interface details & IPs"),
            ("📊", "2m / 10m rolling history"),
            ("🐝", "Menu bar live bandwidth"),
            ("🔒", "No data leaves your Mac"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(features, id: \.label) { f in
                HStack(spacing: 8) {
                    Text(f.icon)
                    Text(f.label).font(DS.fontLabel).foregroundColor(DS.textSecondary)
                    Spacer()
                }
                .padding(10)
                .background(DS.bgCard)
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - HexGridBackground

private struct HexGridBackground: View {
    @State private var phase: CGFloat = 0
    private let hexTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { ctx, size in
            let r: CGFloat = 14
            let w = r * 2
            let h = r * sqrt(3)
            let cols = Int(size.width  / (w * 0.75)) + 2
            let rows = Int(size.height / h) + 2

            for col in 0...cols {
                for row in 0...rows {
                    let x = CGFloat(col) * w * 0.75
                    let y = CGFloat(row) * h + (col % 2 == 0 ? 0 : h / 2)
                    let dist = hypot(x - size.width / 2, y - size.height / 2)
                    let alpha = 0.05 + 0.04 * sin(dist / 30 - phase)
                    drawHex(ctx: ctx, center: CGPoint(x: x, y: y), r: r, alpha: alpha)
                }
            }
        }
        .background(DS.bgSecondary)
        .onReceive(hexTimer) { _ in phase += 0.05 }
    }

    private func drawHex(ctx: GraphicsContext, center: CGPoint, r: CGFloat, alpha: Double) {
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        ctx.stroke(path, with: .color(DS.beeYellow.opacity(alpha)), lineWidth: 0.8)
    }
}
