import SwiftUI
import AppKit

struct CronJobsView: View {
    @EnvironmentObject var cronManager: CronManager

    @State private var selection:  CronEntry.ID?         = nil
    @State private var sortOrder: [KeyPathComparator<CronEntry>] = [KeyPathComparator(\CronEntry.isEnabledRank, order: .reverse)]
    @State private var runOutput:  String?               = nil
    @State private var showRunSheet                      = false
    @State private var runSuccess: Bool                  = false
    @State private var eventMonitor: Any?                = nil

    private var selectedEntry: CronEntry? {
        selection.flatMap { id in cronManager.entries.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            if cronManager.entries.isEmpty && !cronManager.isLoading {
                ContentUnavailableView(
                    "No Cron Jobs",
                    systemImage: "clock.badge.xmark",
                    description: Text("No entries found in your crontab.\nAdd jobs with `crontab -e`.")
                )
            } else {
                // ── Table ──────────────────────────────────────────────────────
                Table(
                    cronManager.entries.sorted(using: sortOrder),
                    selection: $selection,
                    sortOrder: $sortOrder
                ) {
                    // Status dot
                    TableColumn("") { entry in
                        Image(systemName: entry.isEnabled ? "circle.fill" : "circle")
                            .foregroundStyle(entry.isEnabled ? .green : .secondary)
                            .font(.system(size: 9))
                    }
                    .width(22)

                    TableColumn("Schedule", value: \.scheduleHuman) { entry in
                        Text(entry.scheduleHuman)
                            .foregroundStyle(entry.isEnabled ? .primary : .secondary)
                    }
                    .width(min: 130, ideal: 170)

                    TableColumn("Name", value: \.name) { entry in
                        Text(entry.name)
                            .foregroundStyle(entry.isEnabled ? .primary : .secondary)
                    }
                    .width(min: 80, ideal: 130)

                    TableColumn("Command") { entry in
                        Text(entry.command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(entry.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .width(min: 180, ideal: 340)

                    TableColumn("Last Run") { entry in
                        let val = lastRunFor(entry)
                        if cronManager.isRefreshingLastRuns && val == "—" {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(val)
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .width(min: 100, ideal: 150)
                }

                // ── Detail strip ───────────────────────────────────────────────
                if let entry = selectedEntry {
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Full command", systemImage: "terminal")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(entry.command)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        // ── Bottom toolbar ─────────────────────────────────────────────────────
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if let entry = selectedEntry {
                    Button(entry.isEnabled ? "Disable" : "Enable") {
                        Task {
                            if entry.isEnabled { await cronManager.disable(entry) }
                            else               { await cronManager.enable(entry) }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Run Now") {
                        Task {
                            let (ok, out) = await cronManager.runNow(entry)
                            runSuccess = ok
                            runOutput  = out
                            showRunSheet = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Text("\(cronManager.entries.count) job(s) — \(cronManager.activeCount) active")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        // ── Double-click to open crontab in editor ─────────────────────────────
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                if event.clickCount == 2, selection != nil {
                    cronManager.openCrontabInEditor()
                }
                return event
            }
        }
        .onDisappear {
            if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        }
        // ── Run output sheet ───────────────────────────────────────────────────
        .sheet(isPresented: $showRunSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(runSuccess ? "Job succeeded" : "Job failed",
                          systemImage: runSuccess ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(runSuccess ? .green : .red)
                        .font(.headline)
                    Spacer()
                    Button("Close") { showRunSheet = false }
                        .keyboardShortcut(.cancelAction)
                }
                Divider()
                ScrollView {
                    Text(runOutput ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)
            }
            .padding()
            .frame(minWidth: 500, minHeight: 260)
        }
    }

    private func lastRunFor(_ entry: CronEntry) -> String {
        // Best source: mtime of the log file the cron job writes to (>> /path)
        if let date = entry.lastRunDate { return relativeTime(from: date) }
        // Fallback: log scrape cache
        for (cmd, ts) in cronManager.lastRuns {
            if entry.command.contains(cmd) || cmd.contains(entry.command) { return ts }
        }
        return "—"
    }

    private func relativeTime(from date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 0    { return "just now" }
        if secs < 60   { return "\(secs)s ago" }
        let mins = secs / 60
        if mins < 60   { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24  { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7    { return "\(days)d ago" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
