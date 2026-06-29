using MacCleaner.Win.Core.Files;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class LargeOldFilesPage : Page
{
    private readonly ILargeOldFilesService _svc;
    private CancellationTokenSource? _cts;

    public LargeOldFilesPage()
    {
        InitializeComponent();
        _svc = App.Services.GetRequiredService<ILargeOldFilesService>();
        Header.Title = Localization.Loc.Get("LargeOld_Title", "Large & Old");
        Header.Subtitle = Localization.Loc.Get("LargeOld_Subtitle", "Files past the size + age thresholds");
        PathBox.PlaceholderText = Localization.Loc.Get("LargeOld_PathPlaceholder", "Path to scan");
        ScanButton.Content = Localization.Loc.Get("Common_Scan", "Scan");
        MinSizeLabel.Text = Localization.Loc.Get("LargeOld_MinSize", "Min size (MB):");
        MinAgeLabel.Text = Localization.Loc.Get("LargeOld_MinAge", "Min age (days):");
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        PathBox.Text = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
        base.OnNavigatedFrom(e);
    }

    private async void ScanButton_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        ScanButton.IsEnabled = false;
        StatusText.Text = Localization.Loc.Get("Common_Scanning", "Scanning…");
        ResultsList.Items.Clear();

        var filter = new LargeOldFilter(
            RootPath: PathBox.Text,
            MinSizeBytes: (long)(MinSizeMb.Value * 1024 * 1024),
            MinAge: TimeSpan.FromDays(MinAgeDays.Value),
            MaxResults: 1000);

        try
        {
            var rows = await Task.Run(() => _svc.Find(filter, ct), ct);
            if (ct.IsCancellationRequested) return;
            StatusText.Text = string.Format(Localization.Loc.Get("LargeOld_CountFormat", "{0} file(s) match"), rows.Count);
            foreach (var r in rows) ResultsList.Items.Add(BuildRow(r));
        }
        catch (Exception ex)
        {
            StatusText.Text = string.Format(Localization.Loc.Get("Common_FailedFormat", "Failed: {0}"), ex.Message);
        }
        finally
        {
            if (!ct.IsCancellationRequested) ScanButton.IsEnabled = true;
        }
    }

    private static UIElement BuildRow(LargeOldFile r)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = r.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = string.Format(Localization.Loc.Get("LargeOld_RowFormat", "{0} · last modified {1}"), Core.FileSystem.Bytes.Format(r.SizeBytes), r.LastWriteUtc.ToString("yyyy-MM-dd")),
            FontSize = 11,
            Opacity = 0.65
        });
        stack.Children.Add(new TextBlock
        {
            Text = r.FullPath,
            FontSize = 10,
            Opacity = 0.45,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        return stack;
    }
}
