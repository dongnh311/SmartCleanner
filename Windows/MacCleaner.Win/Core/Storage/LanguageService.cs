using Microsoft.Win32;

namespace MacCleaner.Win.Core.Storage;

/// <summary>
/// Persists the UI language choice in HKCU. The Windows analogue of the macOS
/// app writing <c>AppleLanguages</c>: the App reads this at startup and sets
/// <c>ApplicationLanguages.PrimaryLanguageOverride</c> so resources resolve to
/// the chosen language. Empty = follow the system.
/// </summary>
public interface ILanguageService
{
    /// <summary>BCP-47 code ("en", "vi") or empty to follow the system.</summary>
    string Code { get; }
    void SetCode(string code);
}

public sealed class LanguageService : ILanguageService
{
    private const string ValueName = "Language";
    private readonly string _subKey;

    public LanguageService() : this(@"Software\MacCleaner") { }

    /// <summary>Test seam: a throwaway sub-key keeps tests off the real value.</summary>
    public LanguageService(string subKey) => _subKey = subKey;

    public string Code
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(_subKey);
                return key?.GetValue(ValueName) as string ?? "";
            }
            catch { return ""; }
        }
    }

    public void SetCode(string code)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(_subKey);
            key?.SetValue(ValueName, code ?? "");
        }
        catch { /* best effort */ }
    }
}
