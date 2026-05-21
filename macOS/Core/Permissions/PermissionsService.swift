import Foundation
import AppKit
import ApplicationServices

actor PermissionsService {

    private(set) var statuses: [PermissionType: PermissionStatus] = [:]

    func refreshAll() async -> [PermissionType: PermissionStatus] {
        var result: [PermissionType: PermissionStatus] = [:]
        for type in PermissionType.allCases {
            result[type] = check(type)
        }
        statuses = result
        Log.permissions.info("statuses refreshed: \(result.mapValues { "\($0)" }, privacy: .public)")
        return result
    }

    func check(_ type: PermissionType) -> PermissionStatus {
        switch type {
        case .fullDiskAccess: return checkFullDiskAccess()
        case .accessibility:  return checkAccessibility()
        }
    }

    private func checkFullDiskAccess() -> PermissionStatus {
        let probes = ["Library/Safari", "Library/Mail", "Library/Messages"]
        for relative in probes {
            let path = (NSHomeDirectory() as NSString).appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return .granted
            } catch {
                let err = error as NSError
                if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
                    return .denied
                }
            }
        }
        return .unknown
    }

    private func checkAccessibility() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    @MainActor
    static func openSettings(for type: PermissionType) {
        NSWorkspace.shared.open(type.settingsURL)
    }

    /// Variant of `checkAccessibility` that also shows the system prompt the
    /// first time, so the app is added to Privacy → Accessibility. Without
    /// this prompt the app silently won't appear in the list and the user
    /// can't grant access. Apple's `kAXTrustedCheckOptionPrompt` is a
    /// non-Sendable CFString global; the literal "AXTrustedCheckOptionPrompt"
    /// is what it points to.
    @MainActor
    static func requestAccessibilityPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Silent trust check — same signal as `requestAccessibilityPrompt` but
    /// never shows the system dialog. Use this on background re-checks (e.g.
    /// post-wake rebuilds) where popping a permission alert would surprise
    /// the user.
    @MainActor
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
