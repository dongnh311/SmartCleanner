using System.Diagnostics;

namespace MacCleaner.Win.Core.Performance;

public sealed record DiskIoSample(
    string Instance,
    double ReadBytesPerSec,
    double WriteBytesPerSec,
    double QueueLength,
    DateTime Timestamp);

public interface IDiskMonitorService
{
    /// <summary>One read+write+queue sample per physical disk
    /// (instance "0 C:", "1 D:" etc.). Like CPU, the first call against
    /// each counter returns 0 since NextValue needs two ticks to diff.</summary>
    IReadOnlyList<DiskIoSample> Sample();
}

/// <summary>
/// Reads "PhysicalDisk" performance counters — same data Task Manager
/// surfaces in its Disk panel. Counters are cached per-instance to avoid
/// the ~10ms PdhExpandWildCardPath overhead on every tick.
/// </summary>
public sealed class DiskMonitorService : IDiskMonitorService, IDisposable
{
    private readonly object _lock = new();
    private readonly Dictionary<string, (PerformanceCounter R, PerformanceCounter W, PerformanceCounter Q)> _cache = new();
    private DateTime _lastInstanceScanAt = DateTime.MinValue;
    private string[] _instances = Array.Empty<string>();

    public IReadOnlyList<DiskIoSample> Sample()
    {
        EnsureInstanceList();
        var rows = new List<DiskIoSample>(_instances.Length);
        var now = DateTime.UtcNow;

        foreach (var inst in _instances)
        {
            if (string.Equals(inst, "_Total", StringComparison.OrdinalIgnoreCase)) continue;
            var (r, w, q) = GetOrCreate(inst);
            try
            {
                rows.Add(new DiskIoSample(inst, r.NextValue(), w.NextValue(), q.NextValue(), now));
            }
            catch (InvalidOperationException)
            {
                // Instance disappeared mid-scan (USB unplug). Drop the cached
                // counters; the next EnsureInstanceList() will skip it.
                EvictCachedCounters(inst);
            }
        }
        return rows;
    }

    private void EnsureInstanceList()
    {
        // PhysicalDisk instance set changes when drives are mounted/unmounted.
        // Rescan once a minute — fast enough to surface a new USB stick,
        // cheap enough not to pay the PDH cost on every UI tick.
        if (DateTime.UtcNow - _lastInstanceScanAt < TimeSpan.FromMinutes(1)) return;

        lock (_lock)
        {
            try
            {
                var cat = new PerformanceCounterCategory("PhysicalDisk");
                _instances = cat.GetInstanceNames();
            }
            catch
            {
                _instances = Array.Empty<string>();
            }
            _lastInstanceScanAt = DateTime.UtcNow;
        }
    }

    private (PerformanceCounter R, PerformanceCounter W, PerformanceCounter Q) GetOrCreate(string inst)
    {
        lock (_lock)
        {
            if (_cache.TryGetValue(inst, out var t)) return t;
            var trio = (
                R: new PerformanceCounter("PhysicalDisk", "Disk Read Bytes/sec",  inst, readOnly: true),
                W: new PerformanceCounter("PhysicalDisk", "Disk Write Bytes/sec", inst, readOnly: true),
                Q: new PerformanceCounter("PhysicalDisk", "Current Disk Queue Length", inst, readOnly: true));
            _cache[inst] = trio;
            return trio;
        }
    }

    private void EvictCachedCounters(string inst)
    {
        lock (_lock)
        {
            if (!_cache.TryGetValue(inst, out var t)) return;
            t.R.Dispose(); t.W.Dispose(); t.Q.Dispose();
            _cache.Remove(inst);
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            foreach (var (_, t) in _cache)
            {
                t.R.Dispose(); t.W.Dispose(); t.Q.Dispose();
            }
            _cache.Clear();
        }
    }
}
