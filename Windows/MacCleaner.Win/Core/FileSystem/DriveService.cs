using System.IO;

namespace MacCleaner.Win.Core.FileSystem;

public sealed record DriveRow(
    string Name,
    string? VolumeLabel,
    string Format,
    long TotalBytes,
    long FreeBytes,
    bool IsReady,
    DriveType Type)
{
    public long UsedBytes => TotalBytes - FreeBytes;
    public double UsedPercent => TotalBytes == 0 ? 0 : (double)UsedBytes / TotalBytes * 100.0;
}

public interface IDriveService
{
    /// <summary>Fixed + removable + network drives currently mounted.
    /// Mirrors the macOS Dashboard disk card which only shows mounted
    /// APFS volumes — analogous on Windows is "Ready" drives.</summary>
    IReadOnlyList<DriveRow> List();
}

public sealed class DriveService : IDriveService
{
    public IReadOnlyList<DriveRow> List()
    {
        var drives = DriveInfo.GetDrives();
        var rows = new List<DriveRow>(drives.Length);
        foreach (var d in drives)
        {
            bool ready = SafeReady(d);
            rows.Add(new DriveRow(
                Name: d.Name,
                VolumeLabel: ready ? SafeLabel(d) : null,
                Format: ready ? SafeFormat(d) : "",
                TotalBytes: ready ? SafeTotal(d) : 0,
                FreeBytes: ready ? SafeFree(d) : 0,
                IsReady: ready,
                Type: d.DriveType));
        }
        return rows;
    }

    private static bool SafeReady(DriveInfo d) { try { return d.IsReady; } catch { return false; } }
    private static string? SafeLabel(DriveInfo d) { try { return d.VolumeLabel; } catch { return null; } }
    private static string SafeFormat(DriveInfo d) { try { return d.DriveFormat; } catch { return ""; } }
    private static long SafeTotal(DriveInfo d) { try { return d.TotalSize; } catch { return 0; } }
    private static long SafeFree(DriveInfo d) { try { return d.AvailableFreeSpace; } catch { return 0; } }
}
