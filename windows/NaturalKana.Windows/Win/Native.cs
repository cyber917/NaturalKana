using System.Runtime.InteropServices;

namespace NaturalKana.Windows.Win;

public static class Native
{
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
    public const ushort VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_HOME = 0x24, VK_RIGHT = 0x27, VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_A = 0x41;
    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 0x2, KEYEVENTF_EXTENDEDKEY = 0x1;

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO
    {
        public int cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public INPUTUNION u; }

    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public const int GWL_EXSTYLE = -20, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x80;

    public static void SendKeys(params (ushort vk, bool up)[] keys)
    {
        var inputs = keys.Select(k => new INPUT
        {
            type = INPUT_KEYBOARD,
            u = new INPUTUNION { ki = new KEYBDINPUT { wVk = k.vk, dwFlags = (k.up ? KEYEVENTF_KEYUP : 0) | (k.vk is VK_HOME or VK_RIGHT ? KEYEVENTF_EXTENDEDKEY : 0) } },
        }).ToArray();
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    public static void Chord(ushort modifier, ushort key) =>
        SendKeys((modifier, false), (key, false), (key, true), (modifier, true));

    public static bool AnyModifierDown() =>
        new[] { VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN }.Any(vk => (GetAsyncKeyState(vk) & 0x8000) != 0);

    /// Bring a window to the front even when Windows' foreground lock would refuse.
    public static void ForceForeground(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || SetForegroundWindow(hwnd)) return;
        var target = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        var self = GetCurrentThreadId();
        AttachThreadInput(self, target, true);
        SetForegroundWindow(hwnd);
        AttachThreadInput(self, target, false);
    }
}
