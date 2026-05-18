using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.Core;

namespace MacCleaner.Win.App.Views;

public sealed partial class PaintPage : Page
{
    public PaintPage()
    {
        InitializeComponent();
    }

    private void Canvas_Loaded(object sender, RoutedEventArgs e)
    {
        // Accept pen + touch + mouse, mirroring the macOS Paint module's
        // "any pointer works" behaviour. InkCanvas defaults to pen only.
        Canvas.InkPresenter.InputDeviceTypes =
            CoreInputDeviceTypes.Mouse |
            CoreInputDeviceTypes.Pen |
            CoreInputDeviceTypes.Touch;
    }

    private void ClearButton_Click(object sender, RoutedEventArgs e)
    {
        Canvas.InkPresenter.StrokeContainer.Clear();
    }
}
