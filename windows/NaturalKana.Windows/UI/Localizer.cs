using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.UI;

/// Translates the Chinese text written in XAML into the current interface language.
/// The original text is remembered, so the window can be re-translated after the language changes.
static class Localizer
{
    static readonly ConditionalWeakTable<DependencyObject, Dictionary<DependencyProperty, string>> Originals = new();

    /// Call once before code sets any dynamic text (capture), then with capture: false after a language change,
    /// which only re-translates the XAML text remembered on the first pass.
    public static void Apply(DependencyObject root, bool capture = true)
    {
        if (root is FrameworkElement element) Translate(element, FrameworkElement.ToolTipProperty, capture);
        switch (root)
        {
            // Items are filled from code with already translated titles.
            case ComboBox: return;
            // A TextBlock with plain Text holds a single run; translating both would translate twice.
            case TextBlock block when block.Inlines.Count <= 1: Translate(block, TextBlock.TextProperty, capture); return;
            case Run run: Translate(run, Run.TextProperty, capture); return;
            case Window window: Translate(window, Window.TitleProperty, capture); break;
            case HeaderedContentControl headered: Translate(headered, HeaderedContentControl.HeaderProperty, capture); Translate(headered, ContentControl.ContentProperty, capture); break;
            case ContentControl content: Translate(content, ContentControl.ContentProperty, capture); break;
        }
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>()) Apply(child, capture);
    }

    static void Translate(DependencyObject target, DependencyProperty property, bool capture)
    {
        var originals = Originals.GetOrCreateValue(target);
        if (!originals.TryGetValue(property, out var source))
        {
            if (!capture || target.GetValue(property) is not string text || !text.Any(c => c >= 0x3000)) return;
            originals[property] = source = text;
        }
        target.SetValue(property, UIText.T(source));
    }
}
