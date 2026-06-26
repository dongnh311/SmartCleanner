using Microsoft.Win32;

namespace MacCleaner.Win.Core.Storage;

/// <summary>
/// Registers (or removes) MacCleaner in the per-user "run at login" list via
/// HKCU\Software\Microsoft\Windows\CurrentVersion\Run — the Windows analogue
/// of the macOS SMAppService login item. Per-user, so it needs no admin
/// rights and the presence of the value is itself the on/off state.
/// </summary>
public interface IStartupService
{
    /// <summary>True when a Run-key entry for MacCleaner is present.</summary>
    bool IsEnabled { get; }

    /// <summary>Adds or removes the Run-key entry pointing at this executable.</summary>
    void SetEnabled(bool enabled);
}

public sealed class StartupService : IStartupService
{
    private const string RunSubKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly string _valueName;
    private readonly Func<string?> _executablePath;

    public StartupService() : this("MacCleaner", () => Environment.ProcessPath) { }

    /// <summary>
    /// Test seam: lets unit tests use a throwaway value name and a fake
    /// executable path so they never touch the real "MacCleaner" entry.
    /// </summary>
    public StartupService(string valueName, Func<string?> executablePath)
    {
        _valueName = valueName;
        _executablePath = executablePath;
    }

    public bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunSubKey);
            return key?.GetValue(_valueName) is string s && s.Length > 0;
        }
    }

    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunSubKey);
        if (key is null) return;

        if (enabled)
        {
            var path = _executablePath();
            if (string.IsNullOrEmpty(path)) return;
            // Quote the path so a space in the install directory doesn't split
            // it into program + arguments when Windows launches it.
            key.SetValue(_valueName, $"\"{path}\"");
        }
        else if (key.GetValue(_valueName) is not null)
        {
            key.DeleteValue(_valueName, throwOnMissingValue: false);
        }
    }
}
