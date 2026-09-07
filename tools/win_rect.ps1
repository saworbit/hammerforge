# Move/query the Godot editor window. Recording crops to a fixed rect, so the
# window must actually be at that rect: the harness refuses to record otherwise.
#
# The rect is read inside C# and returned as a string. Marshalling a RECT struct
# back through PowerShell's [ref] gives garbage for some fields.
# Parameter names must not be ambiguous prefixes of PowerShell common
# parameters: -W collides with -WarningAction and silently fails to bind.
param([string]$Action = "get", [int]$PosX = 0, [int]$PosY = 0, [int]$Width = 1920,
      [int]$Height = 1080, [string]$Match = "Godot Engine", [string]$ProcessName = "")

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [StructLayout(LayoutKind.Sequential)] private struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
  [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr h, ref POINT p);
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
  // Client-area origin in screen coordinates. The window rect includes border
  // and title bar, so it is not where the editor's contents actually begin.
  public static string Client(IntPtr h) {
    RECT c; GetClientRect(h, out c);
    POINT p; p.X = 0; p.Y = 0; ClientToScreen(h, ref p);
    return p.X + "," + p.Y + "," + (c.R - c.L) + "," + (c.B - c.T);
  }
}
"@

# Narrow to one window. Selecting the first "Godot Engine" window moves
# whichever editor Windows happens to list first, which on a machine with a
# second Godot instance open is the wrong one. -ProcessName is the reliable
# discriminator: it works before the window title mentions a scene.
if ($ProcessName -ne "") {
  $p = Get-Process | Where-Object {
    $_.ProcessName -like "*$ProcessName*" -and $_.MainWindowHandle -ne 0
  } | Select-Object -First 1
} else {
  $p = Get-Process | Where-Object { $_.MainWindowTitle -like "*$Match*" } | Select-Object -First 1
}
if (-not $p) { Write-Output "NOWINDOW"; exit 1 }
$h = $p.MainWindowHandle

if ($Action -eq "set") {
  [Win]::Place($h, $PosX, $PosY, $Width, $Height)
  Start-Sleep -Milliseconds 900
}
if ($Action -eq "client") { Write-Output ([Win]::Client($h)) } else { Write-Output ([Win]::Rect($h)) }
