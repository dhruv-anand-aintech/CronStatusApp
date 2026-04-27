import Foundation

struct LaunchAgentEntry: Identifiable, Equatable {
    var id: String { label }

    var plistURL:  URL
    var isDaemon:  Bool
    var label:     String
    var program:   String
    var programArguments: [String]
    var runAtLoad:     Bool
    var startInterval: Int?
    var keepAlive:     Bool

    // Runtime state (populated by LaunchAgentManager from `launchctl list`)
    var isLoaded:        Bool   = false
    var pid:             Int?  = nil
    var lastExitStatus:  Int?  = nil
    var lastRun:         String = "—"
    var standardOutPath: String? = nil
    var standardErrPath: String? = nil

    /// Numeric sort key: running=2, loaded-but-stopped=1, unloaded=0
    var statusRank: Int { pid != nil ? 2 : isLoaded ? 1 : 0 }

    // ── Computed helpers ──────────────────────────────────────────────────────

    var command: String {
        programArguments.isEmpty ? program : programArguments.joined(separator: " ")
    }

    var triggerHuman: String {
        var parts: [String] = []
        if runAtLoad                { parts.append("At load") }
        if let n = startInterval    { parts.append("Every \(n)s") }
        if !runAtLoad, startInterval == nil { parts.append("On demand") }
        if keepAlive                { parts.append("Keep alive") }
        return parts.joined(separator: ", ")
    }

    var sourceLabel: String {
        let parent = plistURL.deletingLastPathComponent().path
        let home   = FileManager.default.homeDirectoryForCurrentUser.path
        if parent.hasPrefix(home) { return "~/LaunchAgents" }
        return isDaemon ? "LaunchDaemons" : "LaunchAgents"
    }

    // ── Plist decoding ────────────────────────────────────────────────────────

    /// Decodable mirror of the plist keys we care about.
    /// `KeepAlive` can be a Bool *or* a dict of conditions — handle both.
    private struct PlistContent: Decodable {
        var Label:            String?
        var Program:          String?
        var ProgramArguments: [String]?
        var RunAtLoad:        Bool?
        var StartInterval:    Int?
        var keepAliveBool:    Bool?
        var StandardOutPath:  String?
        var StandardErrorPath: String?

        private enum CodingKeys: String, CodingKey {
            case Label, Program, ProgramArguments, RunAtLoad, StartInterval, KeepAlive
            case StandardOutPath, StandardErrorPath
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            Label            = try c.decodeIfPresent(String.self,   forKey: .Label)
            Program          = try c.decodeIfPresent(String.self,   forKey: .Program)
            ProgramArguments = try c.decodeIfPresent([String].self, forKey: .ProgramArguments)
            RunAtLoad        = try c.decodeIfPresent(Bool.self,     forKey: .RunAtLoad)
            StartInterval    = try c.decodeIfPresent(Int.self,      forKey: .StartInterval)
            // KeepAlive: try Bool first, then treat any dict as "true"
            if let b = try? c.decodeIfPresent(Bool.self, forKey: .KeepAlive) {
                keepAliveBool = b
            } else if (try? c.decodeIfPresent([String: Bool].self, forKey: .KeepAlive)) != nil {
                keepAliveBool = true
            }
        }
    }

    init(plistURL: URL, isDaemon: Bool) {
        self.plistURL  = plistURL
        self.isDaemon  = isDaemon
        self.label     = plistURL.deletingPathExtension().lastPathComponent
        self.program   = ""
        self.programArguments = []
        self.runAtLoad = false
        self.keepAlive = false

        guard
            let data    = try? Data(contentsOf: plistURL),
            let content = try? PropertyListDecoder().decode(PlistContent.self, from: data)
        else { return }

        self.label            = content.Label ?? self.label
        self.program          = content.Program ?? ""
        self.programArguments = content.ProgramArguments ?? []
        self.runAtLoad        = content.RunAtLoad ?? false
        self.startInterval    = content.StartInterval
        self.keepAlive        = content.keepAliveBool ?? false
        self.standardOutPath  = content.StandardOutPath
        self.standardErrPath  = content.StandardErrorPath

        // Fall back to first ProgramArguments entry if Program is absent
        if self.program.isEmpty, let first = programArguments.first {
            self.program = first
        }
    }
}
