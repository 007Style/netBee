// ─────────────────────────────────────────────────────────────────────────────
// TrayController.swift  —  NSStatusItem + dashboard window management
//
// Left-click  → toggle dashboard
// Right-click → context menu (Open, About, Quit)
//
// The tray icon renders a live bandwidth sparkline + ↓↑ byte rate, identical
// in spirit to beeMon's CPU sparkline tray icon.
// ─────────────────────────────────────────────────────────────────────────────
import AppKit
import SwiftUI
import Combine

@MainActor
final class TrayController {

    private let statusItem  = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var window:       NSWindow?
    private var cancellables  = Set<AnyCancellable>()
    private var iconTimer:    AnyCancellable?

    // Icon drawing state — rolling 56 samples (wide icon)
    private var rxHistory: [Double] = Array(repeating: 0, count: 56)
    private var txHistory: [Double] = Array(repeating: 0, count: 56)

    init() {
        setupButton()
        setupMenu()
        startIconUpdates()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let btn = statusItem.button else { return }
        btn.action = #selector(handleButtonClick(_:))
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btn.target = self
        renderIcon(rxBps: 0, txBps: 0)
    }

    private func setupMenu() {}   // menu built lazily on right-click

    // MARK: - Icon updates

    private func startIconUpdates() {
        iconTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let total = NetworkMonitor.shared.totalBandwidth
                self.rxHistory.removeFirst()
                self.txHistory.removeFirst()
                self.rxHistory.append(total.rxBps)
                self.txHistory.append(total.txBps)
                self.renderIcon(rxBps: total.rxBps, txBps: total.txBps)
            }
    }

    private func renderIcon(rxBps: Double, txBps: Double) {
        let size    = CGSize(width: 72, height: 18)
        let image   = NSImage(size: size)
        image.lockFocus()

        // Background
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        // Sparkline — RX (green)
        drawSparkline(values: rxHistory, color: NSColor(DS.rxGreen), in: size, yOffset: 0, height: 8)
        // Sparkline — TX (blue) — inverted downward below centre
        drawSparkline(values: txHistory, color: NSColor(DS.txBlue),  in: size, yOffset: 9, height: 8, flipY: true)

        // Text label
        let rxStr = shortBps(rxBps)
        let txStr = shortBps(txBps)
        let label = "\(rxStr) \(txStr)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.80)
        ]
        let str  = NSAttributedString(string: label, attributes: attrs)
        let rect = str.boundingRect(with: size, options: [])
        str.draw(at: NSPoint(x: size.width - rect.width - 2,
                             y: (size.height - rect.height) / 2))

        image.unlockFocus()
        image.isTemplate = false
        statusItem.button?.image = image
    }

    private func drawSparkline(values: [Double], color: NSColor, in size: CGSize,
                               yOffset: CGFloat, height: CGFloat, flipY: Bool = false) {
        guard values.count > 1 else { return }
        let maxVal = values.max() ?? 1.0
        let norm   = maxVal > 0 ? maxVal : 1.0

        let path = NSBezierPath()
        let iconWidth = size.width * 0.55   // left portion for sparkline

        for (i, v) in values.enumerated() {
            let x = CGFloat(i) / CGFloat(values.count - 1) * iconWidth
            let fraction = CGFloat(v / norm)
            let y: CGFloat
            if flipY {
                y = yOffset + (1.0 - fraction) * height * 0.8
            } else {
                y = yOffset + height - fraction * height * 0.8
            }
            i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
        }

        color.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    private func shortBps(_ bps: Double) -> String {
        switch bps {
        case ..<1_024:         return "0"
        case ..<1_048_576:     return String(format: "%.0fK", bps / 1_024)
        case ..<1_073_741_824: return String(format: "%.1fM", bps / 1_048_576)
        default:               return String(format: "%.1fG", bps / 1_073_741_824)
        }
    }

    // MARK: - Click handling

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleDashboard()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open netBee",  action: #selector(openDashboard), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "About netBee", action: #selector(openAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",         action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Window management

    @objc private func openDashboard() {
        showDashboard()
    }

    @objc private func openAbout() {
        showDashboard(tab: .about)
    }

    private func toggleDashboard() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            showDashboard()
        }
    }

    private func showDashboard(tab: DashboardTab = .overview) {
        if window == nil {
            let view       = DashboardView()
            let hosting    = NSHostingView(rootView: view)
            let w          = NSWindow(
                contentRect:    NSRect(x: 0, y: 0, width: 640, height: 560),
                styleMask:      [.titled, .closable, .miniaturizable, .resizable],
                backing:        .buffered,
                defer:          false
            )
            w.title               = "netBee"
            w.contentView         = hosting
            w.isReleasedWhenClosed = false
            w.level               = .floating
            w.titlebarAppearsTransparent = true
            w.backgroundColor     = NSColor(DS.bgPrimary)
            positionNearTray(w)
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionNearTray(_ window: NSWindow) {
        guard let screen = NSScreen.main,
              let btn    = statusItem.button,
              let btnWin = btn.window else {
            window.center()
            return
        }
        let btnFrame   = btnWin.convertToScreen(btn.frame)
        let screenFrame = screen.visibleFrame
        let wFrame      = window.frame

        var x = btnFrame.midX - wFrame.width / 2
        var y = btnFrame.minY - wFrame.height - 6

        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - wFrame.width - 8))
        y = max(screenFrame.minY + 8, y)

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
