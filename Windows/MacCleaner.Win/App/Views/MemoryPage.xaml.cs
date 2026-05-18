using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class MemoryPage : Page
{
    private readonly ISystemMetricsService _metrics;
    private DispatcherQueueTimer? _timer;

    public MemoryPage()
    {
        InitializeComponent();
        _metrics = App.Services.GetRequiredService<ISystemMetricsService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Refresh();
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(1);
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

    private void Refresh()
    {
        var s = _metrics.SampleMemory();
        UsedPercentText.Text = $"{s.UsedPercent:F0}%";
        UsedBar.Value = s.UsedPercent;
        UsedDetailText.Text = $"{Core.FileSystem.Bytes.Format((long)s.UsedBytes)} used";
        TotalDetailText.Text = $"{Core.FileSystem.Bytes.Format((long)s.AvailableBytes)} available · {Core.FileSystem.Bytes.Format((long)s.TotalBytes)} total";
    }
}
