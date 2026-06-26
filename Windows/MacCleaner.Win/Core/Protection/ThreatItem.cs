namespace MacCleaner.Win.Core.Protection;

public enum ThreatSeverity { Info, Warn, Danger }

public enum ThreatKind { RunKey, StartupItem, HashMatch, MarkOfTheWeb }

/// <summary>
/// One flagged item from a malware scan. Mirrors the macOS <c>ThreatItem</c>
/// but with Windows-native kinds (Run keys, Startup folder, Mark-of-the-Web)
/// instead of LaunchAgents / quarantine xattr.
/// </summary>
public sealed record ThreatItem(
    string Title,
    string Path,
    ThreatKind Kind,
    ThreatSeverity Severity,
    IReadOnlyList<string> Signals);
