using MacCleaner.Win.Core.Tools;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MacCleaner.Win.App.Views;

public sealed partial class ShredderPage : Page
{
    private readonly IShredderService _shredder;

    public ShredderPage()
    {
        InitializeComponent();
        _shredder = App.Services.GetRequiredService<IShredderService>();
    }

    private async void ShredButton_Click(object sender, RoutedEventArgs e)
    {
        string path = PathBox.Text.Trim();
        if (string.IsNullOrEmpty(path) || !File.Exists(path))
        {
            StatusText.Text = "Path does not point to an existing file.";
            return;
        }

        var dialog = new ContentDialog
        {
            Title = "Shred this file?",
            Content = $"{path} will be overwritten {(int)PassesBox.Value} time(s) with random bytes and then deleted. This cannot be undone.",
            PrimaryButtonText = "Shred",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };
        var choice = await dialog.ShowAsync();
        if (choice != ContentDialogResult.Primary) return;

        ShredButton.IsEnabled = false;
        StatusText.Text = "Shredding…";
        var result = await _shredder.ShredAsync(path, (int)PassesBox.Value);
        StatusText.Text = result.Succeeded ? "File shredded." : $"Failed: {result.ErrorMessage}";
        ShredButton.IsEnabled = true;
    }
}
