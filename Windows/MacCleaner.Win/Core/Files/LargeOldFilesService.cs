namespace MacCleaner.Win.Core.Files;

public sealed record LargeOldFile(
    string FullPath,
    string Name,
    long SizeBytes,
    DateTime LastWriteUtc);

public sealed record LargeOldFilter(
    string RootPath,
    long MinSizeBytes,
    TimeSpan MinAge,
    int MaxResults);

public interface ILargeOldFilesService
{
    /// <summary>Files under <c>RootPath</c> matching both
    /// <c>SizeBytes &gt;= MinSizeBytes</c> AND
    /// <c>now - LastWriteUtc &gt;= MinAge</c>, ordered descending by size,
    /// capped at <c>MaxResults</c>.</summary>
    IReadOnlyList<LargeOldFile> Find(LargeOldFilter filter, CancellationToken ct = default);
}

public sealed class LargeOldFilesService : ILargeOldFilesService
{
    public IReadOnlyList<LargeOldFile> Find(LargeOldFilter filter, CancellationToken ct = default)
    {
        if (!Directory.Exists(filter.RootPath)) return Array.Empty<LargeOldFile>();

        var cutoff = DateTime.UtcNow - filter.MinAge;
        var results = new List<LargeOldFile>(capacity: Math.Min(filter.MaxResults, 1024));

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };

        IEnumerable<string> files;
        try { files = Directory.EnumerateFiles(filter.RootPath, "*", options); }
        catch { return Array.Empty<LargeOldFile>(); }

        foreach (var path in files)
        {
            ct.ThrowIfCancellationRequested();
            FileInfo info;
            try { info = new FileInfo(path); } catch { continue; }
            if (info.Length < filter.MinSizeBytes) continue;
            DateTime mtime;
            try { mtime = info.LastWriteTimeUtc; } catch { continue; }
            if (mtime > cutoff) continue;
            results.Add(new LargeOldFile(info.FullName, info.Name, info.Length, mtime));
        }

        results.Sort((a, b) => b.SizeBytes.CompareTo(a.SizeBytes));
        if (results.Count > filter.MaxResults)
        {
            results.RemoveRange(filter.MaxResults, results.Count - filter.MaxResults);
        }
        return results;
    }
}
