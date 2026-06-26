using Microsoft.Windows.ApplicationModel.Resources;

namespace MacCleaner.Win.App.Localization;

/// <summary>
/// Thin wrapper over the WindowsAppSDK MRT-Core <see cref="ResourceLoader"/>
/// (works in unpackaged apps). Every lookup takes an English fallback, so a
/// missing key — or resources that fail to load entirely — degrades to English
/// instead of showing a blank or crashing.
/// </summary>
public static class Loc
{
    private static readonly ResourceLoader? Loader = Create();

    private static ResourceLoader? Create()
    {
        try { return new ResourceLoader(); }
        catch { return null; }
    }

    public static string Get(string key, string fallback)
    {
        try
        {
            var value = Loader?.GetString(key);
            return string.IsNullOrEmpty(value) ? fallback : value;
        }
        catch
        {
            return fallback;
        }
    }
}
