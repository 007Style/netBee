// ─────────────────────────────────────────────────────────────────────────────
// main.swift  —  netBee entry point
//
// Boots NSApplication in agent (menu-bar-only) mode and hands off to
// TrayController, which owns the status-bar icon and the dashboard window.
// ─────────────────────────────────────────────────────────────────────────────
import AppKit

// ── Bootstrap ────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and Command-Tab switcher (LSUIElement = true in plist)
        NSApp.setActivationPolicy(.accessory)
        tray = TrayController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
    }
}

// ── Run ───────────────────────────────────────────────────────────────────────

let app  = NSApplication.shared
let del  = AppDelegate()
app.delegate = del
app.run()
