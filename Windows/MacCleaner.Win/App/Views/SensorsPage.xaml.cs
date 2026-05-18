using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class SensorsPage : Page
{
    private readonly ISensorsService _sensors;
    private DispatcherQueueTimer? _timer;

    public SensorsPage()
    {
        InitializeComponent();
        _sensors = App.Services.GetRequiredService<ISensorsService>();
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

    private void Refresh()
    {
        var readings = _sensors.ReadAll();
        if (readings.Count == 0)
        {
            StatusText.Text = "No sensors available. Run as administrator to expose temperatures and voltages.";
            SensorList.Items.Clear();
            return;
        }

        StatusText.Text = $"{readings.Count} sensors";
        SensorList.Items.Clear();
        foreach (var grouping in readings.GroupBy(r => r.HardwareName))
        {
            SensorList.Items.Add(BuildGroup(grouping.Key, grouping));
        }
    }

    private static UIElement BuildGroup(string hardware, IEnumerable<SensorReading> readings)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 8, 12, 8) };
        stack.Children.Add(new TextBlock
        {
            Text = hardware,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 13
        });
        foreach (var r in readings)
        {
            stack.Children.Add(new TextBlock
            {
                Text = $"{r.SensorName}  ·  {Format(r)}",
                FontSize = 11,
                Opacity = 0.7,
                FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono,Consolas,Courier New")
            });
        }
        return stack;
    }

    private static string Format(SensorReading r)
    {
        if (r.Value is not float v) return "—";
        return r.SensorType switch
        {
            LibreHardwareMonitor.Hardware.SensorType.Temperature => $"{v:F1} °C",
            LibreHardwareMonitor.Hardware.SensorType.Load        => $"{v:F0} %",
            LibreHardwareMonitor.Hardware.SensorType.Fan         => $"{v:F0} RPM",
            LibreHardwareMonitor.Hardware.SensorType.Voltage     => $"{v:F2} V",
            LibreHardwareMonitor.Hardware.SensorType.Clock       => $"{v:F0} MHz",
            LibreHardwareMonitor.Hardware.SensorType.Power       => $"{v:F1} W",
            _                                                    => v.ToString("F2")
        };
    }
}
