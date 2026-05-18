using System.Runtime.InteropServices;

namespace MacCleaner.Win.Core.Performance;

public readonly record struct BatterySample(
    bool HasBattery,
    bool IsCharging,
    bool IsOnAC,
    int PercentRemaining,
    TimeSpan? TimeRemaining)
{
    public static BatterySample Unavailable => new(false, false, false, 0, null);
}

public interface IBatteryService
{
    BatterySample Sample();
}

public sealed class BatteryService : IBatteryService
{
    public BatterySample Sample()
    {
        if (!GetSystemPowerStatus(out var status))
        {
            return BatterySample.Unavailable;
        }

        // BatteryFlag == 128 → no system battery; treat as unavailable so
        // desktop PCs render an "n/a" state instead of "0%".
        bool noBattery = (status.BatteryFlag & 0x80) != 0 || status.BatteryLifePercent == 255;
        if (noBattery)
        {
            return BatterySample.Unavailable;
        }

        bool onAc = status.ACLineStatus == 1;
        bool charging = (status.BatteryFlag & 0x08) != 0;
        TimeSpan? remaining = status.BatteryLifeTime >= 0
            ? TimeSpan.FromSeconds(status.BatteryLifeTime)
            : null;

        return new BatterySample(
            HasBattery: true,
            IsCharging: charging,
            IsOnAC: onAc,
            PercentRemaining: status.BatteryLifePercent,
            TimeRemaining: remaining);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public int  BatteryLifeTime;
        public int  BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus lpSystemPowerStatus);
}
