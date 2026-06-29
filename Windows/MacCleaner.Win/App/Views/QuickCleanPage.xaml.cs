using MacCleaner.Win.Core.Cleanup;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class QuickCleanPage : Page
{
    private readonly ICleanupService _cleanup;
    private readonly Dictionary<string, CheckBox> _checkboxes = new();
    private readonly Dictionary<string, TargetScan> _scans = new();
    private CancellationTokenSource? _cts;

    public QuickCleanPage()
    {
        InitializeComponent();
        _cleanup = App.Services.GetRequiredService<ICleanupService>();
        Header.Title = Localization.Loc.Get("QuickClean_Title", "Quick Clean");
        Header.Subtitle = Localization.Loc.Get("QuickClean_Subtitle", "Caches, temp folders, browser data and dump files");
        ScanButton.Content = Localization.Loc.Get("Common_Scan", "Scan");
        CleanButton.Content = Localization.Loc.Get("QuickClean_CleanSelected", "Clean selected");
    }

    private static string LocalizedLabel(CleanupTarget t) =>
        Localization.Loc.Get("Clean_" + t.Id.Replace("-", "_") + "_Label", t.Label);

    private static string LocalizedDesc(CleanupTarget t) =>
        Localization.Loc.Get("Clean_" + t.Id.Replace("-", "_") + "_Desc", t.Description);

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        RenderTargets();
        StatusText.Text = Localization.Loc.Get("QuickClean_Prompt", "Press Scan to estimate reclaimable space.");
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
        base.OnNavigatedFrom(e);
    }

    private void RenderTargets()
    {
        TargetsList.Items.Clear();
        _checkboxes.Clear();
        foreach (var t in CleanupTargets.QuickClean())
        {
            TargetsList.Items.Add(BuildRow(t));
        }
    }

    private UIElement BuildRow(CleanupTarget t)
    {
        var check = new CheckBox { IsChecked = true };
        _checkboxes[t.Id] = check;

        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(12, 6, 12, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        Grid.SetColumn(check, 0); grid.Children.Add(check);

        var stack = new StackPanel { Spacing = 2 };
        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        top.Children.Add(new TextBlock
        {
            Text = LocalizedLabel(t),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        if (t.RequiresAdmin)
        {
            top.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(999),
                Padding = new Thickness(6, 1, 6, 1),
                Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.OrangeRed) { Opacity = 0.18 },
                Child = new TextBlock { Text = "ADMIN", FontSize = 9, FontWeight = Microsoft.UI.Text.FontWeights.Bold }
            });
        }
        stack.Children.Add(top);
        stack.Children.Add(new TextBlock
        {
            Text = LocalizedDesc(t),
            FontSize = 11,
            Opacity = 0.6
        });
        stack.Children.Add(new TextBlock
        {
            Text = t.AbsolutePath,
            FontSize = 10,
            Opacity = 0.45,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(stack, 1); grid.Children.Add(stack);

        var size = new TextBlock
        {
            Name = $"size-{t.Id}",
            Text = "—",
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(size, 2); grid.Children.Add(size);
        return grid;
    }

    private async void ScanButton_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        ScanButton.IsEnabled = false;
        CleanButton.IsEnabled = false;
        StatusText.Text = Localization.Loc.Get("Common_Scanning", "Scanning…");
        _scans.Clear();

        long grand = 0;
        foreach (var t in CleanupTargets.QuickClean())
        {
            StatusText.Text = string.Format(Localization.Loc.Get("QuickClean_ScanningFormat", "Scanning {0}…"), LocalizedLabel(t));
            TargetScan scan = await Task.Run(() => _cleanup.Scan(t, ct), ct);
            if (ct.IsCancellationRequested) return;
            _scans[t.Id] = scan;
            UpdateSizeLabel(t.Id, scan);
            grand += scan.TotalBytes;
        }

        TotalText.Text = string.Format(Localization.Loc.Get("QuickClean_TotalFormat", "Total reclaimable: {0}"), Core.FileSystem.Bytes.Format(grand));
        StatusText.Text = Localization.Loc.Get("QuickClean_ScanComplete", "Scan complete.");
        ScanButton.IsEnabled = true;
        CleanButton.IsEnabled = grand > 0;
    }

    private async void CleanButton_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        ScanButton.IsEnabled = false;
        CleanButton.IsEnabled = false;
        StatusText.Text = Localization.Loc.Get("QuickClean_Cleaning", "Cleaning…");

        long freed = 0;
        int deleted = 0;
        int skipped = 0;
        foreach (var t in CleanupTargets.QuickClean())
        {
            if (!_checkboxes.TryGetValue(t.Id, out var cb) || cb.IsChecked != true) continue;
            StatusText.Text = string.Format(Localization.Loc.Get("QuickClean_CleaningFormat", "Cleaning {0}…"), LocalizedLabel(t));
            var res = await Task.Run(() => _cleanup.Clean(t, ct), ct);
            if (ct.IsCancellationRequested) return;
            freed += res.BytesFreed;
            deleted += res.FilesDeleted;
            skipped += res.FilesSkipped;
        }

        TotalText.Text = string.Format(Localization.Loc.Get("QuickClean_FreedFormat", "Freed: {0} — {1} files deleted, {2} skipped"), Core.FileSystem.Bytes.Format(freed), deleted, skipped);
        StatusText.Text = Localization.Loc.Get("QuickClean_CleanComplete", "Clean complete.");
        ScanButton.IsEnabled = true;
    }

    private void UpdateSizeLabel(string id, TargetScan scan)
    {
        // Find the size TextBlock we tagged in BuildRow.
        foreach (var item in TargetsList.Items)
        {
            if (item is not Grid g) continue;
            foreach (var child in g.Children)
            {
                if (child is TextBlock tb && tb.Name == $"size-{id}")
                {
                    tb.Text = scan.Accessible
                        ? string.Format(Localization.Loc.Get("QuickClean_SizeFormat", "{0} · {1} files"), Core.FileSystem.Bytes.Format(scan.TotalBytes), scan.FileCount)
                        : "n/a";
                    return;
                }
            }
        }
    }
}
