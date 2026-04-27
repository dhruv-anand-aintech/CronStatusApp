import Foundation

struct CronEntry: Identifiable, Equatable {
    var id: Int { lineNumber }
    var lineNumber: Int
    var rawLine:    String
    var isEnabled:  Bool
    var schedule:   String   // raw schedule string (e.g. "0 5 * * *" or "@daily")
    var command:    String
    var isValid:    Bool

    // Individual time fields, populated when schedule is a 5-field expression
    var minute: String = "*"
    var hour:   String = "*"
    var dom:    String = "*"
    var month:  String = "*"
    var dow:    String = "*"

    /// Sort key: enabled=1, disabled=0
    var isEnabledRank: Int { isEnabled ? 1 : 0 }

    /// Parse `>> /path/to/file` or `> /path/to/file` from the command, expanding ~
    var logFilePath: String? {
        guard let range = command.range(of: #">>?\s+(\S+)"#, options: .regularExpression) else { return nil }
        let match = String(command[range])
        let parts = match.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let raw = parts[1]
        if raw == "/dev/null" { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    /// mtime of the log file this cron job writes to, if it exists
    var lastRunDate: Date? {
        guard let path = logFilePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return mtime
    }

    /// Next fire date computed by iterating minutes from now (handles */N, ranges, lists, wildcards)
    var nextRunDate: Date? {
        guard isEnabled, isValid else { return nil }
        if schedule == "@reboot" { return nil }
        if let desc = Self.specials[schedule] {
            // Map specials to equivalent 5-field for calculation
            let mapped: String
            switch schedule {
            case "@hourly":             mapped = "0 * * * *"
            case "@daily", "@midnight": mapped = "0 0 * * *"
            case "@weekly":             mapped = "0 0 * * 0"
            case "@monthly":            mapped = "0 0 1 * *"
            case "@yearly", "@annually":mapped = "0 0 1 1 *"
            default: return nil
            }
            _ = desc
            return nextFire(minute: String(mapped.split(separator: " ")[0]),
                            hour:   String(mapped.split(separator: " ")[1]),
                            dom:    String(mapped.split(separator: " ")[2]),
                            month:  String(mapped.split(separator: " ")[3]),
                            dow:    String(mapped.split(separator: " ")[4]))
        }
        return nextFire(minute: minute, hour: hour, dom: dom, month: month, dow: dow)
    }

    private func nextFire(minute m: String, hour h: String, dom: String, month mo: String, dow dw: String) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        comps.second = 0
        // Start from next minute
        comps.minute = (comps.minute ?? 0) + 1
        guard var candidate = cal.date(from: comps) else { return nil }

        for _ in 0..<(366 * 24 * 60) {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: candidate)
            if matches(c.minute!, field: m) &&
               matches(c.hour!,   field: h) &&
               matches(c.day!,    field: dom) &&
               matches(c.month!,  field: mo) &&
               matchesDow(c.weekday! - 1, field: dw) {  // weekday: 1=Sun → 0-based
                return candidate
            }
            candidate = candidate.addingTimeInterval(60)
        }
        return nil
    }

    private func matches(_ value: Int, field: String) -> Bool {
        if field == "*" { return true }
        for part in field.split(separator: ",") {
            let s = String(part)
            if s.hasPrefix("*/") {
                if let step = Int(s.dropFirst(2)), step > 0, value % step == 0 { return true }
            } else if s.contains("-") {
                let bounds = s.split(separator: "-").compactMap { Int($0) }
                if bounds.count == 2, value >= bounds[0], value <= bounds[1] { return true }
            } else if let v = Int(s), v == value { return true }
        }
        return false
    }

    private func matchesDow(_ value: Int, field: String) -> Bool {
        // Cron dow: 0 and 7 both mean Sunday
        if field == "*" { return true }
        for part in field.split(separator: ",") {
            let s = String(part)
            if let v = Int(s) { if v % 7 == value % 7 { return true } }
            else if s.contains("-") {
                let bounds = s.split(separator: "-").compactMap { Int($0) }
                if bounds.count == 2, value >= bounds[0], value <= bounds[1] { return true }
            }
        }
        return false
    }

    // ── Computed display helpers ──────────────────────────────────────────────

    /// Basename of the first token of the command.
    var name: String {
        guard !command.isEmpty else { return "Unknown" }
        let first = command.split(separator: " ").first.map(String.init) ?? command
        return URL(fileURLWithPath: first).lastPathComponent
    }

    /// Human-readable description of when the job runs.
    var scheduleHuman: String {
        if let desc = Self.specials[schedule] { return desc }
        guard isValid else { return schedule.isEmpty ? "Unknown" : schedule }
        return formatCron()
    }

    static let specials: [String: String] = [
        "@reboot":   "At startup",
        "@hourly":   "Every hour",
        "@daily":    "Daily at midnight",
        "@midnight": "Daily at midnight",
        "@weekly":   "Every Sunday",
        "@monthly":  "1st of month",
        "@yearly":   "January 1st",
        "@annually": "January 1st",
    ]

    // ── Schedule formatting ───────────────────────────────────────────────────

    private func formatCron() -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Every N minutes  (*/N * * * *)
        if minute.hasPrefix("*/"), hour == "*", dom == "*", month == "*", dow == "*" {
            return "Every \(minute.dropFirst(2)) min"
        }
        // Every hour at :MM  (* * * * * → but hour is *)
        if hour == "*", dom == "*", month == "*", dow == "*" {
            let m = minute.count == 1 ? "0\(minute)" : minute
            return "Every hour at :\(m)"
        }
        // Simple daily  (M H * * *)
        if dom == "*", month == "*", dow == "*" {
            if let h = Int(hour), let m = Int(minute) {
                return String(format: "Daily at %02d:%02d", h, m)
            }
            return "Daily h=\(hour) m=\(minute)"
        }
        // General case
        var parts: [String] = []
        if let h = Int(hour), let m = Int(minute) {
            parts.append(String(format: "%02d:%02d", h, m))
        } else {
            parts.append("h=\(hour) m=\(minute)")
        }
        if dow != "*" {
            if let d = Int(dow), d < days.count { parts.append("on \(days[d])") }
            else                                { parts.append("dow=\(dow)") }
        }
        if dom   != "*" { parts.append("day \(dom)") }
        if month != "*" { parts.append("month \(month)") }
        return parts.joined(separator: ", ")
    }
}
