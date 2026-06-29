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
    private readonly ILanguageService _language;
    private bool _initializing;

    public SettingsPage()
    {
        InitializeComponent();
        _sqlite = App.Services.GetRequiredService<ISqliteService>();
        _quarantine = App.Services.GetRequiredService<IQuarantineService>();
        _startup = App.Services.GetRequiredService<IStartupService>();
        _language = App.Services.GetRequiredService<ILanguageService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var version = Assembly.GetExecutingAssembly().GetName().Version;

        Header.Title = Localization.Loc.Get("Settings_Title", "Settings");
        Header.Subtitle = Localization.Loc.Get("Settings_Subtitle", "About this build and where it stores data");
        AboutLabel.Text = Localization.Loc.Get("Settings_About", "About");
        AboutDesc.Text = Localization.Loc.Get("Settings_AboutDesc", "Windows port of the macOS app — same module set, native Win32/WinRT plumbing, see WINDOWS_PORT_PLAN.md.");
        VersionText.Text = string.Format(Localization.Loc.Get("Settings_VersionFormat", "Version {0} · {1}"), version, RuntimeInformation());
        StartupLabel.Text = Localization.Loc.Get("Settings_Startup", "Startup");
        StartupToggle.Header = Localization.Loc.Get("Settings_StartupToggle", "Open MacCleaner at login");
        StartupDesc.Text = Localization.Loc.Get("Settings_StartupDesc", "Adds MacCleaner to your per-user Run list so it starts with Windows. No admin rights needed.");
        DataLocationsLabel.Text = Localization.Loc.Get("Settings_DataLocations", "Data locations");
        OpenQuarantineButton.Content = Localization.Loc.Get("Settings_OpenQuarantine", "Open Quarantine folder");
        OpenTrendsButton.Content = Localization.Loc.Get("Settings_OpenTrends", "Open trends database folder");
        OpenMyToolsButton.Content = Localization.Loc.Get("Settings_ShowMyToolsJson", "Show My Tools JSON");

        // Reflect current state without bouncing the change handlers back at us.
        _initializing = true;
        StartupToggle.IsOn = _startup.IsEnabled;
        LanguageTitle.Text = Localization.Loc.Get("Settings_Language", "Language");
        LanguageCombo.SelectedIndex = _language.Code == "vi" ? 1 : 0;
        _initializing = false;
    }

    private void StartupToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_initializing) return;
        _startup.SetEnabled(StartupToggle.IsOn);
    }

    private void Language_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing) return;
        var code = (LanguageCombo.SelectedItem as ComboBoxItem)?.Tag as string ?? "en";
        _language.SetCode(code);
        LanguageNote.Text = Localization.Loc.Get("Settings_LanguageNote",
            "Restart MacCleaner to apply the change across every screen.");
        LanguageNote.Visibility = Visibility.Visible;
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
