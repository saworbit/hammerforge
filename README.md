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
| **Floor Paint** | Grid-based tool that generates floors/walls with optional heightmap terrain |
| **Face Materials** | Per-face materials, UVs, and surface paint layers |

---

## Features

### Brush Workflow
- **Two-stage CAD drawing** -- drag base, then click height
- **Add / Subtract operations** with pending cut staging
- **Extrude Up / Down** -- click a face and drag to extend brushes vertically
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

### Floor Paint
- Grid-based paint layers with chunked storage
- **Tools:** Brush, Erase, Rect, Line, Bucket, Blend
- **Brush shape:** Square or Circle
- Live preview while dragging
- Greedy-meshed floors and merged wall segments
- Stable IDs with scoped reconciliation (no node churn)
- Paint layers persist in `.hflevel` saves
- **Heightmaps:** import PNG/EXR or generate procedural noise per layer
- **Displaced meshes:** per-vertex heightmap displacement via SurfaceTool
- **Material blending:** four-slot shader with per-cell blend weights (UV2 blend map, RGB = slots B/C/D)
- **Region streaming:** sparse loading of paint chunks for large worlds
- **Auto-connectors:** ramp and stair mesh generation between layers
- **Foliage scatter:** height/slope-filtered MultiMeshInstance3D placement

### Organization + Workflow
- **Visgroups** -- named visibility groups (e.g. "walls", "detail", "lighting") with per-group show/hide toggle
- **Brush/Entity Grouping** -- persistent groups that select/move together (Ctrl+G / Ctrl+U)
- **Texture Lock** -- UV alignment preserved automatically when moving or resizing brushes
- **Cordon (Partial Bake)** -- restrict bake to an AABB region with yellow wireframe visualization
- **Sticky LevelRoot** -- selecting other scene nodes no longer breaks viewport input

### Editor UX
- **4-tab dock** (Brush, Paint, Entities, Manage) with **collapsible sections** for visual hierarchy
- **Context-sensitive shortcut HUD** that updates based on current tool and mode
- **Toolbar shortcut labels**: Draw (D), Sel (S), Ext▲ (U), Ext▼ (J)
- **Paint tool shortcuts**: B / E / R / L / K for Brush / Erase / Rect / Line / Bucket
- **Extrude shortcuts**: U (Extrude Up), J (Extrude Down)
- **Group shortcuts**: Ctrl+G (Group), Ctrl+U (Ungroup)
- **Tooltips** on all dock controls with shortcut hints
- **Selection count** in the status bar
- **Color-coded status bar** (red errors, yellow warnings, auto-clear)
- **Pending cuts** visually distinct (orange-red glow) from applied cuts
- **"No LevelRoot" banner** guides users when no root node is found
- Editor theme parity, high-contrast grid with follow mode
- History panel (beta) and live brush count
- Entity palette with drag-and-drop placement
- **Bake Dry Run** and **Validate Level** actions
- **Performance panel** with brush, paint, and bake stats
- **Settings export/import** for editor preferences

### Bake & Playtest
- Bake draft brushes to meshes + collision
- Optional: merge meshes, LOD generation, UV2 unwrap, navmesh baking
- Optional: **Use Face Materials** (bake per-face materials without CSG)
- Heightmap floors bake directly (bypass CSG) with trimesh collision
- Chunked baking via `LevelRoot.bake_chunk_size`
- **Cordon bake** -- restrict bake to an AABB region (skip brushes outside the cordon)
- Bake progress bar with chunk status updates
- **Playtest button** -- bakes and runs with an FPS controller

### Modular Architecture
- `LevelRoot` is a thin coordinator delegating to **10 subsystem classes** (grid, entity, brush, drag, bake, paint, state, file, validation, visgroup)
- Explicit **input state machine** for drag/paint operations
- Type-safe inter-module calls (no duck-typing)
- Threaded .hflevel I/O with error handling
- **CI**: automated `gdformat` + `gdlint` checks and **GUT unit tests** (47 tests) on push/PR

## Installation

```
1. Copy addons/hammerforge into your project
2. Enable the plugin: Project → Project Settings → Plugins → HammerForge
3. Open a 3D scene and click in the viewport to auto-create LevelRoot
```

For upgrade steps and cache reset help, see `docs/HammerForge_Install_Upgrade.md`.

---

## Quick Start

| Step | Action |
|------|--------|
| **1. Draw a brush** | Tool = Draw, Mode = Add, Shape = Box -> drag base -> click height |
| **2. Extrude a wall** | Tool = Extrude Up (U) -> click face -> drag up -> release |
| **3. Cut a door** | Mode = Subtract -> draw brush -> Apply Cuts -> Bake |
| **4. Face materials** | Paint tab -> Materials section -> Add -> pick `materials/test_mat.tres` -> Face Select Mode -> click faces -> Assign material |
| **5. Surface paint** | Paint Mode -> Paint tab -> Surface Paint section -> Paint Target = Surface -> paint |
| **6. Bake** | Manage tab -> Bake section -> Click Bake (or enable Use Face Materials) |

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/HammerForge_UserGuide.md) | Complete usage documentation |
| [MVP Guide](docs/HammerForge_MVP_GUIDE.md) | Minimum viable product scope |
| [Install + Upgrade](docs/HammerForge_Install_Upgrade.md) | Setup, upgrade, and cache reset |
| [Design Constraints](docs/HammerForge_Design_Constraints.md) | Explicit tradeoffs and limits |
| [Data Portability](docs/HammerForge_Data_Portability.md) | .hflevel/.map/.glb workflow |
| [Demo Clips](docs/demos/README.md) | Clip list and naming scheme |
| [Sample Levels](samples/) | Minimal and stress test scenes |
| [Texture + Materials](docs/HammerForge_Texture_Materials.md) | Face materials, UVs, and surface paint |
| [Development + Testing](DEVELOPMENT.md) | Local setup and test checklist |
| [Floor Paint Design](docs/HammerForge_FloorPaint_Greyboxing.md) | Grid paint system design |
| [Spec](HammerForge_SPEC.md) | Technical specification |
| [Changelog](CHANGELOG.md) | Version history |
| [Roadmap](ROADMAP.md) | Planned features |
| [Contributing](CONTRIBUTING.md) | Contribution guidelines |

## Roadmap

See `ROADMAP.md` for planned work and priorities.

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
  <sub>Last updated: February 25, 2026</sub>
</p>
