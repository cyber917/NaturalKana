using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media.Imaging;
using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.Win;

public sealed record Capture(IntPtr Window, string Text, Native.POINT Anchor, bool AutoSelected, bool WholeField, IntPtr Focus);

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

    static async Task<bool> WaitForModifiersReleased()
    {
        for (var i = 0; i < 100 && Native.AnyModifierDown(); i++) await Task.Delay(10);
        return !Native.AnyModifierDown();
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

    static IntPtr FocusedControl(IntPtr window)
    {
        var thread = Native.GetWindowThreadProcessId(window, out _);
        var info = new Native.GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.GUITHREADINFO>() };
        return Native.GetGUIThreadInfo(thread, ref info) ? info.hwndFocus : IntPtr.Zero;
    }

    sealed class TargetSelection(IntPtr window, IntPtr focus) : ITextSelection
    {
        public bool IsTargetActive => Native.IsWindow(window) && Native.GetForegroundWindow() == window
            && (focus == IntPtr.Zero || FocusedControl(window) == focus);
        public async Task<string?> CopyAsync()
        {
            if (!IsTargetActive) return null;
            var text = await TextBridge.CopyAsync();
            return IsTargetActive ? text : null;
        }
        public async Task SelectAllAsync()
        {
            if (!IsTargetActive) return;
            Native.Chord(Native.VK_CONTROL, Native.VK_A);
            await Task.Delay(30);
        }
        public async Task SelectLineAsync()
        {
            if (!IsTargetActive) return;
            Native.Chord(Native.VK_SHIFT, Native.VK_HOME);
            await Task.Delay(30);
        }
        public async Task<bool> PasteAsync(string text)
        {
            if (!await WaitForModifiersReleased() || !IsTargetActive) return false;
            return await PasteIntoTargetAsync(text, () => IsTargetActive);
        }
    }

    /// Selected text, or the configured fallback; selectAll always checks the whole input box.
    public static async Task<Capture?> CaptureAsync(NoSelectionScope scope, bool selectAll = false)
    {
        var window = Native.GetForegroundWindow();
        var focus = FocusedControl(window);
        var anchor = CaretPosition(window);
        if (!await WaitForModifiersReleased()) return null;
        var saved = ClipboardSnapshot.Take();
        try
        {
            var text = await TextSelection.CaptureAsync(new TargetSelection(window, focus), scope, selectAll);
            return text is null ? null : new Capture(window, text.Text, anchor, text.AutoSelected, text.WholeField, focus);
        }
        finally { saved.Restore(); }
    }

    public static async Task<bool> ReplaceAsync(Capture capture, string replacement)
    {
        if (!Native.IsWindow(capture.Window) || !await WaitForModifiersReleased()) return false;
        Native.ForceForeground(capture.Window);
        await Task.Delay(80);
        var saved = ClipboardSnapshot.Take();
        try
        {
            var text = new CapturedText(capture.Text, capture.AutoSelected, capture.WholeField);
            return await TextSelection.ReplaceAsync(new TargetSelection(capture.Window, capture.Focus), text, replacement);
        }
        finally { saved.Restore(); }
    }

    /// Replace the current selection in the foreground app with text.
    public static async Task<bool> PasteAsync(IntPtr window, string text)
    {
        if (window != IntPtr.Zero) Native.ForceForeground(window);
        else window = Native.GetForegroundWindow();
        var focus = FocusedControl(window);
        await Task.Delay(80);
        if (!await WaitForModifiersReleased()) return false;
        var target = new TargetSelection(window, focus);
        return await PasteIntoTargetAsync(text, () => target.IsTargetActive);
    }

    static async Task<bool> PasteIntoTargetAsync(string text, Func<bool> isTargetActive)
    {
        if (!isTargetActive()) return false;
        var saved = ClipboardSnapshot.Take();
        try
        {
            var written = false;
            Retry(() => { Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true); written = true; });
            if (!written || !isTargetActive()) return false;
            Native.Chord(Native.VK_CONTROL, VK_V);
            // Give the target app time to read the clipboard before restoring it.
            await Task.Delay(600);
            return true;
        }
        finally { saved.Restore(); }
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
        if (!await WaitForModifiersReleased() || Native.GetForegroundWindow() != window) return;
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
