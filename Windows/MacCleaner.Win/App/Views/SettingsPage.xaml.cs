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

    public SettingsPage()
    {
        InitializeComponent();
        _sqlite = App.Services.GetRequiredService<ISqliteService>();
        _quarantine = App.Services.GetRequiredService<IQuarantineService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var version = Assembly.GetExecutingAssembly().GetName().Version;
        VersionText.Text = $"Version {version} · {RuntimeInformation()}";
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
