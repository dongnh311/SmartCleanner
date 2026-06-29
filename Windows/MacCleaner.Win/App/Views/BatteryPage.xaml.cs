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
        Header.Title = Localization.Loc.Get("Battery_Title", "Battery");
        Header.Subtitle = Localization.Loc.Get("Battery_Subtitle", "Power state and remaining capacity");
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
            StateText.Text = Localization.Loc.Get("Battery_NoBattery", "No battery detected");
            RemainingText.Text = "";
            return;
        }

        PercentText.Text = $"{s.PercentRemaining}%";
        PercentBar.Value = s.PercentRemaining;
        StateText.Text = s.IsCharging
            ? Localization.Loc.Get("Battery_Charging", "Charging")
            : (s.IsOnAC ? Localization.Loc.Get("Battery_OnAC", "On AC power")
                        : Localization.Loc.Get("Battery_OnBattery", "On battery"));
        RemainingText.Text = s.TimeRemaining is { } t
            ? string.Format(Localization.Loc.Get("Battery_RemainingFormat", "≈ {0}h {1}m remaining"), t.Hours, t.Minutes)
            : Localization.Loc.Get("Battery_TimeUnavailable", "Time estimate unavailable");
    }
}
