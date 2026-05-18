using System.Net.NetworkInformation;

namespace MacCleaner.Win.Core.Performance;

public sealed record NetworkInterfaceRow(
    string Name,
    string Description,
    NetworkInterfaceType Type,
    OperationalStatus Status,
    long BytesSent,
    long BytesReceived,
    long Speed);

public readonly record struct NetworkThroughput(
    ulong UpBytesPerSec,
    ulong DownBytesPerSec,
    DateTime Timestamp);

public interface INetworkService
{
    IReadOnlyList<NetworkInterfaceRow> List();
    /// <summary>Aggregate per-interface byte counters since the previous
    /// call, divided by elapsed seconds. First call always returns 0 —
    /// there's nothing to diff against yet.</summary>
    NetworkThroughput SampleThroughput();
}

public sealed class NetworkService : INetworkService
{
    private long _lastTotalSent;
    private long _lastTotalReceived;
    private DateTime _lastSampleAt;
    private readonly object _lock = new();

    public IReadOnlyList<NetworkInterfaceRow> List()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus != OperationalStatus.NotPresent)
            .Select(n =>
            {
                var stats = SafeStats(n);
                return new NetworkInterfaceRow(
                    Name: n.Name,
                    Description: n.Description,
                    Type: n.NetworkInterfaceType,
                    Status: n.OperationalStatus,
                    BytesSent: stats?.BytesSent ?? 0,
                    BytesReceived: stats?.BytesReceived ?? 0,
                    Speed: n.Speed);
            })
            .ToArray();
    }

    public NetworkThroughput SampleThroughput()
    {
        long totalSent = 0;
        long totalRecv = 0;
        foreach (var n in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (n.OperationalStatus != OperationalStatus.Up) continue;
            var s = SafeStats(n);
            if (s is null) continue;
            totalSent += s.BytesSent;
            totalRecv += s.BytesReceived;
        }

        lock (_lock)
        {
            var now = DateTime.UtcNow;
            if (_lastSampleAt == default)
            {
                _lastSampleAt = now;
                _lastTotalSent = totalSent;
                _lastTotalReceived = totalRecv;
                return new NetworkThroughput(0, 0, now);
            }

            double elapsed = (now - _lastSampleAt).TotalSeconds;
            if (elapsed <= 0) elapsed = 0.001;

            ulong upBps   = (ulong)Math.Max(0, (long)((totalSent - _lastTotalSent) / elapsed));
            ulong downBps = (ulong)Math.Max(0, (long)((totalRecv - _lastTotalReceived) / elapsed));

            _lastTotalSent = totalSent;
            _lastTotalReceived = totalRecv;
            _lastSampleAt = now;

            return new NetworkThroughput(upBps, downBps, now);
        }
    }

    private static IPv4InterfaceStatistics? SafeStats(NetworkInterface n)
    {
        try { return n.GetIPv4Statistics(); }
        catch { return null; }
    }
}
