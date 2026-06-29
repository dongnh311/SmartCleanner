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
        Header.Title = Localization.Loc.Get("Scroll_Title", "Scroll Denoiser");
        Header.Subtitle = Localization.Loc.Get("Scroll_Subtitle", "Direction-lock filter for cheap mouse wheels");
        Description.Text = Localization.Loc.Get("Scroll_Desc", "Suppresses wheel events whose direction reverses within 80 ms of the previous one — the classic encoder bounce on budget mice.");
        EnableToggle.Header = Localization.Loc.Get("Scroll_Active", "Active");
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
            ? Localization.Loc.Get("Scroll_HookOn", "Hook installed — bouncing wheel events will be suppressed.")
            : Localization.Loc.Get("Scroll_HookOff", "Hook not active.");
    }
}
