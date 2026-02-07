<p align="center">
  <img src="docs/images/hammerforge_logo.png" alt="HammerForge Logo" width="400">
</p>

<h1 align="center">HammerForge</h1>

<p align="center">
  <strong>FPS-style level editor plugin for Godot 4.6+</strong><br>
  Brush-based greyboxing and fast bake workflows inside the editor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.6%2B-478cbf?logo=godot-engine&logoColor=white" alt="Godot 4.6+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Status-Alpha-orange" alt="Alpha">
</p>

---

## What is HammerForge?

HammerForge brings classic brush workflows (Hammer / TrenchBroom style) into Godot. Draw draft brushes, preview quickly, and bake to optimized meshes only when needed.

| Concept | Description |
|---------|-------------|
| **DraftBrush** | Lightweight, editable brush nodes |
| **Bake** | CSG used only at bake time for performance |
| **Floor Paint** | Grid-based tool that generates DraftBrush floors/walls |
| **Face Materials** | Per-face materials, UVs, and surface paint layers |

---

## Features

### Brush Workflow
- **Two-stage CAD drawing** -- drag base, then click height
- **Add / Subtract operations** with pending cut staging
- **Shape palette** -- box, cylinder, sphere, cone, wedge, pyramid, prisms, ellipsoid, capsule, torus, and platonic solids
- **Grid snapping** with quick presets and axis locks
- **Resize gizmo** with full undo/redo support

### Face Materials + UVs
- **Materials palette** (dock) with add/remove and per-face assignment
- **Face select mode** for per-face material painting
- **UV editor** with per-vertex drag handles and reset-to-projection
- Face data persists in `.hflevel` saves

### Surface Paint (3D)
- Paint target switch: **Floor** or **Surface**
- Per-face splat layers with weight images
- Live preview on DraftBrushes (per-face composite)
- Per-layer texture picker and adjustable radius/strength

### Floor Paint (Early)
- Grid-based paint layers with chunked storage
- **Tools:** Brush, Erase, Rect, Line, Bucket
- **Brush shape:** Square or Circle
- Live preview while dragging
- Greedy-meshed floors and merged wall segments
- Stable IDs with scoped reconciliation (no node churn)
- Paint layers persist in `.hflevel` saves

### Editor UX
- **Context-sensitive shortcut HUD** that updates based on current tool and mode
- **Paint tool shortcuts**: B / E / R / L / K for Brush / Erase / Rect / Line / Bucket
- **Tooltips** on all dock controls with shortcut hints
- **Selection count** in the status bar
- **Color-coded status bar** (red errors, yellow warnings, auto-clear)
- **Pending cuts** visually distinct (orange-red glow) from applied cuts
- Editor theme parity, high-contrast grid with follow mode
- History panel (beta) and live brush count
- Entity palette with drag-and-drop placement

### Bake & Playtest
- Bake draft brushes to meshes + collision
- Optional: merge meshes, LOD generation, UV2 unwrap, navmesh baking
- Optional: **Use Face Materials** (bake per-face materials without CSG)
- Chunked baking via `LevelRoot.bake_chunk_size`
- **Playtest button** -- bakes and runs with an FPS controller

### Modular Architecture
- `LevelRoot` is a thin coordinator delegating to **8 subsystem classes** (grid, entity, brush, drag, bake, paint, state, file)
- Explicit **input state machine** for drag/paint operations
- Type-safe inter-module calls (no duck-typing)
- Threaded .hflevel I/O with error handling
- **CI**: automated `gdformat` + `gdlint` checks on push/PR

## Installation

```
1. Copy addons/hammerforge into your project
2. Enable the plugin: Project → Project Settings → Plugins → HammerForge
3. Open a 3D scene and click in the viewport to auto-create LevelRoot
```

---

## Quick Start

| Step | Action |
|------|--------|
| **1. Draw a brush** | Tool = Draw, Mode = Add, Shape = Box -> drag base -> click height |
| **2. Cut a door** | Mode = Subtract -> draw brush -> Apply Cuts -> Bake |
| **3. Face materials** | Materials tab -> Add -> pick `materials/test_mat.tres` (or create a StandardMaterial3D) -> Face Select Mode -> click faces -> Assign material |
| **4. Surface paint** | Paint Mode -> Surface Paint tab -> Paint Target = Surface (not Floor) -> paint |
| **5. Bake** | Click Bake (or enable Use Face Materials) |

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/HammerForge_UserGuide.md) | Complete usage documentation |
| [MVP Guide](docs/HammerForge_MVP_GUIDE.md) | Minimum viable product scope |
| [Texture + Materials](docs/HammerForge_Texture_Materials.md) | Face materials, UVs, and surface paint |
| [Development + Testing](DEVELOPMENT.md) | Local setup and test checklist |
| [Floor Paint Design](docs/HammerForge_FloorPaint_Greyboxing.md) | Grid paint system design |
| [Spec](HammerForge_SPEC.md) | Technical specification |
| [Changelog](CHANGELOG.md) | Version history |

## Roadmap

- [ ] Numeric input during drag
- [ ] Material atlasing for large scenes
- [ ] Decals and trim tools
- [ ] Additional bake pipelines

---

## Troubleshooting

<details>
<summary>Capture exit-time errors (PowerShell)</summary>

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

</details>

---

<p align="center">
  <strong>MIT License</strong><br>
  <sub>Last updated: February 7, 2026</sub>
</p>
