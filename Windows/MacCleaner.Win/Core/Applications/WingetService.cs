using System.Diagnostics;
using System.Text;

namespace MacCleaner.Win.Core.Applications;

public sealed record WingetUpgrade(
    string Id,
    string Name,
    string InstalledVersion,
    string AvailableVersion,
    string Source);

public interface IWingetService
{
    Task<bool> IsAvailableAsync(CancellationToken ct = default);
    /// <summary>Wraps <c>winget upgrade --include-unknown</c>. Empty on
    /// machines where winget is missing or all packages are current.</summary>
    Task<IReadOnlyList<WingetUpgrade>> ListUpgradesAsync(CancellationToken ct = default);
}

/// <summary>
/// Shells out to the <c>winget</c> CLI. The COM API surface
/// (<c>Microsoft.WindowsPackageManager.ComInterop</c>) is faster but
/// only available on packaged installs; the CLI works for everyone
/// who has App Installer.
/// </summary>
public sealed class WingetService : IWingetService
{
    public async Task<bool> IsAvailableAsync(CancellationToken ct = default)
    {
        try
        {
            var (_, exit) = await RunAsync("--version", ct);
            return exit == 0;
        }
        catch
        {
            return false;
        }
    }

    public async Task<IReadOnlyList<WingetUpgrade>> ListUpgradesAsync(CancellationToken ct = default)
    {
        var (stdout, exit) = await RunAsync("upgrade --include-unknown --accept-source-agreements", ct);
        if (exit != 0) return Array.Empty<WingetUpgrade>();
        return ParseUpgradeTable(stdout);
    }

    private static async Task<(string Stdout, int ExitCode)> RunAsync(string args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo("winget", args)
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8
        };

        using var proc = Process.Start(psi);
        if (proc is null) return ("", -1);

        string stdout = await proc.StandardOutput.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);
        return (stdout, proc.ExitCode);
    }

    /// <summary>
    /// winget's upgrade output is a fixed-width table with a header row
    /// like "Name  Id  Version  Available  Source". We locate column
    /// offsets from the header, then slice each data row at those
    /// offsets — far more robust than splitting on whitespace because
    /// app names contain spaces.
    /// </summary>
    private static IReadOnlyList<WingetUpgrade> ParseUpgradeTable(string stdout)
    {
        var lines = stdout.Split('\n').Select(l => l.TrimEnd('\r')).ToArray();

        int headerIdx = Array.FindIndex(lines, l =>
            l.Contains("Name", StringComparison.Ordinal) &&
            l.Contains("Id", StringComparison.Ordinal) &&
            l.Contains("Version", StringComparison.Ordinal) &&
            l.Contains("Available", StringComparison.Ordinal));
        if (headerIdx < 0 || headerIdx + 2 >= lines.Length) return Array.Empty<WingetUpgrade>();

        var header = lines[headerIdx];
        int idCol        = header.IndexOf("Id", StringComparison.Ordinal);
        int versionCol   = header.IndexOf("Version", StringComparison.Ordinal);
        int availableCol = header.IndexOf("Available", StringComparison.Ordinal);
        int sourceCol    = header.IndexOf("Source", StringComparison.Ordinal);
        if (idCol < 0 || versionCol < 0 || availableCol < 0) return Array.Empty<WingetUpgrade>();

        var rows = new List<WingetUpgrade>();
        for (int i = headerIdx + 2; i < lines.Length; i++) // skip header + separator
        {
            var line = lines[i];
            if (string.IsNullOrWhiteSpace(line)) break;
            if (line.StartsWith("-")) break;
            if (line.Length < availableCol) continue;

            string name      = Slice(line, 0, idCol).Trim();
            string id        = Slice(line, idCol, versionCol - idCol).Trim();
            string installed = Slice(line, versionCol, availableCol - versionCol).Trim();
            string available = sourceCol > availableCol
                ? Slice(line, availableCol, sourceCol - availableCol).Trim()
                : line[availableCol..].Trim();
            string source    = sourceCol > 0 && line.Length > sourceCol
                ? line[sourceCol..].Trim()
                : "";

            if (string.IsNullOrEmpty(id)) continue;
            rows.Add(new WingetUpgrade(id, name, installed, available, source));
        }
        return rows;
    }

    private static string Slice(string s, int start, int len)
    {
        int end = Math.Min(s.Length, start + len);
        return start < s.Length ? s[start..end] : "";
    }
}
