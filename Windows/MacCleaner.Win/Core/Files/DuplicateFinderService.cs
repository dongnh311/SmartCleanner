using System.Security.Cryptography;

namespace MacCleaner.Win.Core.Files;

public sealed record DuplicateGroup(
    long SizeBytes,
    string Hash,
    IReadOnlyList<string> Paths);

public interface IDuplicateFinderService
{
    /// <summary>Find duplicate-content files under <paramref name="rootPath"/>.
    /// Two-stage: group by size first, then hash collisions with SHA-256
    /// streaming. Files smaller than <paramref name="minBytes"/> are
    /// skipped — hashing them costs more than reclaiming them.</summary>
    Task<IReadOnlyList<DuplicateGroup>> FindAsync(
        string rootPath,
        long minBytes = 1024,
        CancellationToken ct = default);
}

public sealed class DuplicateFinderService : IDuplicateFinderService
{
    public async Task<IReadOnlyList<DuplicateGroup>> FindAsync(
        string rootPath,
        long minBytes = 1024,
        CancellationToken ct = default)
    {
        if (!Directory.Exists(rootPath)) return Array.Empty<DuplicateGroup>();

        // Pass 1: group candidate paths by file size. Singletons can't
        // possibly be duplicates so we drop them before paying for I/O.
        var bySize = new Dictionary<long, List<string>>();
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };
        IEnumerable<string> files;
        try { files = Directory.EnumerateFiles(rootPath, "*", options); }
        catch { return Array.Empty<DuplicateGroup>(); }

        foreach (var path in files)
        {
            ct.ThrowIfCancellationRequested();
            FileInfo info;
            try { info = new FileInfo(path); } catch { continue; }
            if (info.Length < minBytes) continue;

            if (!bySize.TryGetValue(info.Length, out var bucket))
            {
                bucket = new List<string>();
                bySize[info.Length] = bucket;
            }
            bucket.Add(path);
        }

        // Pass 2: hash each size-collision bucket.
        var groups = new List<DuplicateGroup>();
        foreach (var (size, paths) in bySize)
        {
            if (paths.Count < 2) continue;

            var byHash = new Dictionary<string, List<string>>();
            foreach (var p in paths)
            {
                ct.ThrowIfCancellationRequested();
                string? hex = await HashAsync(p, ct);
                if (hex is null) continue;
                if (!byHash.TryGetValue(hex, out var hashBucket))
                {
                    hashBucket = new List<string>();
                    byHash[hex] = hashBucket;
                }
                hashBucket.Add(p);
            }

            foreach (var (hash, dupePaths) in byHash)
            {
                if (dupePaths.Count < 2) continue;
                groups.Add(new DuplicateGroup(size, hash, dupePaths));
            }
        }

        groups.Sort((a, b) => (b.SizeBytes * (b.Paths.Count - 1)).CompareTo(a.SizeBytes * (a.Paths.Count - 1)));
        return groups;
    }

    private static async Task<string?> HashAsync(string path, CancellationToken ct)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
                bufferSize: 1 << 16, useAsync: true);
            using var sha = SHA256.Create();
            byte[] hash = await sha.ComputeHashAsync(stream, ct);
            return Convert.ToHexString(hash);
        }
        catch
        {
            // Locked / vanished / no rights — skip; the row is just missing
            // from any group it would have joined, which is the safe default.
            return null;
        }
    }
}
