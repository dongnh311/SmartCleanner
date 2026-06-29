using MacCleaner.Win.Core.Files;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class DuplicatesPage : Page
{
    private readonly IDuplicateFinderService _svc;
    private CancellationTokenSource? _cts;

    public DuplicatesPage()
    {
        InitializeComponent();
        _svc = App.Services.GetRequiredService<IDuplicateFinderService>();
        Header.Title = Localization.Loc.Get("Duplicates_Title", "Duplicates");
        Header.Subtitle = Localization.Loc.Get("Duplicates_Subtitle", "SHA-256 streaming match (size pre-filter)");
        PathBox.PlaceholderText = Localization.Loc.Get("Common_PathToScan", "Path to scan");
        ScanButton.Content = Localization.Loc.Get("Common_Scan", "Scan");
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
        StatusText.Text = Localization.Loc.Get("Duplicates_Hashing", "Hashing…");
        GroupsList.Items.Clear();

        try
        {
            var groups = await _svc.FindAsync(PathBox.Text, minBytes: 1024, ct);
            if (ct.IsCancellationRequested) return;

            long reclaimable = groups.Sum(g => g.SizeBytes * (g.Paths.Count - 1));
            StatusText.Text = string.Format(Localization.Loc.Get("Duplicates_ResultFormat", "{0} duplicate group(s) · {1} reclaimable by keeping one copy"), groups.Count, Core.FileSystem.Bytes.Format(reclaimable));
            foreach (var g in groups) GroupsList.Items.Add(BuildGroup(g));
        }
        catch (Exception ex)
        {
            StatusText.Text = string.Format(Localization.Loc.Get("Common_ScanFailedFormat", "Scan failed: {0}"), ex.Message);
        }
        finally
        {
            if (!ct.IsCancellationRequested) ScanButton.IsEnabled = true;
        }
    }

    private static UIElement BuildGroup(DuplicateGroup g)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = string.Format(Localization.Loc.Get("Duplicates_GroupFormat", "{0} copies · {1} each"), g.Paths.Count, Core.FileSystem.Bytes.Format(g.SizeBytes)),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        foreach (var p in g.Paths)
        {
            stack.Children.Add(new TextBlock
            {
                Text = "  " + p,
                FontSize = 11,
                Opacity = 0.65,
                FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }
        return stack;
    }
}
