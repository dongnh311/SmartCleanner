using System.Runtime.InteropServices;

namespace MacCleaner.Win.Core.Cleanup;

public sealed record RecycleBinInfo(long TotalBytes, long ItemCount);

public interface IRecycleBinService
{
    /// <summary>Total size + item count across all per-drive Recycle Bins.
    /// Returns zero if the shell32 query fails (rare).</summary>
    RecycleBinInfo Query();

    /// <summary>Empty the Recycle Bin silently (no confirmation UI,
    /// no progress dialog, no sound). The caller is expected to confirm.</summary>
    void Empty();
}

/// <summary>
/// Wraps shell32 SHQueryRecycleBin / SHEmptyRecycleBin. Both accept a
/// drive root path; passing null queries / empties across every drive.
/// </summary>
public sealed class RecycleBinService : IRecycleBinService
{
    public RecycleBinInfo Query()
    {
        var info = new SHQUERYRBINFO { cbSize = (uint)Marshal.SizeOf<SHQUERYRBINFO>() };
        int hr = SHQueryRecycleBin(null, ref info);
        if (hr != 0) return new RecycleBinInfo(0, 0);
        return new RecycleBinInfo(info.i64Size, info.i64NumItems);
    }

    public void Empty()
    {
        const uint SHERB_NOCONFIRMATION = 0x00000001;
        const uint SHERB_NOPROGRESSUI   = 0x00000002;
        const uint SHERB_NOSOUND        = 0x00000004;
        SHEmptyRecycleBin(IntPtr.Zero, null, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SHQUERYRBINFO
    {
        public uint cbSize;
        public long i64Size;
        public long i64NumItems;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string? pszRootPath, ref SHQUERYRBINFO pSHQueryRBInfo);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr hWnd, string? pszRootPath, uint dwFlags);
}
