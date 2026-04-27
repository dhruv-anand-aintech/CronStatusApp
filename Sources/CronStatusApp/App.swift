import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindow: (() -> Void)?

    // Fired when user double-clicks the .app in Finder while already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openWindow?() }
        return false
    }

    // Keep running when all windows close — don't terminate
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CronStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var cronManager  = CronManager()
    @StateObject private var agentManager = LaunchAgentManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Start as accessory (no Dock icon, no cmd+tab entry)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Switch to .regular (shows in cmd+tab) when the dashboard window opens.
        // Icon must be set AFTER the policy switch — setting it before has no effect.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in
            NSApplication.shared.setActivationPolicy(.regular)
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = icon
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let visible = NSApplication.shared.windows.filter { $0.isVisible && !$0.isMiniaturized }
                if visible.isEmpty {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
            }
        }
    }

    var body: some Scene {
        // Wire delegate so Finder double-click opens the dashboard
        let _ = { appDelegate.openWindow = { openWindow(id: "dashboard") } }()

        // ── Menu bar icon + dropdown ─────────────────────────────────────────
        MenuBarExtra {
            MenuBarView()
                .environmentObject(cronManager)
                .environmentObject(agentManager)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                if agentManager.isLoading || cronManager.isLoading {
                    Text("…")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Text("\(agentManager.runningCount)a · \(cronManager.activeCount)c")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .task {
                // Trigger initial load immediately on launch, not on first menu open
                await agentManager.refresh()
                await cronManager.refresh()
            }
        }
        .menuBarExtraStyle(.window)

        // ── Full dashboard window ────────────────────────────────────────────
        Window("Cron & Launch Agent Monitor", id: "dashboard") {
            DashboardView()
                .environmentObject(cronManager)
                .environmentObject(agentManager)
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1020, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        // Remove the default "New" menu item
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
