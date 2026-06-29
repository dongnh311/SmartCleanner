using System.Diagnostics;
using MacCleaner.Win.Core.Tools;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class MyToolsPage : Page
{
    private readonly IMyToolsService _svc;

    public MyToolsPage()
    {
        InitializeComponent();
        _svc = App.Services.GetRequiredService<IMyToolsService>();
        Header.Title = Localization.Loc.Get("MyTools_Title", "My Tools");
        Header.Subtitle = Localization.Loc.Get("MyTools_Subtitle", "Pinned shortcuts and folders");
        LabelBox.PlaceholderText = Localization.Loc.Get("MyTools_LabelPlaceholder", "Label");
        TargetBox.PlaceholderText = Localization.Loc.Get("MyTools_TargetPlaceholder", "C:\\path\\to\\anything (file, folder, URL)");
        AddButton.Content = Localization.Loc.Get("Common_Add", "Add");
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Refresh();
    }

    private void Refresh()
    {
        ItemsList.Items.Clear();
        var items = _svc.List();
        if (items.Count == 0)
        {
            ItemsList.Items.Add(new TextBlock
            {
                Text = Localization.Loc.Get("MyTools_Empty", "Add a shortcut above to pin it here."),
                Padding = new Thickness(12, 16, 12, 16),
                Opacity = 0.65,
                HorizontalAlignment = HorizontalAlignment.Center
            });
            return;
        }
        foreach (var s in items) ItemsList.Items.Add(BuildRow(s));
    }

    private async void AddButton_Click(object sender, RoutedEventArgs e)
    {
        string label = LabelBox.Text.Trim();
        string target = TargetBox.Text.Trim();
        if (string.IsNullOrEmpty(label) || string.IsNullOrEmpty(target)) return;
        await _svc.AddAsync(label, target);
        LabelBox.Text = "";
        TargetBox.Text = "";
        Refresh();
    }

    private UIElement BuildRow(PinnedShortcut s)
    {
        var grid = new Grid { ColumnSpacing = 8, Padding = new Thickness(12, 6, 12, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock { Text = s.Label, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        stack.Children.Add(new TextBlock
        {
            Text = s.Target,
            FontSize = 11,
            Opacity = 0.65,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(stack, 0); grid.Children.Add(stack);

        var open = new Button { Content = Localization.Loc.Get("Common_Open", "Open") };
        open.Click += (_, _) =>
        {
            try
            {
                Process.Start(new ProcessStartInfo(s.Target) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                _ = new ContentDialog
                {
                    Title = Localization.Loc.Get("MyTools_OpenFailed", "Could not open"),
                    Content = ex.Message,
                    CloseButtonText = Localization.Loc.Get("Common_Close", "Close"),
                    XamlRoot = this.XamlRoot
                }.ShowAsync();
            }
        };
        Grid.SetColumn(open, 1); grid.Children.Add(open);

        var remove = new Button { Content = Localization.Loc.Get("Common_Remove", "Remove") };
        remove.Click += async (_, _) => { await _svc.RemoveAsync(s.Id); Refresh(); };
        Grid.SetColumn(remove, 2); grid.Children.Add(remove);
        return grid;
    }
}
