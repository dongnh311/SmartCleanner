using System.Text.Json;

namespace MacCleaner.Win.Core.Tools;

public sealed record PinnedShortcut(string Id, string Label, string Target);

public interface IMyToolsService
{
    IReadOnlyList<PinnedShortcut> List();
    Task AddAsync(string label, string target, CancellationToken ct = default);
    Task RemoveAsync(string id, CancellationToken ct = default);
}

public sealed class MyToolsService : IMyToolsService
{
    private readonly string _path;
    private readonly object _lock = new();

    public MyToolsService()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacCleaner");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "mytools.json");
    }

    public IReadOnlyList<PinnedShortcut> List() => Load();

    public async Task AddAsync(string label, string target, CancellationToken ct = default)
    {
        var list = Load().ToList();
        list.Add(new PinnedShortcut(Guid.NewGuid().ToString("N"), label, target));
        await SaveAsync(list, ct);
    }

    public async Task RemoveAsync(string id, CancellationToken ct = default)
    {
        var list = Load().Where(s => s.Id != id).ToList();
        await SaveAsync(list, ct);
    }

    private List<PinnedShortcut> Load()
    {
        lock (_lock)
        {
            if (!File.Exists(_path)) return new List<PinnedShortcut>();
            try
            {
                return JsonSerializer.Deserialize<List<PinnedShortcut>>(File.ReadAllText(_path))
                    ?? new List<PinnedShortcut>();
            }
            catch { return new List<PinnedShortcut>(); }
        }
    }

    private async Task SaveAsync(List<PinnedShortcut> list, CancellationToken ct)
    {
        string json = JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(_path, json, ct);
    }
}
