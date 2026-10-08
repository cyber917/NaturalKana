using System.Windows.Media;

namespace NaturalKana.Windows.UI;

/// Minimal palette shared by all windows: black/gray text, one blue accent.
static class Theme
{
    public static readonly Brush Ink = Brush(0x1D, 0x1D, 0x1F);
    public static readonly Brush Gray = Brush(0x6E, 0x6E, 0x73);
    public static readonly Brush Light = Brush(0xAE, 0xAE, 0xB2);
    public static readonly Brush Line = Brush(0xE5, 0xE5, 0xEA);
    public static readonly Brush Hover = Brush(0xF2, 0xF2, 0xF7);
    public static readonly Brush Blue = Brush(0x00, 0x71, 0xE3);
    public static readonly Brush Warning = Brush(0xC9, 0x34, 0x00);
    public static readonly FontFamily Japanese = new("Yu Gothic UI, Microsoft YaHei UI, Segoe UI");
    public static readonly FontFamily Chinese = new("Microsoft YaHei UI, Segoe UI");

    static SolidColorBrush Brush(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
