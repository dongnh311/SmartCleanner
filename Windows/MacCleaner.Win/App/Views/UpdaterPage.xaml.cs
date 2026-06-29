using MacCleaner.Win.Core.Applications;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class UpdaterPage : Page
{
    private readonly IWingetService _winget;
    private CancellationTokenSource? _cts;

    public UpdaterPage()
    {
        InitializeComponent();
        _winget = App.Services.GetRequiredService<IWingetService>();
        Header.Title = Localization.Loc.Get("Updater_Title", "Updater");
        Header.Subtitle = Localization.Loc.Get("Updater_Subtitle", "Pending updates via winget");
        RefreshButton.Content = Localization.Loc.Get("Common_Refresh", "Refresh");
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _cts = new CancellationTokenSource();
        await ReloadAsync(_cts.Token);
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
        base.OnNavigatedFrom(e);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        await ReloadAsync(_cts.Token);
    }

    private async Task ReloadAsync(CancellationToken ct)
    {
        RefreshButton.IsEnabled = false;
        StatusText.Text = Localization.Loc.Get("Updater_Querying", "Querying winget…");
        UpgradesList.Items.Clear();

        try
        {
            if (!await _winget.IsAvailableAsync(ct))
            {
                StatusText.Text = Localization.Loc.Get("Updater_NotInstalled", "winget is not installed. Install \"App Installer\" from the Microsoft Store.");
                return;
            }

            var upgrades = await _winget.ListUpgradesAsync(ct);
            if (ct.IsCancellationRequested) return;

            StatusText.Text = upgrades.Count == 0
                ? Localization.Loc.Get("Updater_UpToDate", "Everything is up to date.")
                : string.Format(Localization.Loc.Get("Updater_CountFormat", "{0} package(s) have updates available"), upgrades.Count);

            foreach (var u in upgrades) UpgradesList.Items.Add(BuildRow(u));
        }
        catch (Exception ex)
        {
            StatusText.Text = string.Format(Localization.Loc.Get("Common_FailedFormat", "Failed: {0}"), ex.Message);
        }
        finally
        {
            if (!ct.IsCancellationRequested) RefreshButton.IsEnabled = true;
        }
    }

    private static UIElement BuildRow(WingetUpgrade u)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = string.IsNullOrEmpty(u.Name) ? u.Id : u.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"{u.InstalledVersion} → {u.AvailableVersion}  ·  {u.Id}  ·  {u.Source}",
            FontSize = 11,
            Opacity = 0.65,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New")
        });
        return stack;
    }
}
