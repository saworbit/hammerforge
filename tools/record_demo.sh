#!/usr/bin/env bash
# Render a HammerForge demo beat to video.
#
# Frames are rendered from INSIDE the editor (HF_DOCSHOT=demo writes a PNG
# sequence), then encoded here. Deliberately not screen capture: gdigrab cannot
# read Godot's D3D12 window, and ddagrab records whatever is composited in front
# of it, which leaks unrelated screen content the moment focus changes.
#
#   tools/record_demo.sh [out.mp4] [fps]
set -euo pipefail

OUT="${1:-docs/demos/beat_draw_floor.mp4}"
FPS="${2:-30}"
USERDIR="$APPDATA/Godot/app_userdata/hammerforge"
FRAMES="$USERDIR/demo_frames"
GODOT="C:\Godot\godot.cmd"
export PATH="$PATH:/c/Users/User/AppData/Local/Microsoft/WinGet/Links"

rm -f "$USERDIR/docshot_ready"
mkdir -p "$(dirname "$OUT")"

cleanup() {
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
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY

echo "rendering frames in the editor"
HF_DOCSHOT=demo cmd //c "$GODOT --editor --path ." >.docshot_demo.log 2>&1 &

for _ in $(seq 1 300); do
  [ -s "$USERDIR/docshot_ready" ] && break
  sleep 1
done
if [ ! -s "$USERDIR/docshot_ready" ]; then
  echo "editor never finished the beat" >&2
  grep -iE 'error|parse' .docshot_demo.log | head -10 >&2
  exit 1
fi

COUNT=$(ls "$FRAMES"/frame_*.png 2>/dev/null | wc -l)
echo "rendered $COUNT frames"
[ "$COUNT" -lt 30 ] && { echo "too few frames" >&2; exit 2; }

OUTWIN="$(cygpath -w "$PWD/$OUT")"
INPAT="$(cygpath -w "$FRAMES")\frame_%05d.png"
ffmpeg -y -hide_banner -loglevel error -framerate "$FPS" -i "$INPAT" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -vf "scale=1280:-2" "$OUTWIN"
echo "wrote $OUT"
