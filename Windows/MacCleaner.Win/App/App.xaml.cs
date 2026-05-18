using MacCleaner.Win.App.Hosts;
using MacCleaner.Win.Core.DI;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace MacCleaner.Win.App;

/// <summary>
/// WinUI 3 application entry. Mirrors the role of <c>MacCleanerApp.swift</c>
/// in the macOS app — owns the DI root, the primary window, and the
/// system-tray icon.
/// </summary>
public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;
    private Window? _window;
    private NotifyIconHost? _tray;

    public App()
    {
        InitializeComponent();
        Services = new ServiceCollection()
            .AddCoreServices()
            .AddAppServices()
            .BuildServiceProvider();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();

        _tray = new NotifyIconHost(
            showMainWindow: () =>
            {
                if (_window is null)
                {
                    _window = new MainWindow();
                }
                _window.Activate();
            },
            exitApp: Exit);
    }
}
