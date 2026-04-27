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
