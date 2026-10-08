using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media.Imaging;

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

    public static async Task<Capture?> CaptureAsync()
    {
        var window = Native.GetForegroundWindow();
        var anchor = CaretPosition(window);
        await WaitForModifiersReleased();
        var saved = ClipboardSnapshot.Take();
        try
        {
            var text = await CopyAsync();
            var autoSelected = false;
            if (text is null)
            {
                // Nothing selected: select from the caret back to the start of the line.
                Native.Chord(Native.VK_SHIFT, Native.VK_HOME);
                await Task.Delay(30);
                text = await CopyAsync();
                autoSelected = text is not null;
            }
            return text is null ? null : new Capture(window, text.Trim(), anchor, autoSelected);
        }
        finally { saved.Restore(); }
    }

    public static async Task PasteAsync(IntPtr window, string text)
    {
        var saved = ClipboardSnapshot.Take();
        Retry(() => Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true));
        Native.ForceForeground(window);
        await Task.Delay(80);
        await WaitForModifiersReleased();
        Native.Chord(Native.VK_CONTROL, VK_V);
        // Give the target app time to read the clipboard before restoring it.
        await Task.Delay(600);
        saved.Restore();
    }

    public static void Refocus(IntPtr window) => Native.ForceForeground(window);

    /// Text caret position in screen pixels; falls back to the mouse pointer for apps without a system caret.
    static Native.POINT CaretPosition(IntPtr window)
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
