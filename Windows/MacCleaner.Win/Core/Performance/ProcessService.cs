using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MacCleaner.Win.Core.Performance;

public sealed record ProcessRow(
    int Pid,
    string Name,
    long WorkingSetBytes,
    string? ExecutablePath,
    DateTime? StartTime);

public interface IProcessService
{
    /// <summary>Snapshot of all visible processes — cheap fields only
    /// (name, PID, working set, path). CPU% requires sampling over time
    /// and is added in a later phase.</summary>
    IReadOnlyList<ProcessRow> List();
}

public sealed class ProcessService : IProcessService
{
    public IReadOnlyList<ProcessRow> List()
    {
        var processes = Process.GetProcesses();
        var rows = new List<ProcessRow>(processes.Length);
        foreach (var p in processes)
        {
            try
            {
                rows.Add(new ProcessRow(
                    Pid: p.Id,
                    Name: p.ProcessName,
                    WorkingSetBytes: p.WorkingSet64,
                    ExecutablePath: TryGetPath(p),
                    StartTime: TryGetStartTime(p)));
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // Process may have exited between GetProcesses() and field reads,
                // or we lack the rights to inspect protected processes — skip
                // silently. The user-facing list will just omit the row.
            }
            finally
            {
                p.Dispose();
            }
        }
        return rows;
    }

    private static string? TryGetPath(Process p)
    {
        try { return p.MainModule?.FileName; }
        catch { return null; }
    }

    private static DateTime? TryGetStartTime(Process p)
    {
        try { return p.StartTime; }
        catch { return null; }
    }
}
