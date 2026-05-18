using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class DiskMonitorPage : Page
{
    private readonly IDiskMonitorService _disks;
    private DispatcherQueueTimer? _timer;

    public DiskMonitorPage()
    {
        InitializeComponent();
        _disks = App.Services.GetRequiredService<IDiskMonitorService>();
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
        DiskList.Items.Clear();
        foreach (var s in _disks.Sample())
        {
            DiskList.Items.Add(BuildRow(s));
        }
    }

    private static UIElement BuildRow(DiskIoSample s)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = s.Instance,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"↓ {Core.FileSystem.Bytes.FormatRateVerbose((ulong)s.ReadBytesPerSec)}  ·  ↑ {Core.FileSystem.Bytes.FormatRateVerbose((ulong)s.WriteBytesPerSec)}  ·  queue {s.QueueLength:F1}",
            FontSize = 12,
            Opacity = 0.7,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New")
        });
        return stack;
    }
}
