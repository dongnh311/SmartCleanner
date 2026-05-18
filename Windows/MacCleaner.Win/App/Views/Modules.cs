using Windows.UI;

namespace MacCleaner.Win.App.Views;

/// <summary>
/// Per-module metadata the navigation shell hands to <see cref="StubPage"/>.
/// Real feature pages replace these stubs phase by phase per
/// <c>WINDOWS_PORT_PLAN.md</c> section 4.
/// </summary>
public sealed record ModuleDescriptor(
    string Tag,
    string Title,
    string Subtitle,
    string Glyph,
    Color Accent);

public static class Modules
{
    private static Color Rgb(byte r, byte g, byte b) => Color.FromArgb(255, r, g, b);

    private static readonly Dictionary<string, ModuleDescriptor> _map = new()
    {
        // Performance
        ["dashboard"]   = new("dashboard",   "Dashboard",        "CPU, RAM, Disk, GPU at a glance",            "", Rgb(0x19, 0x9E, 0xF5)),
        ["processes"]   = new("processes",   "Process Monitor",  "Live process list with CPU, memory, owner",  "", Rgb(0xFF, 0x9F, 0x0A)),
        ["trends"]      = new("trends",      "Usage Trends",     "90-day CPU, memory and disk history",        "", Rgb(0x6B, 0x52, 0xF5)),
        ["memory"]      = new("memory",      "Memory",           "RAM usage and per-process working sets",     "", Rgb(0x0A, 0xB6, 0x7A)),
        ["battery"]     = new("battery",     "Battery",          "Health, cycles, charge state",               "", Rgb(0x30, 0xD1, 0x58)),
        ["sensors"]     = new("sensors",     "Sensors",          "CPU, GPU and chassis temperatures",          "", Rgb(0xFF, 0x45, 0x3A)),
        ["network"]     = new("network",     "Network",          "Interfaces, throughput, per-app bandwidth",  "", Rgb(0x19, 0x9E, 0xF5)),
        ["bluetooth"]   = new("bluetooth",   "Bluetooth",        "Paired devices, battery, RSSI",              "", Rgb(0x6B, 0x52, 0xF5)),
        ["diskmon"]     = new("diskmon",     "Disk Monitor",     "Per-volume I/O, queue depth, SMART",         "", Rgb(0xFF, 0x9F, 0x0A)),
        ["loginitems"]  = new("loginitems",  "Login Items",      "Programs that start with Windows",           "", Rgb(0x0A, 0xB6, 0x7A)),

        // Applications
        ["uninstaller"] = new("uninstaller", "Uninstaller",      "Installed programs (registry + MSI + MSIX)", "", Rgb(0xFF, 0x45, 0x3A)),
        ["updater"]     = new("updater",     "Updater",          "Updates via winget",                         "", Rgb(0x19, 0x9E, 0xF5)),

        // Cleanup
        ["quickclean"]  = new("quickclean",  "Quick Clean",      "Caches, temp, browser data, dump files",     "", Rgb(0x6B, 0x52, 0xF5)),
        ["recyclebin"]  = new("recyclebin",  "Recycle Bin",      "Empty per drive",                            "", Rgb(0xFF, 0x9F, 0x0A)),

        // Files
        ["spacelens"]   = new("spacelens",   "Space Lens",       "Treemap of disk usage",                      "", Rgb(0x6B, 0x52, 0xF5)),
        ["largeold"]    = new("largeold",    "Large & Old",      "Find big files untouched for months",        "", Rgb(0xFF, 0x9F, 0x0A)),
        ["duplicates"]  = new("duplicates",  "Duplicates",       "SHA-256 streaming hash match",               "", Rgb(0x19, 0x9E, 0xF5)),
        ["similar"]     = new("similar",     "Similar Photos",   "Perceptual hash clustering",                 "", Rgb(0x0A, 0xB6, 0x7A)),

        // Tools
        ["shredder"]    = new("shredder",    "Shredder",         "DoD-style overwrite then delete",            "", Rgb(0xFF, 0x45, 0x3A)),
        ["quarantine"]  = new("quarantine",  "Quarantine",       "Restore or purge held-back files",           "", Rgb(0x30, 0xD1, 0x58)),
        ["mytools"]     = new("mytools",     "My Tools",         "Pinned shortcuts and folders",               "", Rgb(0x6B, 0x52, 0xF5)),
        ["clock"]       = new("clock",       "Clock",            "World clock and time zones",                 "", Rgb(0x19, 0x9E, 0xF5)),
        ["paint"]       = new("paint",       "Paint",            "Quick canvas with brushes and layers",       "", Rgb(0xFF, 0x9F, 0x0A)),
        ["scroll"]      = new("scroll",      "Scroll Denoiser",  "Direction-lock filter for cheap wheels",     "", Rgb(0x0A, 0xB6, 0x7A)),
    };

    public static ModuleDescriptor Get(string tag) =>
        _map.TryGetValue(tag, out var d)
            ? d
            : new ModuleDescriptor(tag, tag, "", "", Rgb(0x8E, 0x8E, 0x93));

    public static IReadOnlyCollection<ModuleDescriptor> All => _map.Values;
}
