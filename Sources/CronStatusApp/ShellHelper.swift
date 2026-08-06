import Foundation

/// Run a shell command via `/bin/bash -c` and return (exitCode, combinedOutput).
func shell(_ command: String) async -> (exitCode: Int32, output: String) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments     = ["-c", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            do    { try process.run() }
            catch { continuation.resume(returning: (-1, error.localizedDescription)); return }
            let data   = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: (process.terminationStatus, output))
        }
    }
}

/// Run an executable directly without shell interpolation.
func runProcess(_ executable: String, arguments: [String] = []) async -> (exitCode: Int32, output: String) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do    { try process.run() }
            catch { continuation.resume(returning: (-1, error.localizedDescription)); return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: (process.terminationStatus, output))
        }
    }
}

/// Run a shell command with data written to its stdin.
func shellWithInput(_ command: String, input: String) async -> (exitCode: Int32, output: String) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments     = ["-c", command]
            let inPipe  = Pipe()
            let outPipe = Pipe()
            process.standardInput  = inPipe
            process.standardOutput = outPipe
            process.standardError  = outPipe
            do    { try process.run() }
            catch { continuation.resume(returning: (-1, error.localizedDescription)); return }
            if let data = input.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            inPipe.fileHandleForWriting.closeFile()
            let data   = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: (process.terminationStatus, output))
        }
    }
}
