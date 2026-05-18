using MacCleaner.Win.Core.FileSystem;
using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace MacCleaner.Win.App.Views;

public sealed partial class DashboardPage : Page
{
    private readonly ISystemMetricsService _metrics;
    private readonly IDriveService _drives;
    private DispatcherQueueTimer? _timer;

    public DashboardPage()
    {
        InitializeComponent();
        _metrics = App.Services.GetRequiredService<ISystemMetricsService>();
        _drives = App.Services.GetRequiredService<IDriveService>();
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
        var cpu = _metrics.SampleCpu();
        CpuValueText.Text = $"{cpu.UsagePercent:F0}%";
        CpuBar.Value = cpu.UsagePercent;

        var mem = _metrics.SampleMemory();
        RamValueText.Text = $"{mem.UsedPercent:F0}%";
        RamBar.Value = mem.UsedPercent;
        RamSubText.Text = $"{Core.FileSystem.Bytes.Format((long)mem.UsedBytes)} of {Core.FileSystem.Bytes.Format((long)mem.TotalBytes)}";

        DriveList.Items.Clear();
        foreach (var d in _drives.List())
        {
            DriveList.Items.Add(BuildDriveRow(d));
        }
    }

    private static UIElement BuildDriveRow(DriveRow d)
    {
        var nameText = new TextBlock
        {
            Text = string.IsNullOrEmpty(d.VolumeLabel) ? d.Name : $"{d.Name} {d.VolumeLabel}",
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        var subText = new TextBlock
        {
            Text = d.IsReady
                ? $"{Core.FileSystem.Bytes.Format(d.FreeBytes)} free of {Core.FileSystem.Bytes.Format(d.TotalBytes)}"
                : "Not ready",
            FontSize = 12,
            Opacity = 0.65
        };
        var bar = new ProgressBar { Minimum = 0, Maximum = 100, Value = d.UsedPercent };

        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(nameText);
        stack.Children.Add(bar);
        stack.Children.Add(subText);
        return stack;
    }
}
