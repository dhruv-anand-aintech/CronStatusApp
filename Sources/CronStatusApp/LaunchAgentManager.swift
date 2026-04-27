import Foundation

@MainActor
final class LaunchAgentManager: ObservableObject {
    @Published var agents:    [LaunchAgentEntry] = []
    @Published var isLoading: Bool               = false

    // Label prefixes that belong to Apple/system — hidden by default
    static let systemPrefixes = [
        "com.apple.", "com.openssh.", "org.cups.",
        "com.microsoft.autoupdate", "com.adobe.",
    ]

    // Directories to scan, in order: (URL, isDaemon)
    private static let searchPaths: [(URL, Bool)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (home.appendingPathComponent("Library/LaunchAgents"), false),
            (URL(fileURLWithPath: "/Library/LaunchAgents"),  false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), true),
        ]
    }()

    var runningCount: Int { agents.filter { $0.pid != nil }.count }

    // ── Public API ────────────────────────────────────────────────────────────

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Both of these are fast (<50ms total): launchctl list + ps
        async let runningTask   = fetchRunning()
        async let startTimesTask = fetchProcessStartTimes()
        let (running, startTimes) = await (runningTask, startTimesTask)

        agents = buildAgents(running: running, startTimes: startTimes)
    }

    private func buildAgents(running: [String: (pid: Int?, status: Int?)],
                              startTimes: [Int: String]) -> [LaunchAgentEntry] {
        var result: [LaunchAgentEntry] = []
        for (dirURL, isDaemon) in Self.searchPaths {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for url in urls.filter({ $0.pathExtension == "plist" })
                           .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var entry = LaunchAgentEntry(plistURL: url, isDaemon: isDaemon)
                if let info = running[entry.label] {
                    entry.isLoaded       = true
                    entry.pid            = info.pid
                    entry.lastExitStatus = info.status
                }
                entry.lastRun = resolveLastRun(entry: entry, startTimes: startTimes)
                result.append(entry)
            }
        }
        return result
    }

    /// Determine last run time without any log query:
    /// - Running agent → process start time from `ps`
    /// - Stopped agent → mtime of stdout/stderr log file (if configured in plist)
    private func resolveLastRun(entry: LaunchAgentEntry, startTimes: [Int: String]) -> String {
        if let pid = entry.pid, let t = startTimes[pid] {
            return t
        }
        let logPath = entry.standardOutPath ?? entry.standardErrPath
        if let raw = logPath {
            let path = (raw as NSString).expandingTildeInPath
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date {
                return formatDate(mtime)
            }
        }
        return "—"
    }

    // ── Process start times via `ps` (instant) ────────────────────────────────

    private func fetchProcessStartTimes() async -> [Int: String] {
        let (_, output) = await shell("ps -ax -o pid=,lstart= 2>/dev/null")
        var map: [Int: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: "  1330 Mon Mar 10 14:11:47 2026"
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 5, let pid = Int(parts[0]) else { continue }
            // parts[1..5]: "Mon Mar 10 14:11:47 2026"
            let dateStr = parts.dropFirst().joined(separator: " ")
            map[pid] = formatPsDate(dateStr)
        }
        return map
    }

    /// "Mon Mar 10 14:11:47 2026" → relative string like "5s ago" / "3m ago" / "Mar 10 14:11"
    private func formatPsDate(_ s: String) -> String {
        let parts = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 5 else { return s }
        // parts: [weekday, month, day, time, year] e.g. ["Mon", "Mar", "10", "14:11:47", "2026"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        if let date = df.date(from: s) { return relativeTime(from: date) }
        // fallback: show HH:MM
        let hhmm = parts[3].components(separatedBy: ":").prefix(2).joined(separator: ":")
        return "\(parts[1]) \(parts[2]) \(hhmm)"
    }

    /// Format a Date as relative time
    private func formatDate(_ date: Date) -> String {
        relativeTime(from: date)
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

    // ── launchctl list (fast) ─────────────────────────────────────────────────

    private func fetchRunning() async -> [String: (pid: Int?, status: Int?)] {
        let (_, output) = await shell("launchctl list 2>/dev/null")
        var map: [String: (pid: Int?, status: Int?)] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let pid    = Int(parts[0])
            let status = Int(parts[1])
            let label  = parts[2]
            map[label] = (pid: pid, status: status)
        }
        return map
    }

    // ── launchctl wrappers ────────────────────────────────────────────────────

    func loadAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        await launchctl("load", entry.plistURL.path)
    }
    func unloadAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        await launchctl("unload", entry.plistURL.path)
    }
    func startAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        await launchctl("start", entry.label)
    }
    func stopAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        await launchctl("stop", entry.label)
    }
    func deleteAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        _ = await unloadAgent(entry)
        do {
            try FileManager.default.removeItem(at: entry.plistURL)
            return (true, "")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func restartAgent(_ entry: LaunchAgentEntry) async -> (Bool, String) {
        let uid = getuid()
        let (ok, msg) = await launchctl("kickstart", "-k", "gui/\(uid)/\(entry.label)")
        if ok { return (true, msg) }
        _ = await unloadAgent(entry)
        try? await Task.sleep(nanoseconds: 300_000_000)
        return await loadAgent(entry)
    }

    @discardableResult
    private func launchctl(_ args: String...) async -> (Bool, String) {
        let cmd = (["launchctl"] + args).joined(separator: " ")
        let (code, out) = await shell(cmd)
        return (code == 0, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
