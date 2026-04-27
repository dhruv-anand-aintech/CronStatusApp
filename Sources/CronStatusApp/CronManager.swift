import Foundation
import AppKit

@MainActor
final class CronManager: ObservableObject {
    @Published var entries:              [CronEntry]      = []
    @Published var lastRuns:             [String: String] = [:]   // command fragment → timestamp
    @Published var isLoading:            Bool             = false
    @Published var isRefreshingLastRuns: Bool             = false

    private var rawLines: [String] = []

    private let cacheKey     = "CronStatusApp.lastRuns.cron"
    private let cacheDateKey = "CronStatusApp.lastRunsDate.cron"
    private let cacheTTL:    TimeInterval = 15 * 60   // 15 minutes

    var activeCount: Int { entries.filter(\.isEnabled).count }

    // ── Public API ────────────────────────────────────────────────────────────

    func refresh() async {
        isLoading = true

        // Phase 1 — fast: parse crontab + load cached lastRuns → show UI immediately
        let parsedEntries = await loadCrontab()
        lastRuns = loadCachedLastRuns()
        entries  = parsedEntries
        isLoading = false

        // Phase 2 — slow: re-scrape logs only if cache is stale
        let cacheDate = UserDefaults.standard.double(forKey: cacheDateKey)
        guard Date().timeIntervalSince1970 - cacheDate > cacheTTL else { return }

        isRefreshingLastRuns = true
        let fresh = await fetchLastRuns()
        if !fresh.isEmpty {
            lastRuns = fresh
            saveCachedLastRuns(fresh)
        }
        isRefreshingLastRuns = false
    }

    private func loadCachedLastRuns() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
    }

    private func saveCachedLastRuns(_ dict: [String: String]) {
        UserDefaults.standard.set(dict, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheDateKey)
    }

    func enable(_ entry: CronEntry) async {
        guard entry.lineNumber < rawLines.count else { return }
        var line = rawLines[entry.lineNumber]
        // Strip all leading '#' characters and one optional space
        while line.hasPrefix("#") { line = String(line.dropFirst()) }
        if line.hasPrefix(" ")    { line = String(line.dropFirst()) }
        rawLines[entry.lineNumber] = line
        await commitAndReparse()
    }

    func disable(_ entry: CronEntry) async {
        guard entry.lineNumber < rawLines.count else { return }
        guard !rawLines[entry.lineNumber].hasPrefix("#") else { return }
        rawLines[entry.lineNumber] = "# " + rawLines[entry.lineNumber]
        await commitAndReparse()
    }

    /// Exports the current crontab to a temp file and opens it in the default text editor.
    func openCrontabInEditor() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crontab_edit.txt")
        let content = rawLines.joined(separator: "\n") + "\n"
        try? content.write(to: tmp, atomically: true, encoding: .utf8)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "TextEdit", tmp.path]
        try? task.run()
    }

    func runNow(_ entry: CronEntry) async -> (success: Bool, output: String) {
        let (code, out) = await shell(entry.command)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (code == 0, trimmed.isEmpty ? "(no output)" : trimmed)
    }

    // ── Crontab I/O ───────────────────────────────────────────────────────────

    private func loadCrontab() async -> [CronEntry] {
        let (_, output) = await shell("crontab -l 2>/dev/null")
        var lines = output.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }  // drop spurious trailing blank
        rawLines = lines
        return parse(lines: lines)
    }

    private func commitAndReparse() async {
        let content = rawLines.joined(separator: "\n") + "\n"
        await shellWithInput("crontab -", input: content)
        entries = parse(lines: rawLines)
    }

    // ── Crontab parser ────────────────────────────────────────────────────────

    private func parse(lines: [String]) -> [CronEntry] {
        var results: [CronEntry] = []
        for (i, line) in lines.enumerated() {
            let stripped   = line.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            let isDisabled = stripped.hasPrefix("#")
            let clean      = isDisabled
                ? stripped.drop { $0 == "#" || $0 == " " }.trimmingCharacters(in: .whitespaces)
                : stripped
            let parts      = clean.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard let first = parts.first.map(String.init) else { continue }

            if CronEntry.specials.keys.contains(first) {
                guard parts.count >= 2 else { continue }
                results.append(CronEntry(
                    lineNumber: i, rawLine: stripped, isEnabled: !isDisabled,
                    schedule: first,
                    command:  parts.dropFirst().joined(separator: " "),
                    isValid:  true
                ))
            } else if parts.count >= 6, isCronField(first) {
                results.append(CronEntry(
                    lineNumber: i, rawLine: stripped, isEnabled: !isDisabled,
                    schedule: parts[0...4].joined(separator: " "),
                    command:  String(parts[5]),
                    isValid:  true,
                    minute: String(parts[0]), hour:  String(parts[1]),
                    dom:    String(parts[2]), month: String(parts[3]), dow: String(parts[4])
                ))
            }
        }
        return results
    }

    private func isCronField(_ s: String) -> Bool {
        s.range(of: #"^[\d*,\-/]+$"#, options: .regularExpression) != nil
    }

    // ── Log scraping for last-run times ───────────────────────────────────────

    private func fetchLastRuns() async -> [String: String] {
        // Try unified log first (macOS 10.12+); broaden predicate to catch all cron-related entries
        let (_, output) = await shell(
            #"log show --predicate 'process == "cron" OR senderProcessName == "cron" OR eventMessage CONTAINS "CMD ("' --last 30d --style compact 2>/dev/null | grep -i 'CMD ('"#
        )

        // Match timestamps in compact log format: "YYYY-MM-DD HH:MM:SS" and "CMD (command)"
        guard let pattern = try? NSRegularExpression(
            pattern: #"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*?\bCMD \((.+?)\)"#
        ) else { return [:] }

        var result: [String: String] = [:]

        func scan(_ text: String) {
            for line in text.components(separatedBy: "\n") {
                let ns = line as NSString
                guard let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                      m.numberOfRanges >= 3 else { continue }
                let ts  = ns.substring(with: m.range(at: 1))
                let cmd = ns.substring(with: m.range(at: 2))
                result[cmd] = ts   // log is old→new; last write = most recent
            }
        }

        scan(output)

        // Fallback: /var/log/system.log (older macOS / cron not in unified log)
        if result.isEmpty {
            let (_, syslog) = await shell(#"grep -a 'CMD (' /var/log/system.log 2>/dev/null | tail -500"#)
            // syslog format: "Jan 15 10:30:00 host cron[pid]: (user) CMD (command)"
            guard let sysPattern = try? NSRegularExpression(
                pattern: #"(\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}).*?\bCMD \((.+?)\)"#
            ) else { return result }
            for line in syslog.components(separatedBy: "\n") {
                let ns = line as NSString
                guard let m = sysPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                      m.numberOfRanges >= 3 else { continue }
                let ts  = ns.substring(with: m.range(at: 1))
                let cmd = ns.substring(with: m.range(at: 2))
                result[cmd] = ts
            }
        }

        return result
    }
}
