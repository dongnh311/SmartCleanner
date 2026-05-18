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
            ? "Recycle Bin is empty"
            : $"{info.ItemCount} item(s) across all drives";
        EmptyButton.IsEnabled = info.ItemCount > 0;
    }

    private async void EmptyButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "Empty Recycle Bin?",
            Content = $"This will permanently delete {CountText.Text.ToLowerInvariant()}. This cannot be undone.",
            PrimaryButtonText = "Empty",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };

        var choice = await dialog.ShowAsync();
        if (choice != ContentDialogResult.Primary) return;

        StatusText.Text = "Emptying…";
        EmptyButton.IsEnabled = false;
        await Task.Run(_bin.Empty);
        StatusText.Text = "Done.";
        Refresh();
    }
}
