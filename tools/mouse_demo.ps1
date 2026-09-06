# Drive the real OS mouse for a demo beat.
#
# Synthetic events forwarded into the plugin and Input.warp_mouse() conflict:
# warping emits a genuine motion event with no button held, which cancels an
# in-progress drag. Driving the real mouse avoids that entirely and is what a
# viewer sees anyway.
param(
  [int]$AX, [int]$AY,      # drag start
  [int]$BX, [int]$BY,      # drag end
  [int]$CX, [int]$CY       # height click
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] private static extern void mouse_event(uint f, uint x, uint y, uint d, int e);
  public static void Down() { mouse_event(0x0002, 0, 0, 0, 0); }
  public static void Up()   { mouse_event(0x0004, 0, 0, 0, 0); }
}
"@

function Ease([double]$t) { return $t * $t * (3.0 - 2.0 * $t) }

function Glide($x1, $y1, $x2, $y2, $ms) {
  $steps = [int]($ms / 12)
  if ($steps -lt 2) { $steps = 2 }
  for ($i = 1; $i -le $steps; $i++) {
    $t = Ease($i / [double]$steps)
    [void][M]::SetCursorPos([int]($x1 + ($x2 - $x1) * $t), [int]($y1 + ($y2 - $y1) * $t))
    Start-Sleep -Milliseconds 12
  }
}

[void][M]::SetCursorPos($AX, $AY)
Start-Sleep -Milliseconds 900

[M]::Down()
Start-Sleep -Milliseconds 120
Glide $AX $AY $BX $BY 1100
Start-Sleep -Milliseconds 150
[M]::Up()
Start-Sleep -Milliseconds 500

Glide $BX $BY $CX $CY 700
Start-Sleep -Milliseconds 250
[M]::Down(); Start-Sleep -Milliseconds 90; [M]::Up()
Start-Sleep -Milliseconds 2000
