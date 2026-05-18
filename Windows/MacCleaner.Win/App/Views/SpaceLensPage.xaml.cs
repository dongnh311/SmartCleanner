using MacCleaner.Win.Core.Files;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class SpaceLensPage : Page
{
    private readonly ISpaceLensService _lens;
    private CancellationTokenSource? _cts;

    public SpaceLensPage()
    {
        InitializeComponent();
        _lens = App.Services.GetRequiredService<ISpaceLensService>();
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

    private async void ScanButton_Click(object sender, RoutedEventArgs e) => await ScanAsync(PathBox.Text);

    private async void UpButton_Click(object sender, RoutedEventArgs e)
    {
        var parent = Path.GetDirectoryName(PathBox.Text.TrimEnd('\\'));
        if (string.IsNullOrEmpty(parent)) return;
        PathBox.Text = parent;
        await ScanAsync(parent);
    }

    private async void ChildList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is Grid g && g.Tag is string fullPath && Directory.Exists(fullPath))
        {
            PathBox.Text = fullPath;
            await ScanAsync(fullPath);
        }
    }

    private async Task ScanAsync(string path)
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        ScanButton.IsEnabled = false;
        TotalText.Text = $"Scanning {path}…";
        ChildList.Items.Clear();

        try
        {
            SpaceNode node = await Task.Run(() => _lens.Scan(path, ct), ct);
            if (ct.IsCancellationRequested) return;

            TotalText.Text = $"{Core.FileSystem.Bytes.Format(node.TotalBytes)} in {node.Children.Count} immediate items";
            foreach (var child in node.Children)
            {
                ChildList.Items.Add(BuildRow(child, node.TotalBytes));
            }
        }
        catch (Exception ex)
        {
            TotalText.Text = $"Scan failed: {ex.Message}";
        }
        finally
        {
            if (!ct.IsCancellationRequested) ScanButton.IsEnabled = true;
        }
    }

    private static UIElement BuildRow(SpaceNode n, long parentTotal)
    {
        bool isDir = Directory.Exists(n.FullPath);
        double pct = parentTotal > 0 ? (double)n.TotalBytes / parentTotal * 100.0 : 0;

        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(12, 6, 12, 6), Tag = n.FullPath };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });

        var name = new TextBlock
        {
            Text = (isDir ? "📁 " : "📄 ") + n.Name,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(name, 0); grid.Children.Add(name);

        var bar = new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = pct,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(bar, 1); grid.Children.Add(bar);

        var size = new TextBlock
        {
            Text = $"{Core.FileSystem.Bytes.Format(n.TotalBytes)} · {pct:F1}%",
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        Grid.SetColumn(size, 2); grid.Children.Add(size);
        return grid;
    }
}
