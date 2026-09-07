# Play a scripted sequence of real mouse and keyboard actions.
#
# Synthetic events forwarded into the plugin cannot be mixed with cursor
# movement: Input.warp_mouse emits a genuine motion event with no button held,
# which cancels an in-progress drag. So the demo drives the real OS mouse and
# sends nothing synthetic. A viewer sees exactly what happened.
#
# The beat file is one action per line, coordinates in absolute screen pixels:
#
#   move    X Y MS     glide to X,Y over MS milliseconds (eased)
#   press              left button down
#   release            left button up
#   click              press, brief hold, release
#   dwell   MS         hold still
#   key     NAME MS    hold a key down for MS, then release
#   keydown NAME       hold a key down (pair with keyup)
#   keyup   NAME       release a held key
#   obs     ARGS...    run tools/obs_ctl.py with ARGS (scene cuts mid-take)
#   #                  comment
#
#   powershell -File tools/mouse_beats.ps1 -Script beats.txt [-NoObs]
#
# -NoObs skips `obs` beats, so a beat file can be rehearsed for timing and
# geometry without involving the recorder.

param(
  [Parameter(Mandatory = $true)][string]$Script,
  [switch]$NoObs
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] private static extern void mouse_event(uint f, uint x, uint y, uint d, int e);
  [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint f, int e);
  [DllImport("user32.dll")] private static extern uint MapVirtualKey(uint code, uint mapType);
  public static void Down() { mouse_event(0x0002, 0, 0, 0, 0); }
  public static void Up()   { mouse_event(0x0004, 0, 0, 0, 0); }
  // Send the scan code alongside the virtual key. Godot reads keyboard input
  // through Windows messages, but anything reading raw scan codes (and any
  // future engine build that does) sees nothing from a vk-only event.
  public static void Key(byte vk, bool down) {
    byte scan = (byte)MapVirtualKey(vk, 0);
    keybd_event(vk, scan, down ? 0u : 2u, 0);
  }
}
"@

# Named keys the demos actually use. Single characters fall through to their
# ASCII value, which is the virtual key code for A-Z and 0-9.
$KEYMAP = @{
  "space" = 0x20; "shift" = 0x10; "ctrl" = 0x11; "alt" = 0x12
  "esc" = 0x1B; "enter" = 0x0D; "tab" = 0x09
  "up" = 0x26; "down" = 0x28; "left" = 0x25; "right" = 0x27
}

function KeyCode([string]$name) {
  $k = $name.ToLower()
  if ($KEYMAP.ContainsKey($k)) { return [byte]$KEYMAP[$k] }
  if ($name.Length -eq 1) { return [byte][char]$name.ToUpper() }
  throw "unknown key name: $name"
}

# Smoothstep, so the pointer accelerates and settles rather than sliding at a
# constant machine speed. This is the single biggest difference between reading
# as "someone using it" and reading as "a script".
function Ease([double]$t) { return $t * $t * (3.0 - 2.0 * $t) }

# Release the modifiers before starting and again on the way out. A run that
# dies between keydown and keyup leaves the key held at the OS level, and the
# next run then draws every brush with Shift down -- which in HammerForge means
# "equal sides", so the footprints come out square and nothing about the beat
# file explains why.
function ReleaseModifiers() {
  foreach ($v in 0x10, 0x11, 0x12) { [M]::Key([byte]$v, $false) }
}
ReleaseModifiers
trap { ReleaseModifiers; break }

# Position is tracked here rather than read back from the OS: the first move
# is a jump, and every later move glides from where we left the pointer.
$curX = 0; $curY = 0

function Glide([int]$x2, [int]$y2, [int]$ms) {
  $steps = [Math]::Max(2, [int]($ms / 12))
  $x1 = $script:curX; $y1 = $script:curY
  for ($i = 1; $i -le $steps; $i++) {
    $t = Ease($i / [double]$steps)
    [void][M]::SetCursorPos([int]($x1 + ($x2 - $x1) * $t), [int]($y1 + ($y2 - $y1) * $t))
    Start-Sleep -Milliseconds 12
  }
  $script:curX = $x2; $script:curY = $y2
}

foreach ($line in Get-Content -LiteralPath $Script) {
  $t = $line.Trim()
  if ($t -eq "" -or $t.StartsWith("#")) { continue }
  $p = $t -split '\s+'
  switch ($p[0]) {
    "move" {
      if ($script:curX -eq 0 -and $script:curY -eq 0) {
        # First move is a jump, not a glide: there is no meaningful origin.
        [void][M]::SetCursorPos([int]$p[1], [int]$p[2])
        $script:curX = [int]$p[1]; $script:curY = [int]$p[2]
      } else {
        Glide ([int]$p[1]) ([int]$p[2]) ([int]$p[3])
      }
    }
    "press"   { [M]::Down() }
    "release" { [M]::Up() }
    "click"   { [M]::Down(); Start-Sleep -Milliseconds 90; [M]::Up() }
    "dwell"   { Start-Sleep -Milliseconds ([int]$p[1]) }
    "keydown" { [M]::Key((KeyCode $p[1]), $true) }
    "keyup"   { [M]::Key((KeyCode $p[1]), $false) }
    "key" {
      $code = KeyCode $p[1]
      [M]::Key($code, $true)
      Start-Sleep -Milliseconds ([int]$p[2])
      [M]::Key($code, $false)
    }
    "obs" {
      if ($NoObs) { Write-Host "  (skipped) $t"; continue }
      $rest = $p[1..($p.Length - 1)]
      # Run in-line: a scene cut has to land at this point in the timeline,
      # not whenever a background job happens to get scheduled.
      & python "tools/obs_ctl.py" @rest
      if ($LASTEXITCODE -ne 0) { Write-Error "obs beat failed: $t"; exit 1 }
    }
    default   { Write-Error "unknown beat action: $t"; exit 1 }
  }
}

ReleaseModifiers
