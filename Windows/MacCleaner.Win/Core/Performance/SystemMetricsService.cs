using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MacCleaner.Win.Core.Performance;

public readonly record struct CpuSample(double UsagePercent, DateTime Timestamp);
public readonly record struct MemorySample(ulong TotalBytes, ulong AvailableBytes, DateTime Timestamp)
{
    public ulong UsedBytes => TotalBytes - AvailableBytes;
    public double UsedPercent => TotalBytes == 0 ? 0 : (double)UsedBytes / TotalBytes * 100.0;
}

public interface ISystemMetricsService
{
    CpuSample SampleCpu();
    MemorySample SampleMemory();
    IReadOnlyList<double> CpuHistory { get; }
}

/// <summary>
/// Port of macOS <c>SystemMetrics</c> actor. CPU% comes from a
/// <see cref="PerformanceCounter"/> against "Processor / % Processor Time / _Total";
/// the first read of that counter always returns 0 (NextValue needs two
/// samples to compute a delta), so callers should expect a 0 for the very
/// first <see cref="SampleCpu"/> invocation and a real value on subsequent
/// calls. RAM uses <c>GlobalMemoryStatusEx</c>.
/// </summary>
public sealed class SystemMetricsService : ISystemMetricsService, IDisposable
{
    private readonly PerformanceCounter _cpu;
    private readonly Lock _historyLock = new();
    private readonly List<double> _history = new(HistoryCapacity);
    private const int HistoryCapacity = 60;

    public SystemMetricsService()
    {
        _cpu = new PerformanceCounter("Processor", "% Processor Time", "_Total", readOnly: true);
    }

    public CpuSample SampleCpu()
    {
        double pct = _cpu.NextValue();
        pct = Math.Clamp(pct, 0, 100);

        lock (_historyLock)
        {
            _history.Add(pct);
            if (_history.Count > HistoryCapacity)
            {
                _history.RemoveRange(0, _history.Count - HistoryCapacity);
            }
        }
        return new CpuSample(pct, DateTime.UtcNow);
    }

    public MemorySample SampleMemory()
    {
        var status = new MemoryStatusEx { dwLength = (uint)Marshal.SizeOf<MemoryStatusEx>() };
        if (!GlobalMemoryStatusEx(ref status))
        {
            return new MemorySample(0, 0, DateTime.UtcNow);
        }
        return new MemorySample(status.ullTotalPhys, status.ullAvailPhys, DateTime.UtcNow);
    }

    public IReadOnlyList<double> CpuHistory
    {
        get
        {
            lock (_historyLock) return _history.ToArray();
        }
    }

    public void Dispose() => _cpu.Dispose();

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MemoryStatusEx
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);
}
