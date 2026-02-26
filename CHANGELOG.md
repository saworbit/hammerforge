# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Added
- **Clipping tool:** Split a brush along an axis-aligned plane into two pieces.
  - `clip_brush_by_id(brush_id, axis, split_pos)` on `hf_brush_system.gd`.
  - Auto-detect split axis from face normal via `clip_brush_at_point()`.
  - Snaps split position to grid. Copies material, brush entity class, visgroups, and group ID.
  - Keyboard shortcut: Shift+X. Clip button in Actions section of Manage tab.
  - Full undo/redo support via state snapshot.
- **Entity I/O system:** Source-style entity input/output connections.
  - Data model: output connections stored as `entity_io_outputs` meta on entity nodes.
  - Connection fields: output_name, target_name, input_name, parameter, delay, fire_once.
  - `add_entity_output()`, `remove_entity_output()`, `get_entity_outputs()` on entity system.
  - `find_entities_by_name()` resolves target references across entities and brushes.
  - `get_all_connections()` returns all I/O connections in the scene for visualization.
  - I/O connections serialized in `.hflevel` saves and undo/redo state.
  - Dock UI: collapsible "Entity I/O" section in Entities tab with Output, Target, Input,
    Parameter, Delay, Fire Once fields. Add/Remove buttons and connection ItemList.
  - I/O list auto-refreshes when selecting an entity.
- **Brush entity visual indicators:** Color-coded overlays for tagged brush entities.
  - `func_detail` brushes get cyan tint, `trigger_*` brushes get orange tint.
  - Semi-transparent MeshInstance3D overlay for visual differentiation in viewport.
- **Hollow tool:** Convert a solid brush into a hollow room with configurable wall thickness.
  - Creates 6 wall brushes (top/bottom/left/right/front/back) and removes the original.
  - Preserves material from the original brush. Keyboard shortcut: Ctrl+H.
  - Wall thickness SpinBox in Actions section of Manage tab.
  - Full undo/redo support via state snapshot.
- **Numeric input during drag:** Type exact dimensions while drawing or extruding brushes.
  - During base drag or height adjustment, type digits to set precise size.
  - Enter applies the value and advances/commits. Backspace edits. Escape cancels.
  - Numeric buffer displayed in the shortcut HUD during drag.
- **Brush entity conversion (Tie to Entity):** Tag brushes as brush entity classes.
  - Tie/Untie buttons in Actions section with class dropdown (func_detail, func_wall, trigger_once, trigger_multiple).
  - `func_detail` brushes are excluded from structural CSG bake (detail geometry).
  - `trigger_*` brushes are excluded from structural bake (collision-only volumes).
  - `brush_entity_class` meta persists in `.hflevel` saves and undo/redo state.
- **Move to Floor / Move to Ceiling:** Snap selected brushes to the nearest surface.
  - Raycasts against other brushes and physics bodies to find nearest surface.
  - Grid-snapped result. Keyboard shortcuts: Ctrl+Shift+F (floor), Ctrl+Shift+C (ceiling).
  - Buttons in Actions section of Manage tab. Full undo/redo support.
- **Texture alignment Justify panel:** Quick UV alignment controls in the UV Editor section.
  - Fit, Center, Left, Right, Top, Bottom alignment modes.
  - "Treat as One" checkbox for aligning multiple selected faces as a unified surface.
  - Works with the existing face selection system.
- **Hammer gap analysis** documented in ROADMAP.md with prioritized wave plan.
- **Dock UX overhaul:** Consolidated from 8 tabs to 4 (Brush, Paint, Entities, Manage).
  - New `HFCollapsibleSection` (`ui/collapsible_section.gd`) reusable component for collapsible UI sections.
  - **Brush tab** (was Build): focused on shape, size, grid snap, material, operation mode, texture lock.
  - **Paint tab** (merged FloorPaint + SurfacePaint + Materials + UV): 7 collapsible sections.
  - **Manage tab** reorganized with 8 collapsible sections: Bake, Actions, File, Presets, History, Settings, Performance, plus Visgroups & Cordon.
  - "No LevelRoot" banner displayed at dock top when no root is found.
  - Toolbar buttons now show keyboard shortcut labels: `Draw (D)`, `Sel (S)`, `Ext▲ (U)`, `Ext▼ (J)`.
  - Paint and Manage tab contents built programmatically via `_build_paint_tab()` and `_build_manage_tab()`.
  - Bake options and editor toggles moved from old Build tab into Manage → Bake Settings and Settings sections.
- **Sticky LevelRoot discovery:** Users no longer need to re-select LevelRoot after clicking other nodes.
  - `plugin.gd`: `_handles()` returns true for any node when a LevelRoot exists; `_edit()` keeps `active_root` sticky; deep recursive tree search via `_find_level_root_deep()`.
  - `dock.gd`: sticky `level_root` reference in `_process()`; deep recursive search via `_find_level_root_in()` / `_find_level_root_recursive()`.
- **Visgroups (visibility groups):** Named groups (e.g. "walls", "detail") with per-group show/hide.
  - `HFVisgroupSystem` subsystem manages CRUD, membership (stored as node meta), and visibility refresh.
  - Nodes in ANY hidden visgroup are hidden (Hammer semantics). Nodes not in any visgroup stay visible.
  - Dock UI: visgroup list with [V]/[H] toggle, New/Add Sel/Rem Sel/Delete buttons in Manage tab.
  - Full serialization: visgroups persist in `.hflevel` saves and undo/redo state.
- **Brush/entity grouping:** Persistent groups that select and move together.
  - Single group per node via `group_id` meta. Auto-generated or named groups.
  - Ctrl+G groups selection, Ctrl+U ungroups. Clicking a grouped node selects all group members.
  - Dock UI: Group Sel / Ungroup buttons in Manage tab.
  - Groups persist in `.hflevel` saves and undo/redo state.
- **Texture lock:** UV alignment preserved when moving or resizing brushes.
  - Per-projection-axis UV offset and scale compensation in `face_data.gd`.
  - Supports PLANAR_X/Y/Z and BOX_UV projections. Skips CYLINDRICAL.
  - Toggle via `texture_lock` property on LevelRoot (default: on).
  - Dock UI: "Texture Lock" checkbox in Build tab.
  - Persists in `.hflevel` settings.
- **Cordon (partial bake):** Restrict bake to an AABB region.
  - Brushes outside the cordon AABB are skipped during collection and CSG assembly.
  - Yellow wireframe visualization via ImmediateMesh (12 AABB edge lines).
  - "Set from Selection" computes merged AABB of selected brushes + margin.
  - Dock UI: Enable checkbox, min/max spinboxes, "Set from Selection" button in Manage tab.
  - Persists in `.hflevel` settings.
- **GUT unit test suite** with 47 tests across 4 test files:
  - `test_visgroup_system.gd` (18 tests): CRUD, visibility, membership, serialization.
  - `test_grouping.gd` (9 tests): group creation, meta, ungroup, regroup, serialization.
  - `test_texture_lock.gd` (10 tests): UV compensation for all projection types.
  - `test_cordon_filter.gd` (10 tests): AABB filtering, chunk collection, chunk_coord utility.
- CI workflow now runs GUT tests alongside gdformat/gdlint checks.
- Bake progress updates with chunk status in the dock.
- Bake Dry Run action for preflight counts and chunk estimates.
- Validate Level action with optional auto-fix for common issues.
- Missing dependency checks before bake/export.
- Autosave rotation with timestamped history files.
- Performance panel with brush, paint memory, chunk, and bake time stats.
- Settings export/import for editor preferences.
- Sample levels: minimal scene and stress test scene.
- Install + upgrade guide with cache reset steps.
- Design constraints document to make tradeoffs explicit.
- Data portability guide for `.hflevel`, `.map`, and `.glb`.
- Demo clip checklist and naming convention doc.
- Roadmap and contributing guidelines.
- **Extrude Up / Extrude Down tools** for extending brush faces vertically:
  - Click any brush face and drag to create a new box brush extruding from that face.
  - Extrude Up (green preview) and Extrude Down (red preview) with grid-snapped height.
  - Full undo/redo support via `_commit_brush_placement`.
  - Inherits source brush material automatically.
  - New `HFExtrudeTool` class (`hf_extrude_tool.gd`) using `FaceSelector` raycast.
  - Toolbar buttons (Ext+/Ext-) in same button group as Draw/Select.
  - Keyboard shortcuts: U (Extrude Up), J (Extrude Down).
  - Input state machine: added `EXTRUDE` mode to `HFInputState`.
  - Shortcut HUD: two new views (extrude idle, extruding active).
- **Multi-layer heightmap integration** for floor paint:
  - Heightmap import (PNG/EXR) and procedural noise generation (FastNoiseLite) per paint layer.
  - Per-cell material IDs and blend weights stored alongside existing bitset data.
  - Heightmap-displaced mesh generation via `HFHeightmapSynth` (SurfaceTool with per-vertex displacement).
  - Four-slot blend shader (`hf_blend.gdshader`) using UV2 channel for per-chunk blend maps (RGB = slots B/C/D), with default terrain colors, configurable grid overlay, and tint-compatible texture support.
  - Blend paint tool (`HFStroke.Tool.BLEND = 5`) for painting material blend weights on filled cells.
  - Auto-connector tool (`HFConnectorTool`) generating ramp and stair meshes between layers at different heights.
  - Foliage populator (`HFFoliagePopulator`) with height/slope filtering and MultiMeshInstance3D scatter.
  - Heightmap floors bake directly into output (bypass CSG) with trimesh collision shapes.
  - Dock UI: Heightmap Import/Generate buttons, Height Scale and Layer Y spinboxes, Blend Strength + Blend Slot controls.
- **Four-slot terrain blending** for heightmap floors:
  - New blend map format (RGB weights for slots B/C/D, slot A implicit).
  - Per-layer terrain slot textures + UV scales.
  - Blend Slot selection in the Floor Paint tab.
- **Region streaming** for floor paint:
  - Region-based loading/unloading of paint chunks.
  - `.hfr` region files alongside `.hflevel` with a region index.
  - Floor Paint tab controls for streaming settings + region grid overlay.
- Floor paint brush shape selector (Square or Circle) in the Floor Paint tab.
- Per-face material palette with face selection mode.
- Dynamic context-sensitive shortcut HUD that updates based on current tool and mode.
- Comprehensive tooltips on all dock controls (snap buttons, bake options, paint settings, etc.).
- Selection count indicator in the status bar ("Sel: N brushes").
- Paint tool keyboard shortcuts: B (Brush), E (Erase), R (Rect), L (Line), K (Bucket).
- Color-coded pending cuts: orange-red with high emission to distinguish from applied subtract brushes.
- Color-coded error/warning status messages with auto-clear timeout.
- Sample material resource for palette testing (`materials/test_mat.tres`).
- UV editor for per-face UV editing.
- Surface paint tool with per-face paint layers and texture picker.
- Bake option: Use Face Materials (bake per-face materials without CSG).
- Dock reorganized: Floor Paint and Surface Paint tabs.

### Changed
- Dock consolidated from 8 tabs (Build, FloorPaint, Materials, UV, SurfacePaint, Entities, Manage) to 4 tabs (Brush, Paint, Entities, Manage).
- Build tab renamed to **Brush** tab; bake options and editor toggles moved to Manage tab.
- FloorPaint, SurfacePaint, Materials, and UV tabs merged into single **Paint** tab with collapsible sections.
- Manage tab reorganized with collapsible sections for better discoverability.
- LevelRoot discovery is now "sticky": selecting non-LevelRoot nodes no longer breaks viewport input.
- Plugin `_handles()` uses deep recursive tree search and accepts any node when a LevelRoot exists.
- Dock `_process()` uses sticky reference; only nulls `level_root` when node is removed from tree.
- Brush delete undo now uses brush IDs and `create_brush_from_info()` snapshots for stability.
- New brushes placed via direct placement now receive stable brush IDs.
- Standardized editor actions under a single undo/redo helper with state snapshots.
- Paint Mode can target either floor paint or surface paint.
- .hflevel now persists materials palette and per-face data.
- .hflevel now persists per-chunk `material_ids`, `blend_weights` (+ _2/_3), `heightmap_b64`, `height_scale`, and terrain slot settings.
- Floor paint layers with heightmaps route to `HFHeightmapSynth` (MeshInstance3D) instead of CSG DraftBrush.
- Generated heightmap floors stored under `LevelRoot/Generated/HeightmapFloors`.

### Fixed
- Fixed reconciler ghost references: `_index.erase(gid)` and `remove_child()` before `queue_free()` in `hf_reconciler.gd` to prevent stale node references.
- Fixed silent write failure in `hf_file_system.gd:export_map()` — added `file.get_error()` check after `store_string()`.
- Fixed unreachable guard in `hf_brush_system.gd` — `parts.size() == 0` after `String.split()` changed to `parts.size() < 2`.
- Reverted bloated `level_root.tscn` (11,652 lines of serialized FaceData back to 79-line template).
- Fixed LevelRoot discovery: plugin no longer loses `active_root` when clicking non-LevelRoot nodes; dock uses deep recursive search.
- Fixed dock disabled-state handling for SpinBox controls to avoid invalid `disabled` property assignments.
- Fixed heightmap mesh disappearing on every regeneration (height scale change, second generate noise click). Root cause: `_clear_generated()` used `queue_free()` (deferred) but `reconcile()` ran immediately after, finding ghost nodes still in the tree. Fix: `remove_child()` before `queue_free()`.
- Fixed missing walls when heightmap is active (same `queue_free` timing root cause).
- Fixed heightmap mesh rendering as a featureless white pane. The blend shader required texture samplers (`material_a`/`material_b`) but none were assigned. Added default terrain colors (`color_a` green, `color_b` brown) and a cell grid overlay to the blend shader for immediate visual feedback without imported textures.
- Fixed `test_mat.tres` UTF-8 BOM that prevented Godot from loading the sample material.
- Fixed 59 "Invalid owner" errors during chunked bake: `_assign_owner` was called on chunk nodes before their parent container was added to the scene tree.
- Changed navmesh `cell_height` default from 0.2 to 0.25 to match Godot's NavigationServer3D map default, eliminating mismatch warnings.
- Added `_assign_owner_recursive()` so baked geometry (chunks, meshes, collision, navmesh) all get proper editor ownership in one pass after being added to the tree.
- Added CI workflow (`.github/workflows/ci.yml`) for automated `gdformat` and `gdlint` checks on push/PR.

### Refactored
- Dock UX: rewrote `dock.gd` to build Paint and Manage tab contents programmatically using `HFCollapsibleSection`.
- Dock UX: ~100 `@onready var` declarations changed to plain `var` (controls created in code, not in .tscn).
- Dock UX: `dock.tscn` reduced to ~280 lines (tab shells only; content populated by `_ready()`).
- Replaced duck-typing in `baker.gd` (`has_method("get_faces")/.call()`) with typed `DraftBrush` access.
- Added `_find_level_root_deep()` to `plugin.gd` for recursive LevelRoot discovery.
- Added `_find_level_root_in()` and `_find_level_root_recursive()` to `dock.gd` for deep tree search.
- Split `level_root.gd` from ~2,500 lines into thin coordinator (~1,100 lines) + 8 `RefCounted` subsystem classes in `systems/`.
- Introduced `input_state.gd` (`HFInputState`) state machine replacing 18+ loose drag/paint state variables.
- Replaced ~57 `has_method`/`call` duck-typing patterns in `plugin.gd` and `dock.gd` with direct typed calls.
- Added recursion depth limits and inner-array validation to `hflevel_io.gd` variant encoding/decoding.
- Added null-safety checks in `baker.gd` after `_postprocess_mesh()` and `ImageTexture.create_from_image()`.
- Plugin cleanup (`_exit_tree`) now uses `is_instance_valid()` + `queue_free()` instead of `free()`.
- Removed Godot 3 `Image.lock()`/`unlock()` remnants from `face_data.gd`.
- Added texture image cache in `face_data.gd` paint blending to avoid redundant `get_image()`/resize calls.
- Added early-exit in `plugin.gd` screen bounds calculation for objects fully behind the camera.
- Fixed paint blending loop in `face_data.gd` that only ran when the weight image needed resizing.
- Threaded .hflevel writes now log errors on file open failure and `store_buffer` errors.
- **Code quality audit** (~30 issues across 11 files):
  - Comprehensive duck-typing removal: `baker.gd` (typed `ArrayMesh` cast for lightmap/LODs), `hf_file_system.gd` (direct `GLTFDocument` calls), `plugin.gd` (direct `set_undo_redo`), `dock.gd` (6 sites: undo/redo, cordon visual, brush info, dependency checks).
  - Removed redundancies: duplicate null checks, unbounded `while true` loops, redundant `ensure_dir_for_path`, consolidated init guards.
  - Named constants: `MAX_BUCKET_FILL_CELLS`, `MAX_LAYER_ID_SEARCH`; `is_entity_node()` as primary public API.
  - Extracted `_deserialize_chunks_to_layer()` in `hf_paint_system.gd` (eliminated ~40-line duplication).
  - Fixed O(n²) in `capture_region_index()` via Dictionary lookup.
  - Extracted `_collect_all_chunks()` in `hf_bake_system.gd` (shared by `bake_chunked` and `get_bake_chunk_count`).
  - Added brush/material caching in `hf_brush_system.gd`: O(1) brush ID lookup, O(1) brush count, material instance cache.
  - Cordon visual: persistent `ImmediateMesh` reused via `clear_surfaces()`.
  - Extracted inline GLSL to `highlight.gdshader` file.
  - Added `build_heightmap_model()` on `hf_paint_tool.gd` (shared by 3 heightmap reconcile callers).
  - Signal-driven sync in `dock.gd`: replaced 17 per-frame property writes with signal handlers; throttled perf updates (every 30 frames), sync calls (every 10 frames), flag-driven disabled hints; cached `_control_has_property()`.
  - Input decomposition in `plugin.gd`: split 260-line `_forward_3d_gui_input()` into ~50-line dispatcher + 7 focused handlers + shared `_get_nudge_direction()`.

### UX
- Dock now has 4 tabs (Brush, Paint, Entities, Manage) instead of 8 for faster navigation.
- Collapsible sections throughout Paint and Manage tabs for visual hierarchy and reduced scrolling.
- "No LevelRoot" banner at dock top guides users when no LevelRoot is found.
- Toolbar buttons display keyboard shortcut labels (Draw (D), Sel (S), Ext▲ (U), Ext▼ (J)).
- LevelRoot stays active when clicking other scene nodes (sticky root discovery).
- Shortcut HUD now shows context-sensitive shortcuts (6 different views: draw idle, dragging base, adjusting height, select, floor paint, surface paint).
- HUD displays current axis lock state (e.g. "[X Locked]").
- Status bar errors appear in red, warnings in yellow, and auto-clear after a timeout.
- Bake failure now shows "Bake failed - check Output for details" instead of generic "Error".
- Pending subtract brushes are visually distinct (orange-red, high glow) from applied cuts (standard red).

### Documentation
- Added texture/materials guide, development/testing guide, and updated README/spec/user/MVP docs.
- Updated spec, development guide, MVP guide, and README to reflect subsystem architecture.
- Updated all docs to document new UX features: dynamic HUD, tooltips, shortcuts, pending cut visuals.
- Updated all docs for multi-layer heightmap integration: heightmap workflow, blend tool, connectors, foliage, bake integration.

## [0.1.1] - 2026-02-05

### Added
- Live paint preview while dragging for Brush/Erase/Line/Rect.
- Paint preview reconciliation without node churn (dirty chunk scope).
- Bucket fill improvements and guardrails.
- Paint layer persistence in .hflevel files.
- Log capture guidance for exit-time Godot errors.

### Changed
- Paint preview now updates generated floors/walls in real time.
- Paint tool default radius behavior tuned (radius 1 = single cell).
- Paint chunk indexing now floors correctly for negative coordinates.

### Fixed
- Quadrant mirroring caused by incorrect chunk indexing of negative cells.
- Live preview not appearing until mouse-up.
- Corrupt entity icon references updated in docs.

### Documentation
- Major refresh across README, spec, and guides to reflect paint system and workflows.

## [0.1.0] - 2026-02-04

### Added
- CAD-style brush creation: drag a base, then set height and commit with a second click.
- Modifier keys: Shift (square base), Shift+Alt (cube), Alt (height-only).
- Axis locks for drawing (X/Y/Z).
- Draw/Select tool toggle in the dock.
- Collapsible dock sections for Settings, Presets, and Actions.
- Physics layer presets for baked collision via dock dropdown.
- Live brush count indicator with performance warning colors.
- New SVG icon for LevelRoot in the scene tree.
- Paint Mode: pick an active material and click brushes to apply it in the viewport.
- Active material picker in the dock (resource file dialog for .tres/.material).
- Hover selection highlight (AABB wireframe) when using Select.
- Select tool now yields to built-in gizmos when a brush is already selected.
- Prefab factory for advanced shapes with dynamic shape palette.
- Added wedges, pyramids, prisms, cones, spheres, ellipsoids, capsules, torus, and platonic solids.
- Mesh prefab scaling now respects brush dimensions (capsule/torus/solids).
- Native 4-view layout guidance (uses Godot's built-in view layout).
- Multi-select (Shift-click), Delete to remove, Ctrl+D to duplicate.
- Nudge selected brushes with arrow keys and PageUp/PageDown.
- Auto-create LevelRoot on first click if missing.
- Create Floor button for quick raycast surface setup.
- Pending Subtract cuts with Apply/Clear controls (Bake auto-applies).
- Cylinder brushes, grid snap control, and colored Add/Subtract preview.
- Commit cuts improvements: multi-mesh bake, freeze/restore committed cuts, bake status, bake collision layer control.
- Viewport DraftBrush resize gizmo with face handles (undo/redo friendly).
- Gizmo snapping uses grid_snap during handle drags.
- Line-mesh draft previews for pyramids, prisms, and platonic solids.
- Chunked baking via LevelRoot.bake_chunk_size (default 32).
- Entities container (LevelRoot/Entities) and is_entity meta for selection-only nodes (excluded from bake).
- Entity definitions JSON loader (res://addons/hammerforge/entities.json).
- DraftEntity schema-driven properties with Inspector dropdowns (stored under data/, backward-compatible entity_data/).
- Create DraftEntity action button in the dock.
- Editor-only entity previews (billboards/meshes) driven by entities.json.
- Collision baking uses Add brushes only (Subtract brushes excluded).
- Playtest FPS controller with sprint, crouch, jump, head-bob, FOV stretch, and coyote time.
- Playtest button workflow: bake + launch current scene.
- Player start entity support (entity_class = "player_start").
- Hot-reload signal for running playtests via res://.hammerforge/reload.lock.
- Floor paint system with grid-based paint layers and auto-generated floors/walls.
- Paint tool selector (Brush/Erase/Rect/Line/Bucket), radius control, and layer picker in the dock.
- Stable-ID reconciliation for generated paint geometry to avoid node churn.
- .hflevel persistence for paint layers and chunk data.

### Changed
- Disabled drag-marquee selection in the viewport to avoid input conflicts.
- Paint Mode now routes to the floor paint system (material paint is reserved for a future pass).

### Fixed
- Selection picking now works for cylinders and rotated brushes.
- Height drag direction now matches mouse movement (up = taller).
- Guarded brush deletion to avoid "Remove Node(s)" errors.
- Dock instantiation issues caused by invalid parent paths.
- Commit cuts bake now neutralizes subtract materials so carved faces don't inherit the red preview.
- Playtest spawning now waits for runtime tree readiness to avoid transform warnings.
- Playtest now bakes before hiding draft geometry, so you can see brushes in-game.

### Documentation
- Added user guide and expanded LevelRoot explanation.
- Updated README, user guide, MVP guide, and spec for chunked baking and entity workflow.
- Documented selection limits and drag-marquee being disabled in the viewport.
- Expanded docs for floor paint workflow, layers, and persistence.
- Broad documentation refresh across README/spec/guides for floor paint, layers, and logs.
