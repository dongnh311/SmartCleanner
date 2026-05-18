using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace MacCleaner.Win.App.Controls;

/// <summary>
/// Standard module header — port of macOS <c>Core/UI/ModuleHeader.swift</c>.
/// Hosts a gradient icon backdrop on the left, a title/subtitle stack in the
/// middle, and a trailing slot for action buttons via the <c>Trailing</c>
/// property.
/// </summary>
public sealed partial class ModuleHeader : UserControl
{
    public ModuleHeader()
    {
        InitializeComponent();
        ApplyAccent(Accent);
    }

    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(ModuleHeader),
            new PropertyMetadata("", (d, e) => ((ModuleHeader)d).TitleText.Text = (string)e.NewValue));

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public static readonly DependencyProperty SubtitleProperty =
        DependencyProperty.Register(nameof(Subtitle), typeof(string), typeof(ModuleHeader),
            new PropertyMetadata("", (d, e) => ((ModuleHeader)d).SubtitleText.Text = (string)e.NewValue));

    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    public static readonly DependencyProperty IconGlyphProperty =
        DependencyProperty.Register(nameof(IconGlyphChar), typeof(string), typeof(ModuleHeader),
            new PropertyMetadata("", (d, e) => ((ModuleHeader)d).IconGlyph.Glyph = (string)e.NewValue));

    /// <summary>Segoe Fluent Icons glyph (hex code as string, e.g. "").</summary>
    public string IconGlyphChar
    {
        get => (string)GetValue(IconGlyphProperty);
        set => SetValue(IconGlyphProperty, value);
    }

    public static readonly DependencyProperty AccentProperty =
        DependencyProperty.Register(nameof(Accent), typeof(Color), typeof(ModuleHeader),
            new PropertyMetadata(Colors.SteelBlue, (d, e) => ((ModuleHeader)d).ApplyAccent((Color)e.NewValue)));

    public Color Accent
    {
        get => (Color)GetValue(AccentProperty);
        set => SetValue(AccentProperty, value);
    }

    public static readonly DependencyProperty TrailingProperty =
        DependencyProperty.Register(nameof(Trailing), typeof(object), typeof(ModuleHeader),
            new PropertyMetadata(null, (d, e) => ((ModuleHeader)d).TrailingSlot.Content = e.NewValue));

    public object? Trailing
    {
        get => GetValue(TrailingProperty);
        set => SetValue(TrailingProperty, value);
    }

    private void ApplyAccent(Color accent)
    {
        var lightStop = Color.FromArgb(46, accent.R, accent.G, accent.B);   // ~0.18 alpha
        var darkStop = Color.FromArgb(15, accent.R, accent.G, accent.B);    // ~0.06 alpha
        var strokeColor = Color.FromArgb(64, accent.R, accent.G, accent.B); // ~0.25 alpha

        IconBackdrop.Background = new LinearGradientBrush
        {
            StartPoint = new Windows.Foundation.Point(0, 0),
            EndPoint = new Windows.Foundation.Point(1, 1),
            GradientStops =
            {
                new GradientStop { Color = lightStop, Offset = 0 },
                new GradientStop { Color = darkStop, Offset = 1 }
            }
        };
        IconBackdrop.BorderBrush = new SolidColorBrush(strokeColor);
        IconGlyph.Foreground = new SolidColorBrush(accent);
    }
}
