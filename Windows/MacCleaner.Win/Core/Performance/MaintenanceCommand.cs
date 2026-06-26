namespace MacCleaner.Win.Core.Performance;

public enum MaintenanceCategory
{
    SystemFiles,
    Disk,
    Network,
    Policy,
    Shell,
}

/// <summary>
/// A single Windows upkeep command. The Windows analogue of the macOS
/// <c>MaintenanceCommand</c>: instead of <c>periodic</c>/<c>dscacheutil</c>
/// these are <c>sfc</c>/<c>DISM</c>/<c>chkdsk</c>/<c>ipconfig</c>… Admin items
/// elevate via UAC; the rest run in-process.
/// </summary>
public sealed record MaintenanceCommand(
    string Id,
    string Title,
    string Summary,
    string FileName,
    string Arguments,
    bool RequiresAdmin,
    MaintenanceCategory Category)
{
    public string DisplayCommand =>
        string.IsNullOrEmpty(Arguments) ? FileName : $"{FileName} {Arguments}";

    public static IReadOnlyList<MaintenanceCommand> All { get; } = new[]
    {
        new MaintenanceCommand("flush_dns", "Flush DNS cache",
            "Clears the resolver cache when domain resolution acts up.",
            "ipconfig", "/flushdns", false, MaintenanceCategory.Network),

        new MaintenanceCommand("winsock_reset", "Reset Winsock catalog",
            "Resets the networking stack to defaults. Restart afterwards.",
            "netsh", "winsock reset", true, MaintenanceCategory.Network),

        new MaintenanceCommand("sfc_scan", "Run System File Checker",
            "Scans and repairs protected Windows system files (sfc /scannow).",
            "sfc", "/scannow", true, MaintenanceCategory.SystemFiles),

        new MaintenanceCommand("dism_restore", "Repair the component store",
            "DISM /Online /Cleanup-Image /RestoreHealth — fixes corruption SFC alone can't.",
            "Dism", "/Online /Cleanup-Image /RestoreHealth", true, MaintenanceCategory.SystemFiles),

        new MaintenanceCommand("chkdsk_scan", "Scan the system drive",
            "Online scan of C: for file-system errors (chkdsk C: /scan).",
            "chkdsk", "C: /scan", true, MaintenanceCategory.Disk),

        new MaintenanceCommand("gpupdate", "Refresh Group Policy",
            "Re-applies machine and user policy (gpupdate /force).",
            "gpupdate", "/force", false, MaintenanceCategory.Policy),

        new MaintenanceCommand("restart_explorer", "Restart Explorer",
            "Re-launches the Windows shell — useful after settings changes.",
            "cmd", "/c taskkill /f /im explorer.exe & start explorer.exe", false, MaintenanceCategory.Shell),
    };
}
