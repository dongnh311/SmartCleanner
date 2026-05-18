namespace MacCleaner.Win.Core.Files;

public sealed record SpaceNode(string Name, string FullPath, long TotalBytes, IReadOnlyList<SpaceNode> Children);

public interface ISpaceLensService
{
    /// <summary>Compute a one-level deep size breakdown of the given root —
    /// each direct child folder/file gets its own node. Recursive
    /// expansion is the caller's job (typically TreeView lazy-load).</summary>
    SpaceNode Scan(string rootPath, CancellationToken ct = default);
}

public sealed class SpaceLensService : ISpaceLensService
{
    public SpaceNode Scan(string rootPath, CancellationToken ct = default)
    {
        if (!Directory.Exists(rootPath))
        {
            return new SpaceNode(Path.GetFileName(rootPath), rootPath, 0, Array.Empty<SpaceNode>());
        }

        var children = new List<SpaceNode>();
        long total = 0;

        foreach (var sub in SafeEnumerateDirectories(rootPath))
        {
            ct.ThrowIfCancellationRequested();
            long size = ComputeFolderSize(sub, ct);
            children.Add(new SpaceNode(Path.GetFileName(sub), sub, size, Array.Empty<SpaceNode>()));
            total += size;
        }
        foreach (var file in SafeEnumerateFiles(rootPath))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var info = new FileInfo(file);
                children.Add(new SpaceNode(info.Name, info.FullName, info.Length, Array.Empty<SpaceNode>()));
                total += info.Length;
            }
            catch { /* file vanished or no rights — skip */ }
        }

        children.Sort((a, b) => b.TotalBytes.CompareTo(a.TotalBytes));
        return new SpaceNode(Path.GetFileName(rootPath.TrimEnd('\\')), rootPath, total, children);
    }

    private static long ComputeFolderSize(string folder, CancellationToken ct)
    {
        long total = 0;
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };
        IEnumerable<string> files;
        try { files = Directory.EnumerateFiles(folder, "*", options); }
        catch { return 0; }

        foreach (var path in files)
        {
            ct.ThrowIfCancellationRequested();
            try { total += new FileInfo(path).Length; }
            catch { /* skip racy/locked file */ }
        }
        return total;
    }

    private static IEnumerable<string> SafeEnumerateDirectories(string root)
    {
        try { return Directory.EnumerateDirectories(root); }
        catch { return Array.Empty<string>(); }
    }

    private static IEnumerable<string> SafeEnumerateFiles(string root)
    {
        try { return Directory.EnumerateFiles(root); }
        catch { return Array.Empty<string>(); }
    }
}
