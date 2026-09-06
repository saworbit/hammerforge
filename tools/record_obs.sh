#!/usr/bin/env bash
# Record a HammerForge demo beat with OBS.
#
# OBS Window Capture (WGC) can read Godot's hardware-accelerated window, which
# gdigrab cannot, and is window-scoped so it cannot pick up unrelated screen
# content the way a desktop-region capture does. It can also capture the game
# window that Test Level spawns, which rendering the editor viewport cannot.
#
# Requires OBS_WS_PASSWORD in the environment. Never store it in a file.
#
#   OBS_WS_PASSWORD=... tools/record_obs.sh [out.mp4]
set -euo pipefail

OUT="${1:-docs/demos/beat_draw_floor.mp4}"
USERDIR="$APPDATA/Godot/app_userdata/hammerforge"
GODOT="C:\Godot\godot.cmd"
export PATH="$PATH:/c/Users/User/AppData/Local/Microsoft/WinGet/Links"
: "${OBS_WS_PASSWORD:?set OBS_WS_PASSWORD}"

rm -f "$USERDIR/docshot_ready" "$USERDIR/docshot_go" "$USERDIR/docshot_done"
mkdir -p "$(dirname "$OUT")"

cleanup() {
  python tools/obs_ctl.py stop >/dev/null 2>&1 || true
  taskkill //F //IM "Godot_v4.7-stable_win64.exe" >/dev/null 2>&1 || true
  [ -f project.godot.rec.bak ] && mv -f project.godot.rec.bak project.godot
  [ -f .godot/editor/editor_layout.cfg.rec.bak ] &&
    mv -f .godot/editor/editor_layout.cfg.rec.bak .godot/editor/editor_layout.cfg
}
trap cleanup EXIT

cp project.godot project.godot.rec.bak
cp .godot/editor/editor_layout.cfg .godot/editor/editor_layout.cfg.rec.bak
python - <<'PY'
import io, re
s = io.open('project.godot', encoding='utf-8').read()
s = s.replace(', "res://addons/godot_mcp/plugin.cfg"', '')
s = re.sub(r'^MCPRuntimeProbe=.*\n', '', s, flags=re.M)
io.open('project.godot', 'w', encoding='utf-8', newline='\n').write(s)
p = '.godot/editor/editor_layout.cfg'
s = io.open(p, encoding='utf-8').read()
s = re.sub(r'^dock_hsplit_1=.*$', 'dock_hsplit_1=400', s, flags=re.M)
s = re.sub(r'^open_scenes=.*$', 'open_scenes=PackedStringArray()', s, flags=re.M)
s = re.sub(r'^current_scene=.*$', 'current_scene=""', s, flags=re.M)
s = re.sub(r'^mode=.*$', 'mode="windowed"', s, flags=re.M)
s = re.sub(r'^position=Vector2i.*$', 'position=Vector2i(0, 0)', s, flags=re.M)
s = re.sub(r'^size=Vector2i.*$', 'size=Vector2i(1920, 1080)', s, flags=re.M)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY

echo "launching editor"
HF_DOCSHOT=demo_live cmd //c "$GODOT --editor --path ." >.docshot_demo.log 2>&1 &

for _ in $(seq 1 180); do
  [ -s "$USERDIR/docshot_ready" ] && break
  sleep 1
done
[ -s "$USERDIR/docshot_ready" ] || { echo "editor never signalled ready" >&2; exit 1; }

RECT="$(cat "$USERDIR/docshot_ready")"
IFS=, read -r VX VY VW VH <<<"$RECT"
echo "viewport at ${VX},${VY} ${VW}x${VH}"

# Beat: drag a base across the grid, then click above it to set the height.
AX=$((VX + VW * 34 / 100)); AY=$((VY + VH * 56 / 100))
BX=$((VX + VW * 68 / 100)); BY=$((VY + VH * 74 / 100))
CX=$BX;                      CY=$((BY - 45))

python tools/obs_ctl.py capture "Godot Engine"
python tools/obs_ctl.py start
sleep 2

powershell -NoProfile -ExecutionPolicy Bypass -File tools/win_rect.ps1 -Action set -PosX 0 -PosY 0 -Width 1920 -Height 1080 >/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mouse_demo.ps1 -AX $AX -AY $AY -BX $BX -BY $BY -CX $CX -CY $CY
sleep 1
touch "$USERDIR/docshot_go"
sleep 2

RAW="$(python tools/obs_ctl.py stop | sed 's/^saved: //')"
sleep 4  # OBS finalises the container after StopRecord returns
echo "raw: $RAW"

RAWWIN="$(cygpath -w "$RAW")"
OUTWIN="$(cygpath -w "$PWD/$OUT")"
ffmpeg -y -hide_banner -loglevel error -i "$RAWWIN" -vf "scale=1280:-2" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p "$OUTWIN"
echo "wrote $OUT"
