using System.Windows.Input;
using System.Windows.Interop;

namespace NaturalKana.Windows.Win;

/// Global hotkeys via RegisterHotKey on a message-only window.
public sealed class HotkeyHost : IDisposable
{
    readonly HwndSource source;
    readonly Dictionary<int, Action> actions = new();
    int nextTemporary = 100;

    public HotkeyHost()
    {
        source = new HwndSource(new HwndSourceParameters("NaturalKanaHotkeys") { ParentWindow = new IntPtr(-3) });
        source.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
        {
            if (msg == Native.WM_HOTKEY && actions.TryGetValue(wParam.ToInt32(), out var action)) { handled = true; action(); }
            return IntPtr.Zero;
        });
    }

    /// "Ctrl+Alt+J" → modifiers and virtual key. At least one of Ctrl/Alt/Win is required.
    public static (uint modifiers, uint vk)? Parse(string text)
    {
        uint modifiers = 0;
        Key? key = null;
        foreach (var part in text.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": modifiers |= Native.MOD_CONTROL; break;
                case "alt": modifiers |= Native.MOD_ALT; break;
                case "shift": modifiers |= Native.MOD_SHIFT; break;
                case "win": modifiers |= Native.MOD_WIN; break;
                default:
                    if (key is not null || !Enum.TryParse<Key>(part, true, out var k)) return null;
                    key = k;
                    break;
            }
        }
        if (key is null || (modifiers & (Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_WIN)) == 0 && key != Key.Escape) return null;
        return (modifiers, (uint)KeyInterop.VirtualKeyFromKey(key.Value));
    }

    /// Display/storage form of a key combination, e.g. "Ctrl+Shift+J".
    public static string? Format(ModifierKeys modifiers, Key key)
    {
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift
            or Key.LWin or Key.RWin or Key.System or Key.ImeProcessed or Key.None) return null;
        var parts = new List<string>();
        if (modifiers.HasFlag(ModifierKeys.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(ModifierKeys.Windows)) parts.Add("Win");
        if (!modifiers.HasFlag(ModifierKeys.Control) && !modifiers.HasFlag(ModifierKeys.Alt) && !modifiers.HasFlag(ModifierKeys.Windows)) return null;
        parts.Add(key.ToString());
        return string.Join("+", parts);
    }

    /// Returns false when another app already owns the combination.
    public bool Register(int id, string text, Action action)
    {
        Unregister(id);
        if (Parse(text) is not { } parsed) return false;
        if (!Native.RegisterHotKey(source.Handle, id, parsed.modifiers | Native.MOD_NOREPEAT, parsed.vk)) return false;
        actions[id] = action;
        return true;
    }

    public void Unregister(int id)
    {
        if (actions.Remove(id)) Native.UnregisterHotKey(source.Handle, id);
    }

    /// Registers a set of hotkeys that are removed together (used while a card is visible).
    public IDisposable RegisterTemporary(IEnumerable<(string keys, Action action)> items)
    {
        var ids = new List<int>();
        foreach (var (keys, action) in items)
        {
            var id = nextTemporary++;
            if (Register(id, keys, action)) ids.Add(id);
        }
        return new Release(() => ids.ForEach(Unregister));
    }

    sealed class Release(Action action) : IDisposable { public void Dispose() => action(); }

    public void Dispose()
    {
        foreach (var id in actions.Keys.ToList()) Unregister(id);
        source.Dispose();
    }
}
