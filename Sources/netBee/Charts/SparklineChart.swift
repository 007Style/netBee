// ─────────────────────────────────────────────────────────────────────────────
// SparklineChart.swift  —  Reusable Canvas-based sparkline (matches beeMon style)
// ─────────────────────────────────────────────────────────────────────────────
import SwiftUI

// MARK: - SparklineChart

/// A filled area sparkline drawn with SwiftUI Canvas.
/// Accepts any sequence of Doubles in [0, max] and draws a gradient-filled path.
struct SparklineChart: View {
    let values:     [Double]
    let color:      Color
    var lineWidth:  CGFloat = 1.5
    var fillOpacity: Double = 0.25

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxVal = values.max() ?? 1.0
            let norm   = maxVal > 0 ? maxVal : 1.0

            let pts = values.enumerated().map { i, v -> CGPoint in
                let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                let y = size.height - (CGFloat(v / norm) * size.height)
                return CGPoint(x: x, y: y)
            }

            // ── Fill path ────────────────────────────────────────────────────
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            for pt in pts { fill.addLine(to: pt) }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(fillOpacity)))

            // ── Stroke line ──────────────────────────────────────────────────
            var line = Path()
            line.move(to: pts[0])
            for pt in pts.dropFirst() { line.addLine(to: pt) }
            ctx.stroke(line, with: .color(color), lineWidth: lineWidth)
        }
    }
}

// MARK: - DualSparkline

/// Side-by-side RX (down) / TX (up) sparklines sharing the same canvas height.
struct DualSparklineChart: View {
    let rxValues: [Double]   // receive
    let txValues: [Double]   // transmit
    var height:   CGFloat = 36

    private let rxColor = Color(red: 0.27, green: 0.70, blue: 0.40)   // green
    private let txColor = Color(red: 0.30, green: 0.60, blue: 0.90)   // blue

    var body: some View {
        ZStack {
            SparklineChart(values: rxValues, color: rxColor, lineWidth: 1.5, fillOpacity: 0.20)
            SparklineChart(values: txValues, color: txColor, lineWidth: 1.5, fillOpacity: 0.20)
        }
        .frame(height: height)
    }
}
