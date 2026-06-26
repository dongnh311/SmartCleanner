using System.Diagnostics;
using System.Reflection;
using MacCleaner.Win.Core.Storage;
using MacCleaner.Win.Core.Tools;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class SettingsPage : Page
{
    private readonly ISqliteService _sqlite;
    private readonly IQuarantineService _quarantine;
    private readonly IStartupService _startup;
    private bool _initializing;

    public SettingsPage()
    {
        InitializeComponent();
        _sqlite = App.Services.GetRequiredService<ISqliteService>();
        _quarantine = App.Services.GetRequiredService<IQuarantineService>();
        _startup = App.Services.GetRequiredService<IStartupService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"Version {version} · {RuntimeInformation()}";

        // Reflect current state without bouncing the Toggled handler back at us.
        _initializing = true;
        StartupToggle.IsOn = _startup.IsEnabled;
        _initializing = false;
    }

    private void StartupToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_initializing) return;
        _startup.SetEnabled(StartupToggle.IsOn);
    }

    private static string RuntimeInformation() =>
        $".NET {Environment.Version} · {System.Runtime.InteropServices.RuntimeInformation.OSArchitecture}";

    private void OpenQuarantine_Click(object sender, RoutedEventArgs e) =>
        OpenInExplorer(_quarantine.QuarantineRoot);

    private void OpenTrends_Click(object sender, RoutedEventArgs e) =>
        OpenInExplorer(Path.GetDirectoryName(_sqlite.DatabasePath) ?? "");

    private void OpenMyTools_Click(object sender, RoutedEventArgs e) =>
        OpenInExplorer(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacCleaner"));

    private static void OpenInExplorer(string folder)
    {
        if (string.IsNullOrEmpty(folder)) return;
        try
        {
            if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{folder}\"") { UseShellExecute = true });
        }
        catch { /* user can navigate manually if explorer.exe is missing */ }
    }
}
