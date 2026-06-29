using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class ClockPage : Page
{
    private DispatcherQueueTimer? _timer;
    private readonly List<TimeZoneInfo> _pinned = new();
    private readonly TimeZoneInfo[] _all = TimeZoneInfo.GetSystemTimeZones().ToArray();

    public ClockPage()
    {
        InitializeComponent();
        Header.Title = Localization.Loc.Get("Clock_Title", "Clock");
        Header.Subtitle = Localization.Loc.Get("Clock_Subtitle", "World clock — pinned time zones");
        TzBox.PlaceholderText = Localization.Loc.Get("Clock_FilterPlaceholder", "Filter time zones…");
        AddTzButton.Content = Localization.Loc.Get("Clock_Pin", "Pin");
        // Seed with the local zone so the page renders something meaningful
        // on first navigation without forcing the user to pin anything.
        _pinned.Add(TimeZoneInfo.Local);
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Render();
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(1);
        _timer.IsRepeating = true;
        _timer.Tick += (_, _) => Render();
        _timer.Start();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _timer?.Stop();
        _timer = null;
        base.OnNavigatedFrom(e);
    }

    private void TzBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason != AutoSuggestionBoxTextChangeReason.UserInput) return;
        string q = sender.Text.Trim();
        sender.ItemsSource = string.IsNullOrEmpty(q)
            ? Array.Empty<string>()
            : _all.Where(z => z.DisplayName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                              z.Id.Contains(q, StringComparison.OrdinalIgnoreCase))
                   .Take(20).Select(z => z.Id).ToArray();
    }

    private void AddTzButton_Click(object sender, RoutedEventArgs e)
    {
        string id = TzBox.Text.Trim();
        if (string.IsNullOrEmpty(id)) return;
        try
        {
            var tz = TimeZoneInfo.FindSystemTimeZoneById(id);
            if (!_pinned.Any(z => z.Id == tz.Id)) _pinned.Add(tz);
            TzBox.Text = "";
            Render();
        }
        catch (TimeZoneNotFoundException)
        {
            // Ignore — user typed a non-existent ID.
        }
    }

    private void Render()
    {
        var now = DateTimeOffset.UtcNow;
        ClocksList.Items.Clear();
        foreach (var tz in _pinned)
        {
            ClocksList.Items.Add(BuildRow(tz, TimeZoneInfo.ConvertTime(now, tz)));
        }
    }

    private static UIElement BuildRow(TimeZoneInfo tz, DateTimeOffset local)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 8, 12, 8) };
        stack.Children.Add(new TextBlock
        {
            Text = local.ToString("HH:mm:ss"),
            FontSize = 28,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New")
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"{tz.DisplayName} · {local:yyyy-MM-dd} · UTC{(tz.BaseUtcOffset.TotalHours >= 0 ? "+" : "")}{tz.BaseUtcOffset.TotalHours:0.##}",
            FontSize = 12,
            Opacity = 0.65
        });
        return stack;
    }
}
