using LibreHardwareMonitor.Hardware;

namespace MacCleaner.Win.Core.Performance;

public sealed record SensorReading(
    string HardwareName,
    HardwareType HardwareType,
    string SensorName,
    SensorType SensorType,
    float? Value);

public interface ISensorsService
{
    /// <summary>One pass over CPU + GPU + storage + motherboard sensors.
    /// Returns an empty list if LibreHardwareMonitor can't open any
    /// hardware (e.g. user is not admin and no kernel driver loaded).</summary>
    IReadOnlyList<SensorReading> ReadAll();
}

/// <summary>
/// LibreHardwareMonitor wrapper. The library spawns a kernel driver
/// (WinRing0) the first time a hardware tree is opened, so the user
/// must be admin OR the driver must already be loaded — when neither
/// holds we silently return empty results rather than throw, matching
/// the macOS Sensors module's "best-effort, hide if unavailable" UX.
/// </summary>
public sealed class SensorsService : ISensorsService, IDisposable
{
    private readonly Computer _computer;
    private readonly object _lock = new();
    private bool _opened;

    public SensorsService()
    {
        _computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMemoryEnabled = false,
            IsMotherboardEnabled = true,
            IsStorageEnabled = true,
            IsNetworkEnabled = false
        };
    }

    public IReadOnlyList<SensorReading> ReadAll()
    {
        lock (_lock)
        {
            if (!_opened)
            {
                try
                {
                    _computer.Open();
                    _opened = true;
                }
                catch
                {
                    return Array.Empty<SensorReading>();
                }
            }

            var rows = new List<SensorReading>();
            foreach (var hw in _computer.Hardware)
            {
                hw.Update();
                foreach (var sub in hw.SubHardware)
                {
                    sub.Update();
                    foreach (var sensor in sub.Sensors)
                    {
                        rows.Add(new SensorReading(hw.Name, hw.HardwareType, sensor.Name, sensor.SensorType, sensor.Value));
                    }
                }
                foreach (var sensor in hw.Sensors)
                {
                    rows.Add(new SensorReading(hw.Name, hw.HardwareType, sensor.Name, sensor.SensorType, sensor.Value));
                }
            }
            return rows;
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (_opened)
            {
                try { _computer.Close(); } catch { /* driver may have already unloaded */ }
                _opened = false;
            }
        }
    }
}
