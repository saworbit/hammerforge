# HammerForge User Guide

Last updated: April 13, 2026

This guide covers the current HammerForge workflow in Godot 4.6: brush-based greyboxing, bake, entities, floor paint, and per-face materials/UVs.

## Quick Start
1. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
2. Open any 3D scene.
3. Click in the 3D viewport to auto-create `LevelRoot`.
4. Optional: Click Create Floor for a temporary collidable surface.
5. Draw brushes, then Bake for output geometry.

## LevelRoot
`LevelRoot` is required because it owns the containers and systems HammerForge uses:
- DraftBrushes, PendingCuts, CommittedCuts
- PaintLayers and Generated (floors/walls)
- Entities
- Baker and paint systems

If missing, HammerForge creates it automatically on first viewport click. LevelRoot stays active even when you select other scene nodes (sticky root discovery) -- you do not need to re-select it after clicking a camera, light, or other node.

## First-Run Tutorial
On first launch, an interactive tutorial wizard appears guiding you through 5 steps:

| Step | Goal | Trigger |
|------|------|---------|
| 1 | Draw your first room | Place any brush |
| 2 | Subtract a window | Place a brush with Subtract operation |
| 3 | Paint a floor | Paint cells on any layer |
| 4 | Place an entity | Drag or create an entity |
| 5 | Bake & preview | Run a bake |

Each step auto-advances when you complete the required action. A progress bar shows your position. You can skip individual steps or dismiss the entire tutorial. Progress persists across sessions — if you close the editor at step 3, it resumes there next time.

Check "Don't show again" when dismissing to hide it permanently. Reset by editing `user://hammerforge_prefs.json` and setting `"show_welcome": true` and `"tutorial_step": 0`.

## Coach Marks (First-Use Tool Guides)

When you activate an advanced tool for the first time, a floating overlay appears with step-by-step instructions. Coach marks are available for 10 tools:

| Tool | Trigger | Steps shown |
|------|---------|-------------|
| Polygon | P key | Click vertices → close loop → set height → confirm |
| Path | ; key | Place waypoints → Enter → set height → confirm |
| Vertex Edit | V key | Select → multi-select → edge mode → merge/split |
| Extrude | E/U/J keys | Select brush → click face → drag → confirm |
| Carve | Ctrl+Shift+R | Select brushes → preview (green wireframe) → confirm → delete fragments |
| Clip | Shift+X | Select → preview (cyan wireframe + orange plane) → confirm → split |
| Hollow | Ctrl+H | Select solid → preview (yellow wireframe walls) → confirm → hollow |
| Measure | M key | Click start → click end → Shift+Click to chain → RMB for snap ref |
| Decal | N key | Click surface → resize/rotate → assign material |
| Surface Paint | P toggle | Toggle paint → select tool → click cells |

Each guide has a "Don't show again" checkbox. Dismissed guides are persisted in user prefs. Guides trigger from keyboard shortcuts, the command palette, and context toolbar actions.

## Operation Replay Timeline

Press **Ctrl+Shift+T** to toggle a compact timeline showing your recent operations (up to 20). Each operation appears as a color-coded icon:

| Color | Action Type |
|-------|-------------|
| Blue | Draw / Create brush |
| Red | Delete / Remove |
| Orange | Subtract |
| Green | Extrude |
| Yellow | Carve / Clip |
| Purple | Vertex / Merge / Split |

Hover an entry to see its name and elapsed time. Click an entry, then click **Replay** to undo or redo the history to that point. The timeline records every action that passes through the undo/redo system.

## Undo History Browser

The **Manage** tab → **History** section contains a visual undo history browser with viewport thumbnails. It replaces the plain text history list:

- Up to **30 entries** are recorded, each with a color-coded action icon and an 80x48 viewport thumbnail captured at the time of the action.
- **Hover** an entry to see an enlarged thumbnail preview.
- **Double-click** an entry to navigate the undo/redo system to that point in history.
- **Undo/Redo buttons** are integrated into the browser header, with disabled state automatically tracking the undo/redo manager.
- Action icons reuse the same color scheme as the Operation Replay Timeline (blue=draw, red=delete, etc.).

## Error Prevention & Forgiveness

HammerForge prioritizes non-destructive workflows so you can experiment freely:

### Geometry Previews (Preview Before Commit)

Destructive geometry operations show a wireframe preview overlay before permanently modifying brushes:

| Operation | Preview Color | What It Shows |
|-----------|--------------|---------------|
| Carve (Ctrl+Shift+R) | Green wireframe | All resulting slice pieces |
| Clip (Shift+X) | Cyan wireframe + orange plane | Two resulting halves + the cut surface |
| Hollow (Ctrl+H) | Yellow wireframe | 6 wall pieces at the chosen thickness |
| Extrude (U/J) | Semi-transparent brush | New brush being extruded from the face |
| Subtract (toggle) | Red wireframe | AABB intersection volumes |

Each preview appears immediately, then a confirmation dialog gives you the option to **Cancel** and abort without changing anything.

### Bulk Delete Safeguard

Deleting 3 or more brushes at once prompts a confirmation dialog. The dialog reminds you that Ctrl+Z can undo the deletion. Deleting 1-2 brushes remains instant (no friction for common operations).

### Undo Everything

All brush operations (draw, delete, carve, clip, hollow, extrude, move, resize, merge, material assignment, UV changes) are fully undoable via Ctrl+Z. The Undo History Browser (Manage tab) provides visual navigation with thumbnails.

## Measure Tool (Multi-Ruler)

Press **M** to activate the Measure tool. It supports persistent multi-ruler measurements with angle display and snap references:

- **Click** to set point A, click again to set point B — a ruler line appears with distance, dX/dY/dZ decomposition.
- **Shift+Click** chains a new ruler from the last ruler's endpoint. Consecutive chained rulers that share a vertex display the **angle** between them in degrees.
- Up to **20 rulers** can be active simultaneously, each drawn in a cycling color palette.
- **Right-click** near a ruler to set it as a **snap reference line**. The snap system will project nearby points onto that line.
- Press **A** to toggle align mode on/off.
- Press **Delete/Backspace** to remove the last ruler.
- Press **Escape** to clear all rulers.
- The HUD shows ruler count, distance of the last ruler, and alignment status.

## Command Palette (Ctrl+K)

The command palette is a searchable action list. Open it with **Shift+?**, **F1**, or **Ctrl+K**.

- Type to filter actions by name or keybinding
- **Fuzzy search**: if no exact match, the palette finds approximate matches using subsequence matching with word-boundary bonuses
- **"Did you mean: ..."** suggestion appears when fuzzy matching kicks in
- Actions gray out when unavailable (e.g., Hollow requires a brush selection)
- Press **Enter** to execute the first visible enabled action
- Press **Esc** to close without executing

## Example Library

The **Manage** tab contains an **Examples** section (collapsed by default) with 5 built-in demo levels:

| Example | Difficulty | Key Concepts |
|---------|------------|--------------|
| Simple Room | Beginner | Additive brushes, floor |
| Corridor with Doorway | Beginner | Subtract operations, spatial planning |
| Jump Puzzle Platforms | Intermediate | Multiple brushes, player spawn entity |
| Hollowed Building | Intermediate | Hollow + subtract for windows |
| Simple Arena | Advanced | Multi-level, ramps, cover, multiple spawns |

- **Load** clears the current level and instantiates the example's brushes and entities
- **Study This** shows numbered annotations explaining the design decisions
- Search/filter by title, description, tags, or difficulty level

## Dock Layout (4 tabs)
The dock has 4 tabs with collapsible sections for organized access to all controls. Each collapsible section has a visual separator and indented content; collapsed state persists across sessions. A "No LevelRoot" banner appears at the top when no root node is found.

### Mode Indicator
A colored banner between the toolbar and tabs always shows your current tool and gesture stage:
- **Draw** (blue) -- "Step 1/2: Draw base — 64 x 32 x 48" / "Step 2/2: Set height — 64 x 96 x 48" (live dimensions update as you drag)
- **Select** (green)
- **Extrude ▲** (green) / **Extrude ▼** (red) -- "Extruding..."
- **Paint** (orange)

When typing numeric input during a gesture, the value appears in brackets (e.g. "[64]").

### Toolbar
The compact toolbar shows icon + text labels (Draw, Select, Add, Sub, Paint, Ext Up, Ext Dn) with full descriptions in tooltips. A **?** button at the right end opens a searchable shortcut reference dialog where you can filter by action name or key binding. Press **Shift+?** or **F1** in the 3D viewport to open the command palette for executing any action by name.

### Brush tab
- **Toolbar**: Draw, Select, Add, Sub, Paint, Ext Up, Ext Dn (icon + text labels). Press **?** for searchable shortcuts dialog.
- **Shape**: choose from the palette. Sides for pyramids/prisms.
- **Size** X/Y/Z: defaults for new brushes.
- **Grid Snap**: snap increment with quick preset buttons (1, 2, 4, 8, 16, 32, 64).
- **Snap Modes**: G (Grid), V (Vertex — snap to brush corners), C (Center — snap to brush centers). Toggle independently; closest geometry within threshold beats grid snap.
- **Material**: active material picker.
- **Physics Layer**: collision layer for baked output.
- **Texture Lock**: UV alignment preserved on move/resize (enabled by default).
- **Selection Tools** (visible when brushes are selected, grouped by domain):
  - **Brush Modification**: Hollow (wall thickness spinner + button, Ctrl+H) with yellow wireframe preview; Clip Selected (Shift+X) with cyan wireframe preview + orange split plane. Carve (Ctrl+Shift+R) with green wireframe preview. Merge (Ctrl+Shift+M) combining 2+ brushes.
  - **Positioning**: Move to Floor (Ctrl+Shift+F) / Ceiling (Ctrl+Shift+C).
  - **Entity Binding**: Tie/Untie brush entity class (populated from entity definitions).
  - **Duplicate Array**: count, X/Y/Z offset, Create/Remove Array buttons.
  - **Bulk delete**: deleting 3+ brushes shows a confirmation dialog (undo reminder). Single/dual deletes remain instant.

### Paint tab (collapsible sections)
- **Floor Paint**: Brush, Erase, Rect, Line, Bucket, Blend tools. Brush shape (Square/Circle), radius, and layer picker. Rename button ("R") for custom layer display names.
- **Heightmap**: Import PNG/EXR or Generate procedural noise. Height Scale and Layer Y spinboxes. **Sculpt tools**: Raise, Lower, Smooth, Flatten buttons with strength/radius/falloff spinboxes for interactive terrain editing. **Convert Selection → Heightmap** button rasterizes selected brush top faces into a new heightmap layer (inherits grid origin/basis and chunk_size from the paint layer manager).
- **Blend & Terrain**: Blend Strength, Blend Slot (B/C/D), and Terrain Slot A-D texture pickers with UV scales.
- **Foliage & Scatter**: Interactive scatter brush for foliage and object placement. Pick a mesh resource, set density/radius/height constraints/slope filter/scale variation. Choose Circle or Spline brush shape. Preview generates a MultiMesh preview (Dots/Wireframe/Full). Scatter commits as a permanent `MultiMeshInstance3D`. Clear removes the preview. Spline mode uses selected nodes as path control points with a configurable width band.
- **Regions**: Region Streaming enable, Region Size, Stream Radius, Show Region Grid, memory stats.
- **Materials**: Visual thumbnail browser (`HFMaterialBrowser`) with search, pattern/color filters, and Prototypes/Palette/Favorites view toggle. Add/Remove/Refresh Prototypes buttons. Face Select Mode toggle. Assign to Selected Faces. Right-click thumbnails for context menu (Apply to Faces, Apply to Whole Brush, Toggle Favorite, Copy Name). Hover a thumbnail to preview on selected faces. Press **T** for Texture Picker (eyedropper). The **Refresh Prototypes** button batch-loads 150 built-in SVG textures (15 patterns x 10 colors) for quick greyboxing.
- **UV Editor**: Per-face UV editing with drag handles, Reset Projected UVs, and Justify grid (Fit, Center, Left, Right, Top, Bottom in 3×2 layout).
- **Surface Paint**: Paint Target (Floor/Surface), layers, texture picker, radius/strength.

### Entities tab
- Create DraftEntity button.
- Entity palette with drag-and-drop placement.
- **Entity Properties** (collapsible, context-hidden): auto-generated typed controls based on entity definition. Only visible when an entity is selected.
- **Entity I/O** (collapsible, context-hidden): Output, Target, Input, Parameter fields. Delay (seconds) and Fire Once checkbox. Add Output / Remove buttons and connection ItemList. Only visible when an entity is selected; connections auto-refresh on selection change. **Show I/O Lines** checkbox to visualize connections in the viewport.
- **I/O Wiring** (collapsible, context-hidden, collapsed by default): Quick-wire form (output name, target dropdown, input name, parameter, delay, fire-once). Only visible when an entity is selected. Connection summary shows triggers and triggered-by counts. **Highlight** toggle button pulses all linked entities in the viewport. **Connection Presets** picker with 6 built-in patterns (Door+Light+Sound, Button→Toggle, Alarm Sequence, Pickup+Remove, Damage+Break, Timer Lights) plus user-saved presets. Target tag mapping lets you assign preset target placeholders to actual entity names.

> **Progressive disclosure:** During greyboxing, the Entities tab shows only the entity palette and create button. Entity Properties, Entity I/O, and I/O Wiring sections appear automatically when you select an entity, keeping the UI clean when you're focused on shapes and layout.
  - **I/O connection lines**: Bézier curves with arrowheads, color-coded by output type (cyan=OnTrigger, red=OnDamage, yellow=OnUse, green=OnOpen, magenta=OnBreak, orange=OnTimer). Fire-once connections pulse brighter; delayed connections dim proportionally. Parallel connections between the same pair offset laterally.
  - **Highlight Connected**: when enabled, all entities wired to the selected entity display a pulsing overlay. The context toolbar shows an "HL" toggle and an I/O summary label ("Triggers 2 targets (door1, light1)"). The highlight state stays in sync between the context toolbar and the wiring panel.

### I/O Runtime Signal Translation

Entity I/O connections are automatically translated into live Godot signals when you bake or export a playtest scene. No manual signal wiring is required.

**How it works**: An `HFIODispatcher` node is injected into the exported/baked scene. On `_ready()`, it scans all entities for `entity_io_outputs` metadata and builds a connection table. When a source entity fires an output, the dispatcher delivers to each target via:
1. Direct method call (e.g. `Open()`, `Kill()`)
2. Snake-case variant (e.g. `turn_on()` for `TurnOn`)
3. Generic handler (`_on_io_input(input_name, parameter)`)
4. User signal (`io_Open` emitted on the target)

**Firing outputs from game scripts**:
```gdscript
# From any entity script at runtime:
HFIORuntime.fire_on(self, "OnTrigger")

# Or via the dispatcher directly:
var dispatcher = $HFIODispatcher
dispatcher.fire("my_button", "OnPressed", "fast")
```

**Configuration**:
- **Export Playtest**: always auto-injects the dispatcher when entities have I/O connections.
- **Bake Wire I/O**: enable the `bake_wire_io` checkbox on LevelRoot (Inspector) to attach the dispatcher to the baked container during regular bakes.
- Source entities receive `io_<OutputName>` user signals (e.g. `io_OnTrigger`) so you can also use standard `connect()` / `emit_signal()` patterns.

### Manage tab (collapsible sections)
- **Bake**: Bake button, Bake Selected, Bake Changed, Check Bake Issues, Dry Run, Validate Level/Fix. Options: Merge Meshes, Generate LODs, Lightmap UV2, Texel Size, Navmesh (cell size, agent height), Use Face Materials, Preview Mode (Full/Wireframe/Proxy), Collision Mode (Trimesh/Convex/Visgroup), Convex Clean, Convex Simplify, Bake Estimate label, Quick Play, Play from Camera, Play Selected Area.
- **Actions**: Create Floor, Apply/Clear/Commit/Restore Cuts, Clear Brushes.
- **Spawn**: Validate Spawn (bakes, then runs physics-based checks and shows debug overlay), Create Default Spawn (auto-places a `player_start` at brush centroid), Preview Spawn Debug (bakes, then shows persistent capsule/ray overlay toggle).
- **File**: Save/Load .hflevel, Import/Export .map (Classic Quake / Valve 220), Export .glb.
- **Presets**: Save/rename presets grid.
- **History**: Undo history browser with thumbnails, color-coded action icons, double-click navigation, undo/redo buttons.
- **Settings**: Show HUD, Show Grid, Follow Grid, Debug Logs, Autosave path/toggle, Settings Export/Import.
- **Performance**: Health summary (green/yellow/red), brush count ProgressBar, entity count, vertex estimate, paint memory, chunk count, last bake time, recommended chunk size.
- **Visgroups & Groups**: Visgroup list with [V]/[H] toggle, New/Add Sel/Rem Sel/Delete, Group Sel/Ungroup.
- **Cordon**: Enable checkbox, min/max spinboxes, Set from Selection.
- **Prefabs**: Save/search/filter/delete prefabs. Browse with tag filtering and variant indicators. Drag-from the library to instantiate. Save Linked for live propagation. Right-click for variant/tag editing.

### Quick Play and Spawn Validation
Quick Play (footer button) bakes the level and launches it with a first-person controller. Before every Quick Play:

1. **Spawn lookup**: finds the active `player_start` entity (primary-flagged first, then first found).
2. **Auto-create**: if no `player_start` exists, a safe default is created at the centroid of all brushes + 5 m height.
3. **Validation**: physics-based checks (floor raycast, capsule collision, headroom, below-map). Issues appear as toasts and optional debug overlays.
4. **Fix dialog**: critical issues (severity ≥ 2: inside geometry, floating in void) show a dialog offering "Fix & Play" (snaps to nearest valid floor) or "Cancel". Severity 1 warnings toast and proceed.
5. **Launch**: bakes geometry + collision, then runs the scene with the FPS controller spawned at the validated position and yaw rotation.

#### Play from Camera
Click **Play from Camera** in the Manage tab to playtest from your current editor camera position:
- The spawn entity is temporarily moved to the camera position; camera yaw is written to `entity_data["angle"]`.
- The level bakes, spawn is validated, and the playtest launches.
- After launch, the spawn is automatically restored to its original position and angle.
- On validation failure (severity ≥ 2), the spawn is restored before showing the fix dialog.
- Full undo/redo support records both the position move and yaw change.

#### Play Selected Area
Click **Play Selected Area** to bake and playtest only the region around your current brush selection:
- The current cordon state (enabled, AABB) is saved.
- A temporary cordon is set from the AABB of the selected brushes.
- The level bakes within that cordon, spawn is validated, and the playtest launches.
- After launch, the original cordon state is restored (enabled/disabled, original AABB).
- On validation failure (severity ≥ 2), the cordon is restored before showing the fix dialog.

#### Export Playtest Build
Click **Export Playtest Build** in the Manage tab → Bake section to create a standalone playable scene:
- Validates spawn (severity ≥ 2 blocks the export).
- If no spawn exists, auto-creates a default (fully undoable with state capture).
- Bakes the level in Full mode.
- Packs baked geometry, entities, and default lighting (DirectionalLight3D + WorldEnvironment if none exists) into a temporary scene at `user://hammerforge_playtest.tscn`.
- Launches the scene via `EditorInterface.play_custom_scene()`.
- A toast confirms "Playtest launched" on success.

### Incremental Bake
For faster iteration on large levels:
- **Bake Selected**: bakes only the currently selected brushes and merges the output into the existing baked container. Previously baked geometry is preserved.
- **Bake Changed**: bakes only brushes that have been modified (dirty-tagged) since the last successful bake. Dirty tags survive failed bakes and accumulate until the next success.

### Bake Preview Modes
Use the **Preview Mode** dropdown in the Manage tab → Bake section to choose how baked geometry renders:
- **Full**: standard material rendering (default).
- **Wireframe**: cyan wireframe overlay using a custom shader — useful for inspecting geometry topology.
- **Proxy**: semi-transparent grey unshaded material — ultra-fast rendering for layout testing.

### Bake Options
The Manage tab Bake section exposes additional controls:
- **Chunk Size** (SpinBox, 0-256, default 32): spatial chunk size for bake grouping. Set to 0 to disable chunking.
- **Bake Visible Only** (checkbox): skips hidden visgroups and invisible brushes during bake.
- **Use MultiMesh** (checkbox): after baking, consolidates repeated identical meshes into `MultiMeshInstance3D` nodes. Useful for levels with many copies of the same brush shape — reduces draw calls.
- **Material Atlas** (checkbox): packs per-face albedo textures into a single atlas image so all atlased geometry renders in one draw call. Requires **Use Face Materials** to be enabled. Faces with tiling UVs (scale > 1) are automatically excluded and rendered as separate surfaces with their original material so texture repeat works correctly. Best for levels with many small non-tiling textures. Textures with painted layers or ShaderMaterials are not atlased.
- **Collision Mode** (0/1/2, default 0): controls how baked collision shapes are generated.
  - **0 — Trimesh** (default): single ConcavePolygonShape3D per chunk. Simple but worst-case for physics broadphase.
  - **1 — Per-brush convex**: each brush gets a ConvexPolygonShape3D (convex hull). Much better for physics queries and bot navigation.
  - **2 — Per-visgroup partitioned**: separate StaticBody3D per visgroup, each containing convex hulls for its member brushes. Best for navigation mesh generation and room-based broadphase.
- **Convex Clean** (checkbox, default on): deduplicate vertices before building convex hulls. Disable to keep raw vertex data (degeneracy guard still runs).
- **Convex Simplify** (slider, 0.0–1.0, default 0.0): reduce convex hull complexity by merging nearby vertices into an AABB-proportional grid. Higher values = fewer vertices = simpler collision.
- **Unwrap UV0** (checkbox): applies per-vertex planar UV projection during bake for surfaces that lack explicit UVs.
- **Generate Occluders** (checkbox): automatically generates `OccluderInstance3D` nodes from large flat surfaces during bake. The bake pass groups coplanar triangles across the entire baked hierarchy (including chunked bakes) and emits occluders for groups exceeding the minimum area threshold. This enables Godot's built-in occlusion culling at runtime without manual occluder placement. Sub-controls:
  - **Min Area** (SpinBox, 0.5–100.0, default 4.0): minimum coplanar face-group area in world units² to emit an occluder. Raise this value to reduce occluder count (fewer culling tests); lower it to increase coverage (more surfaces act as occluders). Surfaces smaller than this threshold are skipped.
- **Auto Connectors** (checkbox): auto-generates ramps or stairs between paint layers at different heights during bake. Requires at least 2 paint layers with filled cells at adjacent grid positions and a height difference ≥ 0.1 world units. Sub-controls:
  - **Mode** dropdown: *Ramp* (smooth slope), *Stairs* (stepped), *Auto* (stairs when height diff ≥ 2.0, ramp otherwise).
  - **Step H** (SpinBox, 0.05–2.0): stair step height in world units (only affects Stairs/Auto modes).
  - **Width** (SpinBox, 1–8): connector width in grid cells.
  Connectors are generated before navmesh baking, so the navmesh automatically covers connector surfaces. Auto-connectors are skipped during selection bakes (Bake Selected) to avoid pulling in unrelated geometry.

The main **Bake** button is smart: if only specific brushes have been modified since the last bake, it automatically uses incremental bake (`Bake Changed`) instead of a full re-bake.

### Bake Issue Detection
Click **Check Bake Issues** to scan for potential problems before baking:
- **Degenerate brush** (severity 2): near-zero thickness on any axis — blocks play.
- **Oversized brush** (severity 1): very large dimensions — warning only.
- **Floating subtract** (severity 1): a subtractive brush that doesn't intersect any additive brush.
- **Overlapping subtracts** (severity 1): two subtractive brushes with intersecting AABBs.
- **Open edges** (severity 1): edges shared by only one face — geometry is not watertight.
- **Non-manifold edges** (severity 2): edges shared by 3+ faces — may cause bake artifacts.
- **Non-planar faces** (severity 1): faces with 4+ vertices where a vertex drifts off the face plane beyond `planarity_tolerance` (default 0.01 units). Common in imported .map geometry with floating-point drift.
- **Occlusion missing** (severity 1): occluder generation is enabled but no occluders were created (all surfaces below the minimum area threshold).
- **Occlusion coverage** (severity 0, info): reports occluder count and estimated coverage as a percentage of baked AABB surface area. Appears when occluders exist.
- **Micro-gaps** (severity 1): near-coincident but not-exactly-equal vertices across different brushes that would cause seam tearing after bake. Detected within `weld_tolerance` (default 0.001 units).

**Auto-fix helpers** (available via GDScript API on `level_root.validation_system`):
- `weld_brush_vertices(brush)` — snaps near-coincident vertices to their average. Refreshes face normals and bounds automatically.
- `fix_non_planar_faces(brush)` — projects drifting vertices back onto the face plane.

Both tolerances (`weld_tolerance`, `planarity_tolerance`) are configurable per-instance for noisy imported geometry.

Issues appear as color-coded toast notifications.

### Non-Blocking Face Bakes
When **Use Face Materials** is enabled, full bakes yield back to the editor every 8 brushes so the UI stays responsive during large bakes. A progress label shows "Collecting faces N/M" as geometry is processed. The bake operates on a snapshot of brush state taken at the start, so editing brushes while a bake is running will not produce mixed results — changes are picked up on the next bake.

### Bake Time Estimate
The Manage tab shows an estimated bake time based on the last bake duration and current brush count. Frame-yield idle time during face bakes is excluded from the estimate so it reflects actual work, not editor frame pacing. If the level has more than 500 brushes, a "Chunking recommended" tip appears.

**player_start properties** (set in the Entity Properties panel):
- `primary` (bool) -- preferred spawn when multiple exist.
- `angle` (float, degrees) -- initial yaw rotation for the player.
- `height_offset` (float) -- extra height above floor for safety.

**Manage tab → Spawn section**:
- **Validate Spawn** -- triggers a bake, then runs validation against real collision geometry and shows debug overlay (green/red capsule, floor ray, ceiling ray) for 10 seconds.
- **Create Default Spawn** -- places a `player_start` at brush centroid if none exists. Fully undoable and redoable.
- **Preview Spawn Debug** -- triggers a bake, then shows persistent overlay toggle (stays visible until unchecked).

### Toast Notifications
Transient notifications appear in the dock for important events:
- **Save/load/export** results (success or failure).
- **Bake** completion or errors.
- **Operation errors** with actionable hints (e.g. "Wall thickness 6 is too large — Use a thickness less than 5").
- **Reference cleanup** reports (e.g. "Removed 2 I/O connection(s) targeting deleted brush 'door1'").
- **Autosave failures** (also shown as a persistent red warning label).
- Notifications auto-fade after 4-8 seconds depending on severity (INFO, WARNING, ERROR).

### Context Hints
Each tab shows a contextual hint at the bottom guiding you through the workflow:
- Brush tab: "Click and drag in the viewport to draw your first brush" → "Try: Hollow, Clip, or Extrude"
- Paint tab: "Draw some brushes first, then paint them here"
- Entities tab: "Drag an entity from the palette into the viewport"
- Manage tab: "When ready, use Bake to convert brushes into final geometry"

### Marquee Selection
Click and drag in the 3D viewport while in **Select mode** to draw a selection rectangle. All brushes and entities whose screen-space center falls within the rectangle are selected. Hold **Shift** to add to the existing selection.

In **Face Select mode**, marquee selection works on individual faces — drag a box across multiple brushes to select all faces whose screen-projected center is within the rectangle.

### Selection Filters
Press **Shift+F** or click the **Flt** button on the context toolbar to open the Selection Filter popover. It provides bulk selection tools organized by category:

| Category | Filters | Description |
|----------|---------|-------------|
| **By Normal** | Walls, Floors, Ceilings | Select faces by surface direction |
| **By Material** | Same Material | Select all faces matching the selected face's material |
| **Select Similar** | Similar Faces, Similar Brushes | Faces: match material + normal (15°). Brushes: match size (20% tolerance, orientation-agnostic) |
| **By Visgroup** | *(dynamic)* | One button per visgroup — select all members |
| **By Type** | Detail, Structural | func_detail vs worldspawn brushes |

### Select Similar
Press **Shift+S** to quickly select similar geometry without opening the filter popover:
- When **faces** are selected: selects all faces in the level with matching material AND normal direction (within 15°).
- When **brushes** are selected: selects all brushes with similar dimensions (within 20% tolerance, ignoring orientation/rotation).

### Apply Last Texture
Press **Shift+T** to apply the last texture you sampled with the Texture Picker (T key) to the current selection. Works on both face and brush selections. This enables a fast pick-and-paint workflow: press T to sample a material from any face, then Shift+T to stamp it onto other faces or brushes.

### Smart Contextual Toolbar
A floating mini-toolbar appears in the 3D viewport showing context-sensitive actions based on your current selection and tool state. It eliminates the need to switch dock tabs for common operations:

Each section uses small muted **group labels** (e.g. "Extrude", "Modify", "Select") to visually cluster related tools following Gestalt proximity principles.

- **Brushes selected** → [Extrude] Ext▲/Ext▼ | [Modify] Hollow, Clip, Carve, Merge | Duplicate, Delete | [Select] All, ⌂, Similar, Filters. Prefab buttons appear for instances. Shows "N brush(es) selected" count.
- **Faces selected** → Material thumbnails (favorites strip) | [UV] Fit/Center/L/R/T/B | [Apply] All, Last | Select Similar. Shows "N faces on M brush(es)" count.
- **Entities selected** → [Entity] I/O, Properties | Highlight toggle + I/O summary | Duplicate, Delete. Shows "N entities selected" count.
- **Draw mode (idle)** → [Shape] Box/Cyl/Sph/Cone | Add/Subtract toggle.
- **Dragging** → Live dimensions display | Axis Lock (X/Y/Z) | Cancel.
- **Vertex mode** → [Mode] Vertex/Edge toggle | [Edit] Merge, Split, Convex | Exit.

An **auto-mode hint bar** appears during brush drawing, showing the current operation mode (e.g. "Drawing in Add mode — press Subtract to toggle") with a one-click toggle button.

### Command Palette
Press **Shift+?** or **F1** to open the command palette — a searchable list of all HammerForge actions with key bindings. Actions that cannot run in the current state are grayed out (e.g. Hollow is disabled when nothing is selected, paint tools are disabled outside paint mode). Type to filter, press **Enter** to execute the first matching action, **Esc** to close.

### Viewport Context Menu
Press **Space** to open a context-sensitive popup menu at the cursor position in the 3D viewport. The menu adapts to your current selection and tool state:

- **Brush selected** → Extrude Up/Down, Hollow, Clip, Carve, Duplicate, Delete, grid snap presets, draw shapes
- **Face selected** → UV operations (Fit, Center, Stretch, Tile, Left/Right/Top/Bottom justify), texture tools
- **Entity selected** → I/O Connect, Properties, Duplicate, Delete
- **Draw mode (idle)** → Shape selector, Add/Subtract toggle, grid snap presets
- **Vertex mode** → Merge, Split, sub-mode toggle

**Common footer** (in every context): Select All, Deselect All, Grid Snap submenu (1/2/4/8/16/32/64), Quick Bake, Undo, Redo.

**Highlight Connected** appears as a check item — it reads the current state and toggles it.

The menu only activates when idle (no active drag, paint, or external tool operation). The keybinding is configurable via `hf_keymap.gd`.

### Radial Menu
Press **`` ` ``** (backtick) to open an 8-sector pie menu centered on the cursor. Move the mouse to highlight a sector, then left-click to select:

| Sector | Action |
|--------|--------|
| Box | Switch to Box shape |
| Cylinder | Switch to Cylinder shape |
| Select | Switch to Select tool |
| Paint | Switch to Surface Paint |
| Vertex | Enter Vertex Edit mode |
| Tex Pick | Activate Texture Picker |
| Measure | Activate Measure tool |
| Clip | Activate Clip tool |

**Dead zone:** Moving inside the inner ring (center area) deselects all sectors. Moving outside the outer ring also clears the selection — the cursor must be within the ring to select.

**Dismiss:** Press Escape, backtick, or right-click to close without selecting.

While the radial menu is open, it intercepts all viewport input. The keybinding is configurable via `hf_keymap.gd`.

### Quick Property Popups
Double-tap a key to open a small inline editor for a numeric property:

| Keys | Property | Controls |
|------|----------|----------|
| **G G** | Grid Snap | 1 SpinBox (snap size) |
| **B B** | Brush Size | 3 SpinBoxes (X, Y, Z dimensions) |
| **R R** | Paint Radius | 1 SpinBox (radius) |

The popup appears at the cursor position. Type a value and press **Enter** to apply, or **Escape** to cancel. Clicking outside the popup dismisses it (the click is consumed and does not pass through to the scene).

### Viewport Contextual Hints
When you switch tools, a brief instruction hint appears in the viewport overlay:
- **Draw**: "Click to place corner → drag to set size → release for height"
- **Select**: "Click brush to select, Shift+click to multi-select, drag to move"
- **Extrude Up/Down**: "Click a face to start extruding upward/downward"
- **Paint Floor**: "Click cells to paint, Shift+click to erase"
- **Paint Surface**: "Click brush faces to apply material"

Hints auto-fade after 4 seconds. Once you dismiss a hint (by switching away), it won't appear again. Hint dismissal persists across sessions. To reset all hints, delete `user://hammerforge_prefs.json` or clear the `hints_dismissed` key.

### Brush Color Coding

Brushes use distinct wireframe overlay colors so you can identify their operation type at a glance:

| Operation | Wireframe Color | Fill Color |
|-----------|----------------|------------|
| **Additive** (Union) | Green | Green tint |
| **Subtractive** | Red | Red tint with emission |
| **func_detail** entity | Blue | Bright blue tint |
| **trigger_*** entity | Blue | Medium blue tint |
| **func_wall** entity | Blue | Muted blue tint |
| **Other** brush entity | Blue | Slate blue tint |

This follows the classic level editor convention (Hammer, TrenchBroom): green = additive, red = subtractive, blue = entity.

### Grid Size Indicator

The viewport HUD shows the current grid snap value (e.g. "Grid: 16") persistently in the top-right panel. When the grid size changes — via the dock SpinBox, quick-property popup (G G), or the `[` / `]` hotkeys — the indicator briefly flashes bright yellow-white and fades back, providing instant feedback without leaving the viewport.

**Grid size hotkeys:**
- **`[`** — halve grid snap (e.g. 16 → 8), minimum 0.125
- **`]`** — double grid snap (e.g. 16 → 32), maximum 512

### Subtract Preview
Enable **Subtract Preview** in Manage tab → Settings to see real-time wireframe overlays at the AABB intersection of additive and subtractive brushes. Red wireframe boxes show exactly where subtractive brushes will cut into additive geometry. The preview updates automatically when brushes are added, removed, or moved (with a 0.15s debounce for performance). This helps visualize the effect of subtract operations before baking.

### Status bar
- Shows current status ("Ready", "Baking...", errors in red, warnings in yellow).
- Errors auto-clear after 5 seconds, success messages after 3 seconds.
- Displays selection count ("Sel: N brushes" or "Sel: 3 brushes, 5 faces") when brushes/faces are selected, with a **clear (x)** button to deselect.
- Live brush count with color-coded performance warnings.
- Bake progress bar updates during chunked bakes.
- Performance panel shows active brushes, paint memory, bake chunks, and last bake time.
- **Autosave warning**: a red "Autosave failed!" label appears if a threaded save fails. Auto-hides after 30 seconds.

## Snap Modes
HammerForge supports three snap modes that can be combined:

| Mode | Button | Behavior |
|------|--------|----------|
| **Grid** | G | Snap to grid increments (default, always-on) |
| **Vertex** | V | Snap to the 8 corners of existing brushes |
| **Center** | C | Snap to the center point of existing brushes |

Toggle modes independently using the G/V/C buttons below the Grid Snap row in the Brush tab. When multiple modes are enabled, the closest candidate wins — a nearby brush corner will beat a farther grid point. The snap threshold (default 2.0 world units) determines how close you need to be to a geometry candidate for it to take effect.

**Tip:** Enable Vertex snap when aligning brushes edge-to-edge. Enable Center snap when centering a brush inside another.

## Undo/Redo
- All brush operations (draw, delete, nudge, resize, paint, hollow, clip) support undo/redo.
- **Command collation**: rapid repeated operations (nudging with arrow keys, resizing via gizmo, painting brushes) are merged into a single undo entry within a 1-second window. One undo press reverses the entire sequence.
- Multi-step operations (hollow, clip) use transactions for atomicity.

## Entity Definitions
Brush entity classes (func_detail, func_wall, trigger_once, trigger_multiple) and point entities are data-driven. Definitions are loaded from `entities.json` (if present) or fall back to built-in defaults.

To add custom entity types:
1. Create `res://addons/hammerforge/entities.json`.
2. Add entries with `classname`, `description`, `is_brush_entity`, and optional `color` and `properties`.
3. The dock entity palette and brush entity class dropdown will auto-populate from these definitions.

## Material Library
The material palette can be saved and loaded as a JSON library file:
- **Save**: preserves resource paths of all palette materials.
- **Load**: restores the palette from saved paths.
- **Usage tracking**: materials in use by brushes are tracked; `find_unused_materials()` identifies cleanup candidates.

## Prototype Textures
HammerForge includes 150 built-in SVG prototype textures organized as 15 patterns in 10 color variations. Click **Refresh Prototypes** in the Paint tab → Materials section to add them all to the palette. The **Material Browser** displays them as a visual thumbnail grid with search and pattern/color filters — no need to memorize names. Patterns include solid, brick, checker, cross, diamond, dots, hex, stripes (diagonal/horizontal), triangles, zigzag, and directional arrows (up/down/left/right).

For GDScript API usage, see `docs/HammerForge_Prototype_Textures.md`.

## Design Constraints (Summary)
- DraftBrush previews are lightweight. Final geometry comes from bake.
- Subtractive brushes are staged as Pending Cuts until applied.
- Floor paint is grid-based; heightmaps displace floors only.
- `.map` export/import is for blockouts and does not preserve per-face materials.

For details, see `docs/HammerForge_Design_Constraints.md`.

## Data Portability
- `.hflevel` is the source of truth for full-fidelity editing.
- `.map` exchange is limited to basic brushes and point entities.
- `.glb` export includes baked geometry only.

For full details, see `docs/HammerForge_Data_Portability.md`.

## Install + Upgrade
For install steps, upgrade guidance, and cache reset help, see `docs/HammerForge_Install_Upgrade.md`.

## Shortcut HUD
The on-screen shortcut overlay updates dynamically based on your current tool and mode. Toggle it via the Show HUD checkbox in the Manage tab → Settings section. It shows:

| Context | Shortcuts Shown |
|---------|----------------|
| Draw (idle) | Click+Drag, Shift/Alt modifiers, X/Y/Z axis lock, Ctrl+Scroll size, Ctrl+D, Delete |
| Draw (dragging base) | Shift: Square, Alt+Shift: Cube, Click: Height stage, Right-click: Cancel. Live dimensions shown in banner |
| Draw (adjusting height) | Mouse: Change height, Click: Confirm, Right-click: Cancel. Live dimensions shown in banner |
| Select | Click/Shift/Ctrl selection, Escape, Delete, Ctrl+D, Arrow nudge, Ctrl+H Hollow, Shift+X Clip, Ctrl+Shift+F/C Floor/Ceiling |
| Extrude Up/Down (idle) | Click face + drag, U/J tool switch, Right-click cancel |
| Extrude Up/Down (active) | Move mouse to set height, Release to confirm, Right-click cancel |
| Floor Paint | Click+Drag, B/E/R/L/K tool shortcuts |
| Surface Paint | Click+Drag, radius/strength info |
| Vertex Edit | Click vertex to select, drag to move, E: edge mode, Ctrl+W: merge, Ctrl+E: split |
| Polygon Tool | Click to place verts, Enter: close, Escape: remove last |
| Path Tool | Click to place waypoints, Enter: finalize, Escape: remove last |

The HUD also shows current axis lock state (e.g. "[X Locked]").

## Customizable Keyboard Shortcuts

All keyboard shortcuts are data-driven and can be customized. The default bindings match the shortcuts shown throughout this guide.

**Default bindings:**

| Action | Default Key | Description |
|--------|-------------|-------------|
| Draw tool | D | Switch to Draw mode |
| Select tool | S | Switch to Select mode |
| Extrude Up | E / U | Switch to Extrude Up mode (E skipped in paint/vertex modes) |
| Extrude Down | Shift+E / J | Switch to Extrude Down mode (Shift+E skipped in paint/vertex modes) |
| Delete | Delete | Delete selected brushes |
| Duplicate | Ctrl+D | Duplicate selection |
| Group | Ctrl+G | Group selected brushes |
| Ungroup | Ctrl+U | Ungroup selection |
| Hollow | Ctrl+H | Convert brush to hollow room |
| Clip | Shift+X | Split brush along axis plane |
| Carve | Ctrl+Shift+R | Boolean-subtract from intersecting brushes |
| Move to Floor | Ctrl+Shift+F | Snap to nearest surface below |
| Move to Ceiling | Ctrl+Shift+C | Snap to nearest surface above |
| Measure | M | Multi-ruler tool (persistent rulers, angles, snap ref) |
| Decal | N | Place decal on surface with live preview |
| Polygon | P | Draw convex polygon, extrude to brush |
| Path | ; | Place waypoints, extrude corridor brushes |
| Edge sub-mode | E | Toggle vertex/edge sub-mode (in vertex mode) |
| Split edge | Ctrl+E | Insert midpoint on selected edge |
| Merge vertices | Ctrl+W | Merge selected vertices to centroid |
| Texture Picker | T | Eyedropper — sample face material |
| Apply Last Texture | Shift+T | Apply last picked texture to selection |
| Select All | A | Select all brushes and entities (clears face selection) |
| Deselect All | Shift+A | Deselect everything (brushes, entities, faces) |
| Select Similar | Shift+S | Select faces/brushes similar to current selection |
| Selection Filters | Shift+F | Open selection filter popover |
| Grid Size Down | [ | Halve grid snap (min 0.125) |
| Grid Size Up | ] | Double grid snap (max 512) |
| Axis Lock X/Y/Z | X / Y / Z | Constrain to axis |
| Paint tools | B / E / R / L / K | Bucket / Erase / Ramp / Line / Blend |
| Command palette | Shift+? / F1 / Ctrl+K | Searchable action palette with fuzzy search |
| Operation timeline | Ctrl+Shift+T | Toggle operation replay timeline |

**Rebinding:** Edit `user://hammerforge_keymap.json` (created on first run). Each entry maps an action name to `{"keycode": KEY_*, "ctrl": bool, "shift": bool, "alt": bool}`. Restart the plugin after editing.

**Toolbar labels** and **tooltips** update automatically from the keymap, so custom bindings are always reflected in the UI. Press the **?** button on the toolbar to open a searchable shortcut dialog showing all current keybindings grouped by category (Tools, Editing, Selection, Paint, Axis Lock).

## User Preferences

HammerForge stores cross-session preferences in `user://hammerforge_prefs.json`, separate from per-level settings.

Preferences include:
- Default grid snap size
- Autosave interval
- Recent file list (up to 10)
- Collapsed section states (which dock sections are expanded/collapsed)
- Last active tool
- HUD visibility
- Tutorial wizard visibility and progress step
- Dismissed viewport contextual hints

## Prefabs (Reusable Brush Groups)

Prefabs let you save a selection of brushes and entities as a reusable group and place copies anywhere in your level. The system supports variants, tags, live-linked instances, and visual debug overlays.

### Saving a Prefab
1. Select the brushes and/or entities you want to save.
2. Open Manage tab → Prefabs section.
3. Enter a name and click **Save** (or **Save Linked** to enable live propagation).
4. The prefab is saved as a `.hfprefab` JSON file in `res://prefabs/`.

**Quick Save**: Press **Ctrl+Shift+P** or click **Pfb** in the context toolbar to instantly save the current selection as a prefab with an auto-generated name. Also available via the context toolbar in both brush and entity selected contexts.

### Instantiating a Prefab
- Drag a prefab from the library list into the 3D viewport.
- The brushes and entities are placed at the drop position with new unique IDs.
- Entity I/O connections are automatically remapped to the new entity names.
- Each placed instance is tracked in the prefab system for variant cycling and propagation.
- The operation supports undo/redo.

### Prefab Variants
Prefabs can contain multiple variants (e.g., different door styles: wooden, metal, ornate).

- **Adding a variant**: Right-click a prefab in the library → **Add Variant**. Select the replacement geometry and name the variant.
- **Cycling variants**: Select a placed prefab instance and press **Ctrl+Shift+V** or click **Var▶** in the context toolbar. This cycles through all available variants in place.
- **Variant indicator**: The library list shows `[N variants]` next to prefabs that have multiple variants.

### Live-Linked Prefabs
When you save a prefab with **Save Linked**, all placed instances of that prefab maintain a link to the source file.

- **Push to source**: Edit a placed instance, then click **Push** in the context toolbar to update the `.hfprefab` source file with the current state.
- **Propagate to all**: Click **Pull** on any linked instance to propagate the current source file to all linked instances in the level.
- Per-instance overrides (size, transform changes) are tracked and reapplied after propagation.
- The context toolbar shows a `[linked]` badge on linked prefab instances.

### Tags and Search
- **Adding tags**: Right-click a prefab in the library → **Edit Tags**. Enter comma-separated tags (e.g., `door, architecture, interior`).
- **Searching**: Use the search bar at the top of the prefab library. Searches match both prefab names and tags.
- **Tag filtering**: Use the Tag dropdown to filter the list to prefabs with a specific tag.

### Visual Debug Overlay
When hovering over a node that belongs to a prefab instance in the 3D viewport, a cyan wireframe bounding box appears around the entire instance. If the instance has overrides relative to the source, orange sphere markers appear on modified nodes.

### What's Captured
- Brush geometry (shape, size, operation, material, transform relative to group centroid)
- Entity data (type, class, properties, I/O connections, transform relative to centroid). Each entity receives a stable unique ID on instantiation — entity membership is tracked by UID, not scene name, so renaming nodes or having duplicate names will not break prefab tracking.
- Brush IDs and group IDs are cleared on capture; new ones are assigned on instantiation.
- Tags (metadata for search/filtering)
- Variants (alternate brush/entity configurations stored alongside the base)

### File Format
`.hfprefab` files are JSON with the same encoding as `.hflevel` (Vector3, Transform3D serialized via `HFLevelIO`). They support optional `tags` (string array) and `variants` (named alternate configurations) fields. They are portable and can be shared between projects.

These persist across editor restarts. Per-level settings (cordon, texture lock, materials) remain in `.hflevel` files.

## Tool Availability (Poll System)

Some actions require specific conditions to run:
- **Hollow, Clip, Move to Floor/Ceiling** require at least one brush selected. When nothing is selected, these buttons are grayed out with an inline hint ("Select a brush to use these tools") visible in the Selection Tools section.
- **Face-dependent controls** (Assign to Selected Faces, UV editing) show "Enable Face Select Mode and click a face to edit" when no face is selected.
- **Extrude** requires a LevelRoot in the scene. In extrude mode, a semi-transparent face highlight (green for up, red for down) previews which face you'll select before clicking.
- **External tools** can define their own requirements via `can_activate()`.

The mode indicator banner always shows the current tool and gesture stage. The status bar shows selection count with a clear button.

## Brush Creation (CAD style)
1) Base drag: click and drag to define the base.
2) Height stage: release mouse, move up/down, click to commit.

Modifier keys
- Shift: square base.
- Shift + Alt: cube.
- Alt: height-only.
- X/Y/Z: axis locks (shown in HUD as "[X Locked]" etc.).
- Right-click: cancel.

General keyboard shortcuts
- Delete: remove selected brushes.
- Ctrl+D: duplicate selected brushes.
- Arrow keys: nudge selected brushes (XZ plane).
- PageUp/PageDown: nudge selected brushes (Y axis).
- Escape: clear selection.
- Ctrl+Scroll: adjust brush size.
- `[` / `]`: halve / double grid snap size.

Extrude shortcuts
- U: Extrude Up tool.
- J: Extrude Down tool.

Group shortcuts
- Ctrl+G: Group selected brushes/entities.
- Ctrl+U: Ungroup selected brushes/entities.

Paint tool shortcuts (active when Paint Mode is enabled)
- B: Brush tool.
- E: Erase tool.
- R: Rectangle tool.
- L: Line tool.
- K: Bucket fill tool.

## Vertex Editing

Vertex mode lets you select and move individual brush vertices for precision geometry editing.

### Entering Vertex Mode
Press **V** (keyboard shortcut or the **V** toggle button in the toolbar) to enter vertex mode. Selected brushes show their vertices as crosses and edges as wireframe lines.

### Vertex Sub-Mode
- **Vertex mode** (default): click vertices to select them, drag to move.
- **Edge mode** (press **E** to toggle): click edges to select them. Selected edges highlight orange; hovered edges highlight yellow.

### Edge Operations
- **Split edge** (Ctrl+E): select exactly one edge, then press Ctrl+E to insert a midpoint vertex. The two faces sharing the edge each gain the new vertex. Convexity is mathematically guaranteed.
- **Merge vertices** (Ctrl+W): select 2+ vertices, then press Ctrl+W to merge them to their centroid. Merging is rejected if it would break convexity.

### Convexity Enforcement
All vertex operations validate that the brush remains convex. If a move or merge would create a concave shape, the operation is rejected and the brush reverts to its previous state.

### Clip to Convex
If a brush has been deformed into a non-convex shape (e.g., by external editing or import), use the **Convex** button in the vertex edit context toolbar to recompute its convex hull. This:
1. Computes the convex hull of all brush vertices.
2. Rebuilds faces from the hull planes.
3. Inherits UV settings (projection, scale, offset, rotation, material) from the closest original face for each new hull face.

This is a fallback repair tool, not a modeling operation — it discards any concave geometry.

### Shortcuts
| Key | Action |
|-----|--------|
| V | Enter vertex mode |
| E | Toggle vertex/edge sub-mode |
| Ctrl+E | Split selected edge |
| Ctrl+W | Merge selected vertices |

## Polygon Tool

The polygon tool lets you draw arbitrary convex shapes and extrude them into brushes.

### Workflow
1. Press **P** to activate the Polygon tool.
2. Click in the viewport to place vertices on the ground plane (grid-snapped).
3. Each new vertex is validated for convexity -- concave placements are rejected.
4. Close the polygon by clicking near the first vertex (within the auto-close threshold) or pressing **Enter** (requires 3+ vertices).
5. Move the mouse up/down to set the extrusion height, then click to confirm.
6. The brush is created with full undo/redo support.

### Preview
During placement, a cyan outline shows the polygon shape. During height extrusion, green vertical edges and the top face outline appear.

### Settings
| Setting | Default | Description |
|---------|---------|-------------|
| auto_close_threshold | 1.5 | Distance to first vertex that triggers auto-close |

### Shortcuts
| Key | Action |
|-----|--------|
| P | Activate Polygon tool |
| Left-click | Place vertex / confirm height |
| Enter | Close polygon (3+ verts) / confirm height |
| Escape / Right-click | Remove last vertex / cancel |

## Path Tool

The path tool creates corridors by placing waypoints and extruding a rectangular cross-section along the path.

### Workflow
1. Press **;** (semicolon) to activate the Path tool.
2. Click in the viewport to place waypoints on the ground plane (grid-snapped).
3. Press **Enter** to finalize the path (requires 2+ waypoints).
4. For each segment, an oriented-box brush is created. At interior corners, a miter joint brush fills the gap.
5. All brushes are auto-grouped and created in a single undo action.

### Preview
During placement, a cyan polyline shows the path with parallel offset lines indicating width and perpendicular ticks at waypoints.

### Settings
| Setting | Default | Description |
|---------|---------|-------------|
| path_width | 4.0 | Width of the corridor cross-section |
| path_height | 4.0 | Height of the corridor cross-section |
| miter_joints | true | Fill gaps at path corners with wedge brushes |
| path_extra | None | Auto-generate extras: None, Stairs, Railing, or Trim |
| stair_step_height | 0.25 | Step height for auto-stairs (only when path_extra = Stairs) |
| railing_height | 1.0 | Railing height above path surface |
| railing_thickness | 0.1 | Thickness of railing rails and posts |
| railing_post_spacing | 2.0 | Distance between railing posts |
| trim_width | 0.2 | Width of edge trim strips |
| trim_height | 0.1 | Height of edge trim strips |
| trim_material_idx | -1 | Material index for trim faces (-1 = default material) |

### Auto-Generated Extras
When `path_extra` is set to a value other than None, additional geometry is auto-generated after the base path segments:

- **Stairs**: Step brushes along sloped path segments. Step count is derived from height difference / step height. Flat segments are skipped.
- **Railings**: Top rail + posts on both sides of the path. Posts are spaced evenly along each segment. Both rails and posts share the group ID with path segments.
- **Trim**: Edge strips run alongside both sides of the path. If `trim_material_idx >= 0`, all faces of trim brushes are assigned that material index.

Preview lines during placement: green ticks for stairs, yellow for railings, orange for trim.

### Shortcuts
| Key | Action |
|-----|--------|
| ; | Activate Path tool |
| Left-click | Place waypoint |
| Enter | Finalize path (2+ waypoints) |
| Escape / Right-click | Remove last waypoint / cancel |

## Visgroups (Visibility Groups)
Visgroups let you organize your map into logical groups and toggle their visibility.

1. Open the **Manage** tab in the dock.
2. Type a name in the Visgroup field and click **New** to create a visgroup.
3. Select brushes/entities in the viewport, then click **Add Sel** to add them to the visgroup.
4. Click the visgroup name in the list to toggle between **[V]** (visible) and **[H]** (hidden).

Notes:
- A node can belong to multiple visgroups. If ANY visgroup it belongs to is hidden, the node is hidden.
- Nodes not in any visgroup are always visible.
- Use **Rem Sel** to remove selected nodes from the visgroup, or **Delete** to remove the visgroup entirely.
- Visgroups persist in `.hflevel` saves and undo/redo state.

## Grouping
Groups let you persistently link brushes/entities so they select and move together.

1. Select the brushes/entities you want to group.
2. Press **Ctrl+G** (or click **Group Sel** in the Manage tab → Visgroups & Groups section).
3. Click any member of the group -- all members are selected automatically.
4. Press **Ctrl+U** (or click **Ungroup**) to dissolve the group.

Notes:
- Each node can belong to one group at a time.
- Groups persist in `.hflevel` saves and undo/redo state.

## Per-Face UV Controls

The Paint tab includes a UV Editor section for fine-tuning per-face UV settings:

### Projection Mode
Select a UV projection mode from the dropdown:
- **Planar X/Y/Z**: projects UVs along the specified axis.
- **Box UV**: automatically picks the best axis per face (default for most workflows).
- **Cylindrical**: wraps UVs around a cylinder (best for round shapes).

Click **Re-project UVs** to recompute UVs using the selected projection mode (resets scale/offset/rotation).

### UV Transform
When a face is selected, adjust its UV parameters with the spinboxes:
- **Scale X/Y**: texture repeat scale (default 1.0).
- **Offset X/Y**: texture offset in UV space.
- **Rotation**: texture rotation in degrees.

Changes are live-previewed and fully undoable. Rapid spinbox changes merge into a single undo step.

### Material Browser Integration
Right-click a material thumbnail in the Material Browser and choose **Apply + Re-project (Box UV)** to assign the material and reset UV projection in one step.

## Texture Lock
When Texture Lock is enabled, moving or resizing a brush automatically adjusts its face UVs so textures stay aligned.

1. Check **Texture Lock** in the Brush tab (enabled by default).
2. Move or resize brushes normally -- UV alignment is preserved.
3. Uncheck to disable (UVs will shift with transforms as before).

Notes:
- Works with PLANAR_X, PLANAR_Y, PLANAR_Z, and BOX_UV projections.
- CYLINDRICAL projection is not compensated (complex; future enhancement).
- Persists in `.hflevel` settings.

## Cordon (Partial Bake)
The cordon restricts bake output to an AABB region, useful for iterating on a specific area of a large map.

1. Open the **Manage** tab in the dock.
2. Check **Enable Cordon** to activate.
3. Set the min/max coordinates with the spinboxes, or select brushes and click **Set from Selection**.
4. A yellow wireframe shows the cordon bounds in the viewport.
5. Bake -- only brushes intersecting the cordon AABB are included.

Notes:
- Disable cordon to bake the entire map.
- Cordon settings persist in `.hflevel` saves.

## Extrude (Up / Down)
The Extrude tools let you extend an existing brush by clicking one of its faces and dragging to create a new brush.

1. Press **U** (Extrude Up) or **J** (Extrude Down), or click the toolbar buttons.
2. Move the mouse over brush faces -- a **semi-transparent hover highlight** shows which face you'll select (green for up, red for down).
3. Click on a brush face -- a semi-transparent preview appears.
4. Drag the mouse vertically to set the extrude height (grid-snapped). The mode indicator shows "Extruding..." with numeric input if you type.
5. Release the mouse to commit the new brush.

Notes
- **Extrude Up** shows a green preview; **Extrude Down** shows a red preview.
- The new brush inherits the source brush's material.
- The extruded brush is a standard DraftBrush (box) and works with Bake, materials, and undo/redo.
- Right-click cancels the extrude in progress.

## Floor Paint
1. Enable Paint Mode.
2. Open the **Paint** tab → **Floor Paint** section.
3. Choose tool, brush shape (Square or Circle), radius, and layer.
4. Paint in the viewport.

Notes
- **Brush Shape**: Square fills a full box of cells; Circle clips corners using Euclidean distance.
- Live preview updates while dragging.
- Bucket fills a contiguous region (click filled to erase).
- Generated geometry appears under `LevelRoot/Generated`.
- Generated flat floors/walls are DraftBrush nodes and are included in Bake.

### Region Streaming (Large Worlds)
Region streaming keeps large paint grids responsive by loading only nearby regions.
1. Enable **Streaming** in the Paint tab → Regions section.
2. Set **Region Size** (cells) and **Stream Radius** (regions).
3. Toggle **Show Region Grid** to visualize loaded regions.
4. Paint normally; regions auto-load around the cursor.

Notes
- Region data is saved to `.hfr` files in `<level>.hfregions/`.
- The `.hflevel` stores a region index and layer settings.

### Heightmap Terrain
Heightmaps add vertical displacement to painted floors:
1. Paint cells on a layer using Brush/Rect/Line/Bucket.
2. Click **Import** to load a PNG/EXR heightmap, or **Generate** for procedural noise.
3. Adjust **Height Scale** to control displacement amplitude.
4. Adjust **Layer Y** to set the base height of the layer.

When a layer has a heightmap, its floors are generated as displaced MeshInstance3D nodes (not DraftBrush). These live under `Generated/HeightmapFloors` and are baked directly (bypassing CSG) with trimesh collision shapes.

### Material Blending
The Blend tool paints per-cell material blend weights on filled cells:
1. Fill cells first (Brush/Rect/etc.).
2. Switch to the **Blend** tool.
3. Choose a **Blend Slot** (B/C/D).
4. Adjust **Blend Strength** (0.0-1.0) in the dock.
5. Paint over filled cells to set blend weights.

Blend weights drive a four-slot shader (`hf_blend.gdshader`). Slot A is the implicit base, while slots B/C/D are controlled by the blend map (RGB) sampled on the UV2 channel.

Terrain slots:
- Use **Slot A-D** texture pickers to assign textures for the terrain blend shader.
- **Slot Scale** controls per-slot UV tiling.

## Face Materials and UVs
1. Open the **Paint** tab → **Materials** section.
2. Click **Refresh Prototypes** to load all 150 built-in textures, or click `Add` to load a custom material resource (example: `materials/test_mat.tres`).
3. Browse the visual thumbnail grid — use search, pattern dropdown, or color swatches to filter.
4. Click a thumbnail to select a material. Hover to preview it on selected faces.
5. Enable `Face Select Mode`.
6. Use the Select tool and click faces in the viewport.
7. Click `Assign to Selected Faces`, or right-click the thumbnail → "Apply to Selected Faces".
8. Press **T** to use the **Texture Picker** — click any face to sample its material.

UV editing:
- Open the **Paint** tab → **UV Editor** section after selecting a face.
- Drag UV points to edit.
- Use `Reset Projected UVs` to regenerate UVs from projection.

Notes:
- Face data is stored per DraftBrush face.
- Materials and UVs persist in `.hflevel` saves.

## Surface Paint (3D)
1. Enable Paint Mode.
2. Open the **Paint** tab → **Surface Paint** section and set `Paint Target = Surface` (if needed).
3. Pick a layer and assign a texture.
4. Paint in the viewport.

Notes:
- Radius is in UV space (0.0 to 1.0).
- Surface paint updates the DraftBrush preview immediately.
- Surface paint is separate from floor paint layers.
- If paint affects the floor, set `Paint Target = Surface` in the Surface Paint section.

## Displacement Surfaces

Displacement surfaces turn a flat quad face into a subdivided terrain grid that you can sculpt interactively, similar to Source Engine displacements.

### Creating a Displacement
1. Select a brush and enter **Face Select Mode**.
2. Click a **quad face** (exactly 4 vertices).
3. Open the **Brush** tab → **Displacement** section.
4. Set **Power** (2 = 5x5, 3 = 9x9, 4 = 17x17 vertices).
5. Click **Create**. The face becomes a subdivided grid.

### Painting (Sculpting)
1. Enable **Paint Mode** in the dock and ensure the **Displacement** section is expanded.
2. Select a displaced face.
3. Choose a **Paint Mode**: Raise, Lower, Smooth, Noise, or Alpha.
4. Set **Radius** and **Strength**.
5. Click and drag on the face in the viewport to sculpt.

Paint uses a circular brush with quadratic falloff. Strokes are continuous — the entire stroke commits as a single undo action when you release the mouse button.

### Settings
- **Elevation**: global height scale multiplier for the displacement grid.
- **Power**: subdivision level (changing power resamples existing data via bilinear interpolation).
- **Sew Group**: integer group ID. Click **Sew** to snap shared boundary vertices between adjacent displacements in the same sew group.

### Destroying a Displacement
Click **Destroy** to revert a displaced face back to a flat quad.

Notes:
- Displacement requires a quad face (4 vertices). Triangles and N-gons are not supported.
- Displacement data is serialized in `.hflevel` saves.
- The baker generates per-vertex normals for displaced faces (smooth shading).

## Bevel and Face Inset

### Edge Bevel (Chamfer)
Replace a sharp edge with a rounded profile:
1. Enter **Vertex mode** (V key) and switch to **Edge sub-mode** (E key).
2. Select one or more edges.
3. Open the **Brush** tab → **Bevel** section.
4. Set **Segments** (1-16) and **Radius** (distance the bevel cuts into the brush).
5. Click **Bevel Edge**.

The selected edges are replaced with bevel strip faces. Higher segment counts produce smoother curves.

### Face Inset
Shrink a face inward and create connecting side faces:
1. Select a face in **Face Select Mode**.
2. Open the **Brush** tab → **Bevel** section.
3. Set **Inset** (distance to shrink inward) and optional **Height** (extrude along normal).
4. Click **Inset Face**.

Notes:
- Inset distance cannot exceed the face's corner-to-centroid distance (the operation is rejected with a toast if too large).
- Both bevel and inset operations are fully undoable.

## Entities (early)
- Place nodes under `LevelRoot/Entities` or set meta `is_entity = true`.
- Entities are selectable and excluded from bake.
- Entity palette supports drag-and-drop placement.

Entity definitions live in `res://addons/hammerforge/entities.json`.
Example (billboard preview):

```json
{
  "light_point": {
    "class": "OmniLight3D",
    "preview": {
      "type": "billboard",
      "path": "res://addons/hammerforge/icon.png",
      "color": "#ffff00"
    },
    "properties": [
      {"name": "range", "type": "float", "default": 10.0},
      {"name": "energy", "type": "float", "default": 1.0},
      {"name": "color", "type": "color", "default": "#ffffff"}
    ]
  }
}
```

## Bake Output
Bake creates `BakedGeometry`:
- If chunked baking is enabled, it adds `BakedChunk_x_y_z` nodes.
- Collision shape type depends on **Collision Mode** (Inspector property on LevelRoot):
  - **Mode 0** (default): Each chunk has a MeshInstance3D and StaticBody3D with a single ConcavePolygonShape3D (trimesh).
  - **Mode 1**: Each chunk has a StaticBody3D containing one ConvexPolygonShape3D per brush (convex hulls). Better for physics broadphase and navmesh generation.
  - **Mode 2**: Each visgroup gets its own StaticBody3D with convex hulls for all its member brushes. Ungrouped brushes share a default body. Best for room-based physics partitioning and bot navigation.

Generated flat floor paint brushes are included in the CSG bake. Heightmap floor meshes are duplicated directly into the baked output with trimesh collision shapes (they bypass CSG since they are already ArrayMesh). Heightmap collision is appended after visgroup partitioning (mode 2), so heightmap shapes are always preserved.

Use Face Materials (optional):
- Enables per-face material baking without CSG.
- Subtract brushes are ignored in this mode.
- Bakes cooperatively (yields every 8 brushes) so the editor stays responsive on large levels.

## Save/Load (.hflevel)
- Save .hflevel stores brushes, entities, settings, materials palette, face data, and paint layers.
- Paint layer data includes per-chunk `material_ids`, `blend_weights` (+ _2/_3), optional `heightmap_b64`, `height_scale`, and terrain slot settings.
- Load .hflevel restores them. Missing heightmap/material fields default to zero (backward-compatible).
- Autosave can write to a configurable path.

## Capturing Exit-Time Errors
PowerShell command:

```powershell
Start-Process -FilePath "C:\Godot\Godot_v4.6-stable_win64.exe" `
  -ArgumentList '--editor','--path','C:\hammerforge' `
  -RedirectStandardOutput "C:\Godot\godot_stdout.log" `
  -RedirectStandardError "C:\Godot\godot_stderr.log" `
  -NoNewWindow
```

## Troubleshooting
No brushes appear
- Ensure HammerForge is enabled.
- Select LevelRoot.
- Use Create Floor so raycasts hit something.

Subtract does nothing
- Subtract only affects Add brushes and is visible after Bake.
- Pending cuts appear in bright orange-red; once applied they turn standard red.

Paint preview looks wrong
- Regenerate by deleting `LevelRoot/Generated` and paint again.

Dock not showing
- Restart Godot after enabling the plugin.

Face selection not working
- Enable Face Select Mode in the Paint tab → Materials section.
- Use the Select tool (not Draw).

Material fails to load
- Material `.tres` files must not have a UTF-8 BOM. If Godot reports "Expected '['" on a `.tres` file, re-save it without BOM (or create a fresh one via FileSystem -> New Resource -> StandardMaterial3D).

Heightmap mesh not appearing
- Ensure the active layer has a heightmap assigned (use Import or Generate in the Paint tab → Heightmap section).
- Confirm cells are painted first -- heightmap only displaces filled cells.

Blend shader shows only one slot
- Paint blend weights using the Blend tool on already-filled cells.
- Set a Blend Slot (B/C/D) and assign textures to Slot A-D.

Displacement create fails
- The face must be a quad (exactly 4 vertices). Triangles and N-gons are not supported.
- Ensure a face is selected in Face Select Mode.

Displacement paint does nothing
- Enable Paint Mode in the dock.
- Expand the Displacement section (it must be visible, not collapsed).
- Ensure the face has a displacement (click Create first).

Bevel edge fails
- Enter Vertex mode (V), then Edge sub-mode (E). Select an edge.
- The edge must be shared by exactly 2 faces.

Inset face fails
- The inset distance is too large relative to the face size. Use a smaller value.
- Verify the blend_map texture is generated (requires cells with non-zero blend weights).
