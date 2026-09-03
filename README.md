<h1 align="center">HammerForge</h1>

<p align="center">
  <strong>Brush-based level editor for Godot 4.7+</strong><br>
  Requires Godot 4.7+ (tested on 4.7.stable). Works in both editor and exported games via HFIORuntime.<br>
  Draw rooms, carve doors, paint terrain, and bake to optimized meshes — all inside the Godot editor.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.7%2B-478cbf?logo=godot-engine&logoColor=white" alt="Godot 4.7+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Status-Early%20Alpha-red" alt="Early Alpha">
  <img src="https://img.shields.io/badge/Tests-1885%20passing-brightgreen" alt="1885 tests passing">
  <img src="https://img.shields.io/badge/GDScript-44k%2B%20lines-blueviolet" alt="44k+ lines">
</p>

> **Fair warning:** This is a solo hobby project in early alpha. I built it to support another project and it grew from there. It's buggy, rough around the edges, and a bit directionless. If any of this looks useful to you, I'd genuinely appreciate help testing and filing issues. Contributions welcome -- just know you're signing up for an adventure, not a polished product.

---

## Looking for a Logo

The previous AI-generated logo has been retired. If you're a designer or artist and want to contribute a logo for HammerForge, I'd love to use it (with credit). Requirements: free to use under MIT, ideally SVG so it scales.

**[Issue #61](https://github.com/saworbit/hammerforge/issues/61) has the full brief** — comment there with a sketch, or open a PR. No Godot knowledge needed.

---

## Why HammerForge?

Level editors like Hammer and TrenchBroom proved that **brush-based workflows** are the fastest way to block out 3D spaces. HammerForge brings that paradigm into Godot so you never have to leave the editor:

- **No full-scene live CSG** -- brushes are lightweight preview nodes; full CSG runs only at bake time. An optional, capped subtract overlay computes only nearby cut previews.
- **Two-click geometry** -- drag a base rectangle, click to set height. Extrude faces to extend rooms. Type exact numbers any time.
- **Paint floors and terrain** -- grid-based floor paint with heightmaps, multi-material blending, auto-connectors (ramps/stairs), and foliage scatter.
- **Bake when ready** -- one click produces merged meshes, collision shapes (trimesh, per-brush convex, or per-visgroup partitioned), lightmap UVs, navmeshes, and LODs.

HammerForge is a single `addons/` folder. No external tools, no custom builds, no export plugins. Drop it in, enable, draw.

---

## At a Glance

| | |
|---|---|
| **Subsystem-based coordinator architecture** | **1,790 unit + integration tests** with CI on every push |
| **15 brush shapes** (box through dodecahedron) | **150 built-in prototype textures** for instant greyboxing |
| **Quake `.map`** + **glTF `.glb`** export | **.hflevel** native format with threaded I/O |
| **Customizable keymaps** (JSON) | **Plugin API** for custom tools |
| **Dark/light theme sync** across all custom UI | **Performance health monitor** with recommendations |

---

## Core Workflows

### Draw and Shape Brushes

Two-stage CAD drawing: drag base, click height. Brushes support **Add** and **Subtract** operations with pending cut staging, so you can preview subtractions before committing.

- **15 shapes** -- box, cylinder, sphere, cone, wedge, pyramid, prisms, ellipsoid, capsule, torus, and platonic solids
- **Extrude Up/Down** (E / U or Shift+E / J) -- click any face and drag to extend
- **Hollow** (Ctrl+H) -- convert a solid brush to a room with configurable wall thickness
- **Clip** (Shift+X) -- split a brush along an axis-aligned plane
- **Carve** (Ctrl+Shift+R) -- boolean-subtract one brush from all intersecting brushes
- **Merge** (Ctrl+Shift+M) -- combine 2+ selected brushes into one, preserving per-brush materials and full transforms (rotation/scale)
- **Bevel** -- round off sharp edges with configurable segments and radius (vertex/edge mode)
- **Face Inset** -- shrink a face inward and optionally extrude along its normal
- **Numeric input** -- type exact dimensions during any drag or extrude
- **Resize gizmo** with world-space grid snap, opposite-face anchoring under rotated/non-uniformly scaled parents, and shape-aware sizing: spheres stay uniform, cylinder/cone/capsule X/Z handles change one shared radius, and capsules can never be resized shorter than their diameter

### Vertex Editing

Precision vertex-level editing for fine-tuning brush geometry:

- **Vertex mode** (V) -- select and move individual brush vertices with convexity enforcement
- **Edge sub-mode** (E) -- toggle to select, move, split, and merge edges
- **Edge splitting** (Ctrl+E) -- insert midpoint vertex on a selected edge
- **Vertex merging** (Ctrl+W) -- merge selected vertices to their centroid
- **Wireframe overlay** -- color-coded edge display (gray default, orange selected, yellow hovered)
- **Clip to Convex** -- repair non-convex brushes by recomputing the convex hull with UV inheritance

### Polygon Tool

Draw arbitrary convex polygons and extrude them into brushes:

- **Polygon tool** (P) -- place the first vertex on an exact visible surface or the forward construction plane, then add vertices from that horizontal placement plane; Enter or auto-close to finish
- **Convexity enforcement** -- rejects concave vertex placements in real time
- **Height extrusion** -- drag to set height after closing the polygon
- **Shared snapping** -- placement uses the active Grid, Vertex, Center, Edge, Perpendicular, and reference-line snap modes

### Path Tool

Create corridors and paths by placing waypoints:

- **Path tool** (;) -- place the first waypoint on an exact visible surface or the forward construction plane, then add waypoints from that horizontal placement plane; Enter to finalize
- **Rectangular cross-section** -- configurable width and height per path
- **Miter joints** -- automatic gap-filling brushes at corners
- **Auto-grouping** -- all segment brushes share a group ID
- **Auto-stairs** -- step brushes along sloped segments with configurable step height
- **Auto-railings** -- top rails + posts on both sides with configurable height, thickness, and post spacing
- **Auto-trim strips** -- edge strips alongside path with material auto-assign

### Snap and Align

Geometry-aware snapping goes beyond a simple grid:

| Mode | Key | What it snaps to |
|------|-----|------------------|
| Grid | G | Regular grid intersections |
| Vertex | V | Corners of existing brushes (8 per box) |
| Center | C | Center points of existing brushes |
| Edge | E | Midpoints of existing brush AABB edges |
| Perpendicular | P | Closest point on an existing brush AABB edge |

Closest candidate within threshold wins. Modes combine freely. The Measure tool can set a **custom snap reference line** with Ctrl+Click for alignment along arbitrary axes. **Texture Lock** preserves UV alignment for HammerForge move and resize actions, including nudge and Move to Floor/Ceiling. Godot's native Node3D transform widget keeps brush-local UV data unchanged. **Move to Floor/Ceiling** (Ctrl+Shift+F/C) raycasts to snap brushes vertically. **UV Justify** offers fit/center/left/right/top/bottom/stretch/tile alignment for selected faces.

### Paint Floors and Terrain

Grid-based paint layers with chunked storage for large worlds:

- **Tools:** Brush (B), Erase (E), Rect (R), Line (L), Bucket (K), Blend
- **Sculpting:** Raise, Lower, Smooth, Flatten brushes for interactive terrain editing with configurable strength, radius, and falloff
- **Shapes:** Square, Circle with adjustable radius
- **Heightmaps:** import PNG/EXR or generate procedural noise -- per-vertex displacement via SurfaceTool
- **Displacement surfaces:** Source-style subdivided face grids (power 2-4) with Raise/Lower/Smooth/Noise/Alpha paint modes, sew adjacent displacements, elevation scale
- **Convert Selection to Heightmap:** select brushes → rasterize top faces → create sculptable terrain layer
- **Material blending:** four-slot shader with per-cell blend weights painted directly on the grid
- **Auto-connectors:** ramp and stair mesh generation between layers at different heights, auto-generated during bake with mode selection (Ramp/Stairs/Auto), configurable step height and width
- **Foliage & Scatter brush:** circle/spline shapes, density preview via MultiMesh (Dots/Wireframe/Full), slope/height filtering, align-to-normal, commit as permanent MultiMeshInstance3D
- **Region streaming:** sparse chunk loading for open worlds

### Materials and Surface Paint

- **Visual material browser** -- thumbnail grid with search, pattern/color filters, and Prototypes/Palette/Favorites views
- **150 built-in prototype textures** (15 patterns x 10 colors) -- click **Refresh Prototypes** for instant greyboxing with visual browsing
- **Texture Picker** (T key) -- eyedropper tool samples material from any face
- **Hover preview** -- hovering a thumbnail temporarily previews it on selected faces
- **Right-click context menu** -- Apply to Faces, Apply to Whole Brush, Toggle Favorite, Copy Name
- **Modal Face Select mode** for painting individual faces; entering hides object transform/resize gizmos, manual exit restores the prior object selection, and selecting an object in the Scene tree returns directly to object editing
- **Surface paint** with per-face splat layers, weight images, and live preview
- **UV editor** with per-vertex drag handles and reset-to-projection
- **Material library persistence** -- save/load palettes as JSON with usage tracking

### Entities and I/O

- **Data-driven entity types** from `entities.json` (point entities, brush entities like func_detail, func_wall, trigger volumes)
- **Source-style I/O connections** -- wire output events to target inputs with parameter, delay, and fire-once options; automatically translated to Godot signals on bake/export via `HFIORuntime` dispatcher (direct method calls, snake_case fallback, generic handler, or user signal emission)
- **Smart auto-routed connection lines** -- quadratic Bezier curves with arrowheads, parallel route offset, color-coded by output type (cyan=OnTrigger, red=OnDamage, yellow=OnUse, etc.) and dimmed by delay
- **I/O wiring panel** -- quick-wire form (output/target/input/param/delay/once), connection summary, and preset picker embedded in the Objects tab
- **Connection presets** -- 6 built-in patterns (Door+Light+Sound, Button→Toggle, Alarm Sequence, etc.) plus user-saved presets with target tag mapping
- **Highlight Connected** -- toggle to pulse-highlight all entities linked to the selected one, with summary counts in the context toolbar
- **Declarative property forms** -- dock auto-generates typed controls (string, int, float, bool, enum, color, vector3) from entity definitions
- **Drag-and-drop placement** from the entity palette
- **Clean operation styling** -- additive brushes use an uncluttered green-tinted surface, subtractors retain a clear red semantic outline, and brush entities use an understated blue tint. Hover and selection use sparse, shape-specific structural profiles; render-triangle topology is reserved for explicit editing and bake-preview modes

### Organize Your Level

- **Visgroups** -- named visibility groups ("walls", "detail", "lighting") with per-group show/hide
- **Grouping** (Ctrl+G / Ctrl+U) -- persistent groups that select and move together
- **Cordon** -- restrict bake to an AABB region with yellow wireframe; skip everything outside
- **Reference cleanup** -- deleting brushes auto-cleans group/visgroup membership and warns about dangling entity I/O connections
- **Duplicator** -- create N copies of a brush with progressive offset
- **Prefabs** -- save brush + entity groups as `.hfprefab` files with variants, tags, and live-linked propagation. Drag from library to instantiate with new IDs and remapped I/O
- **Measurement** (M key) -- persistent multi-ruler with angle display, Shift+Click chaining, and snap reference alignment
- **Decal placement** (N key) -- raycast decals onto brush surfaces with live preview
- **Real-time subtract preview** -- toggle wireframe AABB intersection overlays between additive and subtractive brushes
- **Geometry previews before commit** -- carve (green), clip (cyan + orange plane), and hollow (yellow) show wireframe overlay of resulting pieces with confirmation dialog before executing

### Bake and Export

| Option | What it does |
|--------|--------------|
| **Bake** | CSG assembly to merged meshes + collision (trimesh, per-brush convex, or per-visgroup partitioned) |
| **Chunked bake** | Split output by spatial chunks |
| **Cordon bake** | Restrict to AABB region |
| **Face materials** | Bake per-face materials without CSG |
| **Heightmap floors** | Bypass CSG, bake displaced meshes directly with collision |
| **LODs** | Auto-generate level-of-detail meshes |
| **Lightmap UV2** | Unwrap for lightmap baking |
| **Navmesh** | Bake navigation mesh |
| **Dry run** | Preview bake counts without building |
| **Bake Selected** | Bake only selected brushes (merged into existing output) |
| **Bake Changed** | Bake only dirty-tagged brushes since last successful bake |
| **Preview modes** | Full / Wireframe / Proxy toggle for ultra-fast iteration |
| **MultiMesh** | Consolidate repeated identical meshes into MultiMeshInstance3D |
| **Material Atlas** | Pack albedo textures into a single atlas to reduce draw calls (face materials mode) |
| **Collision Mode** | Trimesh (legacy), per-brush convex hulls, or per-visgroup partitioned convex bodies |
| **Bake Visible Only** | Skip hidden visgroups and invisible brushes |
| **Unwrap UV0** | Per-vertex planar UV projection for surfaces without UVs |
| **Check Issues** | Flag degenerate, floating, overlapping, non-manifold, open-edge, non-planar, and micro-gap brushes. Auto-fix: vertex weld + planarity correction |
| **Bake estimate** | Time estimate with "Chunking recommended" tip for large levels |
| **Validate** | Check level integrity before bake |
| **.map export** | Classic Quake or Valve 220 format |
| **.glb export** | glTF binary for external tools |
| **Test Level** | Check, bake, validate spawn, and run with the FPS controller |
| **Play from Camera** | Test from the editor camera position and yaw |
| **Play Selected Area** | Auto-cordon to selection, bake + play that region only |
| **Export Playtest** | Bake + pack a playable scene with player, spawn pose, nested geometry/collision, lighting, and auto-wired I/O; exported levels initialize only the runtime core, not editor tools |
| **Wire I/O** | Auto-translate entity I/O connections to Godot signals in baked output |

---

## Core Loop

The default editor is the five-step greybox path. Extra overlays stay off until you opt in.

1. **Draw** brushes (Add / Subtract)
2. **Assign materials** from the Paint tab
3. **Place entities** and wire I/O
4. **Bake**
5. **Test Level**

Turn on **Test → Settings → Power-user overlays** for the radial menu, coach marks, and operation replay timeline. Command palette, context toolbar, tutorial, Space context menu, and HUD stay available either way.

## Editor UX

HammerForge's dock is designed to stay out of your way while keeping everything reachable:

- **4-tab dock** (**Build, Paint, Objects, Test**) with **collapsible sections** -- persisted state, separators, indented content, context-hidden panels (entity I/O sections appear only when an object is selected)
- **Dark/light theme sync** -- all custom panels adapt to Godot's theme setting automatically
- **Mode indicator banner** -- color-coded strip shows current tool, gesture stage ("Step 1/2: Draw base -- 64 x 32"), and numeric input buffer
- **Toast notifications** -- transient messages for save/load/bake/error results
- **Focused first-run guide** -- two-step **Draw → Test Level** walkthrough with signal-driven auto-advance and persistent progress
- **Dynamic contextual hints** -- viewport overlay hints that appear when switching tools (e.g. "Click to place corner → drag to set size → release for height"), auto-dismiss after 4s with per-hint persistence
- **Searchable shortcut dialog** -- "?" button opens a filterable, categorized shortcut reference (replaces static popup)
- **Smart contextual toolbar** -- floating mini-toolbar in the 3D viewport shows context-sensitive actions (brush ops when brushes selected, UV tools when faces selected, shape picker in draw mode, axis locks while dragging)
- **Command palette** (Shift+? or F1 or Ctrl+K) -- searchable action palette with fuzzy search, "Did you mean" suggestions, and live gray-out for unavailable actions
- **Viewport context menu** (Space) -- context-sensitive right-click-style menu with grid snap presets, UV operations, draw shapes, and toggle items; sections adapt to current selection
- **Predictable camera navigation** -- plain RMB always controls Godot's 3D camera while HammerForge is idle, regardless of selection or persistent tool mode; while held, native WASD flight and mixed mouse input cannot trigger HammerForge actions. Only an active gesture or modal interaction may consume the initial press
- **Radial menu** (`` ` ``, opt-in) -- 8-sector pie menu for quick tool switching (Box, Cylinder, Select, Paint, Vertex, Tex Pick, Measure, Clip). Enable **Power-user overlays** in Test → Settings
- **Quick property popups** (double-tap G G / B B / R R) -- inline numeric entry for grid snap, brush size, and paint radius without leaving the viewport
- **Grid size indicator** -- persistent "Grid: N" display in viewport HUD with flash-on-change feedback; `[` / `]` keys halve/double grid snap instantly
- **Coach marks** (opt-in) -- first-use step-by-step guides for advanced tools (Polygon, Path, Carve, Vertex, Extrude, etc.) with "Don't show again" persistence
- **Undo history browser** -- thumbnail-equipped history panel (Test tab) with double-click navigation to any undo point
- **Operation replay timeline** (Ctrl+Shift+T, opt-in) -- visual timeline of recent operations with undo/redo replay to any recorded point
- **Example library** -- 5 built-in demo levels (Test tab) with difficulty ratings, annotations, and one-click loading for learning
- **Auto-mode hints** -- "Drawing in Add mode" bar appears during drag with one-click Add/Subtract toggle
- **Tool poll system** -- buttons gray out with inline hints when an action can't run ("Select a brush to use these tools")
- **Native Object Select** -- Godot owns ordinary object clicks, empty-space box selection, modifiers, and transform/property widgets. A widget claim wins the complete mouse and keyboard gesture before HammerForge can start a marquee or nudge; buttonless motion and focus recovery clear stale ownership. Shift keeps Godot's native additive/active-selection behavior; Ctrl/Cmd remain available to Godot instead of becoming a HammerForge toggle. Filled face-triangle gizmo targets make brush and visible entity surfaces easy to select; geometry-less or visibly broken preview assets receive a restrained local pick marker, while hidden previews leave no invisible target
- **Focused Face Select** -- face click/marquee is a separate modal state that switches to Select, turns Paint off, and temporarily hides object transform/resize gizmos. Shift adds faces and Ctrl/Cmd toggles them; leaving Paint or choosing an incompatible tool exits cleanly
- **Exact non-box picking** -- hover, face tools, and surface-placement fallbacks hit the real cone, wedge, pyramid, curved, or custom mesh instead of empty space inside its AABB
- **Managed brush/entity editing** -- Delete, Duplicate, and keyboard nudge operate consistently on both brushes and `DraftEntity` nodes through HammerForge undo/state handling
- **Mixed-selection action safety** -- selection-dependent HammerForge edits pass through for native-only selections and stop with a clear warning for mixed HammerForge + Godot selections across keyboard, context toolbar, viewport menu, command palette, and radial entry points
- **Select All / Deselect All** (A / Shift+A) -- Blender-convention quick selection; clears face selection and transitions to object context
- **Performance monitor** -- health summary, brush/entity/vertex counts, chunk recommendations, color-coded ProgressBar
- **Contextual selection tools** -- hollow, clip, move, tie, and duplicator appear in Build only when brushes are selected
- **Live dimensions** -- real-time W x H x D display during drag gestures
- **Operation feedback** -- actionable error toasts with fix hints ("Wall thickness 6 is too large -- Use a thickness less than 5")
- **Instant sync** -- paint, material, and surface paint changes reflected immediately via signals (no polling)
- **Customizable keymaps** -- rebind any shortcut via JSON; toolbar labels auto-update
- **User preferences** -- grid defaults, recent files, UI state persist across sessions

---

## Architecture

HammerForge uses a **coordinator + subsystems** pattern:

`LevelRoot` always initializes the brush, entity, bake, paint, and file core needed to load and run a level. Grid, drawing, snapping, selection, previews, prefab authoring, validation, undo, and the remaining editor services are loaded only by editor builds. Export templates therefore avoid constructing the editor tool graph.

```
plugin.gd            EditorPlugin coordinator with focused input/overlay modules
  ├─ dock.gd         Four-tab UI coordinator with focused handler modules
  └─ level_root.gd   Thin coordinator — owns containers, exports, signals
       ├─ HFBrushSystem     Brush CRUD, hollow, clip, tie, move, UV justify, caching
       ├─ HFDragSystem      Two-stage draw lifecycle + preview management
       ├─ HFExtrudeTool     Face extrusion (Up/Down) via FaceSelector
       ├─ HFPaintSystem     Floor paint layers, heightmaps, blend, surface paint
       ├─ HFBakeSystem      CSG assembly, mesh merge, LOD, navmesh, collision, incremental/selection bake, preview modes
       ├─ HFEntitySystem    Entity CRUD, I/O connections, definition loading, fire_output()
       ├─ HFIORuntime       Runtime I/O-to-Signal dispatcher (auto-injected on bake/export)
       ├─ HFStateSystem     Undo/redo snapshots, transactions, autosave
       ├─ HFFileSystem      Threaded .hflevel / .map / .glb I/O
       ├─ HFValidationSystem Level integrity checks, bake issue detection
       ├─ HFGridSystem      Grid rendering and follow mode
       ├─ HFVisgroupSystem  Named visibility groups + brush grouping
       ├─ HFCarveSystem     Boolean-subtract carve (progressive-remainder slicing)
       ├─ HFIOVisualizer    Entity I/O connection lines in viewport (curved, color-coded, highlight pulse)
       ├─ HFIOPresets       Reusable I/O connection presets (built-in + user-saved)
       ├─ HFSnapSystem      Grid / Vertex / Center / Edge / Perpendicular snap + custom reference lines
       ├─ HFSubtractPreview Live CSG cut overlay with wireframe AABB fallback
       ├─ HFVertexSystem    Vertex/edge selection, move, split, merge with convexity validation
       ├─ HFSpawnSystem     Player spawn lookup, validation, auto-fix, debug visualisation
       ├─ HFPrefabSystem    Instance registry, variant cycling, live-linked propagation
       ├─ HFDisplacementSystem  Displacement surface create/destroy/paint/sew/elevation
       ├─ HFBevelSystem     Edge bevel (chamfer) and face inset
       └─ HFToolRegistry    External tool loading and dispatch
            ├─ HFMeasureTool   Multi-ruler measurement + snap reference (tool_id=100)
            ├─ HFDecalTool     Decal placement with live preview (tool_id=101)
            ├─ HFPolygonTool   Convex polygon → extruded brush (tool_id=102)
            └─ HFPathTool      Waypoint path → corridor brushes (tool_id=103)
```

Key design choices:

- **No live CSG** -- brushes are Node3D with box metadata; CSG runs only during bake
- **RefCounted subsystems** -- each receives a LevelRoot reference; no circular preloads
- **Signal-driven UI** -- signals on LevelRoot replace polling; batched emission prevents UI thrash
- **Tag-based invalidation** -- exact dirty tags on transform, material, UV, paint, and vertex mutations; an ID-keyed change tracker reconciles Godot-owned Inspector/gizmo commits and native undo/redo for selective Bake Changed output
- **Command collation** -- rapid operations merge into single undo entries within a 1-second window
- **Transactions** -- atomic multi-step operations (hollow, clip) with rollback on failure
- **HFOpResult** -- failable operations return structured results with actionable fix hints
- **HFGesture** -- base class for self-contained input tool gestures
- **Explicit state machine** -- `HFInputState` manages IDLE / DRAG_BASE / DRAG_HEIGHT / SURFACE_PAINT / EXTRUDE / VERTEX_EDIT modes
- **Type-safe calls** -- no duck-typing between modules (dynamic dispatch only in undo/redo by design)

---

## Installation

```
1. Copy addons/hammerforge into your project
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge
3. Open a 3D scene and use Create Starter in the empty-state banner
4. Verify: the dock shows Build, Paint, Objects, and Test; the primary toolbar shows Draw, Select, Paint, More, and Help
```

Create Starter adds `LevelRoot`, a floor, sunlight, and a player spawn. Create Empty adds only `LevelRoot`. An intentional Draw-tool left-click can also create an empty root; navigation, selection, and other passive input never modify the scene.

**Upgrading?** See [Install + Upgrade](docs/HammerForge_Install_Upgrade.md) for upgrade steps and cache reset.

### Project MCP for contributors

This repository also vendors a project-scoped Godot MCP server in `addons/godot_mcp`. Each contributor creates an ignored, machine-local `.codex/config.toml`; authentication comes from the user-scoped `HAMMERFORGE_GODOT_MCP_TOKEN` environment variable. Codex configuration, tokens, and Godot `user://` MCP state must never be committed. See [Install + Upgrade](docs/HammerForge_Install_Upgrade.md#project-scoped-godot-mcp-repository-contributors) for the configuration and verification steps.

---

## Quick Start

<!--
  TODO: Record a ~15-second screen capture of the core workflow below,
  save as docs/demos/quickstart_walkthrough.gif (720px wide, looping),
  then uncomment the img tag.
-->
<!-- <img src="docs/demos/quickstart_walkthrough.gif" alt="Quick Start walkthrough — create, draw, and test" width="720"> -->

| Step | Action |
|------|--------|
| **1. Create** | In a 3D scene, click **Create Starter**. Choose **Create Empty** only when you do not want the floor, sunlight, and spawn. |
| **2. Draw** | In **Build**, choose Draw + Solid + Box, drag the base in the viewport, then click to set height. |
| **3. Test** | Click **Test Level (Bake + Play)** in **Test**, or press **Ctrl+Enter**. HammerForge checks, bakes, validates the spawn, and runs the scene. |
| **Optional: Cut** | Press **Q** to switch Solid/Cutout, draw through existing geometry, then apply or commit cuts. |
| **Optional: Material** | Open **Paint → Materials**, select faces, and assign a prototype or project material. |
| **Optional: Floor paint** | Press **Shift+P**, choose Paint/Erase/Rect/Line/Bucket/Blend, and paint cells or surfaces. |

---

## Keyboard Shortcuts

Shortcuts marked with **\*** are rebindable via `user://hammerforge_keymap.json`. Tool-specific keys (M, N, P, ;, A, Ctrl+Shift+P) are defined by their respective tools and are not yet keymap-backed.

| Key | Action | | Key | Action |
|-----|--------|-|-----|--------|
| Q * | Toggle Solid / Cutout | | Shift+P * | Toggle Paint mode |
| Ctrl+Enter * | Test Level | | Ctrl+Shift+Enter * | Check level |
| D * | Draw tool | | B * | Brush (paint) |
| S * | Select tool | | E * | Erase (paint) |
| U * | Extrude Up | | R * | Rect (paint) |
| J * | Extrude Down | | L * | Line (paint) |
| Ctrl+H * | Hollow | | K * / N * | Bucket / Blend (paint) |
| Shift+X * | Clip | | Ctrl+G * | Group selection |
| Ctrl+Shift+R * | Carve | | Ctrl+U * | Ungroup |
| Ctrl+Shift+F * | Move to Floor | | M | Measure tool (multi-ruler) |
| Ctrl+Shift+C * | Move to Ceiling | | N | Decal tool |
| V * | Vertex mode | | P | Polygon tool |
| E * | Edge sub-mode (in vertex) | | ; | Path tool |
| Ctrl+E * | Split edge | | Ctrl+W * | Merge vertices |
| T * | Texture Picker | | ? | Shortcuts popup |
| Shift+? / F1 / Ctrl+K | Command palette | | Ctrl+Shift+T | Operation timeline |
| Shift+S * | Select Similar | | Shift+T * | Apply Last Texture |
| Shift+F * | Selection Filters | | Ctrl+Shift+P | Quick group-to-prefab |
| X / Y / Z * | Axis lock | | A | Align mode (measure) |

---

## Testing

The verified Godot 4.7 CI run on September 3, 2026 contains **1,892 tests across 110 scripts**: **1,885 passing tests**, seven intentional no-assert safety tests, and **8,195 assertions**. All checks run on every push and pull request via GitHub Actions.

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
| [Code of Conduct](CODE_OF_CONDUCT.md) | Expected behavior and how to report a problem |
| [Security Policy](SECURITY.md) | What counts as a vulnerability and how to report one privately |
| [Demo Clips](docs/demos/README.md) | Clip list and naming scheme |
| [Sample Levels](samples/) | Minimal and stress test scenes |

---

## Roadmap Highlights

See [ROADMAP.md](ROADMAP.md) for the full plan.

**Recently shipped:**
- Displacement & Bevel (Source-style displacement surfaces with paint/sew/elevation, edge bevel with slerp arc, face inset)
- Quality-of-Life & Polish (theme sync, undo history browser, multi-ruler measure tool, performance monitor, export playtest)
- Terrain & Organic Enhancements (brush-to-heightmap, foliage scatter, path tool extras)
- Learning & Discovery Aids (coach marks, operation replay timeline, fuzzy command palette, example library)
- I/O-to-Signal runtime bridge (auto-wire entity I/O connections to Godot signals on bake/export)
- I/O Connections & Entity Polish (curved auto-routed lines, connection presets, wiring panel, Highlight Connected)
- Bake & Test Level optimizations (Bake Selected, Bake Changed, preview modes, Play from Camera, Play Selected Area)
- Prefab & Group Enhancements (variants, live-linked, tags/search, quick group-to-prefab)
- Improved selection & multi-select (marquee, selection filters, Select Similar, Apply Last Texture)
- Smart contextual toolbar + command palette with fuzzy search

**Recently shipped (also):**
- Material atlas packing and merge-selected-brushes
- Exact-surface Polygon and Path placement through the shared snap pipeline
- Reliable prefab member tracking across Draft, Pending Cuts, Committed Cuts, and entity containers
- Runtime-only LevelRoot initialization in exported levels
- Snap-to-edge (dock **E**) and snap-to-perpendicular (dock **P**)
- Bake `func_detail` meshes and trigger `Area3D` volumes
- Playtest exports with a spawned FPS player, recursive nested-node ownership, and preserved source transforms
- MultiMesh consolidation that keeps instance transforms in baked-container space

**Current tracked work:**
- Save completion and replacement safety ([#33](https://github.com/saworbit/hammerforge/issues/33), [#51](https://github.com/saworbit/hammerforge/issues/51))
- `.map` entity string round-trip fidelity ([#32](https://github.com/saworbit/hammerforge/issues/32))
- Non-blocking threaded mesh merge ([#35](https://github.com/saworbit/hammerforge/issues/35))
- PBR atlas channels and paint hot paths ([#24](https://github.com/saworbit/hammerforge/issues/24), [#39](https://github.com/saworbit/hammerforge/issues/39))
- Smaller dock and plugin ownership boundaries ([#22](https://github.com/saworbit/hammerforge/issues/22), [#41](https://github.com/saworbit/hammerforge/issues/41))

**Later:**
- Bezier patch editing
- Multiple simultaneous cordons
- Preference packs for one-click workflow presets

---

## Help Wanted

This is a one-person project and there's more here than one person can properly test. If you try HammerForge and something breaks, **please open an issue** -- even a one-liner like "Hollow crashed on a cylinder" is helpful. Specific areas where help would make a real difference:

- **Bug reports** -- the test suite covers a lot, but editor-context bugs are hard to catch headless
- **Playtesting** -- try the workflows (draw, bake, quick play) and report what feels broken or confusing
- **Edge cases** -- large levels, unusual brush shapes, rapid undo/redo, plugin reload cycles
- **Documentation** -- if something in the user guide doesn't match reality, flag it

### Where to start

- **[Good first issues](https://github.com/saworbit/hammerforge/labels/good%20first%20issue)** — scoped small, no deep architecture knowledge needed
- **[Help wanted](https://github.com/saworbit/hammerforge/labels/help%20wanted)** — things I can't get to alone
- **[Browse by area](https://github.com/saworbit/hammerforge/labels)** — `area:` labels map to the dock tabs: Build, Paint, Objects, Test
- **[Milestones](https://github.com/saworbit/hammerforge/milestones)** — what the open work is grouped under
- **[Discussions](https://github.com/saworbit/hammerforge/discussions)** — for questions that aren't bug reports

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup and the check commands, and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for how we treat each other here.

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
Start-Process -FilePath "C:\Godot\Godot_v4.7-stable_win64.exe" `
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
  <sub>Built for Godot 4.7+ | Last updated September 2, 2026</sub>
</p>
