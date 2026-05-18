using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class BatteryPage : Page
{
    private readonly IBatteryService _battery;
    private DispatcherQueueTimer? _timer;

    public BatteryPage()
    {
        InitializeComponent();
        _battery = App.Services.GetRequiredService<IBatteryService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Refresh();
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(5);
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
        var s = _battery.Sample();
        if (!s.HasBattery)
        {
            PercentText.Text = "n/a";
            PercentBar.Value = 0;
            StateText.Text = "No battery detected";
            RemainingText.Text = "";
            return;
        }

        PercentText.Text = $"{s.PercentRemaining}%";
        PercentBar.Value = s.PercentRemaining;
        StateText.Text = s.IsCharging ? "Charging" : (s.IsOnAC ? "On AC power" : "On battery");
        RemainingText.Text = s.TimeRemaining is { } t
            ? $"≈ {t.Hours}h {t.Minutes}m remaining"
            : "Time estimate unavailable";
    }
}
