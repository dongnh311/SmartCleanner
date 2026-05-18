using MacCleaner.Win.Core.Tools;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class QuarantinePage : Page
{
    private readonly IQuarantineService _quarantine;

    public QuarantinePage()
    {
        InitializeComponent();
        _quarantine = App.Services.GetRequiredService<IQuarantineService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        PathLabel.Text = _quarantine.QuarantineRoot;
        Refresh();
    }

    private void Refresh()
    {
        RecordsList.Items.Clear();
        var records = _quarantine.List().OrderByDescending(r => r.QuarantinedAt).ToArray();
        if (records.Length == 0)
        {
            RecordsList.Items.Add(new TextBlock
            {
                Text = "No files in quarantine.",
                Padding = new Thickness(12, 16, 12, 16),
                Opacity = 0.65,
                HorizontalAlignment = HorizontalAlignment.Center
            });
            return;
        }

        foreach (var r in records)
        {
            RecordsList.Items.Add(BuildRow(r));
        }
    }

    private UIElement BuildRow(QuarantineRecord r)
    {
        var grid = new Grid { ColumnSpacing = 8, Padding = new Thickness(12, 6, 12, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock
        {
            Text = Path.GetFileName(r.OriginalPath),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"{Core.FileSystem.Bytes.Format(r.SizeBytes)} · quarantined {r.QuarantinedAt:yyyy-MM-dd HH:mm} UTC",
            FontSize = 11,
            Opacity = 0.65
        });
        stack.Children.Add(new TextBlock
        {
            Text = r.OriginalPath,
            FontSize = 10,
            Opacity = 0.5,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(stack, 0); grid.Children.Add(stack);

        var restore = new Button { Content = "Restore", Tag = r };
        restore.Click += async (_, _) =>
        {
            restore.IsEnabled = false;
            try { await _quarantine.RestoreAsync(r); Refresh(); }
            catch (Exception ex)
            {
                await new ContentDialog
                {
                    Title = "Restore failed",
                    Content = ex.Message,
                    CloseButtonText = "Close",
                    XamlRoot = this.XamlRoot
                }.ShowAsync();
                restore.IsEnabled = true;
            }
        };
        Grid.SetColumn(restore, 1); grid.Children.Add(restore);
        return grid;
    }

    private async void PurgeButton_Click(object sender, RoutedEventArgs e)
    {
        PurgeButton.IsEnabled = false;
        await _quarantine.PurgeOlderThanAsync(TimeSpan.FromDays(7));
        Refresh();
        PurgeButton.IsEnabled = true;
    }
}
