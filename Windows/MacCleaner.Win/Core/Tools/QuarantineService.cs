using System.Text.Json;

namespace MacCleaner.Win.Core.Tools;

public sealed record QuarantineRecord(
    string Id,
    string OriginalPath,
    string QuarantinePath,
    DateTime QuarantinedAt,
    long SizeBytes);

public interface IQuarantineService
{
    string QuarantineRoot { get; }
    Task<QuarantineRecord> QuarantineAsync(string sourcePath, CancellationToken ct = default);
    Task RestoreAsync(QuarantineRecord record, CancellationToken ct = default);
    Task PurgeOlderThanAsync(TimeSpan age, CancellationToken ct = default);
    IReadOnlyList<QuarantineRecord> List();
}

/// <summary>
/// Move-to-managed-folder + manifest. Same shape as the macOS
/// <c>QuarantineService</c>: files moved into a dated quarantine root,
/// metadata persisted as JSON so restore round-trips even after the
/// app restarts, and aged-out entries swept by a separate call.
/// </summary>
public sealed class QuarantineService : IQuarantineService
{
    public string QuarantineRoot { get; }
    private string ManifestPath => Path.Combine(QuarantineRoot, "manifest.json");

    public QuarantineService()
    {
        QuarantineRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacCleaner", "Quarantine");
        Directory.CreateDirectory(QuarantineRoot);
    }

    public async Task<QuarantineRecord> QuarantineAsync(string sourcePath, CancellationToken ct = default)
    {
        if (!File.Exists(sourcePath)) throw new FileNotFoundException(sourcePath);
        string id = Guid.NewGuid().ToString("N");
        string dest = Path.Combine(QuarantineRoot, id + Path.GetExtension(sourcePath));
        long size = new FileInfo(sourcePath).Length;

        await Task.Run(() => File.Move(sourcePath, dest, overwrite: false), ct);

        var record = new QuarantineRecord(id, sourcePath, dest, DateTime.UtcNow, size);
        var manifest = LoadManifest();
        manifest[id] = record;
        await SaveManifestAsync(manifest, ct);
        return record;
    }

    public async Task RestoreAsync(QuarantineRecord record, CancellationToken ct = default)
    {
        if (!File.Exists(record.QuarantinePath)) throw new FileNotFoundException(record.QuarantinePath);
        string targetDir = Path.GetDirectoryName(record.OriginalPath) ?? "";
        if (!string.IsNullOrEmpty(targetDir)) Directory.CreateDirectory(targetDir);
        await Task.Run(() => File.Move(record.QuarantinePath, record.OriginalPath, overwrite: false), ct);

        var manifest = LoadManifest();
        manifest.Remove(record.Id);
        await SaveManifestAsync(manifest, ct);
    }

    public async Task PurgeOlderThanAsync(TimeSpan age, CancellationToken ct = default)
    {
        var cutoff = DateTime.UtcNow - age;
        var manifest = LoadManifest();
        bool dirty = false;
        foreach (var (id, rec) in manifest.ToArray())
        {
            ct.ThrowIfCancellationRequested();
            if (rec.QuarantinedAt > cutoff) continue;
            try { if (File.Exists(rec.QuarantinePath)) File.Delete(rec.QuarantinePath); } catch { /* swallow — purge is best-effort */ }
            manifest.Remove(id);
            dirty = true;
        }
        if (dirty) await SaveManifestAsync(manifest, ct);
    }

    public IReadOnlyList<QuarantineRecord> List() => LoadManifest().Values.ToArray();

    private Dictionary<string, QuarantineRecord> LoadManifest()
    {
        if (!File.Exists(ManifestPath)) return new Dictionary<string, QuarantineRecord>();
        try
        {
            string json = File.ReadAllText(ManifestPath);
            return JsonSerializer.Deserialize<Dictionary<string, QuarantineRecord>>(json)
                ?? new Dictionary<string, QuarantineRecord>();
        }
        catch
        {
            // Corrupt manifest — treat as empty rather than crash on launch.
            // Lost quarantine entries are recoverable manually from the folder.
            return new Dictionary<string, QuarantineRecord>();
        }
    }

    private async Task SaveManifestAsync(Dictionary<string, QuarantineRecord> manifest, CancellationToken ct)
    {
        string json = JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(ManifestPath, json, ct);
    }
}
