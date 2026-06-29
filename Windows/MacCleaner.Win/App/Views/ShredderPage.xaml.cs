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
        Header.Title = Localization.Loc.Get("Shredder_Title", "Shredder");
        Header.Subtitle = Localization.Loc.Get("Shredder_Subtitle", "Overwrite then delete");
        SsdWarning.Text = Localization.Loc.Get("Shredder_SsdWarning", "On SSDs, wear leveling may relocate blocks, so overwrite-then-delete cannot guarantee the original ciphertext is destroyed. Use full-disk BitLocker for SSDs you intend to dispose of.");
        PathBox.PlaceholderText = Localization.Loc.Get("Shredder_PathPlaceholder", "Absolute path to a single file");
        ShredButton.Content = Localization.Loc.Get("Shredder_Shred", "Shred");
        PassesLabel.Text = Localization.Loc.Get("Shredder_Passes", "Passes:");
    }

    private async void ShredButton_Click(object sender, RoutedEventArgs e)
    {
        string path = PathBox.Text.Trim();
        if (string.IsNullOrEmpty(path) || !File.Exists(path))
        {
            StatusText.Text = Localization.Loc.Get("Shredder_BadPath", "Path does not point to an existing file.");
            return;
        }

        var dialog = new ContentDialog
        {
            Title = Localization.Loc.Get("Shredder_DialogTitle", "Shred this file?"),
            Content = string.Format(Localization.Loc.Get("Shredder_DialogContentFormat", "{0} will be overwritten {1} time(s) with random bytes and then deleted. This cannot be undone."), path, (int)PassesBox.Value),
            PrimaryButtonText = Localization.Loc.Get("Shredder_Shred", "Shred"),
            CloseButtonText = Localization.Loc.Get("Common_Cancel", "Cancel"),
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = this.XamlRoot
        };
        var choice = await dialog.ShowAsync();
        if (choice != ContentDialogResult.Primary) return;

        ShredButton.IsEnabled = false;
        StatusText.Text = Localization.Loc.Get("Shredder_Shredding", "Shredding…");
        var result = await _shredder.ShredAsync(path, (int)PassesBox.Value);
        StatusText.Text = result.Succeeded
            ? Localization.Loc.Get("Shredder_Done", "File shredded.")
            : string.Format(Localization.Loc.Get("Common_FailedFormat", "Failed: {0}"), result.ErrorMessage);
        ShredButton.IsEnabled = true;
    }
}
