# Move/query the Godot editor window. Recording crops to a fixed rect, so the
# window must actually be at that rect: the harness refuses to record otherwise.
#
# The rect is read inside C# and returned as a string. Marshalling a RECT struct
# back through PowerShell's [ref] gives garbage for some fields.
# Parameter names must not be ambiguous prefixes of PowerShell common
# parameters: -W collides with -WarningAction and silently fails to bind.
param([string]$Action = "get", [int]$PosX = 0, [int]$PosY = 0, [int]$Width = 1920, [int]$Height = 1080)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [StructLayout(LayoutKind.Sequential)] private struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int n);
  public static void Place(IntPtr h, int x, int y, int w, int hh) {
    ShowWindow(h, 9);
    SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x0040);
    SetForegroundWindow(h);
  }
  public static string Rect(IntPtr h) {
    RECT r; GetWindowRect(h, out r);
    return r.L + "," + r.T + "," + (r.R - r.L) + "," + (r.B - r.T);
  }
}
"@

$p = Get-Process | Where-Object { $_.MainWindowTitle -like '*Godot Engine*' } | Select-Object -First 1
if (-not $p) { Write-Output "NOWINDOW"; exit 1 }
$h = $p.MainWindowHandle

if ($Action -eq "set") {
  [Win]::Place($h, $PosX, $PosY, $Width, $Height)
  Start-Sleep -Milliseconds 900
}
Write-Output ([Win]::Rect($h))
