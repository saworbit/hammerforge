# HammerForge

FPS-style level editor plugin for Godot 4.6+. Brush-based greyboxing and fast bake workflows inside the editor.

Last updated: February 5, 2026

## What is HammerForge?
HammerForge brings classic brush workflows (Hammer / TrenchBroom style) into Godot. You draw draft brushes, preview quickly, and bake to optimized meshes only when needed.

Key ideas:
- DraftBrush nodes are lightweight and editable.
- CSG is only used at bake time.
- Floor Paint is a grid-based authoring tool that generates DraftBrush floors/walls.

## Features

Brush workflow
- Two-stage CAD drawing (base drag, then height click).
- Add and Subtract operations with pending cut staging.
- Shape palette: box, cylinder, sphere, cone, wedge, pyramid, prisms, ellipsoid, capsule, torus, and platonic solids.
- Grid snapping with quick presets and axis locks.
- Draft brush resize gizmo with undo/redo support.

Floor Paint (early)
- Grid-based paint layers with chunked storage.
- Tools: Brush, Erase, Rect, Line, Bucket.
- Live preview while dragging (paint updates as you move).
- Greedy-meshed floors and merged wall segments (generated DraftBrushes).
- Stable IDs with scoped reconciliation to avoid node churn.
- Paint layers persist in .hflevel saves.

Editor UX
- Editor theme parity for the dock.
- On-screen shortcut HUD (optional).
- High-contrast editor grid with follow mode.
- History panel (beta) and live brush count.
- Entity palette with drag-and-drop placement.

Bake and playtest
- Bake draft brushes to meshes + collision.
- Optional merge meshes, LOD generation, UV2 unwrap, and navmesh baking.
- Chunked baking via LevelRoot.bake_chunk_size.
- Playtest button bakes and runs the scene with an FPS controller.

## Installation

1. Copy `addons/hammerforge` into your project.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open a 3D scene and click in the viewport to auto-create LevelRoot.

## Quick start

1. Draw a brush: Tool = Draw, Mode = Add, Shape = Box, drag base, then click height.
2. Cut a door: Mode = Subtract, draw a brush, then Apply Cuts and Bake.
3. Paint floors: Toggle Paint Mode, choose a tool, set radius, and paint.
4. Bake: Click Bake to create optimized geometry.

## Troubleshooting

Capture exit-time errors (PowerShell):

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

## Documentation

- User Guide: `docs/HammerForge_UserGuide.md`
- MVP Guide: `docs/HammerForge_MVP_GUIDE.md`
- Floor Paint Design: `docs/HammerForge_FloorPaint_Greyboxing.md`
- Spec: `HammerForge_SPEC.md`
- Changelog: `CHANGELOG.md`

## Roadmap

- Texture/UV tools
- Numeric input during drag
- Additional bake pipelines

## License
MIT
