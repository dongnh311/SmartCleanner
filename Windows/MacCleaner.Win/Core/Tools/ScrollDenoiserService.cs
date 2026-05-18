using System.Runtime.InteropServices;

namespace MacCleaner.Win.Core.Tools;

public interface IScrollDenoiserService
{
    bool IsEnabled { get; }
    void Enable();
    void Disable();
}

/// <summary>
/// Direction-lock filter for cheap scroll wheels — port of the
/// <c>scroll_denoiser.ahk</c> behaviour shipped on macOS. Installs a
/// low-level mouse hook (WH_MOUSE_LL) and discards wheel events whose
/// direction reverses within <see cref="LockMs"/> of the previous one.
/// </summary>
public sealed class ScrollDenoiserService : IScrollDenoiserService, IDisposable
{
    private const int WH_MOUSE_LL = 14;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int LockMs = 80;

    private LowLevelMouseProc? _proc;
    private IntPtr _hookHandle = IntPtr.Zero;
    private int _lastDirection;
    private long _lastWheelAtMs;
    private readonly object _lock = new();

    public bool IsEnabled => _hookHandle != IntPtr.Zero;

    public void Enable()
    {
        lock (_lock)
        {
            if (_hookHandle != IntPtr.Zero) return;
            _proc = HookProc;
            using var module = System.Diagnostics.Process.GetCurrentProcess().MainModule;
            IntPtr hMod = GetModuleHandle(module?.ModuleName);
            _hookHandle = SetWindowsHookEx(WH_MOUSE_LL, _proc, hMod, 0);
        }
    }

    public void Disable()
    {
        lock (_lock)
        {
            if (_hookHandle == IntPtr.Zero) return;
            UnhookWindowsHookEx(_hookHandle);
            _hookHandle = IntPtr.Zero;
            _proc = null;
        }
    }

    public void Dispose() => Disable();

    private IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && (int)wParam == WM_MOUSEWHEEL)
        {
            var data = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            short delta = (short)((data.mouseData >> 16) & 0xFFFF);
            int direction = Math.Sign(delta);
            long now = Environment.TickCount64;

            if (direction != 0 && _lastDirection != 0 && direction != _lastDirection
                && (now - _lastWheelAtMs) < LockMs)
            {
                // Suppress reversal during lock window — return 1 (non-zero)
                // to consume the event without passing it down the chain.
                return new IntPtr(1);
            }

            _lastDirection = direction;
            _lastWheelAtMs = now;
        }
        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public int x;
        public int y;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
}
