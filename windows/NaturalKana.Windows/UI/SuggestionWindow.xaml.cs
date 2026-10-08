using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.Win;

namespace NaturalKana.Windows.UI;

/// Floating candidate card shown near the caret.
public partial class SuggestionWindow : Window
{
    readonly Native.POINT anchor;
    readonly string draft;
    readonly bool highlight;
    readonly SuggestionLanguage language;
    readonly List<Border> rows = [];
    IReadOnlyList<Suggestion> suggestions = [];
    int selected = -1;
    bool finished;

    /// Raised with the chosen text, or null when the user dismissed the card.
    public event Action<string?, bool>? Finished;

    public SuggestionWindow(string draft, Native.POINT anchor, bool highlight, SuggestionLanguage language)
    {
        InitializeComponent();
        // Digits must reach the window directly even when a Japanese IME is active.
        InputMethod.SetIsInputMethodEnabled(this, false);
        this.draft = draft;
        this.anchor = anchor;
        this.highlight = highlight;
        this.language = language;
        Draft.Text = draft;
        ShowRequesting();
        SourceInitialized += (_, _) => Reposition();
        SizeChanged += (_, _) => Reposition();
        Deactivated += (_, _) => Finish(null, refocus: false);
        PreviewKeyDown += OnKey;
    }

    public void ShowRequesting() => SetStatus("正在获取建议…", Theme.Gray);

    public void ShowMessage(string message, bool warning = false)
    {
        Items.Children.Clear();
        rows.Clear();
        suggestions = [];
        Hint.Visibility = Visibility.Collapsed;
        SetStatus(message, warning ? Theme.Warning : Theme.Ink);
    }

    void SetStatus(string text, Brush color)
    {
        Status.Text = text;
        Status.Foreground = color;
        Status.Visibility = Visibility.Visible;
    }

    public void ShowSuggestions(IReadOnlyList<Suggestion> items)
    {
        suggestions = items;
        Items.Children.Clear();
        rows.Clear();
        Status.Visibility = Visibility.Collapsed;
        Hint.Visibility = Visibility.Visible;
        Register? group = null;
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (item.Register != group)
            {
                group = item.Register;
                Items.Children.Add(new TextBlock
                {
                    Text = Languages.RegisterTitle(language, item.Register),
                    FontSize = 12, Foreground = Theme.Light,
                    Margin = new Thickness(0, Items.Children.Count == 0 ? 2 : 10, 0, 4),
                });
            }
            Items.Children.Add(Row(i, item));
        }
        Select(0);
    }

    Border Row(int index, Suggestion item)
    {
        var text = new TextBlock { FontFamily = Theme.Japanese, FontSize = 16, TextWrapping = TextWrapping.Wrap, Foreground = Theme.Ink };
        foreach (var span in highlight ? SuggestionDiff.Spans(draft, item.Text) : [new SuggestionSpan(item.Text, false)])
            text.Inlines.Add(new Run(span.Text) { Foreground = span.Changed ? Theme.Blue : Theme.Ink });

        var number = new TextBlock
        {
            Text = index < 9 ? (index + 1).ToString() : index == 9 ? "0" : "",
            Width = 22, FontSize = 13, Foreground = Theme.Light, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 2, 0, 0),
        };
        var panel = new DockPanel();
        DockPanel.SetDock(number, Dock.Left);
        panel.Children.Add(number);
        panel.Children.Add(text);

        var row = new Border { Child = panel, Padding = new Thickness(10, 7, 10, 7), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand, Background = Brushes.Transparent };
        row.MouseEnter += (_, _) => Select(index);
        row.MouseLeftButtonUp += (_, _) => Accept(index);
        rows.Add(row);
        return row;
    }

    void Select(int index)
    {
        if (rows.Count == 0) return;
        selected = Math.Clamp(index, 0, rows.Count - 1);
        for (var i = 0; i < rows.Count; i++) rows[i].Background = i == selected ? Theme.Hover : Brushes.Transparent;
    }

    void OnKey(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape: Finish(null, refocus: true); break;
            case Key.Down: Select(selected + 1); break;
            case Key.Up: Select(selected - 1); break;
            case Key.Enter when selected >= 0: Accept(selected); break;
            case >= Key.D1 and <= Key.D9: Accept(e.Key - Key.D1); break;
            case >= Key.NumPad1 and <= Key.NumPad9: Accept(e.Key - Key.NumPad1); break;
            case Key.D0 or Key.NumPad0: Accept(9); break;
            default: return;
        }
        e.Handled = true;
    }

    void Accept(int index)
    {
        if (index >= 0 && index < suggestions.Count) Finish(suggestions[index].Text, refocus: true);
    }

    void Finish(string? text, bool refocus)
    {
        if (finished) return;
        finished = true;
        Hide();
        Finished?.Invoke(text, refocus);
        Close();
    }

    public void ShowNearCaret()
    {
        Show();
        Activate();
        Native.ForceForeground(new WindowInteropHelper(this).Handle);
    }

    /// Place the card below the caret (above it if there is no room), within the monitor work area.
    void Reposition()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero || !Native.GetWindowRect(hwnd, out var rect)) return;
        int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
        var info = new Native.MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFO>() };
        Native.GetMonitorInfo(Native.MonitorFromPoint(anchor, 2), ref info);
        var work = info.rcWork;
        var scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        var shadow = (int)(18 * scale);
        int x = anchor.X - shadow, y = anchor.Y + (int)(6 * scale) - shadow;
        if (y + height > work.Bottom) y = anchor.Y - height - (int)(28 * scale) + shadow;
        x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - width));
        y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - height));
        const uint SWP_NOSIZE = 0x1, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10;
        Native.SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
}
