using MacCleaner.Win.Core.DI;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace MacCleaner.Win.App;

/// <summary>
/// WinUI 3 application entry. Mirrors the role of <c>MacCleanerApp.swift</c>
/// in the macOS app — owns the DI root and the primary window.
/// </summary>
public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;
    private Window? _window;

    public App()
    {
        InitializeComponent();
        Services = new ServiceCollection()
            .AddCoreServices()
            .BuildServiceProvider();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
