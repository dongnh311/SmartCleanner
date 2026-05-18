using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.Versioning;

namespace MacCleaner.Win.Core.Files;

public sealed record SimilarGroup(IReadOnlyList<string> Paths, int RepresentativeDistance);

public interface ISimilarPhotosService
{
    /// <summary>Group near-duplicate photos by perceptual (average) hash.
    /// Files are scanned recursively under <paramref name="rootPath"/>
    /// and clustered by Hamming distance up to <paramref name="maxDistance"/>
    /// bits (≤ 6 is a tight match, ≤ 10 is loose).</summary>
    Task<IReadOnlyList<SimilarGroup>> FindAsync(
        string rootPath,
        int maxDistance = 6,
        CancellationToken ct = default);
}

/// <summary>
/// Average-hash implementation: shrink each image to 8×8 grayscale, take
/// the mean intensity, and emit a 64-bit fingerprint where bit n is set
/// iff pixel n is above the mean. Two images are "similar" if the
/// Hamming distance of their fingerprints is small. aHash is the cheapest
/// pHash variant and is good enough for "the same photo at different
/// resolutions / compressions" — the macOS Vision-backed pHash port can
/// land later via SkiaSharp without changing the consumer.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class SimilarPhotosService : ISimilarPhotosService
{
    private static readonly string[] _extensions =
        [".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff", ".webp"];

    public async Task<IReadOnlyList<SimilarGroup>> FindAsync(
        string rootPath,
        int maxDistance = 6,
        CancellationToken ct = default)
    {
        if (!Directory.Exists(rootPath)) return Array.Empty<SimilarGroup>();

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };

        IEnumerable<string> candidates;
        try
        {
            candidates = Directory.EnumerateFiles(rootPath, "*", options)
                .Where(p => _extensions.Contains(Path.GetExtension(p), StringComparer.OrdinalIgnoreCase));
        }
        catch { return Array.Empty<SimilarGroup>(); }

        var hashes = new List<(string Path, ulong Hash)>();
        await Task.Run(() =>
        {
            foreach (var p in candidates)
            {
                ct.ThrowIfCancellationRequested();
                ulong? h = TryHash(p);
                if (h.HasValue) hashes.Add((p, h.Value));
            }
        }, ct);

        // Greedy clustering: walk each unassigned hash, gather everything
        // within maxDistance, mark assigned. Quadratic but adequate for
        // mid-thousands of photos; revisit with BK-tree if it bites.
        var assigned = new bool[hashes.Count];
        var groups = new List<SimilarGroup>();
        for (int i = 0; i < hashes.Count; i++)
        {
            if (assigned[i]) continue;
            var bucket = new List<string> { hashes[i].Path };
            int worst = 0;
            for (int j = i + 1; j < hashes.Count; j++)
            {
                if (assigned[j]) continue;
                int d = HammingDistance(hashes[i].Hash, hashes[j].Hash);
                if (d <= maxDistance)
                {
                    bucket.Add(hashes[j].Path);
                    assigned[j] = true;
                    if (d > worst) worst = d;
                }
            }
            if (bucket.Count > 1)
            {
                assigned[i] = true;
                groups.Add(new SimilarGroup(bucket, worst));
            }
        }
        return groups;
    }

    private static ulong? TryHash(string path)
    {
        try
        {
            using var src = Image.FromFile(path);
            using var small = new Bitmap(8, 8, PixelFormat.Format24bppRgb);
            using (var g = Graphics.FromImage(small))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
                g.DrawImage(src, 0, 0, 8, 8);
            }

            int[] pixels = new int[64];
            int total = 0;
            for (int y = 0; y < 8; y++)
            {
                for (int x = 0; x < 8; x++)
                {
                    var c = small.GetPixel(x, y);
                    int gray = (c.R * 30 + c.G * 59 + c.B * 11) / 100;
                    pixels[y * 8 + x] = gray;
                    total += gray;
                }
            }
            int mean = total / 64;

            ulong hash = 0;
            for (int i = 0; i < 64; i++)
            {
                if (pixels[i] >= mean) hash |= 1UL << i;
            }
            return hash;
        }
        catch
        {
            // Corrupt/unsupported image, denied access, or GDI+ choke
            // (HEIF without codec). Skip — pHash is best-effort.
            return null;
        }
    }

    private static int HammingDistance(ulong a, ulong b) =>
        System.Numerics.BitOperations.PopCount(a ^ b);
}
