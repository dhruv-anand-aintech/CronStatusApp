import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindow: (() -> Void)?

    // Fired when user double-clicks the .app in Finder while already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.activate(ignoringOtherApps: true)
            openWindow?()
        }
        return true
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
    @StateObject private var guardianManager = GuardianManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Start as accessory (no Dock icon, no cmd+tab entry)
        NSApplication.shared.setActivationPolicy(.accessory)
        let dashboardTitle = "Cron & Launch Agent Monitor"

        // Promote only the dashboard. MenuBarExtra also creates key windows, but
        // those transient popovers must not make the app appear in the Dock.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title == dashboardTitle else { return }
            NSApp.setActivationPolicy(.regular)
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title == dashboardTitle else { return }
            DispatchQueue.main.async {
                let dashboardVisible = NSApp.windows.contains {
                    $0.title == dashboardTitle && $0.isVisible && !$0.isMiniaturized
                }
                if !dashboardVisible {
                    NSApp.setActivationPolicy(.accessory)
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
                .environmentObject(guardianManager)
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
                
                // Start periodic guardian checks
                while true {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
                    await agentManager.refresh()
                    await guardianManager.checkAgents(agents: agentManager.agents, agentManager: agentManager)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // ── Full dashboard window ────────────────────────────────────────────
        Window("Cron & Launch Agent Monitor", id: "dashboard") {
            DashboardView()
                .environmentObject(cronManager)
                .environmentObject(agentManager)
                .environmentObject(guardianManager)
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1020, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        // Remove the default "New" menu item
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
