namespace MacCleaner.Win.Core.Cleanup;

public sealed record TargetScan(
    CleanupTarget Target,
    long TotalBytes,
    int FileCount,
    bool Accessible);

public sealed record CleanResult(
    long BytesFreed,
    int FilesDeleted,
    int FilesSkipped);

public interface ICleanupService
{
    /// <summary>Walk a target directory and report total reclaimable size.
    /// Returns Accessible=false if the path can't be enumerated at all
    /// (missing folder or denied access — caller hides those rows).</summary>
    TargetScan Scan(CleanupTarget target, CancellationToken ct = default);

    /// <summary>Delete files under <paramref name="target"/>. Best-effort:
    /// skips files we don't own or that are currently locked. Empty
    /// directories left behind are NOT removed — Windows keeps them
    /// pinned for apps that recreate them on launch.</summary>
    CleanResult Clean(CleanupTarget target, CancellationToken ct = default);
}

public sealed class CleanupService : ICleanupService
{
    public TargetScan Scan(CleanupTarget target, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(target.AbsolutePath) || !Directory.Exists(target.AbsolutePath))
        {
            return new TargetScan(target, 0, 0, false);
        }

        long total = 0;
        int count = 0;
        foreach (var info in SafeEnumerate(target.AbsolutePath, ct))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                total += info.Length;
                count++;
            }
            catch
            {
                // FileInfo.Length can throw if the file vanished mid-walk.
                // Ignore — the size is at-rest and a missing file is fine.
            }
        }
        return new TargetScan(target, total, count, true);
    }

    public CleanResult Clean(CleanupTarget target, CancellationToken ct = default)
    {
        if (!Directory.Exists(target.AbsolutePath))
        {
            return new CleanResult(0, 0, 0);
        }

        long freed = 0;
        int deleted = 0;
        int skipped = 0;
        foreach (var info in SafeEnumerate(target.AbsolutePath, ct))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                long size = info.Length;
                info.Delete();
                freed += size;
                deleted++;
            }
            catch
            {
                // Locked/in-use file, or the file was already removed by
                // another process between enumeration and Delete. Count
                // it and continue — partial success is the norm here.
                skipped++;
            }
        }
        return new CleanResult(freed, deleted, skipped);
    }

    private static IEnumerable<FileInfo> SafeEnumerate(string root, CancellationToken ct)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };
        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(root, "*", options);
        }
        catch
        {
            yield break;
        }

        foreach (var path in files)
        {
            ct.ThrowIfCancellationRequested();
            FileInfo info;
            try
            {
                info = new FileInfo(path);
            }
            catch
            {
                continue;
            }
            yield return info;
        }
    }
}
