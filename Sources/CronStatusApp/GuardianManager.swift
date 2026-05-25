import Foundation
import AppKit

@MainActor
final class GuardianManager: ObservableObject {
    @Published var guardedLabels: Set<String> = []
    @Published var lastErrorCounts: [String: Int] = [:]
    @Published var lastPopupTimes: [String: Date] = [:]
    
    private let guardedLabelsKey = "CronStatusApp.guardedLabels"
    private let popupCooldown: TimeInterval = 300 // 5 minutes
    private var isChecking = false

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: guardedLabelsKey) {
            guardedLabels = Set(saved)
        }
    }

    func toggleGuarding(for label: String, agents: [LaunchAgentEntry]) {
        if guardedLabels.contains(label) {
            guardedLabels.remove(label)
            lastErrorCounts.removeValue(forKey: label)
            lastPopupTimes.removeValue(forKey: label)
        } else {
            guardedLabels.insert(label)
            if let agent = agents.first(where: { $0.label == label }) {
                if let logPath = getRelevantLogPath(for: agent) {
                    lastErrorCounts[label] = getErrorCount(at: logPath)
                }
            }
        }
        UserDefaults.standard.set(Array(guardedLabels), forKey: guardedLabelsKey)
    }

    func isGuarded(_ label: String) -> Bool {
        guardedLabels.contains(label)
    }

    private func getRelevantLogPath(for agent: LaunchAgentEntry) -> String? {
        // Prefer stderr, then stdout
        if let err = agent.standardErrPath { return (err as NSString).expandingTildeInPath }
        if let out = agent.standardOutPath { return (out as NSString).expandingTildeInPath }
        return nil
    }

    func checkAgents(agents: [LaunchAgentEntry], agentManager: LaunchAgentManager) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        
        for agent in agents {
            guard guardedLabels.contains(agent.label) else { continue }

            // 1. Check if running (only for keepAlive agents)
            if agent.keepAlive && agent.pid == nil && agent.isLoaded {
                showPopup(for: agent, message: "Agent '\(agent.label)' is NOT running.", agentManager: agentManager)
            }

            // 2. Check logs for errors
            if let logPath = getRelevantLogPath(for: agent) {
                let currentErrorCount = getErrorCount(at: logPath)
                
                if let lastCount = lastErrorCounts[agent.label] {
                    if currentErrorCount > lastCount {
                        let newErrors = currentErrorCount - lastCount
                        showPopup(for: agent, message: "Agent '\(agent.label)' detected \(newErrors) new errors in log.", agentManager: agentManager)
                    }
                }
                lastErrorCounts[agent.label] = currentErrorCount
            }
        }
    }

    private func getErrorCount(at path: String) -> Int {
        // For large files, we should avoid reading the whole thing. 
        // But for this status app, a simple count is okay if the file is manageable.
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else { return 0 }
        
        let pattern = "ERROR:"
        let parts = content.components(separatedBy: pattern)
        return parts.count - 1
    }

    private func showPopup(for agent: LaunchAgentEntry, message: String, agentManager: LaunchAgentManager) {
        let now = Date()
        if let lastPopup = lastPopupTimes[agent.label], now.timeIntervalSince(lastPopup) < popupCooldown {
            return
        }
        
        lastPopupTimes[agent.label] = now
        
        let alert = NSAlert()
        alert.messageText = "Agent Guardian"
        alert.informativeText = message
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Inspect")
        alert.addButton(withTitle: "Dismiss")
        alert.alertStyle = .warning
        
        // Modal alert blocks the thread but it's on the main actor so it's "safe" for simple popups
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn { // Restart
            Task {
                _ = await agentManager.restartAgent(agent)
                await agentManager.refresh()
            }
        } else if response == .alertSecondButtonReturn { // Inspect
            openLog(for: agent)
        }
    }

    private func openLog(for agent: LaunchAgentEntry) {
        // Try to open the most relevant log file
        let paths = [
            agent.standardErrPath,
            agent.standardOutPath,
            // Fallback: check if there's a daemon.log in the same directory
            agent.standardOutPath.map { (($0 as NSString).deletingLastPathComponent as NSString).appendingPathComponent("daemon.log") }
        ].compactMap { $0 }.map { ($0 as NSString).expandingTildeInPath }

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                // Use 'open' command via shell to ensure it opens in the default app reliably
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [path]
                try? task.run()
                return
            }
        }
        
        // If no log file exists, open the directory if possible
        if let firstPath = paths.first {
            let dir = (firstPath as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: dir) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
            }
        }
    }
}
