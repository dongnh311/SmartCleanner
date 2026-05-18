namespace MacCleaner.Win.Core.Cleanup;

public sealed record CleanupTarget(
    string Id,
    string Label,
    string Description,
    string AbsolutePath,
    bool RequiresAdmin);

public static class CleanupTargets
{
    /// <summary>
    /// Standard Quick Clean targets — mirrors WINDOWS_PORT_PLAN.md
    /// section 2.1 #13. Paths are resolved against environment variables
    /// at call-site, so this list is safe to enumerate at startup.
    /// </summary>
    public static IReadOnlyList<CleanupTarget> QuickClean()
    {
        string temp        = Environment.GetEnvironmentVariable("TEMP") ?? "";
        string localApp    = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string winTemp     = @"C:\Windows\Temp";
        string prefetch    = @"C:\Windows\Prefetch";
        string sdDownload  = @"C:\Windows\SoftwareDistribution\Download";
        string thumbCache  = Path.Combine(localApp, @"Microsoft\Windows\Explorer");
        string chromeCache = Path.Combine(localApp, @"Google\Chrome\User Data\Default\Cache");
        string edgeCache   = Path.Combine(localApp, @"Microsoft\Edge\User Data\Default\Cache");
        string crashDumps  = Path.Combine(localApp, @"CrashDumps");
        string dxCache     = Path.Combine(localApp, @"D3DSCache");

        return new[]
        {
            new CleanupTarget("user-temp",       "User temp files",   "Files in your %TEMP% folder older than 1 hour.", temp,        false),
            new CleanupTarget("windows-temp",    "Windows temp",      "C:\\Windows\\Temp — shared scratch space.",       winTemp,     true),
            new CleanupTarget("prefetch",        "Prefetch",          "Windows launch-time prediction cache; regenerated.", prefetch, true),
            new CleanupTarget("windows-update",  "Windows Update DL", "Downloaded update packages awaiting cleanup.",     sdDownload,  true),
            new CleanupTarget("thumb-cache",     "Thumbnail cache",   "Explorer thumbnail database (thumbcache_*.db).",   thumbCache,  false),
            new CleanupTarget("chrome-cache",    "Chrome cache",      "Default profile HTTP cache.",                      chromeCache, false),
            new CleanupTarget("edge-cache",      "Edge cache",        "Default profile HTTP cache.",                      edgeCache,   false),
            new CleanupTarget("crash-dumps",     "Crash dumps",       "Per-user dump files written by WER.",              crashDumps,  false),
            new CleanupTarget("directx-cache",   "DirectX shader cache","Shader-compiler scratch.",                       dxCache,     false),
        };
    }
}
