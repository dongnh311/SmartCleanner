using Microsoft.UI.Xaml.Controls;

namespace MacCleaner.Win.App.Views;

public sealed partial class PaintPage : Page
{
    public PaintPage()
    {
        InitializeComponent();
        Header.Title = Localization.Loc.Get("Paint_Title", "Paint");
        Header.Subtitle = Localization.Loc.Get("Paint_Subtitle", "Canvas — InkCanvas wiring deferred");
        PendingTitle.Text = Localization.Loc.Get("Paint_Pending", "Paint canvas pending");
        PendingDesc.Text = Localization.Loc.Get("Paint_PendingDesc", "A SkiaSharp-backed canvas will replace the InkCanvas placeholder in a follow-up commit once a working build configuration is identified.");
    }
}
