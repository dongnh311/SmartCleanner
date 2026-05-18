using H.NotifyIcon;
using Microsoft.UI.Xaml.Controls;

namespace MacCleaner.Win.App.Hosts;

/// <summary>
/// Owns the system-tray <see cref="TaskbarIcon"/>. App.xaml.cs constructs
/// this once after the main window is shown so the icon lives for the
/// entire process. The menu items are scaffolds — click handlers will
/// route to actual navigation once Phase 2 wires real pages.
/// </summary>
public sealed class NotifyIconHost : IDisposable
{
    private readonly TaskbarIcon _icon;
    private readonly Action _showMainWindow;
    private readonly Action _exitApp;

    public NotifyIconHost(Action showMainWindow, Action exitApp)
    {
        _showMainWindow = showMainWindow;
        _exitApp = exitApp;

        var menu = new MenuFlyout();

        var open = new MenuFlyoutItem { Text = "Open MacCleaner" };
        open.Click += (_, _) => _showMainWindow();
        menu.Items.Add(open);
        menu.Items.Add(new MenuFlyoutSeparator());

        var quick = new MenuFlyoutItem { Text = "Quick Clean" };
        quick.Click += (_, _) => _showMainWindow();
        menu.Items.Add(quick);

        var dash = new MenuFlyoutItem { Text = "Dashboard" };
        dash.Click += (_, _) => _showMainWindow();
        menu.Items.Add(dash);

        menu.Items.Add(new MenuFlyoutSeparator());

        var exit = new MenuFlyoutItem { Text = "Exit" };
        exit.Click += (_, _) => _exitApp();
        menu.Items.Add(exit);

        _icon = new TaskbarIcon
        {
            ToolTipText = "MacCleaner",
            ContextFlyout = menu
        };
        _icon.ForceCreate();
        _icon.LeftClickCommand = new RelayCommand(() => _showMainWindow());
    }

    public void Dispose() => _icon.Dispose();

    private sealed class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action _execute;
        public RelayCommand(Action execute) { _execute = execute; }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _execute();
        public event EventHandler? CanExecuteChanged { add { } remove { } }
    }
}
