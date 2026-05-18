using MacCleaner.Win.App.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;

namespace MacCleaner.Win.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "MacCleaner for Windows";
        ContentFrame.Navigate(typeof(StubPage), Modules.Get("dashboard"));
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(StubPage), new ModuleDescriptor(
                "settings", "Settings", "App preferences",
                "", Color.FromArgb(255, 142, 142, 147)));
            return;
        }

        if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
        {
            ContentFrame.Navigate(typeof(StubPage), Modules.Get(tag));
        }
    }
}
