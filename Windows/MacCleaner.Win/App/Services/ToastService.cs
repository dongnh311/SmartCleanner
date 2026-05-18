using MacCleaner.Win.Core.Alerts;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace MacCleaner.Win.App.Services;

/// <summary>
/// AppNotification-based toast — works for both packaged and unpackaged
/// WinUI 3 apps in WindowsAppSDK 1.2+, no Start Menu shortcut shim required.
/// The manager must be initialized once at app startup
/// (<see cref="EnsureRegistered"/>); subsequent <see cref="Notify"/> calls
/// just enqueue an XML payload.
/// </summary>
public sealed class ToastService : IToastService, IDisposable
{
    private static bool _registered;
    private static readonly Lock _lock = new();

    public ToastService()
    {
        EnsureRegistered();
    }

    public void Notify(string title, string body)
    {
        var payload = new AppNotificationBuilder()
            .AddText(title)
            .AddText(body)
            .BuildNotification();
        AppNotificationManager.Default.Show(payload);
    }

    private static void EnsureRegistered()
    {
        if (_registered) return;
        lock (_lock)
        {
            if (_registered) return;
            AppNotificationManager.Default.Register();
            _registered = true;
        }
    }

    public void Dispose()
    {
        // Unregistering on dispose is unnecessary for an app-lifetime
        // singleton — the OS cleans up when the process exits.
    }
}
