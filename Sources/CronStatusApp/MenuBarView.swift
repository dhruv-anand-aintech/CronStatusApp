import SwiftUI

/// Content of the MenuBarExtra popup.
struct MenuBarView: View {
    @EnvironmentObject var cronManager:  CronManager
    @EnvironmentObject var agentManager: LaunchAgentManager
    @Environment(\.openWindow) private var openWindow

    private var userAgents: [LaunchAgentEntry] {
        agentManager.agents.filter { agent in
            !LaunchAgentManager.systemPrefixes.contains { agent.label.hasPrefix($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Summary header ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                summaryRow(icon: "gearshape.2",
                           text: "Agents: \(agentManager.runningCount) / \(userAgents.count) running")
                summaryRow(icon: "clock.badge.checkmark",
                           text: "Cron: \(cronManager.activeCount) / \(cronManager.entries.count) active")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // ── Launch agents ─────────────────────────────────────────────────
            if !userAgents.isEmpty {
                SectionHeader("Launch Agents")
                ForEach(userAgents.sorted { $0.pid != nil && $1.pid == nil }.prefix(10)) { agent in
                    EntryRow(bullet: agent.pid != nil ? "circle.fill" : "circle",
                             color:  agent.pid != nil ? .green : .secondary,
                             title:  agent.label,
                             detail: agent.pid.map { "pid \($0)" } ?? "stopped")
                }
                overflowNote(shown: 10, total: userAgents.count)
                Divider()
            }

            // ── Cron jobs ─────────────────────────────────────────────────────
            if !cronManager.entries.isEmpty {
                SectionHeader("Cron Jobs")
                ForEach(cronManager.entries.sorted { $0.isEnabled && !$1.isEnabled }.prefix(10)) { job in
                    EntryRow(bullet: job.isEnabled ? "circle.fill" : "circle",
                             color:  job.isEnabled ? .green : .secondary,
                             title:  job.scheduleHuman,
                             detail: job.name)
                }
                overflowNote(shown: 10, total: cronManager.entries.count)
                Divider()
            }

            // ── Actions ───────────────────────────────────────────────────────
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            } label: {
                Label("Open Dashboard…", systemImage: "rectangle.on.rectangle")
            }
            .keyboardShortcut("d")

            Button {
                Task {
                    await cronManager.refresh()
                    await agentManager.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .disabled(cronManager.isLoading || agentManager.isLoading)

            Divider()

            Button("Quit CronStatus", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .frame(minWidth: 290)
        .task {
            // First load when the menu is opened
            if cronManager.entries.isEmpty  { await cronManager.refresh() }
            if agentManager.agents.isEmpty  { await agentManager.refresh() }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder
    private func overflowNote(shown: Int, total: Int) -> some View {
        if total > shown {
            Text("  … \(total - shown) more — open Dashboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
        }
    }
}

// ── Reusable sub-views ────────────────────────────────────────────────────────

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6).padding(.bottom, 2)
    }
}

private struct EntryRow: View {
    var bullet: String
    var color:  Color
    var title:  String
    var detail: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: bullet)
                .foregroundStyle(color)
                .font(.system(size: 8))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
