using System.Security.Cryptography;

namespace MacCleaner.Win.Core.Tools;

public sealed record ShredResult(bool Succeeded, string? ErrorMessage);

public interface IShredderService
{
    /// <summary>Overwrite the file in place <paramref name="passes"/> times
    /// with cryptographic random bytes, flush, then delete. Each pass
    /// rewrites the whole length so the next one starts from a fresh
    /// random sequence — SSDs may relocate blocks (caller-side
    /// disclaimer is expected).</summary>
    Task<ShredResult> ShredAsync(string path, int passes = 3, CancellationToken ct = default);
}

public sealed class ShredderService : IShredderService
{
    private const int ChunkSize = 1 << 16; // 64 KB — same buffer the mac Shredder uses

    public async Task<ShredResult> ShredAsync(string path, int passes = 3, CancellationToken ct = default)
    {
        if (!File.Exists(path)) return new ShredResult(false, "File does not exist.");
        try
        {
            long length = new FileInfo(path).Length;
            byte[] buffer = new byte[ChunkSize];

            for (int pass = 0; pass < passes; pass++)
            {
                ct.ThrowIfCancellationRequested();
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.None,
                    bufferSize: ChunkSize, useAsync: true);
                long remaining = length;
                while (remaining > 0)
                {
                    ct.ThrowIfCancellationRequested();
                    int toWrite = (int)Math.Min(ChunkSize, remaining);
                    RandomNumberGenerator.Fill(buffer.AsSpan(0, toWrite));
                    await stream.WriteAsync(buffer.AsMemory(0, toWrite), ct);
                    remaining -= toWrite;
                }
                await stream.FlushAsync(ct);
            }
            File.Delete(path);
            return new ShredResult(true, null);
        }
        catch (OperationCanceledException)
        {
            return new ShredResult(false, "Cancelled.");
        }
        catch (Exception ex)
        {
            return new ShredResult(false, ex.Message);
        }
    }
}
