using Microsoft.Win32;

namespace MacCleaner.Win.Core.Storage;

public sealed record LoginItem(
    string Name,
    string Command,
    RegistryHive Hive,
    bool Is64BitView);

public sealed record InstalledProgram(
    string DisplayName,
    string? DisplayVersion,
    string? Publisher,
    string? InstallLocation,
    string? UninstallString,
    long? EstimatedSizeBytes,
    DateTime? InstallDate,
    RegistryHive Hive,
    bool Is64BitView);

public interface IRegistryService
{
    /// <summary>Programs registered to launch with Windows. Reads
    /// HKCU\...\Run and HKLM\...\Run in both 64-bit and 32-bit views.</summary>
    IReadOnlyList<LoginItem> ListLoginItems();

    /// <summary>Installed-programs scan for the Uninstaller module.
    /// Walks the standard Uninstall keys under HKCU and HKLM (64-bit + WoW64).</summary>
    IReadOnlyList<InstalledProgram> ListInstalledPrograms();
}

public sealed class RegistryService : IRegistryService
{
    private const string RunSubKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string UninstallSubKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";

    public IReadOnlyList<LoginItem> ListLoginItems()
    {
        var items = new List<LoginItem>();
        ReadRunKey(RegistryHive.CurrentUser,  RegistryView.Default,   items);
        ReadRunKey(RegistryHive.LocalMachine, RegistryView.Registry64, items);
        ReadRunKey(RegistryHive.LocalMachine, RegistryView.Registry32, items);
        return items;
    }

    public IReadOnlyList<InstalledProgram> ListInstalledPrograms()
    {
        var rows = new List<InstalledProgram>();
        ReadUninstall(RegistryHive.CurrentUser,  RegistryView.Default,   rows);
        ReadUninstall(RegistryHive.LocalMachine, RegistryView.Registry64, rows);
        ReadUninstall(RegistryHive.LocalMachine, RegistryView.Registry32, rows);
        return rows;
    }

    private static void ReadRunKey(RegistryHive hive, RegistryView view, List<LoginItem> sink)
    {
        try
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var key = root.OpenSubKey(RunSubKey);
            if (key is null) return;
            foreach (var name in key.GetValueNames())
            {
                if (key.GetValue(name) is string cmd)
                {
                    sink.Add(new LoginItem(name, cmd, hive, view == RegistryView.Registry64));
                }
            }
        }
        catch (UnauthorizedAccessException)
        {
            // No rights to read this hive view (e.g. HKLM\Run when the user
            // is heavily locked down). Silent skip — the rest of the list
            // is still meaningful.
        }
    }

    private static void ReadUninstall(RegistryHive hive, RegistryView view, List<InstalledProgram> sink)
    {
        try
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var key = root.OpenSubKey(UninstallSubKey);
            if (key is null) return;
            foreach (var subName in key.GetSubKeyNames())
            {
                using var sub = key.OpenSubKey(subName);
                if (sub is null) continue;
                if (sub.GetValue("DisplayName") is not string display || display.Length == 0) continue;
                if ((sub.GetValue("SystemComponent") as int?) == 1) continue;
                if (sub.GetValue("ParentKeyName") is string) continue;

                sink.Add(new InstalledProgram(
                    DisplayName: display,
                    DisplayVersion: sub.GetValue("DisplayVersion") as string,
                    Publisher: sub.GetValue("Publisher") as string,
                    InstallLocation: sub.GetValue("InstallLocation") as string,
                    UninstallString: sub.GetValue("UninstallString") as string,
                    EstimatedSizeBytes: sub.GetValue("EstimatedSize") is int kb ? kb * 1024L : null,
                    InstallDate: ParseInstallDate(sub.GetValue("InstallDate") as string),
                    Hive: hive,
                    Is64BitView: view == RegistryView.Registry64));
            }
        }
        catch (UnauthorizedAccessException)
        {
            // Same defensive skip as the Run-key reader above.
        }
    }

    private static DateTime? ParseInstallDate(string? raw) =>
        DateTime.TryParseExact(raw, "yyyyMMdd",
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var d) ? d : null;
}
