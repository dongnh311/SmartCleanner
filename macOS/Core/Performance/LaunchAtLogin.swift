import Foundation
import ServiceManagement

/// Registers MacCleaner itself as a macOS login item via the modern
/// ServiceManagement API (macOS 13+). No helper bundle and no hand-written
/// launchd plist — `SMAppService.mainApp` toggles the app's own
/// "Open at Login" entry, the same one that appears under
/// System Settings › General › Login Items.
@MainActor
enum LaunchAtLogin {

    /// True when the OS currently launches MacCleaner at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `.requiresApproval` means the user must flip the switch on in
    /// System Settings › General › Login Items (common for ad-hoc / un-
    /// notarised builds). The Settings UI surfaces this as a hint.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers / unregisters the main app. Returns false if the OS
    /// refused the change.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
            return true
        } catch {
            Log.app.error("LaunchAtLogin.setEnabled(\(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
