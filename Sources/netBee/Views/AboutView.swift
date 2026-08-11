// ─────────────────────────────────────────────────────────────────────────────
// AboutView.swift  —  About panel — no-scroll, live-data graphics
//
// Layout (760 × ~545 content area, no ScrollView):
//
//   ┌──────────────────────────────────────────────────────────┐
//   │          StarNetworkCanvas  (fills flex space)           │
//   ├──────────────────┬───────────────────────────────────────┤
//   │  🐝 logo / ver   │  tagline · email · feature grid       │
//   ├──────────────────┴───────────────────────────────────────┤
//   │  Live BW sparkline │ Connection donut │ Latency bars     │
//   └──────────────────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

// MARK: - AboutView

struct AboutView: View {
    @State private var glowPulse = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Animated hero strip ───────────────────────────────────────────
            StarNetworkCanvas()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            Divider().background(DS.border)

            // ── Info row: logo left, details right ───────────────────────────
            HStack(alignment: .top, spacing: 0) {

                // LEFT — bee + name + version
                VStack(spacing: 8) {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(DS.beeYellow.opacity(glowPulse ? 0.50 : 0.12), lineWidth: 18)
                            .frame(width: 80, height: 80)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                                       value: glowPulse)
                        Circle().fill(DS.bgPrimary).frame(width: 70, height: 70)
                        Text("🐝").font(.system(size: 40))
                    }
                    Text("netBee")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DS.textPrimary)
                    Text("v\(version)")
                        .font(DS.fontMono).foregroundColor(DS.textSecondary)
                    Text("native macOS network monitor")
                        .font(.system(size: 10)).foregroundColor(DS.textMuted)
                    Spacer()
                }
                .frame(width: 200)
                .padding(.vertical, 14)

                Divider().background(DS.border).padding(.vertical, 10)

                // RIGHT — tagline + features
                VStack(alignment: .leading, spacing: 8) {
                    Text("From the minds of Daneyand & IBM's Bob")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.beeYellow)
                    Text("daneyand@ibm.com")
                        .font(DS.fontMono).foregroundColor(DS.textSecondary)

                    Divider().background(DS.border)

                    let features: [(String, String)] = [
                        ("📶", "Bandwidth per interface"), ("⏱",  "Latency per gateway"),
                        ("🔗", "Per-process connections"), ("🔌", "Interface details & IPs"),
                        ("📊", "2 m / 10 m rolling history"), ("🐝", "Menu bar live bandwidth"),
                        ("🔒", "No data leaves your Mac"),  ("🌐", "IPv4 & IPv6 support"),
                    ]
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                        ForEach(features, id: \.1) { f in
                            HStack(spacing: 6) {
                                Text(f.0)
                                Text(f.1).font(DS.fontLabel).foregroundColor(DS.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(DS.bgCard).cornerRadius(7)
                        }
                    }
                    Text("Pure Swift · SwiftUI · Zero dependencies · macOS 13+")
                        .font(.system(size: 10)).foregroundColor(DS.textMuted)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .background(DS.bgPrimary)

            Divider().background(DS.border)

            // ── Live graphics strip ───────────────────────────────────────────
            HStack(spacing: 0) {
                LiveBandwidthCard()
                Divider().background(DS.border)
                ConnectionDonutCard()
                Divider().background(DS.border)
                LatencyBarsCard()
            }
            .frame(height: 130)
            .background(DS.bgSecondary)
        }
        .background(DS.bgPrimary)
        .onAppear { glowPulse = true }
    }
}

// MARK: - LiveBandwidthCard

private struct LiveBandwidthCard: View {
    @StateObject private var monitor = NetworkMonitor.shared
    @State private var rxValues: [Double] = Array(repeating: 0, count: 60)
    @State private var txValues: [Double] = Array(repeating: 0, count: 60)
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIVE BANDWIDTH").font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted).tracking(1)
            ZStack(alignment: .bottomLeading) {
                DualSparklineChart(rxValues: rxValues, txValues: txValues, height: 56)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 1) {
                    Text("↓ \(formatBps(monitor.totalBandwidth.rxBps))")
                        .font(DS.fontValue).foregroundColor(DS.rxGreen)
                    Text("↑ \(formatBps(monitor.totalBandwidth.txBps))")
                        .font(DS.fontValue).foregroundColor(DS.txBlue)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onReceive(ticker) { _ in
            rxValues.removeFirst(); rxValues.append(monitor.totalBandwidth.rxBps)
            txValues.removeFirst(); txValues.append(monitor.totalBandwidth.txBps)
        }
    }
}

// MARK: - ConnectionDonutCard

private struct ConnectionDonutCard: View {
    @StateObject private var tracker = ConnectionTracker.shared

    private var established: Int { tracker.connections.filter { $0.state == .established }.count }
    private var listening:   Int { tracker.connections.filter { $0.state == .listen      }.count }
    private var other:       Int {
        let t = tracker.connections.count
        return max(0, t - established - listening)
    }
    private var total: Int { tracker.connections.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONNECTIONS").font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted).tracking(1)
            HStack(spacing: 10) {
                // Donut canvas
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2
                    let r  = min(cx, cy) - 4
                    let lineW: CGFloat = 12
                    guard total > 0 else {
                        // empty ring
                        var p = Path(); p.addArc(center: CGPoint(x: cx, y: cy),
                            radius: r, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                        ctx.stroke(p, with: .color(DS.border), lineWidth: lineW)
                        return
                    }
                    let slices: [(Double, Color)] = [
                        (Double(established) / Double(total), DS.rxGreen),
                        (Double(listening)   / Double(total), DS.txBlue),
                        (Double(other)       / Double(total), DS.warnAmber),
                    ]
                    var startAngle = -90.0
                    for (fraction, color) in slices where fraction > 0 {
                        let sweep = fraction * 360
                        var p = Path()
                        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                                 startAngle: .degrees(startAngle),
                                 endAngle:   .degrees(startAngle + sweep),
                                 clockwise: false)
                        ctx.stroke(p, with: .color(color), lineWidth: lineW)
                        startAngle += sweep
                    }
                    // centre count
                    ctx.draw(Text("\(total)").font(.system(size: 13, weight: .bold))
                                .foregroundColor(DS.textPrimary),
                             at: CGPoint(x: cx, y: cy),
                             anchor: .center)
                }
                .frame(width: 72, height: 72)

                // Legend
                VStack(alignment: .leading, spacing: 4) {
                    legendRow(DS.rxGreen,   "Estab",  established)
                    legendRow(DS.txBlue,    "Listen", listening)
                    legendRow(DS.warnAmber, "Other",  other)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func legendRow(_ color: Color, _ label: String, _ n: Int) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundColor(DS.textMuted)
            Spacer()
            Text("\(n)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.textPrimary)
        }
    }
}

// MARK: - LatencyBarsCard

private struct LatencyBarsCard: View {
    @StateObject private var latency = LatencyMonitor.shared

    private var items: [InterfaceLatency] {
        Array(latency.results.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LATENCY").font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted).tracking(1)

            if items.isEmpty {
                Text("Probing…").font(.system(size: 10)).foregroundColor(DS.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 5) {
                    ForEach(items) { item in
                        LatencyBarRow(item: item)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

private struct LatencyBarRow: View {
    let item: InterfaceLatency

    // Max scale: 200 ms = full bar
    private let maxMs: Double = 200

    var body: some View {
        HStack(spacing: 6) {
            Text(shortName(item.friendlyName))
                .font(.system(size: 9)).foregroundColor(DS.textMuted)
                .frame(width: 36, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(DS.bgCard)
                    if item.isReachable {
                        let fraction = min(item.current / maxMs, 1.0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(latencyColor(item.current))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 10)

            Text(item.isReachable ? String(format: "%.0f ms", item.current) : "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(item.isReachable ? latencyColor(item.current) : DS.textMuted)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func shortName(_ name: String) -> String {
        // "en0 — Wi-Fi" → "Wi-Fi", else first token
        if let dash = name.range(of: " — ") { return String(name[dash.upperBound...]) }
        return name.components(separatedBy: " ").first ?? name
    }
}

// MARK: - StarNetworkCanvas

private struct StarNetworkCanvas: View {

    @State private var phase:    CGFloat = 0
    @State private var hexPhase: CGFloat = 0

    private let animTimer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
    private let hexTimer  = Timer.publish(every: 0.05,     on: .main, in: .common).autoconnect()

    private let stars: [(angleOffset: CGFloat, orbitR: CGFloat, size: CGFloat, speed: CGFloat)] = [
        (0.00, 0.30, 4.5, 0.40), (0.62, 0.20, 3.0, 0.65),
        (1.26, 0.38, 5.5, 0.28), (1.88, 0.15, 2.5, 0.90),
        (2.51, 0.35, 4.0, 0.33), (3.14, 0.24, 3.5, 0.55),
        (3.77, 0.40, 6.0, 0.22), (4.40, 0.18, 2.0, 0.80),
        (5.03, 0.28, 4.0, 0.45), (5.66, 0.12, 2.5, 1.00),
        (0.30, 0.42, 5.0, 0.20), (1.00, 0.22, 3.0, 0.70),
    ]

    var body: some View {
        Canvas { ctx, size in
            drawHexGrid(ctx: ctx, size: size)
            let pos = starPositions(size: size)
            drawEdges(ctx: ctx, positions: pos)
            drawStars(ctx: ctx, positions: pos)
        }
        .background(DS.bgSecondary)
        .onReceive(animTimer) { _ in phase    += 0.008 }
        .onReceive(hexTimer)  { _ in hexPhase += 0.04  }
    }

    private func starPositions(size: CGSize) -> [CGPoint] {
        let cx = size.width / 2, cy = size.height / 2
        let r  = min(size.width, size.height) / 2
        return stars.map { s in
            CGPoint(x: cx + cos(s.angleOffset + phase * s.speed) * r * s.orbitR,
                    y: cy + sin(s.angleOffset + phase * s.speed) * r * s.orbitR * 0.55)
        }
    }

    private func drawEdges(ctx: GraphicsContext, positions: [CGPoint]) {
        for i in 0..<positions.count {
            for j in (i+1)..<positions.count {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let d  = sqrt(dx*dx + dy*dy)
                guard d < 200 else { continue }
                var p = Path(); p.move(to: positions[i]); p.addLine(to: positions[j])
                ctx.stroke(p, with: .color(DS.beeYellow.opacity(Double(1 - d/200) * 0.35)), lineWidth: 0.8)
            }
        }
    }

    private func drawStars(ctx: GraphicsContext, positions: [CGPoint]) {
        for (i, pos) in positions.enumerated() {
            let r = stars[i].size / 2
            let pulse = 0.6 + 0.4 * sin(phase * 2.0 + CGFloat(i))
            ctx.fill(Path(ellipseIn: .init(x: pos.x-r*3, y: pos.y-r*3, width: r*6, height: r*6)),
                     with: .color(DS.beeYellow.opacity(0.06 * pulse)))
            ctx.fill(Path(ellipseIn: .init(x: pos.x-r,   y: pos.y-r,   width: r*2, height: r*2)),
                     with: .color(DS.beeYellow.opacity(0.75 * pulse)))
        }
    }

    private func drawHexGrid(ctx: GraphicsContext, size: CGSize) {
        let r: CGFloat = 14, w = r*2, h = r*sqrt(3)
        for col in 0...(Int(size.width/(w*0.75))+2) {
            for row in 0...(Int(size.height/h)+2) {
                let x = CGFloat(col)*w*0.75
                let y = CGFloat(row)*h + (col%2==0 ? 0 : h/2)
                let a = 0.04 + 0.03*sin(hypot(x-size.width/2, y-size.height/2)/28 - hexPhase)
                var p = Path()
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3 - .pi / 6
                    let pt = CGPoint(x: x+r*cos(angle), y: y+r*sin(angle))
                    i==0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
                ctx.stroke(p, with: .color(DS.beeYellow.opacity(a)), lineWidth: 0.7)
            }
        }
    }
}
