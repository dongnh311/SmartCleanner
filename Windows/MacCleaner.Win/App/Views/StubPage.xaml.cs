using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class StubPage : Page
{
    public StubPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is not ModuleDescriptor d) return;

        Header.Title = d.Title;
        Header.Subtitle = d.Subtitle;
        Header.IconGlyphChar = d.Glyph;
        Header.Accent = d.Accent;
        StatusText.Text = $"The {d.Title} module is part of the phased Windows port — see WINDOWS_PORT_PLAN.md for the schedule.";
    }
}
