import Foundation

struct MaintenanceRunResult: Sendable {
    let success: Bool
    /// Trimmed stdout on success, or the failure / cancellation message.
    let output: String
}

/// Executes a `MaintenanceCommand` from inside the app.
///
/// Admin commands are elevated through the native macOS authorization prompt
/// (`do shell script … with administrator privileges`), which needs **no**
/// privileged helper, SMJobBless, or Developer ID — so it works on this
/// ad-hoc-signed build. Non-admin commands run directly via `zsh`. Nothing
/// leaves the machine; the password the user types goes straight to macOS's
/// Security framework, never to us.
enum MaintenanceRunner {

    static func run(_ cmd: MaintenanceCommand) async -> MaintenanceRunResult {
        if cmd.requiresAdmin {
            // `with administrator privileges` already runs as root, so any
            // inline `sudo` would try to prompt on a tty we don't have — strip
            // it. Then escape for the AppleScript string literal.
            let stripped = cmd.command.replacingOccurrences(of: "sudo ", with: "")
            let escaped = stripped
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let source = "do shell script \"\(escaped)\" with administrator privileges"
            return await runAppleScript(source)
        } else {
            return await runProcess("/bin/zsh", ["-c", cmd.command])
        }
    }

    /// Runs an AppleScript off the main thread (fresh instance, so the
    /// thread-safety caveat doesn't apply) and presents the auth prompt
    /// branded as MacCleaner.
    private static func runAppleScript(_ source: String) async -> MaintenanceRunResult {
        await withCheckedContinuation { (cont: CheckedContinuation<MaintenanceRunResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let msg = (errorInfo["NSAppleScriptErrorMessage"] as? String)
                        ?? "Authorization was cancelled or the command failed."
                    cont.resume(returning: MaintenanceRunResult(success: false, output: msg))
                } else {
                    let text = (result?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: MaintenanceRunResult(success: true, output: text))
                }
            }
        }
    }

    private static func runProcess(_ launchPath: String, _ args: [String]) async -> MaintenanceRunResult {
        await withCheckedContinuation { (cont: CheckedContinuation<MaintenanceRunResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: MaintenanceRunResult(success: false, output: error.localizedDescription))
                    return
                }
                // Maintenance commands emit little output, so reading fully
                // before waitUntilExit won't deadlock on the 64 KB pipe buffer.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let out = (String(data: outData, encoding: .utf8) ?? "")
                let err = (String(data: errData, encoding: .utf8) ?? "")
                let ok = process.terminationStatus == 0
                let text = (ok ? out : (err.isEmpty ? out : err))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: MaintenanceRunResult(success: ok, output: text))
            }
        }
    }
}
