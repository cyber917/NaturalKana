using System.Windows.Input;
using System.Windows.Interop;

namespace NaturalKana.Windows.Win;

/// Global hotkey via RegisterHotKey on a message-only window.
public sealed class Hotkey : IDisposable
{
    const int Id = 0x4E4B;
    readonly HwndSource source;
    public event Action? Pressed;
    public string? Registered { get; private set; }

    public Hotkey()
    {
        source = new HwndSource(new HwndSourceParameters("NaturalKanaHotkey") { ParentWindow = new IntPtr(-3) });
        source.AddHook((IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) =>
        {
            if (msg == Native.WM_HOTKEY && wParam.ToInt32() == Id) { handled = true; Pressed?.Invoke(); }
            return IntPtr.Zero;
        });
    }

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
                default: if (Enum.TryParse<Key>(part, true, out var k)) key = k; else return null; break;
            }
        }
        if (key is null || modifiers == 0) return null;
        return (modifiers, (uint)KeyInterop.VirtualKeyFromKey(key.Value));
    }

    /// Returns false when another app already owns the combination.
    public bool Register(string text)
    {
        Native.UnregisterHotKey(source.Handle, Id);
        Registered = null;
        if (Parse(text) is not { } parsed) return false;
        if (!Native.RegisterHotKey(source.Handle, Id, parsed.modifiers | Native.MOD_NOREPEAT, parsed.vk)) return false;
        Registered = text;
        return true;
    }

    public void Dispose()
    {
        Native.UnregisterHotKey(source.Handle, Id);
        source.Dispose();
    }
}
