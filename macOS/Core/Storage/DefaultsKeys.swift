import Foundation

/// Central registry of every UserDefaults key the app reads or writes.
/// Anchoring them here makes it possible to audit (or migrate) the full
/// set in one place — important when a settings format changes and we
/// have to ship a one-shot migrator. Each value is wrapped in a versioned
/// suffix (`.v1`) where the data is encoded, so a future schema bump can
/// keep both keys alive during the migration window.
enum DefaultsKeys {
    /// Master alert toggle. v1 = bool.
    static let alertsEnabled = "Alerts.enabled.v1"
    /// Prefix — append the rule ID for per-rule on/off bool.
    static let alertsRulePrefix = "Alerts.rule."

    /// Saved timezone list for the world-clock view. v1 = JSON-encoded array.
    static let clockTimezones = "ClockService.timezones.v1"
    /// 24-hour vs 12-hour toggle for the clock.
    static let clockUse24Hour = "ClockService.use24Hour"

    /// Menu-bar metric pill enablement set. v1 = JSON-encoded array.
    static let menuBarEnabledMetrics = "MenuBarConfig.enabledMetrics.v1"

    /// Menu-bar display mode (full / info / icon / hidden). Raw enum string.
    static let menuBarDisplayMode = "MenuBarConfig.displayMode.v1"

    /// Menu-bar separator between metric pills (pipe / space). Raw enum string.
    static let menuBarSeparator = "MenuBarConfig.separator.v1"

    /// Menu-bar metric label style (short "C" / full "CPU"). Raw enum string.
    static let menuBarLabelStyle = "MenuBarConfig.labelStyle.v1"

    /// Pinned MyTools entries — JSON-encoded array.
    static let myToolsPinned = "myTools.pinned"

    /// One-shot onboarding wizard completion flag.
    static let onboardingCompleted = "onboarding.completed"

    /// Opt-in public-IP lookup. Off by default for privacy.
    static let publicIPEnabled = "PublicIPService.enabled"

    /// Recent Activity inspector pane visibility. Closed by default —
    /// users open it on demand via the toolbar button.
    static let recentActivityVisible = "RecentActivity.visible.v1"

    /// Paint right-side panel (Layers + History) visibility.
    static let paintPanelVisible = "Paint.panelVisible.v1"

    /// Realtime protection master switch. Off by default — background
    /// file-watching + auto-quarantine is a deliberate opt-in. Bool.
    static let realtimeProtectionEnabled = "RealtimeProtection.enabled.v1"
    /// User-contributed malware SHA-256 blocklist merged on top of the
    /// bundled list. v1 = JSON-encoded array of lowercase hex strings.
    static let realtimeProtectionUserHashes = "RealtimeProtection.userHashes.v1"

    /// Scroll Denoiser master enable. Bool.
    static let scrollDenoiserEnabled = "ScrollDenoiser.enabled.v1"
    /// Scroll Denoiser tunable settings — JSON-encoded `DirectionLockSettings`.
    static let scrollDenoiserSettings = "ScrollDenoiser.settings.v1"

    /// User-added folders / files that the cleanup engine must never
    /// touch. v1 = JSON-encoded array of absolute paths.
    static let whitelistCustomPaths = "Whitelist.customPaths.v1"

    /// User-added apps whose standard Library/* paths are always
    /// protected regardless of whether the app is running. v1 = JSON-
    /// encoded array of `{ bundleID, name }`.
    static let whitelistCustomApps = "Whitelist.customApps.v1"
}
