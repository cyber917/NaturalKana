using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media.Imaging;
using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.Win;

public sealed record Capture(IntPtr Window, string Text, Native.POINT Anchor, bool AutoSelected);

/// Gets the sentence the user wants checked and writes the chosen suggestion back,
/// using copy/paste so it works in any app. The user's clipboard is restored afterwards.
public static class TextBridge
{
    const ushort VK_C = 0x43, VK_V = 0x56;

    sealed record ClipboardSnapshot(string? Text, BitmapSource? Image, StringCollection? Files)
    {
        public static ClipboardSnapshot Take()
        {
            try
            {
                return new(Clipboard.ContainsText() ? Clipboard.GetText() : null,
                           Clipboard.ContainsImage() ? Clipboard.GetImage() : null,
                           Clipboard.ContainsFileDropList() ? Clipboard.GetFileDropList() : null);
            }
            catch (System.Runtime.InteropServices.COMException) { return new(null, null, null); }
        }

        public void Restore()
        {
            Retry(() =>
            {
                if (Text is null && Image is null && Files is null) { Clipboard.Clear(); return; }
                var data = new DataObject();
                if (Text is not null) data.SetText(Text);
                if (Image is not null) data.SetImage(Image);
                if (Files is not null) data.SetFileDropList(Files);
                Clipboard.SetDataObject(data, true);
            });
        }
    }

    static void Retry(Action action)
    {
        for (var i = 0; i < 10; i++)
        {
            try { action(); return; }
            catch (System.Runtime.InteropServices.COMException) { Thread.Sleep(30); }
        }
    }

    static async Task WaitForModifiersReleased()
    {
        for (var i = 0; i < 100 && Native.AnyModifierDown(); i++) await Task.Delay(10);
    }

    static async Task<string?> CopyAsync()
    {
        var before = Native.GetClipboardSequenceNumber();
        Native.Chord(Native.VK_CONTROL, VK_C);
        for (var i = 0; i < 40; i++)
        {
            await Task.Delay(15);
            if (Native.GetClipboardSequenceNumber() != before)
            {
                await Task.Delay(20);
                string? text = null;
                Retry(() => text = Clipboard.ContainsText() ? Clipboard.GetText() : null);
                return string.IsNullOrWhiteSpace(text) ? null : text;
            }
        }
        return null;
    }

    /// Selected text, or (when nothing is selected) the whole input box / the line before the caret.
    public static async Task<Capture?> CaptureAsync(NoSelectionScope scope)
    {
        var window = Native.GetForegroundWindow();
        var anchor = CaretPosition(window);
        await WaitForModifiersReleased();
        var saved = ClipboardSnapshot.Take();
        try
        {
            var text = await CopyAsync();
            var hadSelection = text is not null;
            if (text is null && scope == NoSelectionScope.WholeField)
            {
                Native.Chord(Native.VK_CONTROL, Native.VK_A);
                await Task.Delay(30);
                text = await CopyAsync();
            }
            // Current line, also the fallback for boxes that ignore Ctrl+A.
            if (text is null)
            {
                Native.Chord(Native.VK_SHIFT, Native.VK_HOME);
                await Task.Delay(30);
                text = await CopyAsync();
            }
            return text is null ? null : new Capture(window, text.Trim(), anchor, AutoSelected: !hadSelection);
        }
        finally { saved.Restore(); }
    }

    /// Replace the current selection in the foreground app with text.
    public static async Task PasteAsync(IntPtr window, string text)
    {
        var saved = ClipboardSnapshot.Take();
        Retry(() => Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true));
        if (window != IntPtr.Zero) Native.ForceForeground(window);
        await Task.Delay(80);
        await WaitForModifiersReleased();
        Native.Chord(Native.VK_CONTROL, VK_V);
        // Give the target app time to read the clipboard before restoring it.
        await Task.Delay(600);
        saved.Restore();
    }

    /// Put text on the clipboard for the user to paste manually.
    public static void Copy(string text) =>
        Retry(() => Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true));

    /// Return focus; collapse a selection we made ourselves so the user's text is not left highlighted.
    public static async Task RefocusAsync(IntPtr window, bool collapseSelection)
    {
        Native.ForceForeground(window);
        if (!collapseSelection) return;
        await Task.Delay(60);
        await WaitForModifiersReleased();
        Native.SendKeys((Native.VK_RIGHT, false), (Native.VK_RIGHT, true));
    }

    /// Text caret position in screen pixels; falls back to the mouse pointer for apps without a system caret.
    public static Native.POINT CaretPosition(IntPtr window)
    {
        var thread = Native.GetWindowThreadProcessId(window, out _);
        var info = new Native.GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.GUITHREADINFO>() };
        if (Native.GetGUIThreadInfo(thread, ref info) && info.hwndCaret != IntPtr.Zero)
        {
            var point = new Native.POINT { X = info.rcCaret.Left, Y = info.rcCaret.Bottom };
            if (Native.ClientToScreen(info.hwndCaret, ref point) && (point.X != 0 || point.Y != 0)) return point;
        }
        Native.GetCursorPos(out var cursor);
        return cursor;
    }
}
