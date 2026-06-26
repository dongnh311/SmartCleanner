using System.Security.Cryptography;
using MacCleaner.Win.Core.Tools;
using Microsoft.Win32;

namespace MacCleaner.Win.Core.Protection;

public enum RealtimeAction { Detected, Quarantined, Alerted }

public sealed record RealtimeEvent(
    string Title,
    string Path,
    ThreatSeverity Severity,
    RealtimeAction Action,
    DateTime Timestamp);

public interface IRealtimeProtectionService
{
    bool IsEnabled { get; }
    bool IsRunning { get; }
    int WatchedPathCount { get; }
    int SignatureCount { get; }
    IReadOnlyList<RealtimeEvent> RecentEvents { get; }

    /// <summary>Raised (possibly off the UI thread) whenever state or the
    /// detection list changes — subscribers must marshal to their UI.</summary>
    event Action? Changed;

    void SetEnabled(bool enabled);
    void Start();
    void Stop();
    void ClearEvents();
}

/// <summary>
/// Userspace, reactive realtime protection — the Windows analogue of the
/// macOS <c>RealtimeProtectionService</c>. <see cref="FileSystemWatcher"/>s
/// (the FSEvents equivalent) watch the drop zones + Startup; new files are
/// SHA-256'd against the blocklist and auto-quarantined on a match, and
/// content-verified ransomware canaries alert on tampering.
/// </summary>
public sealed class RealtimeProtectionService : IRealtimeProtectionService, IDisposable
{
    private const string RegPath = @"Software\MacCleaner";
    private const string EnabledValue = "RealtimeEnabled";
    private const string CanaryName = ".maccleaner-canary.txt";
    private const string CanaryContent =
        "MacCleaner ransomware canary — do not edit, move or delete. If this file changes an alert fires.";
    private const long MaxHashBytes = 64L * 1024 * 1024;

    private readonly IMalwareHashStore _hashes;
    private readonly IQuarantineService _quarantine;

    private readonly List<FileSystemWatcher> _watchers = new();
    private readonly HashSet<string> _canaries = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<RealtimeEvent> _events = new();
    private readonly object _gate = new();

    public RealtimeProtectionService(IMalwareHashStore hashes, IQuarantineService quarantine)
    {
        _hashes = hashes;
        _quarantine = quarantine;
    }

    public event Action? Changed;

    public bool IsEnabled => ReadEnabled();
    public bool IsRunning { get; private set; }
    public int WatchedPathCount { get { lock (_gate) { return _watchers.Count; } } }
    public int SignatureCount => _hashes.Count;

    public IReadOnlyList<RealtimeEvent> RecentEvents
    {
        get { lock (_gate) { return _events.ToList(); } }
    }

    public void SetEnabled(bool enabled)
    {
        WriteEnabled(enabled);
        if (enabled) Start();
        else Stop();
    }

    public void Start()
    {
        if (IsRunning) return;

        foreach (var dir in WatchedDirectories())
        {
            try
            {
                PlantCanary(dir);   // plant before the watcher goes live (no self-trigger)
                var watcher = new FileSystemWatcher(dir)
                {
                    IncludeSubdirectories = false,
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                };
                watcher.Created += OnChanged;
                watcher.Changed += OnChanged;
                watcher.Renamed += OnRenamed;
                watcher.Deleted += OnChanged;
                watcher.EnableRaisingEvents = true;
                lock (_gate) { _watchers.Add(watcher); }
            }
            catch
            {
                // Inaccessible directory — skip it, keep protection on for the rest.
            }
        }

        IsRunning = true;
        Changed?.Invoke();
    }

    public void Stop()
    {
        lock (_gate)
        {
            foreach (var w in _watchers)
            {
                try { w.EnableRaisingEvents = false; w.Dispose(); } catch { /* best effort */ }
            }
            _watchers.Clear();
        }
        IsRunning = false;
        Changed?.Invoke();
    }

    public void ClearEvents()
    {
        lock (_gate) { _events.Clear(); }
        Changed?.Invoke();
    }

    public void Dispose() => Stop();

    // MARK: - Canary (content-verified so planting / benign touches don't alarm)

    /// <summary>True only on a real change: the file is gone or its content no
    /// longer matches what we wrote. Pure + static so it's unit-testable.</summary>
    public static bool IsCanaryTampered(string path, string expectedContent)
    {
        try
        {
            if (!File.Exists(path)) return true;
            return File.ReadAllText(path) != expectedContent;
        }
        catch
        {
            return true;
        }
    }

    private void PlantCanary(string dir)
    {
        try
        {
            var path = Path.Combine(dir, CanaryName);
            File.WriteAllText(path, CanaryContent);
            try { File.SetAttributes(path, FileAttributes.Hidden); } catch { /* non-fatal */ }
            _canaries.Add(path);
        }
        catch
        {
            // Couldn't plant here — the watcher still catches blocklist hits.
        }
    }

    // MARK: - Watcher callbacks

    private void OnChanged(object sender, FileSystemEventArgs e) => Process(e.FullPath);
    private void OnRenamed(object sender, RenamedEventArgs e) => Process(e.FullPath);

    private async void Process(string path)
    {
        try
        {
            if (_canaries.Contains(path))
            {
                if (IsCanaryTampered(path, CanaryContent))
                {
                    AddEvent(new RealtimeEvent("Ransomware canary tampered", path,
                        ThreatSeverity.Danger, RealtimeAction.Alerted, DateTime.Now));
                }
                return;
            }

            if (!File.Exists(path)) return;

            long length;
            try { length = new FileInfo(path).Length; } catch { return; }
            if (length == 0 || length > MaxHashBytes) return;

            var hex = HashFile(path);
            if (hex is null || !_hashes.Contains(hex)) return;

            try
            {
                await _quarantine.QuarantineAsync(path);
                AddEvent(new RealtimeEvent(Path.GetFileName(path), path,
                    ThreatSeverity.Danger, RealtimeAction.Quarantined, DateTime.Now));
            }
            catch
            {
                AddEvent(new RealtimeEvent(Path.GetFileName(path), path,
                    ThreatSeverity.Danger, RealtimeAction.Detected, DateTime.Now));
            }
        }
        catch
        {
            // A watcher callback must never throw onto the threadpool.
        }
    }

    private void AddEvent(RealtimeEvent evt)
    {
        lock (_gate)
        {
            _events.Insert(0, evt);
            if (_events.Count > 50) _events.RemoveRange(50, _events.Count - 50);
        }
        Changed?.Invoke();
    }

    // MARK: - Helpers

    private static IEnumerable<string> WatchedDirectories()
    {
        var dirs = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            Environment.GetFolderPath(Environment.SpecialFolder.Startup),
        };
        return dirs.Where(d => !string.IsNullOrEmpty(d) && Directory.Exists(d)).Distinct();
    }

    private static string? HashFile(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            using var sha = SHA256.Create();
            return Convert.ToHexString(sha.ComputeHash(stream)).ToLowerInvariant();
        }
        catch
        {
            return null;
        }
    }

    private static bool ReadEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegPath);
            return (key?.GetValue(EnabledValue) as int?) == 1;
        }
        catch { return false; }
    }

    private static void WriteEnabled(bool value)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RegPath);
            key?.SetValue(EnabledValue, value ? 1 : 0, RegistryValueKind.DWord);
        }
        catch { /* best effort */ }
    }
}
