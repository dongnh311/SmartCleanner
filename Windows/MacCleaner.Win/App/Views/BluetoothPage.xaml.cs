using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class BluetoothPage : Page
{
    private readonly IBluetoothService _bluetooth;
    private CancellationTokenSource? _cts;

    public BluetoothPage()
    {
        InitializeComponent();
        _bluetooth = App.Services.GetRequiredService<IBluetoothService>();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _cts = new CancellationTokenSource();
        await ReloadAsync(_cts.Token);
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
        base.OnNavigatedFrom(e);
    }

    private async Task ReloadAsync(CancellationToken ct)
    {
        StatusText.Text = "Scanning…";
        DevicesList.Items.Clear();
        try
        {
            var devices = await _bluetooth.ListAsync(ct);
            if (ct.IsCancellationRequested) return;
            StatusText.Text = devices.Count == 0
                ? "No paired devices found."
                : $"{devices.Count} paired device(s)";
            foreach (var d in devices)
            {
                DevicesList.Items.Add(BuildRow(d));
            }
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Bluetooth scan failed: {ex.Message}";
        }
    }

    private static UIElement BuildRow(BluetoothDeviceRow d)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = d.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"{(d.IsLowEnergy ? "LE" : "Classic")} · {(d.IsConnected ? "Connected" : "Disconnected")} · {(d.IsPaired ? "Paired" : "Unpaired")}",
            FontSize = 11,
            Opacity = 0.65
        });
        return stack;
    }
}
