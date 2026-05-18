using MacCleaner.Win.Core.Files;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class SimilarPhotosPage : Page
{
    private readonly ISimilarPhotosService _svc;
    private CancellationTokenSource? _cts;

    public SimilarPhotosPage()
    {
        InitializeComponent();
        _svc = App.Services.GetRequiredService<ISimilarPhotosService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        PathBox.Text = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
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
        StatusText.Text = "Hashing photos…";
        GroupsList.Items.Clear();

        try
        {
            var groups = await _svc.FindAsync(PathBox.Text, (int)MaxDist.Value, ct);
            if (ct.IsCancellationRequested) return;
            StatusText.Text = $"{groups.Count} cluster(s)";
            foreach (var g in groups) GroupsList.Items.Add(BuildGroup(g));
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Scan failed: {ex.Message}";
        }
        finally
        {
            if (!ct.IsCancellationRequested) ScanButton.IsEnabled = true;
        }
    }

    private static UIElement BuildGroup(SimilarGroup g)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = $"{g.Paths.Count} similar (worst distance {g.RepresentativeDistance})",
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
