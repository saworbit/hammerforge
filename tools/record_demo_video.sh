#!/usr/bin/env bash
# Record a HammerForge demo video with OBS.
#
# Why OBS rather than ffmpeg screen capture: gdigrab cannot read Godot's D3D12
# window (it fails with "Failed to capture image"), and ddagrab is
# monitor-scoped, so it records whatever is composited in front of the target --
# a privacy hazard, not just a bug. OBS Window Capture (WGC) reads
# hardware-accelerated windows, is bounded to one window, includes the real
# cursor, and can also capture the game window that Test Level spawns.
#
# The environment swap is delegated to capture_ui.py so there is exactly one
# implementation of it, and it is the crash-safe one.
#
#   OBS_WS_PASSWORD=... tools/record_demo_video.sh <beats-name> [out.mp4]
#
# Beat sequences live in tools/beats/<name>.beats, with placeholders resolved
# against the editor's 3D viewport rect at runtime.
#
# HF_DRY=1 runs the beats without OBS and without encoding, for iterating on
# geometry and timing. Beats are cheap to change and every real take costs a
# minute, so rehearsing is worth a flag.
set -euo pipefail

BEATS_NAME="${1:?usage: record_demo_video.sh <beats-name> [out.mp4]}"
OUT="${2:-docs/demos/${BEATS_NAME}.mp4}"
# Resolve once, here: the encode step needs an absolute path, and blindly
# prefixing $PWD turns a caller-supplied absolute path into nonsense.
case "$OUT" in
  /* | [A-Za-z]:[\/]*) ;;
  *) OUT="$PWD/$OUT" ;;
esac
BEATS_SRC="tools/beats/${BEATS_NAME}.beats"
USERDIR="$APPDATA/Godot/app_userdata/hammerforge"
GODOT="${GODOT:-C:\\Godot\\godot.cmd}"
export PATH="$PATH:/c/Users/User/AppData/Local/Microsoft/WinGet/Links"
DRY="${HF_DRY:-}"
[ -n "$DRY" ] || : "${OBS_WS_PASSWORD:?set OBS_WS_PASSWORD}"
[ -f "$BEATS_SRC" ] || { echo "no such beat file: $BEATS_SRC" >&2; exit 1; }

# Refuse to record alongside another editor. capture_ui.py rewrites
# project.godot for the run, so any editor already holding it puts up a "files
# have been modified outside Godot" dialog -- which is a real window, sits on
# top of the playtest, and lands in the take instead of the game. It also
# competes for the capture, and can save the project back at a different
# engine version.
STRAY="$(powershell -NoProfile -Command "
  Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue |
    Where-Object { \$_.ProcessName -notlike '*console*' } |
    ForEach-Object { \"\$(\$_.Id) \$(\$_.ProcessName)\" }" | tr -d '\r')" || true
if [ -n "${STRAY:-}" ] && [ -z "${HF_ALLOW_STRAY_EDITOR:-}" ]; then
  echo "Refusing to record: another Godot editor is running." >&2
  echo "$STRAY" | sed 's/^/  /' >&2
  echo "Close it, or set HF_ALLOW_STRAY_EDITOR=1 to record anyway." >&2
  exit 1
fi

rm -f "$USERDIR/docshot_ready" "$USERDIR/docshot_go" "$USERDIR/docshot_done"
mkdir -p "$(dirname "$OUT")" .docshot-tmp

cleanup() {
  [ -n "$DRY" ] || python tools/obs_ctl.py stop >/dev/null 2>&1 || true
  taskkill //F //IM "Godot_v4.7-stable_win64.exe" >/dev/null 2>&1 || true
  python tools/capture_ui.py --restore-only >/dev/null 2>&1 || true
  rm -rf .docshot-tmp
}
trap cleanup EXIT

# Same swap the screenshot path uses: MCP out, capture plugin in, layout reset,
# all restorable if this dies.
python tools/capture_ui.py --prepare-only

# World points have to be requested before launch: the editor projects them
# with its own camera once it is composed, and writes the answers beside the
# viewport rect.
python - "$BEATS_SRC" "$USERDIR/docshot_project" <<'PYPTS'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
pts = re.findall(r"\bw\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\)",
                 open(src, encoding="utf-8").read())
open(dst, "w", encoding="utf-8", newline="\n").write(
    "".join("%s,%s,%s\n" % t for t in pts))
print("  %d world points to project" % len(pts))
PYPTS

echo "launching editor"
HF_DOCSHOT=demo_live cmd //c "$GODOT --editor --path ." >.docshot-tmp/editor.log 2>&1 &

# Nothing here moves the editor window. capture_ui.py pinned its geometry in the
# editor layout before launch, so it comes up windowed at a known size -- and a
# window moved after the plugin measures the viewport would invalidate every
# coordinate below it.

echo "waiting for the editor to compose"
for _ in $(seq 1 240); do
  [ -s "$USERDIR/docshot_ready" ] && break
  sleep 1
done
if [ ! -s "$USERDIR/docshot_ready" ]; then
  echo "editor never signalled ready" >&2
  grep -iE 'error|parse' .docshot-tmp/editor.log | head -10 >&2
  exit 1
fi

# Line one of the ready file is the viewport rect, relative to the window; the
# rest is the projection data the resolver below needs. `read` returns non-zero
# at EOF, and under `set -e` reading straight from the file would kill the
# script immediately after a successful wait, so a here-string supplies the
# terminating newline.
RECT="$(cat "$USERDIR/docshot_ready")"
IFS=, read -r VX VY VW VH <<<"$RECT"
# The plugin reports the viewport relative to the window; Win32 supplies the
# client-area origin in real desktop coordinates. Adding them is the only
# combination both the mouse and the editor agree on.
CLIENT="$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/win_rect.ps1 -Action client -ProcessName "Godot_v4.7" | tr -cd "0-9,-")" || true
IFS=, read -r CX CY _CW _CH <<<"$CLIENT"
echo "client area at ${CX},${CY}; viewport +${VX},+${VY} ${VW}x${VH}"
VX=$((VX + CX))
VY=$((VY + CY))
echo "viewport absolute: ${VX},${VY}"

BEATS=".docshot-tmp/resolved.beats"
python - "$BEATS_SRC" "$BEATS" "$USERDIR/docshot_ready" "$VX" "$VY" "$CX" "$CY" <<'PYBEATS'
import re, sys

src, dst, ready = sys.argv[1:4]
vx, vy, cx, cy = map(int, sys.argv[4:8])

lines = open(ready, encoding="utf-8").read().splitlines()
vw, vh = map(int, lines[0].split(",")[2:4])
grid, ppu = map(float, lines[1].split(","))
points = [tuple(map(int, l.split(","))) for l in lines[2:] if l.strip()]

# w(x,y,z) is a point in the level, projected by the editor's own camera, so a
# beat can say where a wall goes instead of guessing at a screen fraction.
#
# up(h) extrudes to h units. The drag tool reads height off mouse pixels --
# grid_snap + pixels_up / height_pixels_per_unit, then snapped -- so the click
# that sets a 48-unit wall sits (48 - 16) * 4 = 128px above the drag release.
#
# vx()/vy() are fractions of the 3D viewport and cx()/cy() pixel offsets from
# the window's client origin: dock buttons live outside the viewport, so no
# viewport fraction can address them.
WORLD = re.compile(r"\bw\(\s*-?[0-9.]+\s*,\s*-?[0-9.]+\s*,\s*-?[0-9.]+\s*\)")
UP = re.compile(r"\bup\(\s*(-?[0-9.]+)\s*\)")
FRAC = re.compile(r"\b(vx|vy|cx|cy)\((-?[0-9.]+)\)")

state = {"idx": 0, "last": None, "anchored": False}


def world(_m):
    i = state["idx"]
    if i >= len(points):
        raise SystemExit("more w() points in the beats than the editor projected")
    state["idx"] = i + 1
    px, py = points[i]
    return "%d %d" % (vx + px, vy + py)


def up(m):
    """Height is measured from where the base drag was released, so a second
    up() in the same gesture must not stack on the first."""
    if state["last"] is None:
        raise SystemExit("up() with no preceding move to extrude from")
    state["anchored"] = True
    lx, ly = state["last"]
    return "%d %d" % (lx, ly - round((float(m.group(1)) - grid) * ppu))


def frac(m):
    kind, val = m.group(1), float(m.group(2))
    if kind == "vx":
        return str(int(vx + vw * val))
    if kind == "vy":
        return str(int(vy + vh * val))
    if kind == "cx":
        return str(int(cx + val))
    return str(int(cy + val))


out = []
for line in open(src, encoding="utf-8").read().splitlines():
    if line.strip() and not line.lstrip().startswith("#"):
        state["anchored"] = False
        line = FRAC.sub(frac, UP.sub(up, WORLD.sub(world, line)))
        parts = line.split()
        if parts[0] == "move" and not state["anchored"]:
            state["last"] = (int(parts[1]), int(parts[2]))
    out.append(line)

open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("  resolved %d beats, %d world points, grid=%g ppu=%g"
      % (sum(1 for l in out if l.strip() and not l.lstrip().startswith("#")),
         state["idx"], grid, ppu))
PYBEATS

# Identify our editor by scene and binary. Another Godot instance open on
# this machine would otherwise be captured instead.
if [ -z "$DRY" ]; then
  python tools/obs_ctl.py capture --scene HammerForgeDemo "hf_demo_empty.tscn" "4.7"
  python tools/obs_ctl.py start
  sleep 2
fi

# Diagnostic: the window must still be where the plugin measured it.
NOW="$(powershell -NoProfile -ExecutionPolicy Bypass -File tools/win_rect.ps1 -Action get -ProcessName "Godot_v4.7" | tr -cd "0-9,-")" || true
echo "window at play time: ${NOW:-<none>}   first beat: $(grep -m1 "^move" "$BEATS")"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mouse_beats.ps1 -Script "$BEATS"   ${DRY:+-NoObs}

if [ -n "$DRY" ]; then
  echo "dry run: beats played, nothing recorded"
  touch "$USERDIR/docshot_go"
  exit 0
fi

# Stop recording BEFORE releasing the editor. The plugin quits the moment it
# sees the marker, so anything captured after this is the window closing --
# the clip would end on a black frame that reads as a crash.
sleep 1
RAW="$(python tools/obs_ctl.py stop | sed 's/^saved: //')"
touch "$USERDIR/docshot_go"
sleep 4  # OBS finalises the container after StopRecord returns
[ -f "$RAW" ] || { echo "OBS reported no output file" >&2; exit 1; }
RAWWIN="$(cygpath -w "$RAW")"

# Belt and braces: if a black tail survives anyway, cut it. A clip ending on
# black looks like a failure regardless of the cause.
BLACK="$(ffmpeg -hide_banner -nostats -i "$RAWWIN" -vf "blackdetect=d=0.2:pic_th=0.98" -f null - 2>&1 | grep -o "black_start:[0-9.]*" | tail -1 | cut -d: -f2)" || true
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAWWIN")"
TRIM=""
if [ -n "${BLACK:-}" ]; then
  # A generous window: the playtest's own window stops presenting when the
  # editor takes it back, so the black tail can be several seconds long. It is
  # still a tail, and a clip that ends on black reads as a crash.
  ENDS="$(python -c "import sys;b,d=float(sys.argv[1]),float(sys.argv[2]);print('yes' if d-b<12.0 else 'no')" "$BLACK" "$DUR")"
  if [ "$ENDS" = "yes" ]; then
    TRIM="-t $BLACK"
    echo "trimming black tail from ${BLACK}s"
  fi
fi

# -an drops the audio track. OBS records desktop audio alongside the window,
# and the picture being window-scoped says nothing about what the speakers were
# playing. These clips have no narration, so there is nothing to lose and a
# whole category of accident to avoid.
ffmpeg -y -hide_banner -loglevel error -i "$RAWWIN" $TRIM -vf "scale=1280:-2" -an -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p "$(cygpath -w "$OUT")"
echo "wrote $OUT"
