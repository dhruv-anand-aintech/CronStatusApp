import SwiftUI
import AppKit

@main
struct CronStatusApp: App {
    @StateObject private var cronManager  = CronManager()
    @StateObject private var agentManager = LaunchAgentManager()

    init() {
        // Start as accessory (no Dock icon, no cmd+tab entry)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Switch to .regular (shows in cmd+tab) when the dashboard window opens,
        // back to .accessory when all windows close.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in
            NSApplication.shared.setActivationPolicy(.regular)
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
