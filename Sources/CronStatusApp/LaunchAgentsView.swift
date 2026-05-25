import SwiftUI
import AppKit

struct LaunchAgentsView: View {
    @EnvironmentObject var agentManager: LaunchAgentManager
    @EnvironmentObject var guardianManager: GuardianManager

    @State private var selection:        String?                              = nil
    @State private var filterText                                             = ""
    @State private var showSystemAgents                                      = false
    @State private var sortOrder: [KeyPathComparator<LaunchAgentEntry>] = [KeyPathComparator(\LaunchAgentEntry.statusRank, order: .reverse)]
    @State private var actionError:      String?                             = nil
    @State private var confirmDelete:    LaunchAgentEntry?                   = nil
    @State private var eventMonitor: Any? = nil

    private var filtered: [LaunchAgentEntry] {
        agentManager.agents.filter { agent in
            if !showSystemAgents,
               LaunchAgentManager.systemPrefixes.contains(where: { agent.label.hasPrefix($0) }) {
                return false
            }
            guard !filterText.isEmpty else { return true }
            return agent.label.localizedCaseInsensitiveContains(filterText)
                || agent.command.localizedCaseInsensitiveContains(filterText)
        }
    }

    private var selectedAgent: LaunchAgentEntry? {
        selection.flatMap { id in agentManager.agents.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Filter bar ────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by label or command…", text: $filterText)
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 16)
                Toggle("System", isOn: $showSystemAgents)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if filtered.isEmpty && !agentManager.isLoading {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "gearshape.badge.xmark",
                    description: Text(filterText.isEmpty
                        ? "No plist files found in LaunchAgents or LaunchDaemons directories."
                        : "No agents match '\(filterText)'.")
                )
            } else {
                // ── Table ──────────────────────────────────────────────────────
                Table(
                    filtered.sorted(using: sortOrder),
                    selection: $selection,
                    sortOrder: $sortOrder
                ) {
                    tableColumnsA()
                    tableColumnsB()
                }

                // ── Detail strip ───────────────────────────────────────────────
                if let agent = selectedAgent {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Command", systemImage: "terminal")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(agent.command.isEmpty ? "(no command specified)" : agent.command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Text(agent.plistURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .help(agent.plistURL.path)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        // ── Bottom toolbar ─────────────────────────────────────────────────────
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if let agent = selectedAgent {
                    // Load/Unload
                    if agent.isLoaded {
                        Button("Unload") { act { await agentManager.unloadAgent(agent) } }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Load")   { act { await agentManager.loadAgent(agent) } }
                            .buttonStyle(.bordered)
                    }
                    // Start/Stop/Restart
                    if agent.pid != nil {
                        Button("Stop")    { act { await agentManager.stopAgent(agent) } }
                            .buttonStyle(.bordered)
                        Button("Restart") { act { await agentManager.restartAgent(agent) } }
                            .buttonStyle(.borderedProminent)
                    } else if agent.isLoaded {
                        Button("Start")   { act { await agentManager.startAgent(agent) } }
                            .buttonStyle(.borderedProminent)
                    }
                    // Delete plist
                    Button("Delete…", role: .destructive) { confirmDelete = agent }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Text("\(filtered.count) shown of \(agentManager.agents.count) total")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        // ── Double-click to open .plist in default editor ──────────────────────
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                if event.clickCount == 2, let agent = selectedAgent {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-a", "TextEdit", agent.plistURL.path]
                    try? task.run()
                }
                return event
            }
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        }
        // ── Delete confirmation ────────────────────────────────────────────────
        .alert("Delete Agent?", isPresented: .init(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let agent = confirmDelete {
                    act { await agentManager.deleteAgent(agent) }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This will unload \"\(confirmDelete?.label ?? "")\" and delete its plist file. This cannot be undone.")
        }
        // ── Error alert ────────────────────────────────────────────────────────
        .alert("Action Failed", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @TableColumnBuilder<LaunchAgentEntry, KeyPathComparator<LaunchAgentEntry>>
    private func tableColumnsA() -> some TableColumnContent<LaunchAgentEntry, KeyPathComparator<LaunchAgentEntry>> {
        TableColumn("", value: \LaunchAgentEntry.statusRank) { agent in
            statusImage(agent)
        }.width(22)

        TableColumn("Guard") { agent in
            Toggle("", isOn: Binding(
                get: { guardianManager.isGuarded(agent.label) },
                set: { _ in guardianManager.toggleGuarding(for: agent.label, agents: agentManager.agents) }
            ))
            .toggleStyle(.checkbox)
            .help("Notify if process stops or errors appear in logs")
        }.width(40)

        TableColumn("Label", value: \.label) { agent in
            Text(agent.label).lineLimit(1).help(agent.label)
        }.width(min: 180, ideal: 300)

        TableColumn("PID") { agent in
            Text(agent.pid.map(String.init) ?? "—")
                .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
        }.width(60)

        TableColumn("Exit") { agent in
            let code = agent.lastExitStatus
            Text(code.map(String.init) ?? "—")
                .foregroundStyle(code != nil && code != 0 ? .red : .secondary)
                .font(.system(.body, design: .monospaced))
        }.width(55)

        TableColumn("Trigger", value: \.triggerHuman) { agent in
            Text(agent.triggerHuman).foregroundStyle(.secondary).font(.system(size: 11))
        }.width(min: 80, ideal: 140)
    }

    @TableColumnBuilder<LaunchAgentEntry, KeyPathComparator<LaunchAgentEntry>>
    private func tableColumnsB() -> some TableColumnContent<LaunchAgentEntry, KeyPathComparator<LaunchAgentEntry>> {
        TableColumn("Source", value: \.sourceLabel) { agent in
            Text(agent.sourceLabel).foregroundStyle(.secondary).font(.system(size: 11))
        }.width(min: 70, ideal: 110)

        TableColumn("Last Run") { agent in
            Text(agent.lastRun).foregroundStyle(.secondary).font(.system(size: 11, design: .monospaced))
        }.width(min: 90, ideal: 120)

        TableColumn("Next Run") { agent in
            if agent.keepAlive && agent.pid == nil {
                Text("on exit").foregroundStyle(.orange).font(.system(size: 11))
            } else if let next = agent.nextRunDate {
                Text(relativeTime(from: next)).foregroundStyle(.secondary).font(.system(size: 11, design: .monospaced))
            } else {
                Text("—").foregroundStyle(.secondary).font(.system(size: 11))
            }
        }.width(min: 80, ideal: 110)

        TableColumn("Runs") { agent in
            Text(agent.runCount.map(String.init) ?? "—")
                .foregroundStyle(.secondary).font(.system(size: 11, design: .monospaced))
        }.width(50)

        TableColumn("Installed") { agent in
            Text(agent.plistCreated.map { shortDate($0) } ?? "—")
                .foregroundStyle(.secondary).font(.system(size: 11))
        }.width(min: 70, ideal: 90)

        TableColumn("Modified") { agent in
            Text(agent.plistModified.map { shortDate($0) } ?? "—")
                .foregroundStyle(.secondary).font(.system(size: 11))
        }.width(min: 70, ideal: 90)
    }

    @ViewBuilder
    private func statusImage(_ agent: LaunchAgentEntry) -> some View {
        let shouldBeRunning = agent.startInterval != nil || agent.keepAlive
        if agent.pid != nil {
            Image(systemName: "circle.fill")
                .foregroundStyle(.green).font(.system(size: 9))
        } else if let code = agent.lastExitStatus, code != 0 {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red).font(.system(size: 9))
        } else if agent.isLoaded && shouldBeRunning {
            // Loaded, expects to be running periodically, but currently idle
            Image(systemName: "circle.fill")
                .foregroundStyle(.yellow).font(.system(size: 9))
        } else if agent.isLoaded {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary).font(.system(size: 9))
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary).font(.system(size: 9))
        }
    }

    private func relativeTime(from date: Date) -> String {
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0   { return "overdue" }
        if secs < 60   { return "in \(secs)s" }
        let mins = secs / 60
        if mins < 60   { return "in \(mins)m" }
        let hours = mins / 60
        if hours < 24  { return "in \(hours)h" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }

    private func act(_ action: @escaping () async -> (Bool, String)) {
        Task {
            let (ok, msg) = await action()
            await agentManager.refresh()
            if !ok, !msg.isEmpty { actionError = msg }
        }
    }
}
