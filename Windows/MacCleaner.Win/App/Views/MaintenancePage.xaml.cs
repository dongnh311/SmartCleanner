using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.ApplicationModel.DataTransfer;

namespace MacCleaner.Win.App.Views;

public sealed partial class MaintenancePage : Page
{
    private readonly IMaintenanceService _service;
    private bool _built;

    public MaintenancePage()
    {
        InitializeComponent();
        _service = App.Services.GetRequiredService<IMaintenanceService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (_built) return;
        _built = true;

        foreach (var group in MaintenanceCommand.All.GroupBy(c => c.Category))
        {
            Host.Children.Add(new TextBlock
            {
                Text = group.Key.ToString(),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                Opacity = 0.6,
                Margin = new Thickness(0, 4, 0, 0)
            });

            foreach (var cmd in group)
            {
                Host.Children.Add(BuildCard(cmd));
            }
        }
    }

    private UIElement BuildCard(MaintenanceCommand cmd)
    {
        var content = new StackPanel { Spacing = 6 };

        // Header row: title (+ ADMIN badge) on the left, Copy/Run on the right.
        var headerGrid = new Grid();
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        titleRow.Children.Add(new TextBlock
        {
            Text = cmd.Title,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });
        if (cmd.RequiresAdmin)
        {
            titleRow.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(999),
                Padding = new Thickness(6, 1, 6, 1),
                VerticalAlignment = VerticalAlignment.Center,
                Background = new SolidColorBrush(Colors.Orange) { Opacity = 0.25 },
                Child = new TextBlock { Text = "ADMIN", FontSize = 9, FontWeight = FontWeights.Bold }
            });
        }
        Grid.SetColumn(titleRow, 0);
        headerGrid.Children.Add(titleRow);

        var result = new TextBlock
        {
            Visibility = Visibility.Collapsed,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true
        };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };

        var copy = new Button { Content = "Copy" };
        copy.Click += (_, _) =>
        {
            var data = new DataPackage();
            data.SetText(cmd.DisplayCommand);
            Clipboard.SetContent(data);
        };
        buttons.Children.Add(copy);

        var run = new Button { Content = "Run" };
        if (!_service.IsAvailable(cmd))
        {
            run.IsEnabled = false;
            run.Content = "Unavailable";
        }
        else
        {
            run.Click += async (_, _) =>
            {
                run.IsEnabled = false;
                var label = run.Content;
                run.Content = "Running…";

                var outcome = await _service.RunAsync(cmd);

                run.Content = label;
                run.IsEnabled = true;
                result.Visibility = Visibility.Visible;
                result.Text = outcome.Output;
                result.Foreground = new SolidColorBrush(outcome.Success ? Colors.SeaGreen : Colors.IndianRed);
            };
        }
        buttons.Children.Add(run);

        Grid.SetColumn(buttons, 1);
        headerGrid.Children.Add(buttons);

        content.Children.Add(headerGrid);
        content.Children.Add(new TextBlock { Text = cmd.Summary, FontSize = 12, Opacity = 0.65, TextWrapping = TextWrapping.Wrap });
        content.Children.Add(new TextBlock
        {
            Text = cmd.DisplayCommand,
            FontFamily = new FontFamily("Cascadia Mono,Consolas,Courier New"),
            FontSize = 11,
            Opacity = 0.6,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(result);

        return new Border
        {
            Style = (Style)Application.Current.Resources["Card"],
            Child = content
        };
    }
}
