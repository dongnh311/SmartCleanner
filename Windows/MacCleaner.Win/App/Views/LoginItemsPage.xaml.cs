using MacCleaner.Win.Core.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.Win32;

namespace MacCleaner.Win.App.Views;

public sealed partial class LoginItemsPage : Page
{
    private readonly IRegistryService _registry;

    public LoginItemsPage()
    {
        InitializeComponent();
        _registry = App.Services.GetRequiredService<IRegistryService>();
        Header.Title = Localization.Loc.Get("LoginItems_Title", "Login Items");
        Header.Subtitle = Localization.Loc.Get("LoginItems_Subtitle", "Programs that start with Windows");
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var items = _registry.ListLoginItems();
        CountText.Text = string.Format(
            Localization.Loc.Get("LoginItems_CountFormat", "{0} entries across HKCU and HKLM (64-bit + WoW64)"),
            items.Count);

        ItemsList.Items.Clear();
        foreach (var item in items.OrderBy(i => i.Hive).ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase))
        {
            ItemsList.Items.Add(BuildRow(item));
        }
    }

    private static UIElement BuildRow(LoginItem item)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };

        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        header.Children.Add(new TextBlock
        {
            Text = item.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        header.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(999),
            Padding = new Thickness(6, 1, 6, 1),
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(
                Microsoft.UI.Colors.LightGray) { Opacity = 0.35 },
            Child = new TextBlock
            {
                FontSize = 9,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Text = item.Hive == RegistryHive.LocalMachine
                    ? (item.Is64BitView ? "HKLM·64" : "HKLM·32")
                    : "HKCU"
            }
        });

        stack.Children.Add(header);
        stack.Children.Add(new TextBlock
        {
            Text = item.Command,
            FontSize = 11,
            Opacity = 0.65,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            TextWrapping = TextWrapping.NoWrap,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        return stack;
    }
}
