# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Added
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
- Brush delete undo now uses brush IDs and `create_brush_from_info()` snapshots for stability.
- New brushes placed via direct placement now receive stable brush IDs.
- Standardized editor actions under a single undo/redo helper with state snapshots.
- Paint Mode can target either floor paint or surface paint.
- .hflevel now persists materials palette and per-face data.
- .hflevel now persists per-chunk `material_ids`, `blend_weights` (+ _2/_3), `heightmap_b64`, `height_scale`, and terrain slot settings.
- Floor paint layers with heightmaps route to `HFHeightmapSynth` (MeshInstance3D) instead of CSG DraftBrush.
- Generated heightmap floors stored under `LevelRoot/Generated/HeightmapFloors`.

### Fixed
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

### UX
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
