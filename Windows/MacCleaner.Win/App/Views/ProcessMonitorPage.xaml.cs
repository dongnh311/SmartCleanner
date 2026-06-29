using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class ProcessMonitorPage : Page
{
    private readonly IProcessService _processes;
    private DispatcherQueueTimer? _timer;
    private string _filter = "";
    private IReadOnlyList<ProcessRow> _lastSnapshot = Array.Empty<ProcessRow>();

    public ProcessMonitorPage()
    {
        InitializeComponent();
        _processes = App.Services.GetRequiredService<IProcessService>();
        Header.Title = Localization.Loc.Get("Processes_Title", "Process Monitor");
        Header.Subtitle = Localization.Loc.Get("Processes_Subtitle", "Live process snapshot, refreshed every 2 seconds");
        FilterBox.PlaceholderText = Localization.Loc.Get("Processes_FilterPlaceholder", "Filter by name…");
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Refresh();

        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(2);
        _timer.IsRepeating = true;
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _timer?.Stop();
        _timer = null;
        base.OnNavigatedFrom(e);
    }

    private void FilterBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _filter = FilterBox.Text.Trim();
        RenderFilteredView();
    }

    private void Refresh()
    {
        _lastSnapshot = _processes.List();
        RenderFilteredView();
    }

    private void RenderFilteredView()
    {
        var filtered = string.IsNullOrEmpty(_filter)
            ? _lastSnapshot
            : _lastSnapshot.Where(p => p.Name.Contains(_filter, StringComparison.OrdinalIgnoreCase)).ToArray();

        var ordered = filtered
            .OrderByDescending(p => p.WorkingSetBytes)
            .Take(500) // cap UI churn — 500 covers the heaviest tail
            .ToArray();

        ProcessList.Items.Clear();
        foreach (var row in ordered)
        {
            ProcessList.Items.Add(BuildRow(row));
        }

        CountText.Text = ordered.Length == _lastSnapshot.Count
            ? string.Format(Localization.Loc.Get("Processes_CountFormat", "{0} processes"), ordered.Length)
            : $"{ordered.Length} / {_lastSnapshot.Count}";
    }

    private static UIElement BuildRow(ProcessRow p)
    {
        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(12, 6, 12, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star) });

        var name = new TextBlock { Text = p.Name, TextTrimming = TextTrimming.CharacterEllipsis };
        var pid = new TextBlock
        {
            Text = p.Pid.ToString(),
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            FontSize = 12,
            Opacity = 0.75
        };
        var mem = new TextBlock
        {
            Text = Core.FileSystem.Bytes.Format(p.WorkingSetBytes),
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New"),
            FontSize = 12,
            Opacity = 0.85
        };
        var path = new TextBlock
        {
            Text = p.ExecutablePath ?? "—",
            FontSize = 12,
            Opacity = 0.65,
            TextTrimming = TextTrimming.CharacterEllipsis
        };

        Grid.SetColumn(name, 0); grid.Children.Add(name);
        Grid.SetColumn(pid,  1); grid.Children.Add(pid);
        Grid.SetColumn(mem,  2); grid.Children.Add(mem);
        Grid.SetColumn(path, 3); grid.Children.Add(path);
        return grid;
    }
}
