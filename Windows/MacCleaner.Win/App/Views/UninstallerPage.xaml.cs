using MacCleaner.Win.Core.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class UninstallerPage : Page
{
    private readonly IRegistryService _registry;
    private IReadOnlyList<InstalledProgram> _all = Array.Empty<InstalledProgram>();
    private string _filter = "";

    public UninstallerPage()
    {
        InitializeComponent();
        _registry = App.Services.GetRequiredService<IRegistryService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _all = _registry.ListInstalledPrograms();
        Render();
    }

    private void FilterBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _filter = FilterBox.Text.Trim();
        Render();
    }

    private void Render()
    {
        IEnumerable<InstalledProgram> view = _all;
        if (!string.IsNullOrEmpty(_filter))
        {
            view = view.Where(p =>
                p.DisplayName.Contains(_filter, StringComparison.OrdinalIgnoreCase) ||
                (p.Publisher?.Contains(_filter, StringComparison.OrdinalIgnoreCase) ?? false));
        }

        var ordered = view
            .OrderByDescending(p => p.EstimatedSizeBytes ?? 0)
            .ThenBy(p => p.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        ProgramsList.Items.Clear();
        foreach (var p in ordered) ProgramsList.Items.Add(BuildRow(p));

        CountText.Text = ordered.Length == _all.Count
            ? $"{ordered.Length} programs"
            : $"{ordered.Length} / {_all.Count}";
    }

    private static UIElement BuildRow(InstalledProgram p)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };

        var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        top.Children.Add(new TextBlock
        {
            Text = p.DisplayName,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        if (!string.IsNullOrEmpty(p.DisplayVersion))
        {
            top.Children.Add(new TextBlock
            {
                Text = p.DisplayVersion,
                FontSize = 11,
                Opacity = 0.55,
                FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New")
            });
        }
        stack.Children.Add(top);

        var sub = new List<string>();
        if (!string.IsNullOrWhiteSpace(p.Publisher)) sub.Add(p.Publisher);
        if (p.EstimatedSizeBytes is long size && size > 0) sub.Add(Core.FileSystem.Bytes.Format(size));
        if (p.InstallDate is DateTime d) sub.Add(d.ToString("yyyy-MM-dd"));
        if (sub.Count > 0)
        {
            stack.Children.Add(new TextBlock
            {
                Text = string.Join(" · ", sub),
                FontSize = 11,
                Opacity = 0.6
            });
        }
        return stack;
    }
}
