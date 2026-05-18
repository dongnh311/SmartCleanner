using MacCleaner.Win.Core.Tools;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class ScrollDenoiserPage : Page
{
    private readonly IScrollDenoiserService _svc;

    public ScrollDenoiserPage()
    {
        InitializeComponent();
        _svc = App.Services.GetRequiredService<IScrollDenoiserService>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        EnableToggle.IsOn = _svc.IsEnabled;
        UpdateStatus();
    }

    private void EnableToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (EnableToggle.IsOn) _svc.Enable();
        else _svc.Disable();
        UpdateStatus();
    }

    private void UpdateStatus()
    {
        StatusText.Text = _svc.IsEnabled
            ? "Hook installed — bouncing wheel events will be suppressed."
            : "Hook not active.";
    }
}
