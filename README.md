<p align="center">
  <img src="docs/images/hammerforge_logo.png" alt="HammerForge Logo" width="400">
</p>

<h1 align="center">HammerForge</h1>

<p align="center">
  <strong>Brush-based level editor for Godot 4.6+</strong><br>
  Draw rooms, carve doors, paint terrain, and bake to optimized meshes — all inside the Godot editor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.6%2B-478cbf?logo=godot-engine&logoColor=white" alt="Godot 4.6+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Status-Alpha-orange" alt="Alpha">
  <img src="https://img.shields.io/badge/Tests-694%20passing-brightgreen" alt="694 tests passing">
  <img src="https://img.shields.io/badge/GDScript-23k%2B%20lines-blueviolet" alt="23k+ lines">
</p>

---

## Why HammerForge?

Level editors like Hammer and TrenchBroom proved that **brush-based workflows** are the fastest way to block out 3D spaces. HammerForge brings that paradigm into Godot so you never have to leave the editor:

- **No live CSG** -- brushes are lightweight preview nodes; CSG runs only at bake time, keeping the editor snappy even with hundreds of brushes.
- **Two-click geometry** -- drag a base rectangle, click to set height. Extrude faces to extend rooms. Type exact numbers any time.
- **Paint floors and terrain** -- grid-based floor paint with heightmaps, multi-material blending, auto-connectors (ramps/stairs), and foliage scatter.
- **Bake when ready** -- one click produces merged meshes, collision shapes, lightmap UVs, navmeshes, and LODs.

HammerForge is a single `addons/` folder. No external tools, no custom builds, no export plugins. Drop it in, enable, draw.

---

## At a Glance

| | |
|---|---|
| **Modular subsystem architecture** | **694 unit + integration tests** with CI on every push |
| **15 brush shapes** (box through dodecahedron) | **150 built-in prototype textures** for instant greyboxing |
| **Quake `.map`** + **glTF `.glb`** export | **.hflevel** native format with threaded I/O |
| **Customizable keymaps** (JSON) | **Plugin API** for custom tools |

---

## Core Workflows

### Draw and Shape Brushes

Two-stage CAD drawing: drag base, click height. Brushes support **Add** and **Subtract** operations with pending cut staging, so you can preview subtractions before committing.

- **15 shapes** -- box, cylinder, sphere, cone, wedge, pyramid, prisms, ellipsoid, capsule, torus, and platonic solids
- **Extrude Up/Down** (U / J) -- click any face and drag to extend
- **Hollow** (Ctrl+H) -- convert a solid brush to a room with configurable wall thickness
- **Clip** (Shift+X) -- split a brush along an axis-aligned plane
- **Carve** (Ctrl+Shift+R) -- boolean-subtract one brush from all intersecting brushes
- **Numeric input** -- type exact dimensions during any drag or extrude
- **Resize gizmo** with full undo/redo

### Vertex Editing

Precision vertex-level editing for fine-tuning brush geometry:

- **Vertex mode** (V) -- select and move individual brush vertices with convexity enforcement
- **Edge sub-mode** (E) -- toggle to select, move, split, and merge edges
- **Edge splitting** (Ctrl+E) -- insert midpoint vertex on a selected edge
- **Vertex merging** (Ctrl+W) -- merge selected vertices to their centroid
- **Wireframe overlay** -- color-coded edge display (gray default, orange selected, yellow hovered)

### Polygon Tool

Draw arbitrary convex polygons and extrude them into brushes:

- **Polygon tool** (P) -- click to place vertices on the ground plane, Enter or auto-close to finish
- **Convexity enforcement** -- rejects concave vertex placements in real time
- **Height extrusion** -- drag to set height after closing the polygon
- **Grid snapping** -- vertices snap to the active grid

### Path Tool

Create corridors and paths by placing waypoints:

- **Path tool** (;) -- click to place waypoints, Enter to finalize
- **Rectangular cross-section** -- configurable width and height per path
- **Miter joints** -- automatic gap-filling brushes at corners
- **Auto-grouping** -- all segment brushes share a group ID

### Snap and Align

Geometry-aware snapping goes beyond a simple grid:

| Mode | Key | What it snaps to |
|------|-----|------------------|
| Grid | G | Regular grid intersections |
| Vertex | V | Corners of existing brushes (8 per box) |
| Center | C | Center points of existing brushes |

Closest candidate within threshold wins. Modes combine freely. **Texture Lock** preserves UV alignment when moving or resizing. **Move to Floor/Ceiling** (Ctrl+Shift+F/C) raycasts to snap brushes vertically. **UV Justify** offers fit/center/left/right/top/bottom alignment for selected faces.

### Paint Floors and Terrain

Grid-based paint layers with chunked storage for large worlds:

- **Tools:** Brush (B), Erase (E), Rect (R), Line (L), Bucket (K), Blend
- **Sculpting:** Raise, Lower, Smooth, Flatten brushes for interactive terrain editing with configurable strength, radius, and falloff
- **Shapes:** Square, Circle with adjustable radius
- **Heightmaps:** import PNG/EXR or generate procedural noise -- per-vertex displacement via SurfaceTool
- **Material blending:** four-slot shader with per-cell blend weights painted directly on the grid
- **Auto-connectors:** ramp and stair mesh generation between layers at different heights
- **Foliage scatter:** height/slope-filtered MultiMeshInstance3D placement
- **Region streaming:** sparse chunk loading for open worlds

### Materials and Surface Paint

- **Visual material browser** -- thumbnail grid with search, pattern/color filters, and Prototypes/Palette/Favorites views
- **150 built-in prototype textures** (15 patterns x 10 colors) -- click **Refresh Prototypes** for instant greyboxing with visual browsing
- **Texture Picker** (T key) -- eyedropper tool samples material from any face
- **Hover preview** -- hovering a thumbnail temporarily previews it on selected faces
- **Right-click context menu** -- Apply to Faces, Apply to Whole Brush, Toggle Favorite, Copy Name
- **Face select mode** for painting materials onto individual brush faces
- **Surface paint** with per-face splat layers, weight images, and live preview
- **UV editor** with per-vertex drag handles and reset-to-projection
- **Material library persistence** -- save/load palettes as JSON with usage tracking

### Entities and I/O

- **Data-driven entity types** from `entities.json` (point entities, brush entities like func_detail, func_wall, trigger volumes)
- **Source-style I/O connections** -- wire output events to target inputs with parameter, delay, and fire-once options
- **I/O viewport visualization** -- colored lines between connected entities (green=standard, orange=fire_once, yellow=selected)
- **Declarative property forms** -- dock auto-generates typed controls (string, int, float, bool, enum, color, vector3) from entity definitions
- **Drag-and-drop placement** from the entity palette
- **Color-coded overlays** -- cyan for func_detail, orange for triggers

### Organize Your Level

- **Visgroups** -- named visibility groups ("walls", "detail", "lighting") with per-group show/hide
- **Grouping** (Ctrl+G / Ctrl+U) -- persistent groups that select and move together
- **Cordon** -- restrict bake to an AABB region with yellow wireframe; skip everything outside
- **Reference cleanup** -- deleting brushes auto-cleans group/visgroup membership and warns about dangling entity I/O connections
- **Duplicator** -- create N copies of a brush with progressive offset
- **Prefabs** -- save brush + entity groups as `.hfprefab` files, drag from library to instantiate with new IDs and remapped I/O
- **Decal placement** (N key) -- raycast decals onto brush surfaces with live preview
- **Real-time subtract preview** -- toggle wireframe AABB intersection overlays between additive and subtractive brushes

### Bake and Export

| Option | What it does |
|--------|--------------|
| **Bake** | CSG assembly to merged meshes + trimesh collision |
| **Chunked bake** | Split output by spatial chunks |
| **Cordon bake** | Restrict to AABB region |
| **Face materials** | Bake per-face materials without CSG |
| **Heightmap floors** | Bypass CSG, bake displaced meshes directly with collision |
| **LODs** | Auto-generate level-of-detail meshes |
| **Lightmap UV2** | Unwrap for lightmap baking |
| **Navmesh** | Bake navigation mesh |
| **Dry run** | Preview bake counts without building |
| **Validate** | Check level integrity before bake |
| **.map export** | Classic Quake or Valve 220 format |
| **.glb export** | glTF binary for external tools |
| **Quick Play** | Bake + validate spawn + run with FPS controller |

---

## Editor UX

HammerForge's dock is designed to stay out of your way while keeping everything reachable:

- **4-tab dock** (Brush, Paint, Entities, Manage) with **collapsible sections** -- persisted state, separators, indented content
- **Mode indicator banner** -- color-coded strip shows current tool, gesture stage ("Step 1/2: Draw base -- 64 x 32"), and numeric input buffer
- **Toast notifications** -- transient messages for save/load/bake/error results
- **Interactive tutorial wizard** -- 5-step guided walkthrough (Draw → Subtract → Paint → Entity → Bake) with signal-driven auto-advance, progress bar, and persistent resume across sessions
- **Dynamic contextual hints** -- viewport overlay hints that appear when switching tools (e.g. "Click to place corner → drag to set size → release for height"), auto-dismiss after 4s with per-hint persistence
- **Searchable shortcut dialog** -- "?" button opens a filterable, categorized shortcut reference (replaces static popup)
- **Tool poll system** -- buttons gray out with inline hints when an action can't run ("Select a brush to use these tools")
- **Contextual selection tools** -- hollow, clip, move, tie, duplicator appear in Brush tab only when brushes are selected
- **Live dimensions** -- real-time W x H x D display during drag gestures
- **Operation feedback** -- actionable error toasts with fix hints ("Wall thickness 6 is too large -- Use a thickness less than 5")
- **Instant sync** -- paint, material, and surface paint changes reflected immediately via signals (no polling)
- **Customizable keymaps** -- rebind any shortcut via JSON; toolbar labels auto-update
- **User preferences** -- grid defaults, recent files, UI state persist across sessions

---

## Architecture

HammerForge uses a **coordinator + subsystems** pattern:

```
plugin.gd            EditorPlugin — input routing, toolbar, viewport overlay
  └─ level_root.gd   Thin coordinator (~1,100 lines) — owns containers, exports, signals
       ├─ HFBrushSystem     Brush CRUD, hollow, clip, tie, move, UV justify, caching
       ├─ HFDragSystem      Two-stage draw lifecycle + preview management
       ├─ HFExtrudeTool     Face extrusion (Up/Down) via FaceSelector
       ├─ HFPaintSystem     Floor paint layers, heightmaps, blend, surface paint
       ├─ HFBakeSystem      CSG assembly, mesh merge, LOD, navmesh, collision
       ├─ HFEntitySystem    Entity CRUD, I/O connections, definition loading
       ├─ HFStateSystem     Undo/redo snapshots, transactions, autosave
       ├─ HFFileSystem      Threaded .hflevel / .map / .glb I/O
       ├─ HFGridSystem      Grid rendering and follow mode
       ├─ HFVisgroupSystem  Named visibility groups + brush grouping
       ├─ HFCarveSystem     Boolean-subtract carve (progressive-remainder slicing)
       ├─ HFIOVisualizer    Entity I/O connection lines in viewport
       ├─ HFSnapSystem      Grid / Vertex / Center snap with threshold
       ├─ HFSubtractPreview Wireframe AABB intersection overlay for subtract brushes
       ├─ HFVertexSystem    Vertex/edge selection, move, split, merge with convexity validation
       ├─ HFSpawnSystem     Player spawn lookup, validation, auto-fix, debug visualisation
       └─ HFToolRegistry    External tool loading and dispatch
            ├─ HFMeasureTool   Ruler/distance measurement (tool_id=100)
            ├─ HFDecalTool     Decal placement with live preview (tool_id=101)
            ├─ HFPolygonTool   Convex polygon → extruded brush (tool_id=102)
            └─ HFPathTool      Waypoint path → corridor brushes (tool_id=103)
```

Key design choices:

- **No live CSG** -- brushes are Node3D with box metadata; CSG runs only during bake
- **RefCounted subsystems** -- each receives a LevelRoot reference; no circular preloads
- **Signal-driven UI** -- signals on LevelRoot replace polling; batched emission prevents UI thrash
- **Tag-based invalidation** -- dirty tags on brushes/paint for selective reconciliation
- **Command collation** -- rapid operations merge into single undo entries within a 1-second window
- **Transactions** -- atomic multi-step operations (hollow, clip) with rollback on failure
- **HFOpResult** -- failable operations return structured results with actionable fix hints
- **HFGesture** -- base class for self-contained input tool gestures
- **Explicit state machine** -- `HFInputState` manages IDLE / DRAG_BASE / DRAG_HEIGHT / SURFACE_PAINT / EXTRUDE modes
- **Type-safe calls** -- no duck-typing between modules (dynamic dispatch only in undo/redo by design)

---

## Installation

```
1. Copy addons/hammerforge into your project
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge
3. Open a 3D scene and click in the viewport to auto-create LevelRoot
4. Verify: dock appears with 4 tabs (Brush, Paint, Entities, Manage), toolbar shows D/S/+/-/P/▲/▼, snap buttons show G/V/C
```

See [Install + Upgrade](docs/HammerForge_Install_Upgrade.md) for upgrade steps and cache reset.

---

## Quick Start

| Step | Action |
|------|--------|
| **1. Draw** | Tool = Draw, Mode = Add, Shape = Box -> drag base -> click height |
| **2. Extrude** | Press U (Extrude Up) -> click a face -> drag -> release |
| **3. Subtract** | Mode = Subtract -> draw a brush through a wall -> Apply Cuts -> Bake |
| **4. Material** | Paint tab -> Materials -> **Refresh Prototypes** -> browse thumbnails -> Face Select Mode -> click faces -> Assign |
| **5. Paint floor** | Paint Mode -> Brush tool (B) -> paint grid cells -> switch layers for different heights |
| **6. Bake** | Manage tab -> Bake -> click Bake (or Quick Play to bake + run) |

---

## Keyboard Shortcuts

All shortcuts are rebindable via `user://hammerforge_keymap.json`.

| Key | Action | | Key | Action |
|-----|--------|-|-----|--------|
| D | Draw tool | | B | Brush (paint) |
| S | Select tool | | E | Erase (paint) |
| U | Extrude Up | | R | Rect (paint) |
| J | Extrude Down | | L | Line (paint) |
| Ctrl+H | Hollow | | K | Bucket (paint) |
| Shift+X | Clip | | Ctrl+G | Group selection |
| Ctrl+Shift+R | Carve | | Ctrl+U | Ungroup |
| Ctrl+Shift+F | Move to Floor | | M | Measure tool |
| Ctrl+Shift+C | Move to Ceiling | | N | Decal tool |
| V | Vertex mode | | P | Polygon tool |
| E | Edge sub-mode (in vertex) | | ; | Path tool |
| Ctrl+E | Split edge | | Ctrl+W | Merge vertices |
| T | Texture Picker | | ? | Shortcuts popup |
| X / Y / Z | Axis lock | | | |

---

## Testing

622 tests across 38 files using the [GUT](https://github.com/bitwes/Gut) framework, including unit tests and end-to-end integration tests. All checks run on every push via GitHub Actions.

```bash
# Run all tests headless
godot --headless -s res://addons/gut/gut_cmdln.gd --path .

# Reset prefs for the editor smoke checklist
godot --headless -s res://tools/prepare_editor_smoke.gd --path .

# If class_names aren't imported
godot --headless --import --path .

# Format + lint
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/HammerForge_UserGuide.md) | Complete usage documentation |
| [MVP Guide](docs/HammerForge_MVP_GUIDE.md) | Architecture and contributor reference |
| [Install + Upgrade](docs/HammerForge_Install_Upgrade.md) | Setup, upgrade, and cache reset |
| [Design Constraints](docs/HammerForge_Design_Constraints.md) | Explicit tradeoffs and limits |
| [Data Portability](docs/HammerForge_Data_Portability.md) | .hflevel / .map / .glb workflow |
| [Texture + Materials](docs/HammerForge_Texture_Materials.md) | Face materials, UVs, and surface paint |
| [Prototype Textures](docs/HammerForge_Prototype_Textures.md) | Built-in 150 SVG textures |
| [Floor Paint Design](docs/HammerForge_FloorPaint_Greyboxing.md) | Grid paint system design |
| [Editor Smoke Checklist](docs/HammerForge_Editor_Smoke_Checklist.md) | Repeatable live-editor verification flow |
| [Development + Testing](DEVELOPMENT.md) | Local setup, architecture, test checklist |
| [Spec](HammerForge_SPEC.md) | Technical specification |
| [Changelog](CHANGELOG.md) | Version history |
| [Roadmap](ROADMAP.md) | Planned features and priorities |
| [Contributing](CONTRIBUTING.md) | How to contribute |
| [Demo Clips](docs/demos/README.md) | Clip list and naming scheme |
| [Sample Levels](samples/) | Minimal and stress test scenes |

---

## Roadmap Highlights

See [ROADMAP.md](ROADMAP.md) for the full plan.

**Recently shipped:**
- Visual material browser with thumbnail grid, search, pattern/color filters, favorites, and hover preview
- Texture Picker tool (T key) — eyedropper to sample face materials
- Vertex editing enhancements (edge sub-mode, split, merge, wireframe overlay)
- Polygon tool (click convex vertices, extrude to brush)
- Path tool (waypoints, rectangular cross-section, miter joints)
- Interactive tutorial wizard with 5-step guided walkthrough
- Prefab system (save/load/drag-and-drop reusable brush+entity groups)

**Next up:**
- Displacement sewing (stitch adjacent heightmap edges)
- Material atlasing for large scenes
- Merge tool (combine two adjacent brushes)

**Later:**
- Bezier patch editing
- Snap-to-edge and snap-to-perpendicular modes
- Multiple simultaneous cordons
- Preference packs for one-click workflow presets

---

## Troubleshooting

<details>
<summary>Plugin not loading or dock missing</summary>

1. Close Godot
2. Delete `.godot/editor` (and optionally `.godot/imported`)
3. Reopen and re-enable the plugin

</details>

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

<details>
<summary>"class_names not imported" when running tests</summary>

Run `godot --headless --import --path .` first, then re-run the test command.

</details>

---

<p align="center">
  <strong>MIT License</strong><br>
  <sub>Built for Godot 4.6+ | Last updated March 28, 2026</sub>
</p>
