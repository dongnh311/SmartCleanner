using MacCleaner.Win.Core.Performance;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class NetworkPage : Page
{
    private readonly INetworkService _network;
    private DispatcherQueueTimer? _timer;

    public NetworkPage()
    {
        InitializeComponent();
        _network = App.Services.GetRequiredService<INetworkService>();
        Header.Title = Localization.Loc.Get("Network_Title", "Network");
        Header.Subtitle = Localization.Loc.Get("Network_Subtitle", "Active interfaces and total throughput");
        DownloadLabel.Text = Localization.Loc.Get("Common_Download", "Download");
        UploadLabel.Text = Localization.Loc.Get("Common_Upload", "Upload");
        InterfacesLabel.Text = Localization.Loc.Get("Network_Interfaces", "Interfaces");
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
        var tp = _network.SampleThroughput();
        DownText.Text = Core.FileSystem.Bytes.FormatRateVerbose(tp.DownBytesPerSec);
        UpText.Text   = Core.FileSystem.Bytes.FormatRateVerbose(tp.UpBytesPerSec);

        InterfacesList.Items.Clear();
        foreach (var iface in _network.List())
        {
            InterfacesList.Items.Add(BuildRow(iface));
        }
    }

    private static UIElement BuildRow(NetworkInterfaceRow iface)
    {
        var stack = new StackPanel { Spacing = 2, Padding = new Thickness(12, 6, 12, 6) };
        stack.Children.Add(new TextBlock
        {
            Text = iface.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"{iface.Type} · {iface.Status} · ↑ {Core.FileSystem.Bytes.Format(iface.BytesSent)} · ↓ {Core.FileSystem.Bytes.Format(iface.BytesReceived)}",
            FontSize = 11,
            Opacity = 0.65
        });
        return stack;
    }
}
