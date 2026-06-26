using MacCleaner.Win.App.Localization;
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
        LocalizeNav();
        NavigateTo("dashboard");
    }

    /// <summary>
    /// Translates the navigation pane (items + section headers) from the
    /// resource catalogue. Done in code with an English fallback so a missing
    /// resource never blanks the sidebar.
    /// </summary>
    private void LocalizeNav()
    {
        foreach (var entry in Nav.MenuItems)
        {
            switch (entry)
            {
                case NavigationViewItem item when item.Tag is string tag:
                    item.Content = Loc.Get("Nav_" + tag, item.Content as string ?? tag);
                    break;
                case NavigationViewItemHeader header when header.Content is string text:
                    header.Content = Loc.Get("NavSection_" + text, text);
                    break;
            }
        }
    }

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage));
            return;
        }

        if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
        {
            NavigateTo(tag);
        }
    }

    /// <summary>Routes a nav tag to its real page if Phase 2+ shipped one;
    /// otherwise falls through to the generic stub. Add cases here as
    /// modules land.</summary>
    private void NavigateTo(string tag)
    {
        Type pageType = tag switch
        {
            "dashboard"  => typeof(DashboardPage),
            "processes"  => typeof(ProcessMonitorPage),
            "memory"     => typeof(MemoryPage),
            "battery"    => typeof(BatteryPage),
            "network"    => typeof(NetworkPage),
            "diskmon"    => typeof(DiskMonitorPage),
            "bluetooth"  => typeof(BluetoothPage),
            "sensors"    => typeof(SensorsPage),
            "loginitems" => typeof(LoginItemsPage),
            "maintenance"=> typeof(MaintenancePage),
            "malware"    => typeof(MalwarePage),
            "uninstaller"=> typeof(UninstallerPage),
            "updater"    => typeof(UpdaterPage),
            "quickclean" => typeof(QuickCleanPage),
            "recyclebin" => typeof(RecycleBinPage),
            "spacelens"  => typeof(SpaceLensPage),
            "largeold"   => typeof(LargeOldFilesPage),
            "duplicates" => typeof(DuplicatesPage),
            "similar"    => typeof(SimilarPhotosPage),
            "shredder"   => typeof(ShredderPage),
            "quarantine" => typeof(QuarantinePage),
            "mytools"    => typeof(MyToolsPage),
            "clock"      => typeof(ClockPage),
            "paint"      => typeof(PaintPage),
            "scroll"     => typeof(ScrollDenoiserPage),
            _            => typeof(StubPage)
        };

        object? parameter = pageType == typeof(StubPage) ? Modules.Get(tag) : null;
        ContentFrame.Navigate(pageType, parameter);
    }
}
