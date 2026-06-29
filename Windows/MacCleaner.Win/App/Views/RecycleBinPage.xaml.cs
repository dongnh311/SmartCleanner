using MacCleaner.Win.Core.Cleanup;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace MacCleaner.Win.App.Views;

public sealed partial class RecycleBinPage : Page
{
    private readonly IRecycleBinService _bin;

    public RecycleBinPage()
    {
        InitializeComponent();
        _bin = App.Services.GetRequiredService<IRecycleBinService>();
        Header.Title = Localization.Loc.Get("RecycleBin_Title", "Recycle Bin");
        Header.Subtitle = Localization.Loc.Get("RecycleBin_Subtitle", "Empty across all drives");
        RefreshButton.Content = Localization.Loc.Get("Common_Refresh", "Refresh");
        EmptyButton.Content = Localization.Loc.Get("RecycleBin_Empty", "Empty Recycle Bin");
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        Refresh();
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e) => Refresh();

    private void Refresh()
    {
        var info = _bin.Query();
        SizeText.Text = Core.FileSystem.Bytes.Format(info.TotalBytes);
        CountText.Text = info.ItemCount == 0
            ? Localization.Loc.Get("RecycleBin_IsEmpty", "Recycle Bin is empty")
            : string.Format(Localization.Loc.Get("RecycleBin_CountFormat", "{0} item(s) across all drives"), info.ItemCount);
        EmptyButton.IsEnabled = info.ItemCount > 0;
    }

    private async void EmptyButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = Localization.Loc.Get("RecycleBin_DialogTitle", "Empty Recycle Bin?"),
            Content = string.Format(Localization.Loc.Get("RecycleBin_DialogContentFormat", "This will permanently delete {0}. This cannot be undone."), CountText.Text.ToLowerInvariant()),
            PrimaryButtonText = Localization.Loc.Get("Common_EmptyButton", "Empty"),
            CloseButtonText = Localization.Loc.Get("Common_Cancel", "Cancel"),
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };

        var choice = await dialog.ShowAsync();
        if (choice != ContentDialogResult.Primary) return;

        StatusText.Text = Localization.Loc.Get("RecycleBin_Emptying", "Emptying…");
        EmptyButton.IsEnabled = false;
        await Task.Run(_bin.Empty);
        StatusText.Text = Localization.Loc.Get("Common_Done", "Done.");
        Refresh();
    }
}
