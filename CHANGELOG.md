# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Added
- **New HammerForge Level template** (Apr 2026): One-click starter level creation from the
  Manage tab. Creates a floor (CSGBox3D), directional sun light (DefaultSun), and player spawn
  in a single undoable action. Aimed at eliminating the "where do I start?" moment for new users.

  **DefaultSun** is a DirectionalLight3D at (-45, 30, 0) with shadows enabled. It is fully
  tracked by the state system (capture/restore round-trips correctly through undo/redo) and
  is duplicated into Quick Play and Export Playtest scenes so editor and playtest lighting match.

  Files: `level_root.gd` (modified), `systems/hf_state_system.gd` (modified),
  `dock.gd` (modified), `ui/manage_tab_builder.gd` (modified).

- **HFLog test-aware warning wrapper** (Apr 2026): New `hf_log.gd` (`HFLog`) utility class
  that routes runtime warnings through a testable channel. Tests can capture and suppress
  expected warnings via `begin_test_capture()` / `end_test_capture()` / `get_captured_warnings()`
  without polluting the test output. 15 production call sites converted across 5 files
  (hflevel_io, hf_prefab, hf_bake_system, hf_bevel_system, hf_displacement_system).
  5 test files updated with symmetric capture/assert helpers.

  Files: `hf_log.gd` (new), `hflevel_io.gd` (modified), `hf_prefab.gd` (modified),
  `systems/hf_bake_system.gd` (modified), `systems/hf_bevel_system.gd` (modified),
  `systems/hf_displacement_system.gd` (modified), `tests/test_hflevel_io.gd` (modified),
  `tests/test_prefab.gd` (modified), `tests/test_bake_system.gd` (modified),
  `tests/test_bevel.gd` (modified), `tests/test_displacement.gd` (modified).

### Fixed
- **Playtest sun yaw divergence**: The fallback PlaytestSun in `export_playtest_scene()` used
  yaw -30 while the editor convention is +30, causing lighting to flip between editor and
  playtest. Fixed to use consistent (+30) yaw. DefaultSun (from New Level) is now duplicated
  into the playtest scene, so the fallback is only used when no sun exists at all.

- **Gestalt UI grouping & industry-standard keybindings** (Apr 2026): Keybinding alignment with
  Blender/Hammer conventions and visual tool grouping following Gestalt proximity principles.

  **New keybindings (Blender convention):**
  - **E** — Extrude Up (matches Blender's E for extrude). Context-aware: skipped in paint mode
    (E = Erase) and vertex mode (E = edge toggle). U still works as an alternative.
  - **Shift+E** — Extrude Down. Same context guards. J still works as an alternative.
  - **A** — Select All brushes and entities. Clears face selection first to ensure context
    toolbar transitions to object mode.
  - **Shift+A** — Deselect All (brushes, entities, and faces). Uses `clear_face_selection()`
    for proper visual cleanup and signal emission.

  **Context toolbar group labels:** Small muted category headers before each tool cluster
  (Extrude, Modify, Select, UV, Apply, Entity, Mode, Edit, Shape) make it immediately clear
  which tools belong together, following Gestalt proximity/similarity principles.

  **Dock Selection Tools sub-headers:** The flat tool list in the Brush tab's Selection Tools
  section is now organized into labeled sub-groups with centered separator lines: Brush
  Modification (Hollow + Clip), Positioning (Floor/Ceiling), Entity Binding (Tie/Untie),
  and Duplicate Array.

  **Viewport context menu:** Select All / Deselect All added to the common footer (available
  in every context).

  **Command palette:** New "Selection" category header groups Select All, Deselect All, Select
  Similar, and Selection Filters together. Previously these actions were uncategorized and
  invisible in the palette.

  Files: `hf_keymap.gd` (modified), `plugin.gd` (modified), `ui/hf_context_toolbar.gd`
  (modified), `ui/hf_viewport_context_menu.gd` (modified), `ui/selection_tools_builder.gd`
  (modified), `ui/hf_hotkey_palette.gd` (modified).

- **Error prevention & forgiveness** (Apr 2026): Geometry preview overlays and confirmation
  dialogs for destructive operations, reducing accidental mistakes.

  **Carve preview** (`HFCarvePreview`): green wireframe overlay shows the resulting slice pieces
  before committing a carve. Confirmation dialog with Cancel to abort. Covers both hotkey
  (Ctrl+Shift+R) and context toolbar paths.

  **Clip preview** (`HFClipPreview`): cyan wireframe shows the two resulting halves plus a
  semi-transparent orange quad for the split plane. Confirmation dialog before committing.

  **Hollow preview** (`HFHollowPreview`): yellow wireframe shows all 6 wall pieces that would
  result from hollowing. Supports real-time `update_thickness()` for interactive preview.
  Confirmation dialog before committing. Covers both dock button and hotkey (Ctrl+H) paths.

  **Bulk delete confirmation**: deleting 3+ brushes at once shows a confirmation dialog
  reassuring users that Ctrl+Z can undo. Single/dual brush deletes remain instant.

  **Dialog lifecycle safety**: all confirmation dialogs are tracked in `_pending_dialogs` and
  auto-freed on plugin teardown. Confirmed callbacks guard `is_instance_valid(root)` to prevent
  operating on a dead LevelRoot after scene change.

  Files: `systems/hf_carve_preview.gd` (new), `systems/hf_clip_preview.gd` (new),
  `systems/hf_hollow_preview.gd` (new), `level_root.gd` (modified), `plugin.gd` (modified),
  `dock.gd` (modified).

- **Progressive disclosure for Entity I/O** (Apr 2026): Entity I/O and I/O Wiring sections in
  the Entities tab are now context-hidden — they only appear when an entity is selected, matching
  the existing Entity Properties behavior. I/O Wiring also defaults to collapsed. This keeps the
  Entities tab clean during greyboxing and reveals wiring complexity only when you're actively
  editing an entity.

  Files: `dock.gd` (modified), `ui/entity_tab_builder.gd` (modified).

- **Visual system status feedback** (Apr 2026): Classic editor-style visual feedback for brush
  operations, grid awareness, and system state.

  **Operation-coded wireframe colors:** Brushes now use distinct wireframe overlay colors by
  operation type, matching the convention established by Hammer and TrenchBroom:
  - **Green** wireframe + fill for additive (union) brushes.
  - **Red** wireframe + fill for subtractive brushes (unchanged).
  - **Blue** spectrum for brush entities — bright blue for `func_detail`, medium blue for
    `trigger_*`, muted blue for `func_wall`, slate blue for other entity classes.
  - New `_apply_additive_wireframe_overlay()` in `brush_instance.gd` creates a green wireframe
    overlay for additive brushes (mirroring the existing subtract wireframe overlay). Both
    overlays now refresh on face-preview mesh rebuilds to prevent geometry drift.

  **Grid size viewport indicator:** The shortcut HUD (`shortcut_hud.gd`) now displays the
  current grid snap value persistently (e.g. "Grid: 16") in the top-right viewport panel.
  Uses `%g` formatting for exact display at all snap values (including fractional like 0.125).

  **Grid change flash:** When the grid snap value changes, the indicator briefly flashes
  bright yellow-white and fades back over 0.6 seconds, providing immediate visual confirmation
  without requiring the user to look away from the viewport.

  **Grid size hotkeys** (`[` / `]`): Halve or double the grid snap with a single keypress.
  Clamped to 0.125–512 range. Registered as `grid_decrease` / `grid_increase` in `hf_keymap.gd`
  (user-remappable). Shortcut hint added to draw-idle HUD display.

  **Signal-driven HUD sync:** `dock.gd` emits `grid_snap_applied(value)` from both
  `_apply_grid_snap()` and `_on_root_grid_snap_changed()`, ensuring the HUD updates for all
  grid change origins — dock SpinBox, snap buttons, quick-property popup, `[`/`]` hotkeys,
  state restore, or any direct `root.grid_snap` assignment.

  Files: `brush_instance.gd` (modified), `shortcut_hud.gd` (modified), `plugin.gd` (modified),
  `dock.gd` (modified), `hf_keymap.gd` (modified).

### Fixed
- **Test cleanup leaks** (Apr 2026): Fixed test-owned resource leaks in
  `test_brush_to_heightmap.gd`, `test_context_toolbar.gd`, and `test_selection_features.gd`.
  Heightmap tests now register detached converted layers for cleanup; toolbar tests use GUT's
  auto-queue-free path. Orphan/resource leak shutdown errors eliminated.
  Total: **1370 tests across all files**, full suite passes cleanly in 91.7s.

- **Viewport-centric UI** (Apr 2026): Three Fitts's-Law-driven viewport overlays that keep the
  cursor in the 3D viewport instead of traveling to the dock panel.

  **Context Menu** (Space key): A `PopupMenu` with context-sensitive sections based on the current
  selection state (brush/face/entity/draw/vertex). Sections include grid snap presets (1/2/4/8/16/32/64),
  UV operations submenu, draw shapes submenu, and toggle items like Highlight Connected (check item
  that reads and inverts current state). Position is converted from SubViewport to window coordinates
  via `DisplayServer.mouse_get_position() - get_window().position`. Only activates when idle (no
  active drag, paint, or external tool).

  **Radial Menu** (`` ` `` backtick key): A custom `Control` overlay drawing 8 pie sectors via
  `_draw()` — Box, Cylinder, Select, Paint, Vertex, Tex Pick, Measure, Clip. Added to
  `CONTAINER_SPATIAL_EDITOR_MENU` with `PRESET_FULL_RECT`. Center position uses `event.position`
  from `_forward_3d_gui_input` directly (same coordinate space as the overlay canvas — proven by
  marquee overlay). Hover detection via `_segment_at_position()` helper with inner dead zone
  (`INNER_RADIUS = 30`) and outer ring boundary (`OUTER_RADIUS = 120`). Click recomputes segment
  from `event.position` at click time instead of trusting stale hover state. Dismiss via
  Escape / backtick / RMB. While active, the radial intercepts all input at the top of
  `_forward_3d_gui_input` before paint/vertex/external tool handlers.

  **Quick Property Popups** (double-tap G G / B B / R R): `PanelContainer` with labeled SpinBoxes
  for rapid numeric entry without leaving the viewport. Three property types: Grid Snap (1 spinbox),
  Brush Size (3 XYZ spinboxes), Paint Radius (1 spinbox). Positioned in overlay space with bounds
  clamping. Auto-dismiss on Enter/Escape; click-away dismiss handled by plugin.gd (checks
  `get_rect()` against `event.position`, consumes the dismissing click).

  **Integration:**
  - Unified `_dispatch_viewport_action()` in plugin.gd handles all action strings from context menu,
    radial, context toolbar, and command palette.
  - Keybindings configurable via `hf_keymap.gd` (`context_menu`, `radial_menu` actions in "Tools"
    category). `load_or_default()` merges missing default bindings into existing user JSON files.
  - Command palette gains `context_menu` and `radial_menu` actions with idle-state gray-out.
  - Theme-aware colors via `HFThemeUtils`.

  Files: `ui/hf_viewport_context_menu.gd` (new), `ui/hf_radial_menu.gd` (new),
  `ui/hf_quick_property.gd` (new), plugin.gd (modified), hf_keymap.gd (modified),
  `ui/hf_hotkey_palette.gd` (modified).

- **Automated occluder generation** (Apr 2026): New bake pass that analyzes baked mesh geometry
  to automatically generate `OccluderInstance3D` nodes for runtime occlusion culling.

  Coplanar triangles from baked meshes (including chunked `BakedChunk_*` hierarchies) are grouped
  by normal direction (5° threshold) and plane distance (0.1 unit threshold). Groups exceeding a
  configurable minimum area produce `ArrayOccluder3D` resources parented under a single `Occluders`
  container node. Re-baking is idempotent — previous occluders are replaced, not duplicated.

  **Configuration (LevelRoot exports):**
  - `bake_generate_occluders` (bool, default off): master toggle.
  - `bake_occluder_min_area` (float, default 4.0): minimum coplanar face-group area (world units²)
    to emit an occluder. Smaller surfaces rarely block enough pixels to justify culling overhead.

  **Dock UI:** "Generate Occluders" checkbox and "Min Area" SpinBox in Manage tab → Bake section.
  Settings persist in `.hflevel` save/load and sync bidirectionally with LevelRoot exports.

  **Validation:** `check_occlusion_coverage()` now runs as part of `check_bake_issues()`:
  - Warns when occluder generation is enabled but produced no occluders (surfaces too small).
  - Reports info-level coverage stats (occluder count + estimated % of baked AABB surface).

  13 new tests in `test_occluder_generation.gd`: direct-child meshes, chunked hierarchy
  (`BakedChunk_*` intermediary nodes), coplanar merging, plane separation, min-area filtering,
  idempotent re-generation, postprocess toggle, validation coverage and missing-occluder warnings.

- **I/O-to-Signal runtime bridge** (Apr 2026): Entity I/O connections now automatically translate
  into live Godot signals at bake and export time, eliminating the need for manual runtime wiring.

  New `HFIORuntime` dispatcher node (`hf_io_runtime.gd`, `class_name HFIORuntime`) scans entities
  for `entity_io_outputs` metadata and builds a runtime connection table keyed by node instance ID.
  On output fire, the dispatcher delivers to target entities via a 4-tier resolution cascade:
  1. Direct method call (e.g. `target.Open()`)
  2. Snake-case variant (e.g. `target.turn_on()` for input name `TurnOn`)
  3. Generic handler (`target._on_io_input(input_name, parameter)`)
  4. User signal emission (`io_Open` signal on target)

  Source entities receive `io_<OutputName>` user signals so game scripts can use standard
  `emit_signal("io_OnTrigger", "")` / `connect()` patterns. Delay and fire-once semantics are
  handled automatically. Debug signals `io_fired` and `io_received` emit per-delivery for
  accurate fan-out reporting.

  **Integration points:**
  - `export_playtest_scene()` auto-injects an `HFIODispatcher` child when entities have I/O
    connections — exported scenes are play-ready with no additional setup.
  - New `bake_wire_io` export on LevelRoot (Inspector toggle, default off): when enabled,
    `postprocess_bake()` attaches a dispatcher to the baked container with `extra_scan_roots`
    pointing to the sibling `entities_node`.
  - `HFEntitySystem.fire_output(entity, output_name, parameter)` delegates to the dispatcher
    when present, falls back to direct multi-target resolution otherwise.

  **Robustness:**
  - Connections keyed by node instance ID — duplicate source names are isolated per-instance.
    `fire_from(entity)` dispatches only that entity's connections; `fire("name")` fans out to
    all sources sharing the name.
  - `extra_scan_root_paths: Array[NodePath]` (@export) persists across scene save/reload.
    Transient `extra_scan_roots: Array[Node]` covers live-session bake paths.
  - `wire()` is safe to call repeatedly: `_disconnect_all_signals()` tears down stale lambdas
    before reconnecting; `_prune_overlapping_roots()` deduplicates by instance ID and removes
    descendant roots covered by an ancestor, preventing double-registration.
  - `_find_dispatcher()` walks up to tree root as fallback when `current_scene` is null
    (editor context, GUT tests).

  36 new tests in `test_io_runtime.gd`: wiring, method dispatch (direct/snake-case/generic/signal
  fallback), parameter passing/override, fire-once, user signal creation and emission, multi-target
  fan-out, chain reactions, debug signal accuracy (per-target `io_fired`/`io_received`), missing
  target safety, rewire idempotency (no duplicate handlers), duplicate source isolation
  (`fire_from` vs `fire`), extra scan roots (transient, NodePath, overlap dedup, descendant
  pruning), `fire_on()` static helper, `HFEntitySystem.fire_output()` fallback.
  Total: **1357 tests across 74 files**.

- **Collision chunking for bot navigation** (Apr 2026): Replaced monolithic ConcavePolygonShape3D
  collision with a 3-tier collision mode system for better physics broadphase and navigation mesh
  generation. Configured via `bake_collision_mode` on LevelRoot (Inspector export):
  - **Mode 0** (default): Legacy trimesh — single ConcavePolygonShape3D (backward compatible).
  - **Mode 1**: Per-brush convex hulls — each brush gets a ConvexPolygonShape3D via
    `Baker.build_convex_collision_shapes()`. Supports `bake_convex_clean` (deduplicate vertices,
    default true) and `bake_convex_simplify` (AABB-proportional grid merge, 0.0–1.0).
  - **Mode 2**: Per-visgroup partitioned collision — separate StaticBody3D per visgroup, each
    containing convex hulls for its member brushes. Ungrouped brushes fall into a default body.

  Works across all bake paths: face-material (`bake_from_faces`), CSG single (`bake_single`),
  and CSG chunked (`bake_chunked`). Subtractive brushes are excluded from convex hull generation.
  Real mesh vertices are extracted (not AABB corners) so non-box shapes get accurate collision.
  Visgroup partitioning runs before heightmap collision append to prevent heightmap shape loss.
  Degeneracy guard always runs (vertex dedup for unique count ≥ 4) regardless of `convex_clean`
  setting. Settings persist in `.hflevel` via `capture_hflevel_settings()`/`apply_hflevel_settings()`.

  22 new tests: 11 in `test_baker.gd` (convex shape generation, dedup, simplification, clean
  flag, trimesh default, face bake convex mode, snapshot hull verts) and 11 in `test_bake_system.gd`
  (collision data collection, subtractive filtering, real mesh verts, entity brush skip, 6 async
  integration tests for mode 2 single/chunked/heightmap/trimesh preservation).
  Total: **1321 tests across 73 files**.

## [0.2.0] - 2026-04-09
### Added
- **Map import vertex welding** (Apr 2026): `MapIO.parse_map_text()` now runs a post-parse
  vertex welding pass on all parsed brush face points before constructing brush geometry.
  Near-coincident vertices (within `import_weld_tolerance`, default 0.01 units) are averaged
  to a shared position, closing micro-gaps caused by floating-point representation drift in
  legacy .map editors. Uses BFS over a spatial hash with 27-cell neighbor lookup so pairs
  straddling a snap-grid boundary are never missed. The tolerance is configurable via the
  static `MapIO.import_weld_tolerance` property; set to 0.0 to disable.

- **Non-planar face detection** (Apr 2026): `HFValidationSystem.check_bake_issues()` now
  flags faces with 4+ vertices where any vertex deviates from the face plane beyond
  `planarity_tolerance` (default 0.01 units). Reported as `type: "non_planar"`, severity 1.
  Adjustable per-instance via `val_sys.planarity_tolerance`.

- **Micro-gap detection** (Apr 2026): `check_bake_issues()` now detects near-coincident
  but not-exactly-equal vertices across different brushes that would cause seam tearing
  after bake. Reported as `type: "micro_gap"`, severity 1. Tolerance controlled by
  `val_sys.weld_tolerance` (default 0.001 units).

- **Vertex welding auto-fix** (Apr 2026): `HFValidationSystem.weld_brush_vertices(brush)`
  snaps all vertices within `weld_tolerance` of each other to their averaged position using
  BFS grouping over a 27-cell spatial hash. Calls `ensure_geometry()` on every modified face
  to refresh normals and bounds. Returns the count of welded vertices.

- **Planarity auto-fix** (Apr 2026): `HFValidationSystem.fix_non_planar_faces(brush)`
  projects drifting vertices back onto the best-fit plane defined by each face's first three
  vertices. Calls `ensure_geometry()` after correction. Returns the count of vertices fixed.

- **Configurable validation tolerances** (Apr 2026): `HFValidationSystem` gains two public
  properties — `weld_tolerance` (default 0.001) for vertex coincidence and `planarity_tolerance`
  (default 0.01) for face-plane deviation. These control the new checks and auto-fix methods.
  The `_edge_key()` function used by non-manifold/open-edge detection retains its fixed 0.001
  precision — it is intentionally decoupled from `weld_tolerance` so topology checks remain
  stable regardless of the weld knob setting.

  21 new tests in `test_weld_and_planarity.gd`: non-planar detection (5), vertex welding (3),
  planarity fix (3), micro-gap detection (2), edge-key independence (1), boundary-straddling
  coverage (3), MapIO integration (2), MapIO unit (2).
  Total: **1299 tests across 73 files**.

### Changed
- **Non-blocking face-mode bakes** (Apr 2026): Full bakes using the face-material path
  (`bake_use_face_materials = true`) no longer freeze the editor. The bake system now operates in two
  phases:
  1. **Synchronous snapshot**: captures each brush's triangulated face geometry, resolved materials,
     and world transform into plain data (PackedArrays + Material refs) before any yields. This
     ensures the bake operates on a single coherent scene state regardless of edits during the bake.
  2. **Cooperative yield pass**: iterates the frozen snapshots in batches of 8 brushes, yielding
     `process_frame` between batches so the editor remains responsive. Progress is reported via
     `bake_progress` signals ("Collecting faces N/M").

  `baker.gd` gains four new public methods: `snapshot_brush_faces()` (pre-triangulate + resolve
  materials for one brush), `collect_snapshot_groups()` (world-space transform + grouping from frozen
  data), `collect_brush_face_groups()` (convenience wrapper for sync callers), and
  `build_mesh_from_groups()` (atlas pass + ArrayMesh + collision from pre-collected groups). The
  existing `bake_from_faces()` remains as a thin synchronous wrapper for backward compatibility.

  Bake time estimation (`estimate_bake_time()`) is also corrected: frame-yield idle time is tracked
  via `_yield_overhead_ms` and subtracted from `_last_bake_duration_ms` in both `bake()` and
  `bake_selected()`, so the ms-per-brush ratio reflects actual CPU work rather than wall-clock time
  inflated by editor frame pacing.

  **Note**: Material *resources* referenced in the snapshot are not deep-cloned. If a
  `StandardMaterial3D` property is mutated in-place during the yield window, the baked output will
  reflect the new property value. This is an accepted trade-off — the window is narrow and the
  material identity is correct.

### Fixed
- **Preview node memory leaks during undo/redo** (Apr 2026): Editor preview geometry (drag preview
  brushes, extrude preview brushes, subtract preview wireframes) could leak MeshInstance3D nodes during
  rapid undo/redo cycles. Three fixes:
  1. `plugin.gd` now connects to `EditorUndoRedoManager.version_changed` and force-resets transient
     input modes (DRAG_BASE, DRAG_HEIGHT, EXTRUDE, SURFACE_PAINT) via `HFInputState._force_reset()`,
     which cascades through `_on_input_state_force_reset` to free drag/extrude preview nodes.
     Persistent modes (VERTEX_EDIT) are explicitly excluded — `commit_action()` fires
     `version_changed` after every vertex operation, so resetting it would desynchronize
     `_vertex_mode` in plugin.gd from `input_state.mode`. The transient-mode predicate is extracted
     to `HFInputState.is_transient_preview_mode()` (shared between plugin.gd and tests).
  2. `HFSubtractPreview` gains a `destroy()` method that immediately frees all pooled MeshInstance3D
     nodes and the container Node3D (via `free()`, not `queue_free()`, to prevent orphans during
     tree teardown where the next frame may never arrive).
  3. `level_root.gd _exit_tree()` now calls `subtract_preview.destroy()`,
     `extrude_tool.cancel_extrude()`, and `drag_system._clear_preview()` to clean up all preview
     nodes when the LevelRoot leaves the scene tree.
  8 new tests: 6 in `test_drag_dimensions.gd` (version_changed predicate for all 6 input modes),
  2 in `test_subtract_preview.gd` (destroy with/without prior enable).
  Total: **1278 tests across 73 files**.

### Added
- **Better Terrain Integration — Auto Connectors** (Apr 2026): Auto-generate ramps or stairs between
  height levels during bake. `HFAutoConnector` class (`paint/hf_auto_connector.gd`) scans all paint
  layer pairs, detects cross-layer height boundaries (adjacent cells where one layer's filled cell
  neighbours another layer's filled cell at a different height, threshold ≥0.1 world units), groups
  contiguous boundary edges by direction, and generates connector meshes via the existing
  `HFConnectorTool`. Three modes: **Ramp** (smooth slope), **Stairs** (stepped with configurable step
  height), and **Auto** (picks stairs when height diff ≥ threshold, ramp otherwise). Connector width
  configurable in cells. Deduplication uses canonical 6-part key (both layer indices + both cell coords)
  so corner and T-junction edges are never dropped. Integrated into `HFBakeSystem.postprocess_bake()` —
  connectors generate before navmesh bake so `PARSED_GEOMETRY_STATIC_COLLIDERS` mode picks up connector
  collision shapes. Selection bakes (`bake_selected`) skip auto-connectors to avoid pulling in
  unrelated geometry. 4 new export properties on LevelRoot: `bake_auto_connectors`, `bake_connector_mode`,
  `bake_connector_stair_height`, `bake_connector_width`. Dock UI: "Auto Connectors" checkbox, Mode
  dropdown (Ramp/Stairs/Auto), Step Height and Width spinboxes in Manage tab Bake section. Full state
  persistence in `.hflevel` via `hf_state_system.gd` and dock settings export/import.
  27 tests in `test_auto_connector.gd` + 13 integration tests in `test_bake_system.gd`.
  Total: **1270 tests across 72 files**.
### Fixed
- **NavigationMesh parsed_geometry_type property name** (Apr 2026): `bake_navmesh()` unconditionally
  assigned `nav_mesh.parsed_geometry_type`, which was renamed to `geometry_parsed_geometry_type` in
  Godot 4.6. Every navmesh bake logged `Invalid assignment of property or key 'parsed_geometry_type'`
  and silently failed to set collider-only parse mode. Extracted to version-safe
  `_set_parsed_geometry_type(target, value)` static helper that probes both property names via `in`.
  4 unit tests exercise both branches (new-name, legacy-name via mock, both-names priority, neither-name
  fallback).
- **Merge Tool** (Apr 2026): Combine 2+ selected brushes into a single CUSTOM brush before baking.
  `HFBrushSystem.merge_brushes_by_ids()` collects all faces from source brushes and transforms
  their `local_verts` and normals through the full `Transform3D` pipeline (source local → world →
  merged local) using `affine_inverse()`, so rotated and scaled brushes merge correctly. The merged
  brush inherits the first source brush's full `global_transform` (not just position). Per-brush
  `material_override` is registered into the MaterialManager via `add_material_to_palette()` and
  stamped as `material_idx` on faces that relied on the brush-level override (material_idx == -1),
  so multi-material merges preserve all visual appearances. Metadata (visgroups, group_id,
  brush_entity_class) inherited from first brush. Pre-validation via `can_merge_brushes()` rejects
  < 2 brushes, missing IDs, and mixed operation types (add/subtract). Keybinding: **Ctrl+Shift+M**.
  Context toolbar "Mrg" button, command palette entry, full undo/redo via `HFUndoHelper.commit()`.
  23 tests in `test_merge_tool.gd` covering validation, face combining, full-transform vertex/normal
  rotation, multi-material index separation, same-material dedup, and metadata preservation.
  Total: **1226 tests across 71 files**.
- **Material Atlasing** (Apr 2026): Packs per-face material albedo textures into a single atlas
  to reduce draw calls on baked levels. `HFMaterialAtlas` class (`hf_material_atlas.gd`) with
  shelf bin-packing, gutter padding (2px edge-pixel extension to prevent mipmap bleed), and
  half-texel UV inset (clamped for small tiles so 1px textures never collapse to zero-size rects).
  Baker integration in `bake_from_faces()`: when `use_atlas` is enabled, faces are split per-material
  into tiling vs non-tiling sub-groups — faces with UVs outside [0,1] (e.g. `uv_scale > 1`) are
  excluded from the atlas and rendered as separate surfaces with their original material so hardware
  texture repeat works correctly, while non-tiling faces of the same material are still atlased.
  Dock UI: "Material Atlas" checkbox in Manage tab Bake section (requires Face Materials enabled).
  `bake_use_atlas` property on LevelRoot, persisted in `.hflevel` state via `hf_state_system.gd`,
  synced in dock settings export/import, and wired through `build_bake_options()`.
  26 new tests in `test_material_atlas.gd` covering atlas building, UV remapping, shelf packing,
  gutter fill, small-tile inset clamping, tiling exclusion, per-face tiling split, and full baker
  integration. Total: **1203 tests across 70 files**.
- **Displacement surfaces** (Apr 2026): Source Engine-style displacement surfaces on quad brush faces.
  `HFDisplacementData` resource stores a subdivided grid (power 2-4, producing 5x5 to 17x17 vertices)
  with per-vertex distance offsets along the face normal. `HFDisplacementSystem` subsystem provides
  create/destroy, paint (Raise/Lower/Smooth/Noise/Alpha modes with quadratic falloff), sew adjacent
  displacements along shared edges, elevation scale, and power resampling via bilinear interpolation.
  `FaceData.displacement` property integrates with the existing `triangulate()` → `baker.bake_from_faces()`
  pipeline, generating subdivided grid meshes with per-vertex normals and CW winding. Baker supports
  per-vertex normals for displacement faces. Dock UI includes a collapsible Displacement section in the
  Brush tab with create/destroy, power/elevation spinboxes, paint mode dropdown, radius/strength controls,
  smooth/noise/sew buttons, and sew group spinbox. Plugin handles displacement paint input with raycast
  plane intersection, convex polygon bounds check, and quadratic falloff brush. All operations are fully
  undoable via `_try_undoable_action()` with return-value checking. Continuous paint strokes capture
  pre-state on mouse-down and commit a single undo action on mouse-up. Displacement data serializes
  in `.hflevel` saves via `to_dict()`/`from_dict()`.
- **Edge bevel (chamfer)** (Apr 2026): `HFBevelSystem` subsystem replaces a sharp edge shared by two
  faces with configurable bevel segments (1-16) approximating a rounded profile. Uses slerp arc
  interpolation between face pull-back directions. Generates bevel strip quads, corner cap triangle fans
  at both endpoints, and updates all neighboring faces' shared vertices based on face-normal side
  assignment to maintain manifold topology. Dock UI includes a collapsible Bevel section with segments
  and radius spinboxes. Requires vertex/edge mode (V key) with an edge selected.
- **Face inset** (Apr 2026): `HFBevelSystem.inset_face()` shrinks a face inward by a configurable
  distance and creates connecting side quads between the original boundary and the inset boundary.
  Optional height parameter extrudes the inset face along its normal. Collapse guard rejects inset
  distances that would degenerate the face. Dock UI provides inset distance and height spinboxes.
- **LevelRoot displacement/bevel API** (Apr 2026): 11 delegate methods on LevelRoot for undo system
  compatibility: `create_displacement`, `destroy_displacement`, `set_displacement_elevation`,
  `set_displacement_power`, `set_displacement_sew_group`, `smooth_displacement`, `noise_displacement`,
  `sew_all_displacements`, `paint_displacement`, `bevel_edge`, `inset_face`. All call through to
  subsystems and `tag_brush_dirty()` on success.
- **`_try_undoable_action()` dock helper** (Apr 2026): Generic helper that captures pre-state, calls a
  LevelRoot method, checks the bool return value, and only commits undo + records history on success.
  Used by all displacement/bevel dock callbacks to ensure no false success toasts or empty undo entries.
- 55 new tests across 2 files (`test_displacement.gd` 40, `test_bevel.gd` 15). Total: **1172 tests
  across 69 files**.

### Fixed
- **Dialog/timer lambda capture crashes** (Apr 2026): Six unguarded lambda closures connected to
  `ConfirmationDialog.confirmed/canceled` signals and `SceneTreeTimer.timeout` could fire after the
  owning node (`dock.gd`, `hf_spawn_system.gd`, `hf_prefab_library.gd`) was freed during plugin
  reload or scene transitions, producing "Lambda capture at index 0 was freed" errors. Added
  `is_instance_valid(self)` guards to all six closures: spawn fix dialog confirmed/canceled
  (dock.gd), paint layer rename dialog confirmed (dock.gd), scatter mesh file dialog file_selected
  (dock.gd), debug cleanup timer (hf_spawn_system.gd), and prefab variant/tags dialog confirmed
  (hf_prefab_library.gd).
- **Inside-out face rendering** (Apr 2026): Manually-defined brush faces (`_build_box_faces()`, polygon
  tool, path tool) used CCW vertex winding, which Godot 4's CW front-face convention treated as
  back-facing. Textures appeared on the inside of brushes. Fixed by reversing vertex order to CW in all
  three face generators and swapping the cross-product in `_compute_normal()` (`(c-a).cross(b-a)` instead
  of `(b-a).cross(c-a)`) so `ensure_geometry()` naturally produces outward normals for CW-wound faces.
  Includes `winding_version` serialization field and centroid-based load-time migration in
  `apply_serialized_faces()` so existing `.hflevel` and `.hfprefab` saves render correctly without
  manual intervention.
- **Index rebasing in merged geometry** (Apr 2026): `baker.gd _concat_surface_arrays()` appended
  `ARRAY_INDEX` buffers without rebasing by the running vertex count, corrupting triangles when
  merging indexed surfaces. Also failed when mixing indexed and non-indexed surfaces (first non-indexed
  caused later indexed buffers to be silently dropped). Now synthesizes sequential indices for
  non-indexed surfaces and rebases all subsequent indices by the accumulated vertex count.
- **Convex hull face reconstruction** (Apr 2026): `hf_vertex_system.gd _faces_from_convex_hull()`
  tracked an `assigned` dictionary that prevented hull vertices from appearing in multiple faces.
  Since convex hull vertices belong to 3+ faces (e.g., cube corners), this dropped valid faces and
  produced incomplete shells. Rewritten to track discovered *planes* (by normal+distance dedup)
  instead, allowing vertices to participate in all their coplanar groups.
- **Preview visuals on chunked bakes** (Apr 2026): `hf_bake_system.gd _apply_preview_visuals()` only
  iterated direct children, missing `MeshInstance3D` and `MultiMeshInstance3D` nodes nested under
  `BakedChunk_*` nodes from chunked bakes. Extracted to `_apply_material_recursive()` that walks the
  full subtree.
- **UV spinbox edits not undoable** (Apr 2026): `dock.gd _on_uv_param_changed()` mutated `FaceData`
  directly without going through the undo system. Now routes through `level_root.set_face_uv_params()`
  via `HFUndoHelper.commit()` with a collation tag so rapid spinbox drags merge into one undo step.
- **UV undo history spam** (Apr 2026): `HFUndoHelper.commit()` fired the history callback on every
  collated commit, flooding the history UI with duplicate entries during spinbox drags. Now only fires
  on the first action of a collation run. Collation tracking and history callback logic extracted into
  `_update_collation()` / `_fire_history_cb()` helpers, wired into all three code paths (>5 args,
  null undo_redo, and normal) so suppression works everywhere.
- **bake_unwrap_uv0 not persisted** (Apr 2026): The "Unwrap UV0" toggle was exported on `level_root`
  and used in bake options but missing from `hf_state_system.gd capture_hflevel_settings()` /
  `apply_hflevel_settings()`, silently resetting across state round-trips. Added to both.
- **HFUndoHelper >5 args collation** (Apr 2026): The >5-args early-return path in `undo_helper.gd`
  passed an empty dict `{}` to `_update_collation()`, so `_last_collation_state.is_empty()` was
  always true and subsequent same-tag calls could never collate. Now captures actual state before
  the early return.

### Added
- **Clip to Convex** (Apr 2026): `hf_vertex_system.gd clip_to_convex(brush_id)` computes the convex
  hull of a brush's vertices and rebuilds its faces to match. Each hull face inherits UV settings
  (projection, scale, offset, rotation, material) from the closest original face by normal dot
  product. Available as "Convex" button in vertex edit context toolbar and via the command palette.
- **Smart incremental bake** (Apr 2026): The main Bake button now auto-detects dirty brushes and
  routes to `bake_dirty()` when `_dirty_brush_ids` is non-empty and no full reconcile is needed,
  avoiding unnecessary full re-bakes during iterative editing.
- **Chunk Size control** (Apr 2026): SpinBox in Manage tab Bake section (0-256, default 32) to
  configure `bake_chunk_size` directly from the dock. Synced through toggle/float bindings, root
  state sync, and preset save/load.
- **Bake Visible Only** (Apr 2026): Checkbox in Manage tab Bake section that skips hidden brushes
  during bake. Filtering applied in both `append_brush_list_to_csg()` and
  `_append_face_bake_container()`. Persisted in state system and presets.
- **MultiMesh bake consolidation** (Apr 2026): "Use MultiMesh" checkbox in Manage tab Bake section.
  `_consolidate_to_multimesh()` in `hf_bake_system.gd` post-processes the baked container, grouping
  identical mesh resources and replacing groups of 2+ with `MultiMeshInstance3D` nodes (preserving
  materials). Preview visuals (wireframe/proxy) apply to consolidated MMI nodes.
- **Non-manifold geometry warnings** (Apr 2026): `check_bake_issues()` in `hf_validation_system.gd`
  now analyzes edge adjacency from each brush's `FaceData.local_verts`. Reports open edges
  (shared by 1 face, severity 1) and non-manifold edges (shared by 3+ faces, severity 2).
- **UV projection controls** (Apr 2026): Per-face UV controls in Paint tab — projection dropdown
  (Planar X/Y/Z, Box UV, Cylindrical), scale/offset/rotation spinboxes, and Re-project button.
  Material browser gains "Apply + Re-project (Box UV)" context action.
- **UV0 unwrap during bake** (Apr 2026): Optional "Unwrap UV0" toggle applies per-vertex planar
  projection based on dominant normal axis during bake. Available in Manage tab Bake section.
- **Subtract brush wireframe overlay** (Apr 2026): Subtraction brushes render a red-orange wireframe
  overlay (shared shader across all instances) for visibility in both face-material and fallback
  material paths.
- **Per-surface material preservation in baker** (Apr 2026): `_merge_entries_worker()` groups meshes
  by material and `bake_from_faces()` builds a single ArrayMesh with one surface per material group,
  preserving per-face materials through the bake pipeline.
- **HFUndoHelper 4/5-arg support** (Apr 2026): `undo_helper.gd` `commit()` now handles methods with
  up to 5 arguments (was limited to 3), enabling undo for `set_face_uv_params()` and similar.
- **Face winding migration** (Apr 2026): `to_dict()` now writes `winding_version: 1`. On load,
  `apply_serialized_faces()` detects v0 data and runs `_migrate_face_winding()`, which computes the
  brush centroid and reverses any face whose normal points inward. This correctly handles both old CCW
  manual faces (reversed to CW) and old CW mesh-extracted faces (left unchanged). No manual
  intervention is needed for existing saves.
- 29 new tests: mixed indexed/non-indexed concat (5), recursive preview on chunks (5), UV-history
  collation (8), >5-arg collation (1), baker material preservation (10), winding migration v0→v1 (1),
  winding round-trip v1 (1). Total: **1120 tests across 67 files**.

- **UV transform order corrected** (Apr 2026): `_apply_uv_transform()` in `face_data.gd` previously
  applied rotation after scale+offset (`(uv * scale + offset).rotated(R)`), which rotated the offset
  and caused texture drift when combining rotation with offset. Now applies rotation first
  (`uv.rotated(R) * scale + offset`), matching Valve 220 convention. Includes v0→v1 migration in
  `from_dict()`: uniform-scale faces get offset adjusted; non-uniform-scale+rotated faces are baked
  to `custom_uvs`. `to_dict()` now writes `uv_format_version: 1`.
- **Carve UV preservation** (Apr 2026): `hf_carve_system.gd` carved slice pieces previously lost all
  UV settings from the original brush, defaulting to PLANAR_Z with no offset. `_copy_uv_settings_to_piece()`
  now matches each slice face to the best source face by normal dot product, copies `uv_scale`,
  `uv_offset`, `uv_rotation`, and `material_idx`, sets BOX_UV projection, and compensates the UV
  offset for the positional difference between the original brush center and the slice center so
  textures remain aligned across all surviving faces.
- **Tile justify mode fixed** (Apr 2026): The "tile" UV justify mode in `hf_brush_system.gd` was using
  `1.0 / max(axis)` which fit the larger axis to 1.0 (letterbox behavior). Now uses `1.0 / min(axis)`
  so the shorter axis fills 0..1 and the longer axis tiles past 1.0, preserving aspect ratio.

### Added
- **Stretch and Tile UV justify modes** (Apr 2026): `hf_brush_system.gd` `_justify_face()` now
  supports "stretch" (non-uniform scale to fill 0..1 on both axes) and "tile" (uniform scale so the
  shorter axis fills 0..1, longer axis tiles, centered). Available via context toolbar and dock UI.
- **Rotation texture lock support** (Apr 2026): `face_data.gd` gains `adjust_uvs_for_rotation(angle_rad)`
  which counter-rotates the UV rotation parameter and clears cached UVs. `hf_brush_system.gd` gains
  `_adjust_face_uvs_for_rotation(draft, angle_rad)` wrapper. Ready to wire into future brush rotation
  features (brushes are currently axis-aligned).

- **Signal disconnection leaks in plugin.gd** (Apr 2026): 10 signals connected in `_enter_tree()`
  (context toolbar ×5, hotkey palette ×1, selection filter ×1, dock ×3) were missing corresponding
  disconnections in `_exit_tree()`. This caused duplicate signal handlers after plugin reload cycles,
  leading to repeated action firings and potential crashes.
- **Timer cleanup in level_root.gd** (Apr 2026): Added `_exit_tree()` method to properly stop and
  disconnect `_autosave_timer` and `_reload_timer` signals. Previously, disabling autosave via the
  property setter called `queue_free()` without disconnecting the `timeout` signal first.
- **Extrude tool crash on deleted brush** (Apr 2026): `hf_extrude_tool.gd` now validates
  `is_instance_valid(source_brush)` in `update_extrude()`, `_update_preview()`, and
  `end_extrude_info()`. If the source brush is deleted mid-extrude (e.g., undo), the tool
  gracefully cancels instead of crashing on a freed object reference. `level_root.update_extrude()`
  now detects the self-cancellation and syncs `input_state.end_extrude()` so the HUD and numeric
  input path leave extrude mode cleanly.
- **Input state machine overlapping transitions** (Apr 2026): `input_state.gd` now warns and
  force-resets when `begin_drag()`, `begin_surface_paint()`, `begin_extrude()`, or
  `begin_vertex_edit()` are called from a non-IDLE state. `advance_to_height()` validates it's
  in DRAG_BASE before transitioning. The new `on_force_reset` callback (set by `level_root.gd`)
  tears down active tool implementations (drag preview, extrude preview, vertex selection) before
  mode changes, keeping the state machine and tool objects in sync.
- **Prefab overlay parent null check** (Apr 2026): `hf_prefab_overlay.gd` `hide_overlay()` now
  checks `get_parent()` is not null before calling `remove_child()`, preventing crashes if the
  parent node was freed during plugin unload.
- **Vertex edge array bounds** (Apr 2026): `hf_vertex_system.gd` `split_edge()` now validates
  `edge.size() >= 2` before indexing, preventing out-of-bounds access on malformed input.
- **Duplicate variable declaration in plugin.gd** (Apr 2026): `_on_context_toolbar_action()` had a
  redundant `var root` inside the `"highlight_connected"` match branch that shadowed the function-level
  `root`, causing a parse error. Removed the duplicate.
- **Debug `and true` remnants in dock.gd** (Apr 2026): Four surface paint/UV functions
  (`_on_uv_reset`, `_on_surface_paint_layer_add`, `_on_surface_paint_layer_remove`,
  `_on_surface_paint_texture_selected`) had leftover `and true` in conditions that made the
  conditional check a no-op. Removed all four.
- **Timer closure crash in dock.gd** (Apr 2026): `_on_tutorial_completed()` used a direct method
  reference in `create_timer().timeout.connect(_close_tutorial)`. If the dock was freed before the
  2-second timer fired, the callback would reference a freed object. Wrapped in a lambda with
  `is_instance_valid(self)` guard.
- **Timer nodes leaked in level_root.gd** (Apr 2026): `_exit_tree()` disconnected timer signals but
  never called `queue_free()` on `_autosave_timer` or `_reload_timer`, leaking child Timer nodes.
  Now frees and nulls both.
- **get_parent() null crashes across 8 files** (Apr 2026): `remove_child()` was called via
  `node.get_parent().remove_child(node)` without checking `get_parent()` for null in:
  hf_decal_tool.gd, hf_measure_tool.gd (×2), hf_path_tool.gd, hf_polygon_tool.gd, plugin.gd,
  hf_prefab_system.gd (×2), brush_manager.gd. All now guard with `if node.get_parent():`.
- **Orphan nodes in bulk-clear paths** (Apr 2026): `hf_entity_system.gd clear_entities()`,
  `hf_brush_system.gd clear_brushes()`, and `brush_manager.gd clear_brushes()` called
  `queue_free()` without `remove_child()` first. During state restore, old nodes could still be
  in the tree when new nodes were added. All now call `remove_child()` before `queue_free()`.
- **Division by zero in merge_vertices** (Apr 2026): `hf_vertex_system.gd merge_vertices()` divided
  by `vert_indices.size()` to compute centroid, ignoring that out-of-bounds indices are skipped. If
  all indices were invalid, this was a divide-by-zero. Now tracks `valid_count` and early-returns
  if zero.
- **Edge hover bounds check** (Apr 2026): `hf_vertex_system.gd update_edge_hover()` now validates
  `pick.edge.size() >= 2` before indexing into the edge array.
- **Extrude preview orphan node** (Apr 2026): `hf_extrude_tool.gd _update_preview()` created a
  `_preview_brush` DraftBrush but only added it to the tree if `draft_brushes_node` existed. If
  null, the node leaked. Now `free()`s and nulls it in the else branch.
- **Axis lock return value discarded** (Apr 2026): `hf_drag_system.gd update_drag()` called
  `_apply_axis_lock()` but discarded the return value, making axis lock position clamping a
  silent no-op. Now assigns the result back to `input_state.drag_end`.

### Added
- **Quality-of-Life & Polish** (Apr 2026):
  - **Dark/Light Theme Sync** (`HFThemeUtils`): static utility class detecting dark/light theme via
    `EditorInterface` base color luminance. All custom UI panels (context toolbar, coach marks, hotkey
    palette, operation replay, toasts, selection filter) now use theme-aware colors instead of
    hardcoded values. Each component gains a `refresh_theme_colors()` method called from
    `plugin.gd:_on_editor_theme_changed()`. Toggling Godot's theme instantly updates all HammerForge
    custom panels.
  - **Undo History Browser with Thumbnails** (`HFHistoryBrowser`): replaces the plain ItemList in the
    Manage tab History section. Up to 30 entries with action name, color-coded icon, and viewport
    thumbnail (80x48 captured from `EditorInterface.get_editor_viewport_3d()`). Hover for enlarged
    preview; double-click to navigate undo history to that version. Undo/Redo buttons integrated
    into the browser header.
  - **Measurement Tool Improvements** (`HFMeasureTool`): persistent multi-ruler system (up to 20
    rulers with cycling colors). Shift+Click chains from last endpoint. Angle display between
    consecutive chained rulers at shared vertices. Right-click a ruler to set it as snap reference
    line (projected via `HFSnapSystem.set_custom_snap_line()`). A key toggles align mode. Delete
    removes last ruler; Escape clears all. HUD shows ruler count, distance, alignment status.
  - **Snap System Custom Lines** (`HFSnapSystem`): new `set_custom_snap_line()` /
    `clear_custom_snap_line()` methods. `snap_point()` now considers custom reference lines
    alongside grid/vertex/center candidates.
  - **Performance Monitor Enhancement**: Manage tab Performance section expanded with Entity Count,
    Vertex Estimate, Recommended Chunk Size, and Health summary (green/yellow/red color-coded).
    ProgressBar for brush count (max 200, color-coded). New `level_root` helpers:
    `get_entity_count()`, `get_total_vertex_estimate()`, `get_recommended_chunk_size()`,
    `get_level_health()`.
  - **One-Click Export Playtest Build**: "Export Playtest Build" button in Manage tab Bake section.
    Validates spawn (severity ≥ 2 blocks), bakes, packs baked scene + entities + default lighting as
    temporary `.tscn` at `user://hammerforge_playtest.tscn`, launches via
    `EditorInterface.play_custom_scene()`. Auto-created spawns are fully undoable (state capture
    before spawn creation). New `level_root.export_playtest_scene()` method.
  - 117 new tests across 7 files (theme_utils 15, perf_monitor 5, measure_tool 17, snap_system_custom
    6, history_browser 10, export_playtest 3, dock_history_and_playtest 7 + updates to existing).
    Total: **1091 tests across 62 files**.

- **Terrain & Organic Enhancements** (Apr 2026):
  - **Convert Selection to Heightmap** (`HFBrushToHeightmap`): select brushes → rasterize top faces
    onto a grid → create a sculptable heightmap paint layer. Dock button in Paint tab → Heightmap
    section. Converted layers inherit `base_grid` origin/basis and `chunk_size` from the paint layer
    manager. Emits `paint_layer_changed` and calls `regenerate_paint_layers()` for immediate geometry.
    Supports `grid_snap` as cell size and `height_scale_spin` for height multiplier.
  - **Foliage & Scatter brush** (`HFScatterBrush`): interactive scatter placement with circle and
    spline brush shapes, density/radius/height/slope filtering, scale variation, align-to-normal, and
    deterministic seeding. Preview via MultiMesh (Dots/Wireframe/Full modes). Commit creates permanent
    `MultiMeshInstance3D`. Full dock UI in Paint tab → Foliage & Scatter section with mesh picker,
    density/radius/height/slope/scale spinboxes, shape selector, and Preview/Scatter/Clear buttons.
    Spline mode uses selected node positions as control points with configurable width band.
  - **Path tool extras** (`HFPathTool`): auto-generate stairs (step brushes along sloped segments),
    railings (top rails + posts on both sides with configurable spacing), and trim strips (edge strips
    with material auto-assign) along path tool paths. New `path_extra` enum setting (None/Stairs/
    Railing/Trim) with 8 additional schema parameters. Preview lines: green ticks for stairs,
    yellow for railings, orange for trim.
  - **Dock-level integration tests** (`test_dock_terrain_integration.gd`): 30 tests covering the
    full heightmap convert pipeline (selection → convert → grid inheritance → signal emission →
    regenerate), scatter handler paths (preview circle/spline, commit, clear, stale state cleanup),
    `_build_scatter_settings` UI-to-settings wiring, and `_get_active_paint_layer` lookups.
    Uses a real `LevelRoot` with `auto_spawn_player=false` to avoid bake/playtest orphans.
  - 77 new tests across 4 files (test_brush_to_heightmap 11, test_scatter_brush 14,
    test_path_tool_extras 22, test_dock_terrain_integration 30). Total: **974 tests across 55 files**.

- **Learning & Discovery Aids** (Apr 2026):
  - **Coach marks** (`HFCoachMarks`): first-use floating step-by-step guides for 10 advanced tools
    (Polygon, Path, Carve, Vertex Edit, Extrude, Clip, Hollow, Measure, Decal, Surface Paint).
    Auto-triggered on tool activation. Per-tool "Don't show again" persisted via user prefs.
  - **Operation replay timeline** (`HFOperationReplay`): compact horizontal timeline of up to 20
    recent operations with color-coded icons per action type. Hover for elapsed time, click Replay to
    undo/redo to that point in the history. Toggle with Ctrl+Shift+T. Records undo versions from
    `EditorUndoRedoManager` and drives `UndoRedo.undo()`/`redo()` to reach the target version.
  - **Enhanced command palette** (Ctrl+K): fuzzy search with subsequence matching, word-boundary and
    consecutive-character bonuses. "Did you mean: ..." suggestion when no exact match found. Caps at 5
    fuzzy results. Ctrl+K added as additional toggle shortcut alongside Shift+? and F1.
  - **Example library** (`HFExampleLibrary`): 5 built-in demo levels (Simple Room, Corridor with
    Doorway, Jump Puzzle Platforms, Hollowed Building, Simple Arena) with difficulty badges, tags,
    searchable browser, and "Study This" annotations. Load button clears the scene and instantiates
    brushes + entities from JSON definitions. Section in Manage tab (collapsed by default).
  - `data/example_levels.json`: structured example level data with brush/entity definitions and
    per-level annotations.
  - 63 new tests across 4 files (test_coach_marks 14, test_operation_replay 23, test_fuzzy_search 9,
    test_example_library 17). Total: **944 tests across 54 files**.

- **I/O Connections & Entity Polish** (Apr 2026):
  - **Smart auto-routing**: connection lines now use quadratic Bézier curves with arrowheads instead
    of straight lines. Parallel connections between the same pair of entities offset laterally to
    avoid overlap (0.3 units per route).
  - **Color by type/delay**: output names are mapped to colors (cyan=OnTrigger, red=OnDamage,
    yellow=OnUse, green=OnOpen, magenta=OnBreak, orange=OnTimer, etc.). Fire-once connections pulse
    brighter. Delayed connections dim proportionally.
  - **I/O wiring panel** (`HFIOWiringPanel`): embedded in Entities tab with connection summary,
    outputs list, quick-wire form (output/target dropdown/input/param/delay/once), and preset
    picker with target tag mapping.
  - **Connection presets** (`HFIOPresets`): 6 built-in presets (Door+Light+Sound, Button→Toggle,
    Alarm Sequence, Pickup+Remove, Damage+Break, Timer Lights). Save entity connections as reusable
    user presets. Target tags map to actual entity names at apply time. User presets persist to the
    editor config directory (not the repo).
  - **Highlight Connected**: toggle to pulse-highlight all entities linked to the selected entity.
    SphereMesh overlays with animated alpha. Summary label in context toolbar ("Triggers 2 targets").
  - **Cross-UI highlight sync**: `highlight_connected` is authoritative on the visualizer, pushed
    to context toolbar via state dict and to wiring panel via `_sync_highlight_button()`. Both paths
    use `set_pressed_no_signal()` to avoid signal loops.
  - Context toolbar gains "HL" toggle button and "IOSummary" label in entity section.
  - `level_root.gd` gains `io_presets` subsystem, `set_highlight_connected()`, and
    `get_connection_summary()` delegation methods.
  - 57 new tests across 3 files (test_io_presets 21, test_io_visualizer_enhanced 20,
    test_io_highlight_sync 16). Total: **873 tests across 50 files**.

- **Bake & Quick Play Optimizations** (Apr 2026):
  - **Bake Selected**: bake only the currently selected brushes and merge output into the existing
    baked container (preserving previously baked geometry).
  - **Bake Changed**: bake only brushes flagged dirty since the last successful bake. Dirty tags are
    retained across failed bakes (`_last_bake_success` guard) and accumulate until the next success.
  - **Bake preview modes**: Full / Wireframe / Proxy toggle in Manage tab. Wireframe uses inline
    `ShaderMaterial` with `render_mode wireframe`. Proxy uses unshaded semi-transparent grey.
  - **Bake time estimate**: extrapolated from the last bake duration and brush count ratio. Shown in
    the Manage tab bake section; includes a "Chunking recommended" tip for >500 brushes.
  - **Bake issue detection** (`check_bake_issues()`): degenerate brush (near-zero thickness sev=2,
    oversized sev=1), floating subtract (sev=1), overlapping subtracts (sev=1). Color-coded overlay
    via `user_message` toast.
  - **Play from Camera**: temporarily moves spawn to editor camera position and writes camera yaw to
    `entity_data["angle"]`, bakes, validates, plays, then restores spawn to its original
    position/angle. Full undo/redo support via `_record_spawn_camera_undo()`.
  - **Play Selected Area**: saves cordon state, sets cordon from selection AABB, bakes within that
    region, validates spawn, plays, then restores the original cordon. Cordon is restored on both
    success and error (severity ≥ 2) paths.
  - Both new Quick Play modes share the same severity ≥ 2 blocking, auto-create, and fix-dialog
    patterns as the standard Quick Play path.
  - **Expanded validation** (`HFValidationSystem.check_bake_issues()`): non-convex/degenerate
    brushes, floating detail, overlapping subtracts with structured severity + message dicts.
  - 30 new tests (bake_system additions, bake_issues, quick_play_modes). Total: **807 tests
    across 47 files**.

- **Prefab variants** (Mar 2026): Prefabs can now contain multiple variants (e.g., wooden/metal/ornate
  door styles). Variants are stored alongside the base data in `.hfprefab` files. Cycle through
  variants on a placed instance with **Ctrl+Shift+V** or the **Var▶** context toolbar button.
  Add new variants via right-click → "Add Variant" in the prefab library.
- **Live-linked prefabs** (Mar 2026): "Save Linked" creates prefab instances that maintain a
  connection to the source `.hfprefab` file. Edit one instance and **Push** changes back to the
  source, or **Pull** to propagate the source to all linked instances. Per-instance overrides
  (transforms, sizes) are preserved during propagation.
- **Enhanced prefab browser** (Mar 2026): Searchable prefab library with tag filtering, variant
  count indicators, right-click context menu (Add Variant, Edit Tags, Delete), and "Save Linked"
  button alongside standard save. Tags support comma-separated values and are persisted in the
  `.hfprefab` file format.
- **Quick group-to-prefab** (Mar 2026): **Ctrl+Shift+P** or **Pfb** button in the context toolbar
  saves the current selection as a prefab instantly with an auto-generated name based on contents.
  Available in both brush-selected and entity-selected toolbar contexts.
- **Prefab ghost overlay** (Mar 2026): Hovering a node that belongs to a prefab instance in the
  3D viewport draws a cyan wireframe bounding box around the entire instance. Orange sphere markers
  highlight nodes with per-instance overrides.
- **HFPrefabSystem subsystem** (Mar 2026): New `systems/hf_prefab_system.gd` subsystem manages
  instance registry, variant cycling, override tracking, live-linked propagation, push-to-source,
  and state serialization. Integrates with undo/redo via state capture/restore.
- **Prefab tags** (Mar 2026): `.hfprefab` files now support a `tags` field (array of strings)
  for categorization. Tags are searchable in the library and filterable via a dropdown.
- 24 new tests (variants, tags, system state, overrides, suggestions, overlay). Total: **777 tests
  across 45 files**.

### Fixed
- **Godot 4.6 API compatibility fixes (Mar 2026):**
  - **Dock undo/redo buttons targeted wrong history**: `_on_history_undo()`, `_on_history_redo()`,
    `_update_history_buttons()`, and `_get_undo_version()` all hard-coded
    `EditorUndoRedoManager.GLOBAL_HISTORY`, but HammerForge actions are recorded against the
    scene's history (first do/undo object is the LevelRoot node). Buttons could disable
    incorrectly or no-op. Fixed with `_get_scene_history_id()` /
    `_get_scene_undo_redo()` helpers that resolve the correct history via
    `get_object_history_id(level_root)`.
  - **`EditorUndoRedoManager` has no `undo()`/`redo()`/`has_undo()`/`has_redo()`**: dock
    buttons called these directly on `EditorUndoRedoManager` which doesn't expose them.
    Fixed to call them on the `UndoRedo` object returned by `get_history_undo_redo()`.
  - **`Image.load()` removed in Godot 4**: `hf_heightmap_io.gd` used the Godot 3 instance
    method. Replaced with the static `Image.load_from_file()` (returns `Image` or `null`).
  - **`popup_centered(Vector2(...))` type mismatch**: two dialog popups passed `Vector2` instead
    of `Vector2i`. Fixed in heightmap import and terrain slot texture dialogs.
  - **Gizmo redraw via nonexistent methods**: `brush_gizmo_plugin.gd` tried `set_dirty()` /
    `redraw()` on `EditorNode3DGizmo` which aren't exposed to script. Replaced with
    `gizmo.get_node_3d().update_gizmos()`.
- **Selection filter popup not attached to scene tree (Mar 2026):**
  - `HFSelectionFilter` (`PopupPanel`, a `Window` subclass) was instantiated but never added
    to the tree, so `popup()` silently failed. Now added as a child of
    `EditorInterface.get_base_control()`.
- **Node-only selection filters left stale face context (Mar 2026):**
  - Filters like "Similar Brushes", visgroup, and detail/structural applied node selection
    without clearing `root.face_selection`. The context toolbar kept showing face-mode UI and
    material ops targeted old faces. Fixed: node-only filter results now call
    `_apply_face_selection(root, {})` to clear faces and update the HUD before applying node
    selection.
- **Apply Last Texture only affected first brush (Mar 2026):**
  - `_apply_last_texture()` broke after the first `DraftBrush` in the selection loop. Fixed to
    iterate all selected brushes. Same fix applied to `_on_context_material_apply()`.
- **Selection filters used local-space normals (Mar 2026):**
  - Normal-based face filters (Walls/Floors/Ceilings) and "Select Similar Faces" compared
    `face.normal` in local space. Rotated brushes would be classified incorrectly. Fixed to
    transform normals to world space via `brush.global_transform.basis * face.normal`. Same
    fix applied to `_select_similar_faces()` in `plugin.gd`.
- **Material assignment no longer requires face selection (Mar 2026):**
  - Double-clicking a texture in the material browser, or clicking the Assign button, now
    falls back to **whole-brush assignment** when no individual faces are selected but brushes
    are selected in the viewport. Previously this showed "No faces selected — select faces
    first" even with brushes highlighted.
  - New `resolve_material_assign_action()` pure-decision helper on `dock.gd` encapsulates
    the face-vs-brush fallback logic, shared by `_on_material_assign()`,
    `_on_browser_material_double_clicked()`, and available for future callers.
- **Texture reimport no longer clears brush selection (Mar 2026):**
  - Loading prototype SVG textures in the material browser could trigger Godot's texture
    reimport pipeline, which emitted spurious empty `selection_changed` signals that cleared
    the dock's brush selection cache.
  - Added `should_suppress_empty_selection()` static guard in `plugin.gd`: ignores empty
    editor selection events when `hf_selection` is still populated. Intentional deselects
    (Escape key, delete, dock Clear Selection button, Commit Cuts) clear `hf_selection`
    first so the guard lets them through.
  - New `selection_clear_requested` signal on `dock.gd` lets the dock tell the plugin to
    clear its cache before calling `editor_selection.clear()`.
  - Reordered `hf_selection.clear()` before `selection.clear()` in three plugin deselect
    paths (Escape, delete brushes, duplicate brushes) for consistency with the guard.
- **Prefab system stability fixes (Apr 2026):**
  - **Inferred-type compilation errors**: GDScript `:=` on untyped `root` parameter returns
    caused Godot 4.6 parse failures in `plugin.gd` and `hf_prefab_overlay.gd`. Changed to
    explicit typed declarations (`var x: Type = ...`).
  - **Undo/redo lost prefab node tags**: `restore_state()` rebuilt the `_instances` registry
    but never re-tagged scene nodes with `hf_prefab_instance`/`hf_prefab_source`/
    `hf_prefab_variant` meta. Prefab overlay and toolbar badge stopped working after undo.
    Fixed by calling `_tag_nodes(rec)` in the restore loop.
  - **Entity identity collisions**: Prefab instance entity membership was tracked by scene
    node name, which can collide across unrelated entities. Replaced with stable UIDs
    (`hf_prefab_entity_id` meta) assigned at registration time. `hf_prefab.gd` `instantiate()`
    now returns `entity_nodes` (Node3D refs) alongside `entity_names`.
  - **Permanent prefab buttons in context toolbar**: Var▶/Push/Pull buttons were permanently
    appended to toolbar sections on first prefab selection and never removed. Rebuilt as
    named child nodes created at build time, toggled visible/hidden in `_apply_context()`
    based on whether a prefab instance is currently selected.
  - **Vertex system API mismatch**: Context toolbar and hotkey palette dispatchers called
    nonexistent `set_sub_mode()`, `merge_selected()`, and `split_selected_edge()` on
    `HFVertexSystem`. Fixed to use `sub_mode` property assignment and new
    `_vertex_merge_selected()` / `_vertex_split_selected_edge()` helpers that resolve
    selection state before calling `merge_vertices()` / `split_edge()`.
  - **Orphan warnings in prefab tests**: `queue_free()` defers deletion past GUT's per-test
    orphan counter. Changed to immediate `free()` in test cleanup.

### Added
- **Improved Selection & Multi-Select (Mar 2026):**
  - **Marquee / box selection**: click-and-drag in Select mode to rubber-band select brushes
    and entities. In Face Select mode, marquee selects individual faces across multiple brushes.
    Semi-transparent blue overlay rectangle drawn during drag. Uses `_select_nodes_in_rect()` for
    brushes/entities and new `_select_faces_in_rect()` for face mode.
  - **Selection filter popover** (`ui/hf_selection_filter.gd`): popup panel with bulk selection
    tools organized by category:
    - **By Normal**: Walls (|Y| < 0.3), Floors (Y > 0.7), Ceilings (Y < -0.7).
    - **By Material**: select all faces matching the currently selected face's material.
    - **Select Similar**: Similar Faces (material + normal within 15°), Similar Brushes (size
      within 20% tolerance, orientation-agnostic).
    - **By Visgroup**: dynamic buttons for each visgroup (auto-rebuilt on open).
    - **By Type**: Detail Brushes (func_detail), Structural (worldspawn).
    Emits `filter_applied(nodes, faces)` signal handled by plugin to apply selection.
  - **"Select Similar" hotkey** (Shift+S): quick-invoke from viewport. Selects faces with
    matching material + normal when faces are selected, or brushes with similar size when
    brushes are selected.
  - **"Apply Last Texture" hotkey** (Shift+T): applies the last texture picked with the
    Texture Picker (T) to the current face or brush selection. Stores `_last_picked_material_index`
    when T picks a material.
  - **"Selection Filters" hotkey** (Shift+F): opens the selection filter popover at mouse position.
  - **Enhanced selection count badge**: status bar now shows combined counts when applicable
    (e.g. "Sel: 3 brushes, 5 faces").
  - **Context toolbar updates**: face section gains "Sim" (Select Similar) and "Last" (Apply
    Last Texture) buttons; brush section gains "Sim" and "Flt" (Selection Filters) buttons.
    Labels now show "N brush(es) selected", "N faces on M brush(es)", "N entities selected".
  - **Command palette updates**: `select_similar`, `apply_last_texture`, and `selection_filter`
    actions added with live gray-out rules.
  - **3 new keymap bindings** in "Tools" and "Selection" categories with human-readable labels.
  - **18 new GUT tests** (`test_selection_features.gd`): keymap binding matches, labels,
    categories, display strings, toolbar label content, `_size_similar()` helper logic.
    **Total: 753 tests across 44 files.**
- **Smart Contextual Toolbar + Command Palette (Mar 2026):**
  - **Floating context toolbar** (`ui/hf_context_toolbar.gd`): appears in the 3D viewport overlay with
    context-sensitive actions based on current selection and tool state. Automatically shows/hides as
    context changes — no manual tab switching needed.
  - **Brush selected** → Extrude Up/Down, Hollow, Clip, Carve, Duplicate, Delete buttons. Label shows
    "N brush(es)" count.
  - **Face selected** → Material thumbnail strip (5 favorites), UV Justify buttons (Fit/Center/L/R/T/B),
    "Apply to Whole Brush" button. Label shows "N face(s)" count.
  - **Entity selected** → I/O connect and Properties quick-edit buttons (jump to Entities tab),
    Duplicate, Delete.
  - **Draw idle** → Quick shape selector (Box/Cyl/Sph/Cone), Add/Subtract toggle with color-coded label
    (green Add / red Sub) and one-click switch.
  - **Dragging** → Live dimension display, Axis Lock buttons (X/Y/Z), Cancel button.
  - **Vertex edit** → Vertex/Edge sub-mode toggle, Merge, Split, Exit buttons.
  - **Auto-mode hint bar**: during brush drawing, a blue overlay bar appears with the current operation
    mode ("Drawing in Add mode — press Subtract to toggle") and a one-click "Switch to Subtract/Add"
    button. Fades in smoothly, auto-hides when not drawing.
  - **Command palette** (`ui/hf_hotkey_palette.gd`): searchable action palette toggled with `Shift+?`
    or `F1`. Lists all HammerForge actions grouped by category (Tools, Editing, Paint, Axis Lock) with
    key bindings. Live search filters by action name or binding. **Live gray-out**: actions that cannot
    run in the current state are visually disabled (e.g. Hollow grayed out with no brush selection,
    paint tools grayed out outside paint mode, vertex tools grayed outside vertex mode). Press Enter to
    execute the first visible+enabled match. Esc to close.
  - **Dock integration**: `dock.gd` gains `_apply_material_to_whole_brush()` and
    `_on_face_assign_material()` convenience methods for toolbar-initiated material assignment.
  - **Plugin integration** (`plugin.gd`): context toolbar and palette added to
    `CONTAINER_SPATIAL_EDITOR_MENU` alongside existing HUD. State updates every frame via
    `_update_context_toolbar_state()` which computes brush/entity/face counts, input mode, operation,
    and vertex state. Action dispatch routes to existing dock/plugin methods (hollow, clip, carve,
    justify, axis lock, tool switch, etc.) with full undo/redo support.
  - **32 new GUT tests** (`test_context_toolbar.gd` 20 tests, `test_hotkey_palette.gd` 12 tests):
    context determination, label content, action signals, material thumbnails, search filtering,
    gray-out logic, toggle visibility. **Total: 726 tests across 43 files.**
- **Player Spawn System + Quick Play Overhaul (Mar 2026):**
  - **New subsystem** (`systems/hf_spawn_system.gd`): `HFSpawnSystem` manages spawn lookup, physics-
    based validation, auto-fix, default spawn creation, and debug visualisation. Follows the
    coordinator+subsystem pattern (RefCounted, injected LevelRoot reference).
  - **Spawn validation** before every Quick Play: floor raycast (PhysicsDirectSpaceState3D), capsule
    collision check (player-sized CapsuleShape3D), ceiling/headroom check, and below-map heuristic.
    Returns structured result with issues list, severity (NONE/WARNING/ERROR), and suggested fix
    position. Runs in < 5 ms via direct space queries.
  - **Auto-fix dialog**: when spawn has critical issues (inside geometry, floating), a
    ConfirmationDialog offers "Fix & Play" (snaps to suggested position) or "Cancel". Warnings
    show a toast but proceed automatically.
  - **Auto-create fallback spawn**: if no `player_start` entity exists, Quick Play auto-creates one
    at the centroid of all brushes + safe height offset, with a warning toast.
  - **Debug visualisation** (`show_validation_debug()`): green/red capsule preview at spawn
    position, floor ray (ImmediateMesh line to hit point or red ray to void), ceiling ray (yellow),
    floor disc marker, red collision sphere for penetration issues. Auto-cleans after configurable
    duration or stays persistent (duration=0) for the "Preview Spawn Debug" toggle.
  - **Manage tab → Spawn section**: "Validate Spawn" button (runs validation + shows debug for 10s),
    "Create Default Spawn" button (creates fallback player_start), "Preview Spawn Debug" checkbox
    (persistent visualisation toggle).
  - **player_start entity enhanced** (`entities.json`): three new properties — `primary` (bool,
    preferred spawn for Quick Play), `angle` (float, yaw rotation in degrees), `height_offset`
    (float, extra height above floor). Color changed from green to cyan. Auto-generated property
    form in Entities dock via existing `hf_entity_def.gd` loader.
  - **Playtest FPS controller** (`playtest_fps.gd`): new `player_start_position` and
    `player_start_rotation_y` exports. `_ready()` applies spawn position/rotation if set.
  - **level_root.gd**: `spawn_system` subsystem initialised in `_ready()`. `_start_playtest()`
    rewritten to use `spawn_system.get_active_spawn()` with primary-flag priority, yaw rotation
    from `angle` property, and legacy fallback scan.
  - **Quick Play tooltip**: dynamically shows active spawn name and position.
  - **21 new GUT tests** (`tests/test_spawn_system.gd`): spawn lookup (no spawns, single, primary
    priority, first fallback, non-player_start filtering), validation (null, not-in-tree, no-physics),
    auto-fix (applies suggested position, null safety), default creation (empty level, brush
    centroid), debug viz (create/cleanup, floor hit, issues, null safety), entity property helpers,
    severity ordering. **Total: 685 tests across 41 files.**
- **Visual Texture Browser + Texture Picker (Mar 2026):**
  - **Visual material browser** (`ui/hf_material_browser.gd`): replaces the text-only material
    ItemList with a scrollable thumbnail grid (64px cells, 5 columns). Each cell shows the actual
    SVG texture preview via `TextureRect`, with a short label and tooltip. Click to select, right-click
    for context menu (Apply to Faces, Apply to Whole Brush, Toggle Favorite, Copy Name).
  - **Search and filters**: live text search bar, pattern dropdown filter (15 patterns + "All"),
    color swatch row (10 clickable color buttons + "All"), and view toggle (Prototypes / Palette /
    Favorites). Filters combine — e.g. pattern=brick + color=red + search="dark" all narrow together.
  - **Favorites system**: right-click any thumbnail to toggle favorite. Favorites view shows only
    starred materials. Favorite state persists in the browser instance.
  - **Hover preview**: hovering a thumbnail in the browser temporarily applies that material to all
    currently selected faces in the viewport. Material reverts on mouse leave.
  - **Texture Picker tool** (T key): eyedropper that raycasts to the face under the cursor, reads
    its `material_idx` from `FaceData`, and sets it as the current selection in the browser. Registered
    in `HFKeymap` under the "Tools" category with display label "Texture Picker".
  - **Context menu**: `PopupMenu` with "Apply to Selected Faces" (uses existing
    `assign_material_to_selected_faces` state action), "Apply to Whole Brush" (iterates selected
    brushes), "Toggle Favorite", and "Copy Name" (clipboard).
  - **Drag-and-drop support**: thumbnails emit drag data `{"type": "hammerforge_material", "index": N}`
    with a thumbnail + label drag preview, following the existing entity/brush preset pattern.
  - **"Load Prototypes" renamed to "Refresh Prototypes"** for clarity (behavior unchanged).
  - **Status bar**: shows "X of Y materials" with filter state, or guidance text when palette is empty.
  - **Backwards compatibility**: hidden legacy `ItemList` preserved for `_refresh_materials_list()`
    sync path; browser rebuilds via new `_refresh_material_browser()` called alongside it.
- **Vertex Editing Enhancements + Polygon Tool + Path Tool (Mar 2026):**
  - **Edge sub-mode for vertex editing** (`systems/hf_vertex_system.gd`): new `VertexSubMode` enum
    (VERTEX, EDGE) toggled with `E` key. Edge selection, additive/toggle selection, wireframe overlay
    (dim gray default, orange selected, yellow hovered). `get_brush_edges()` extracts unique undirected
    edges from face data with canonical deduplication. `pick_edge()` projects edges to screen space for
    click selection. Edge selection syncs to vertex selection so `move_vertices()` works transparently.
  - **Edge splitting** (`Ctrl+E`): `split_edge()` inserts midpoint vertex into every face containing
    the edge, updating `local_verts` and calling `ensure_geometry()`. Mathematically guaranteed to
    preserve convexity on convex hulls. Face snapshot undo via `get_pre_op_snapshots()`.
  - **Vertex merging** (`Ctrl+W`): `merge_vertices()` computes centroid of selected vertices, replaces
    all occurrences in all faces, removes degenerate faces (< 3 unique verts). Validates convexity;
    reverts via face snapshots if invalid.
  - **Edge wireframe overlay** in `plugin.gd :: _update_vertex_overlay`: ImmediateMesh `PRIMITIVE_LINES`
    pass draws all brush edges with color-coded selection/hover state before vertex crosses.
  - **`get_single_selected_edge()`**: returns `[brush_id, edge]` when exactly one edge is selected,
    empty array otherwise. Used by split_edge input handler.
  - **`get_all_edge_world_positions()`**: returns `[{a, b, selected, hovered}]` for overlay rendering.
  - **Static `_point_to_segment_dist_2d()`**: 2D point-to-segment distance for edge picking.
  - **Polygon tool** (`hf_polygon_tool.gd`): `HFPolygonTool` extends `HFEditorTool` (tool_id=102,
    KEY_P). Three-phase state machine: IDLE → PLACING_VERTS → SETTING_HEIGHT. Click to place convex
    polygon vertices on ground plane (grid-snapped), auto-close when clicking near first point (threshold
    configurable via `auto_close_threshold` setting), or Enter to close manually. Mouse drag sets
    extrusion height. Convexity enforced via 2D cross product on XZ plane (`_is_convex_xz()` static
    method). Face data construction: top (CCW winding), bottom (CW), N side quads, all in local space
    relative to AABB center. Winding detection via shoelace formula. ImmediateMesh preview (cyan outline,
    green vertical edges during height stage). Creates brush via `create_brush_from_info()` with undo/redo.
  - **Path tool** (`hf_path_tool.gd`): `HFPathTool` extends `HFEditorTool` (tool_id=103,
    KEY_SEMICOLON). Two-phase state machine: IDLE → PLACING_WAYPOINTS. Click to place waypoints on
    ground plane, Enter to finalize (requires 2+). For each consecutive waypoint pair, builds an
    oriented-box brush (8 corners from direction + perpendicular vectors, 6 FaceData quads). Miter joint
    brushes fill triangular gaps at interior waypoints (angular sorting for convex hull, skipped if angle
    too straight or too acute). All brushes share a `group_id` for auto-grouping. Settings:
    `path_width` (4.0), `path_height` (4.0), `miter_joints` (bool, true). ImmediateMesh preview (cyan
    polyline, parallel width offset lines, perpendicular ticks). Single undo action for entire path.
  - **New keymap bindings** (`hf_keymap.gd`): `vertex_edge_mode` (E), `vertex_merge` (Ctrl+W),
    `vertex_split_edge` (Ctrl+E). Added to "Tools" category with display labels.
  - **Shortcut HUD update** (`shortcut_hud.gd`): vertex edit hints now include "E: Toggle edge mode"
    and "Ctrl+W: Merge verts | Ctrl+E: Split edge".
  - **Tool registry update** (`hf_tool_registry.gd`): `activate_tool()` now accepts optional
    `EditorUndoRedoManager` parameter, passed to tools that create brushes.
  - **Base tool update** (`hf_editor_tool.gd`): added `var undo_redo: EditorUndoRedoManager` member
    for tools that create brushes (polygon, path).
  - **GUT tests**: 3 new test files — `test_vertex_edges.gd` (19 tests: edge extraction, dedup,
    selection, world positions, split, merge, sub-mode, point-to-segment), `test_polygon_tool.gd`
    (16 tests: convexity validation, face construction, normals, empty/degenerate, tool metadata),
    `test_path_tool.gd` (15 tests: segment brush construction, miter joints, face validation,
    tool metadata). Total: **622 tests** across **38 files**.
- **UX Feature Wave — Tutorial, Hints, Subtract Preview, Prefabs (Mar 2026):**
  - **Dynamic contextual hints** (`shortcut_hud.gd`): viewport overlay hints appear when switching
    tool modes (draw, select, extrude, paint). Each hint shows instructional text specific to the
    current mode (e.g. "Click to place corner → drag to set size → release for height"). Auto-fades
    after 4 seconds via tween. Per-hint dismissal persists in user preferences via
    `is_hint_dismissed()` / `dismiss_hint()` on `hf_user_prefs.gd`. `MODE_HINTS` const dictionary
    maps mode keys to hint strings.
  - **Searchable shortcut dialog** (`ui/hf_shortcut_dialog.gd`): replaces the static shortcuts
    popup. Extends `AcceptDialog` with a search `LineEdit` and categorized `Tree`. Categories
    (Tools, Editing, Paint, Axis Lock) populated from `HFKeymap.get_category()` and
    `get_action_label()`. Real-time case-insensitive filtering on action name or key binding string.
  - **Interactive tutorial wizard** (`ui/hf_tutorial_wizard.gd`): 5-step guided first-run experience
    replacing the static welcome panel. Steps: Draw room (`brush_added` signal) → Subtract window
    (`brush_added` + operation validation) → Paint floor (`paint_layer_changed`) → Place entity
    (`entity_added`) → Bake & preview (`bake_finished`). Each step listens for the corresponding
    LevelRoot signal. Optional validation (e.g. `_validate_subtract` checks `operation ==
    SUBTRACTION`). ProgressBar shows step N of 5. Skip Step / Dismiss buttons. Progress persisted
    via `tutorial_step` in user prefs. Dock `highlight_tab()` flashes the relevant tab on each step.
  - **Real-time subtract preview** (`systems/hf_subtract_preview.gd`): wireframe AABB intersection
    overlays between additive and subtractive brushes. Uses ImmediateMesh `PRIMITIVE_LINES` (same
    12-edge box pattern as cordon wireframe). Red material `Color(1.0, 0.3, 0.3, 0.7)`, unshaded,
    no depth test. Debounced rebuild (0.15s), MeshInstance3D pool (max 50), automatic update on
    `brush_added` / `brush_removed` / `brush_changed` signals. Toggle via `show_subtract_preview`
    export on LevelRoot (persisted in state settings). Checkbox in Manage tab → Settings.
  - **Prefab system** (`hf_prefab.gd` + `ui/hf_prefab_library.gd`): save and load reusable brush +
    entity groups as `.hfprefab` JSON files. `HFPrefab.capture_from_selection()` computes centroid
    and stores transforms relative to it. `instantiate()` assigns new brush IDs, offsets transforms,
    and remaps entity I/O connections via name map. Uses `begin_signal_batch()` /
    `end_signal_batch()` for atomic multi-brush creation. `HFPrefabLibrary` dock section in Manage
    tab shows `.hfprefab` files from `res://prefabs/` with drag-and-drop support. Plugin handles
    `"hammerforge_prefab"` drop type with raycast + snap + undo/redo.
  - **New public API methods**: `HFBrushSystem.next_brush_id()` (public wrapper),
    `HFEntitySystem.remap_io_connections()` (remap I/O targets on prefab instantiate),
    `HFKeymap.get_all_bindings()`, `HFKeymap.get_category()`, `HFKeymap.get_action_label()`.
  - **GUT tests**: 4 new test files — `test_shortcut_dialog.gd` (8), `test_tutorial_wizard.gd` (7),
    `test_subtract_preview.gd` (8), `test_prefab.gd` (11). Plus 3 additions to
    `test_user_prefs.gd`. Total: **568 tests** across **34 files**.
- **Usability & Feature Upgrade (Mar 2026):**
  - **Bake failure toast notifications**: `warn_bake_failure()` now emits contextual error messages
    via `user_message` signal (e.g. "No draft brushes found", "You have N pending cuts — try
    'Commit Cuts' before baking", "CSG produced no geometry — check brush operations"). Null baker
    guard also toasts.
  - **Silent failure logging in paint system**: ~20 guard clauses across `hf_paint_system.gd`,
    `hf_paint_tool.gd` now emit `push_warning()` for internal logging and `user_message` for
    user-facing failures (heightmap import failure, paint input ignored, bucket fill limit hit).
  - **Entity definition load error reporting**: `hf_entity_def.gd` now emits `push_error()` on JSON
    parse failure, `push_warning()` for malformed entries and fallback to built-in defaults.
  - **Paint layer rename**: new `display_name` field on `HFPaintLayer` with `rename_layer()` on
    `HFPaintLayerManager`. Dock shows "R" rename button with dialog. Display names serialize in
    `.hflevel` and fall back to layer ID when empty. Backward compatible.
  - **Axis lock visual indicator**: dock shows X/Y/Z toggle buttons with color-coded pressed states
    (red=X, green=Y, blue=Z). Bidirectional sync with keyboard axis lock via
    `set_pressed_no_signal()`.
  - **Entity I/O viewport visualization**: `HFIOVisualizer` (`systems/hf_io_visualizer.gd`) draws
    ImmediateMesh lines between connected entities. Color-coded: green=standard, orange=fire_once,
    yellow=selected entity connections. Throttled refresh (10 frames). Toggle in Entities tab.
  - **Measurement/ruler tool**: `HFMeasureTool` (`hf_measure_tool.gd`) extends `HFEditorTool`
    (tool_id=100, M key). Click point A → click point B → persistent line + Label3D with distance
    and dX/dY/dZ decomposition. Grid-snapped. Escape clears.
  - **Terrain sculpting brushes**: 4 new stroke tools — SCULPT_RAISE, SCULPT_LOWER, SCULPT_SMOOTH,
    SCULPT_FLATTEN (HFStroke.Tool values 6-9). Operates directly on heightmap Image pixels with
    configurable strength, radius, and falloff curve. Dock shows 4 toggle buttons + 3 spinboxes.
    Flatten captures height on first click and lerps toward it.
  - **Dock decomposition into tab builders**: extracted ~2,000 lines from `dock.gd` into 4 builder
    files: `ui/paint_tab_builder.gd`, `ui/entity_tab_builder.gd`, `ui/manage_tab_builder.gd`,
    `ui/selection_tools_builder.gd`. Each is RefCounted, receives dock reference, has `build()` and
    `connect_signals()` methods. `dock.gd` reduced by ~35%.
  - **Baker test coverage**: new `tests/test_bake_system.gd` with 18 tests covering
    `build_bake_options()`, `_is_structural_brush()`, `_is_trigger_brush()`, `count_brushes_in()`,
    `chunk_coord()`, `bake_dry_run()`, `warn_bake_failure()`, and structural filtering.
  - **Carve tool**: `HFCarveSystem` (`systems/hf_carve_system.gd`) — boolean-subtract one brush from
    all intersecting brushes. Progressive-remainder algorithm produces up to 6 box slices per target.
    Preserves material, operation, visgroups, group_id, brush_entity_class. Ctrl+Shift+R shortcut.
    Undo/redo via `HFUndoHelper`.
  - **Decal/overlay system**: `HFDecalTool` (`hf_decal_tool.gd`) extends `HFEditorTool`
    (tool_id=101, N key). Raycast placement of Godot `Decal` nodes oriented to surface normal. Live
    preview follows cursor. Declarative settings: texture path, size, fade. Tagged with `hf_decal`
    meta for serialization.
  - **Integration test suite**: new `tests/test_integration.gd` with 22 end-to-end tests across 8
    categories: brush lifecycle, paint + heightmap, entity workflow, visgroup cross-system, snap
    system, bake cross-system, entity I/O cleanup, and brush info round-trip.
  - **GUT tests**: 99 new tests across 3 files. Total: **512 tests** across **30 files**.
- **FreeCAD-Inspired Improvements (Mar 2026):**
  - **Operation result reporting** (`hf_op_result.gd`): `HFOpResult` lightweight result class returned
    by `hollow_brush_by_id()`, `clip_brush_by_id()`, and `delete_brush_by_id()`. Carries `ok`, `message`,
    and `fix_hint` fields. Failed operations now surface actionable toast notifications (e.g. "Wall
    thickness 6 is too large for brush (smallest dim 10) — Use a thickness less than 5") instead of
    silently returning. `_op_fail()` helper emits `user_message` signal at WARNING level automatically.
  - **Geometry-aware snap system** (`hf_snap_system.gd`): centralized `HFSnapSystem` with three snap
    modes — **Grid** (existing behavior), **Vertex** (8 box corners of all brushes), and **Center**
    (brush centers). Closest geometry candidate within threshold beats grid snap. `_snap_point()` in
    `level_root.gd` now delegates to the snap system. Dock shows G/V/C toggle buttons below the grid
    snap row. Replaces the previous grid-only snapping.
  - **Live dimensions during drag**: `input_state.gd` gains `get_drag_dimensions()` and
    `format_dimensions()`. The mode indicator banner now shows real-time brush dimensions during
    DRAG_BASE and DRAG_HEIGHT gestures (e.g. "Step 1/2: Draw base — 64 x 32 x 48",
    "Step 2/2: Set height — 64 x 96 x 48").
  - **Reference cleanup on deletion**: `delete_brush()` now calls `_cleanup_brush_references()` which
    strips group membership (auto-cleans empty groups), clears visgroup meta, and warns via toast when
    entity I/O connections targeting the deleted node are removed. New
    `cleanup_dangling_connections(deleted_name)` on `HFEntitySystem` removes all I/O connections
    targeting a deleted node and returns the removal count. Exposed on LevelRoot as a delegate.
  - **GUT tests** for new systems: `test_op_result.gd` (15), `test_snap_system.gd` (12),
    `test_drag_dimensions.gd` (8), `test_reference_cleanup.gd` (9) = 44 new tests.
    Total: 413 tests across 27 files.
- **UX Intuitiveness Overhaul (Mar 2026):**
  - **Mode indicator banner**: colored banner between toolbar and tabs shows current tool, gesture
    stage ("Step 1/2: Draw base"), and numeric input. Color-coded per tool: Draw (blue), Select
    (green), Extrude Up (green), Extrude Down (red), Paint (orange). Replaces ambiguous footer text.
  - **Toast notification system** (`ui/hf_toast.gd`): transient notifications surface errors and
    confirmations in the dock. Levels: INFO, WARNING, ERROR with color-coded backgrounds and
    auto-fade. Connected to save/load/export/bake results and new `user_message` signal on
    LevelRoot. Replaces silent `push_error`/`push_warning` calls for user-facing operations.
  - **Readable toolbar labels**: toolbar buttons now show icon + text label (Draw, Select, Add,
    Sub, Paint, Ext Up, Ext Dn) instead of blanking text when icons load.
  - **Inline disabled hints**: "Select a brush to use these tools" text in Selection Tools section
    and "Enable Face Select Mode and click a face to edit" in Materials section. Visible without
    hovering, toggles based on selection/face state.
  - **First-run welcome panel** (`ui/hf_welcome_panel.gd`): 5-step quick-start guide shown on
    first launch. "Don't show again" checkbox persists via user preferences.
  - **Context-sensitive next action hints**: per-tab hint labels at the bottom of each dock tab
    guide users through the workflow (e.g. "Click and drag in the viewport to draw your first
    brush", "Try: Hollow, Clip, or Extrude"). Updates based on scene state.
  - **Shortcuts quick-reference popup**: "?" button on toolbar opens a popup listing all keybindings
    grouped by context (Tools, Editing, Paint, Axis Lock) plus drag/extrude tips. Built dynamically
    from keymap data.
  - **Face hover highlight for extrude**: in extrude mode, hovering over a brush face shows a
    semi-transparent overlay (green for up, red for down) previewing which face will be selected.
    Uses StandardMaterial3D with alpha transparency for filled overlay.
  - **Clear selection button**: small "x" button appears next to "Sel: N brushes" in the footer
    when selection is non-empty. Provides a visible deselect action beyond the Escape key.
  - **`user_message` signal** on LevelRoot: subsystems can surface messages to the dock toast
    system via `root.user_message.emit(text, level)`.
  - `show_welcome` and `hints_dismissed` added to user preferences defaults.
- **Built-in prototype textures (Mar 2026):**
  - **150 SVG prototype textures** (15 patterns x 10 colors) ship with the plugin at
    `addons/hammerforge/textures/prototypes/`. Patterns include solid, brick, checker, cross,
    diamond, dots, hex, stripes (diagonal/horizontal), triangles, zigzag, and directional arrows.
  - **"Load Prototypes" button** in Paint tab → Materials section: one-click batch-load of all 150
    textures as `StandardMaterial3D` resources into the material palette.
  - **`HFPrototypeTextures` catalog class** (`hf_prototype_textures.gd`): static API for querying
    patterns/colors, loading individual textures, creating materials, and batch-populating a
    `MaterialManager`. Uses hardcoded arrays for headless-test compatibility.
  - **HTML preview page** (`docs/prototype_textures_preview.html`): self-contained browser-viewable
    catalog of all 150 textures with search and filtering.
  - **Documentation** (`docs/HammerForge_Prototype_Textures.md`): patterns/colors reference, UI and
    GDScript usage, API reference.
  - **GUT tests** (`tests/test_prototype_textures.gd`): 27 test cases covering catalog constants,
    path generation, resource loading, material persistence (resource_path), and batch loading.
- **Dock UX improvements (Mar 2026):**
  - **Selection Tools section** in Brush tab: hollow, clip, move floor/ceiling, tie entity, and
    duplicator controls now appear contextually when brushes are selected (moved from Manage tab).
  - **Collapsible section polish**: each section now has an HSeparator divider and 4px left-indented
    content for visual hierarchy. Collapsed state persists across sessions via user preferences.
  - **Signal-driven paint/material/face sync**: paint layer, material palette, surface paint, and
    face selection updates are now instant via `paint_layer_changed`, `material_list_changed`,
    `face_selection_changed`, and `selection_changed` signals (replaced 10-frame polling throttle).
  - **`material_list_changed` signal** on LevelRoot: emitted on material add/remove for instant
    dock sync.
  - **`face_selection_changed` signal** on LevelRoot: emitted from `select_face_at_screen()`,
    `toggle_face_selection()`, and `clear_face_selection()` (only when selection actually changes).
    Drives UV/surface paint panel sync and disabled-hint updates.
  - **Initial sync on root connect**: `_connect_root_signals()` now calls `_sync_materials_from_root()`
    and `_sync_surface_paint_from_root()` so existing materials/surface data appear immediately.
  - **Initial selection state on startup**: plugin pushes cached editor selection to dock in
    `_enter_tree()`, so Selection Tools visibility is correct from first frame.
  - **Compact toolbar**: single-char button labels (D, S, +, -, P, ▲, ▼) with full descriptions in
    tooltips. VSeparator before extrude buttons. Labels update from keymap.
  - **UV Justify grid**: 3x2 GridContainer layout replaces cramped 2-row HBoxContainer.
  - **Autosave warning** defined in dock.tscn (was runtime-created Label).
- **Customizable keymaps** (`hf_keymap.gd`): all keyboard shortcuts are now data-driven via
  `HFKeymap` instead of hardcoded `KEY_*` constants. Bindings stored as action → {keycode, ctrl,
  shift, alt} maps. `load_or_default()` reads `user://hammerforge_keymap.json` or falls back to
  built-in defaults. `matches(action, event)` replaces ~25 inline keycode checks in `plugin.gd`.
  `get_display_string()` provides human-readable labels (e.g. "Ctrl+Shift+F"). Toolbar button
  labels and tooltips update from keymap automatically. `set_binding()` + `save()` for rebinding.
- **User preferences** (`hf_user_prefs.gd`): application-scoped preferences that persist across
  sessions via `user://hammerforge_prefs.json`. Stores: default grid snap, autosave interval,
  recent files (max 10, deduplicated, MRU order), collapsed section states, last tool ID, HUD
  visibility. Separate from per-level settings in `hf_state_system.gd`. Loaded in plugin
  `_enter_tree()` and passed to dock.
- **Gesture poll system**: `can_activate()` and `get_poll_fail_reason()` on `HFEditorTool`;
  `can_start()` on `HFGesture`. Dock disables selection-dependent buttons (Hollow, Clip, Floor,
  Ceiling) when nothing is selected. Plugin guards keyboard shortcuts with early-exit when
  `hf_selection` is empty.
- **Tag-based reconciler invalidation**: `tag_brush_dirty()`, `tag_paint_dirty()`,
  `tag_full_reconcile()`, and `consume_dirty_tags()` on LevelRoot. Brush system tags dirty on
  create/delete/transform; tags full reconcile on structural operations (hollow, clip). Enables
  future selective reconciliation (skip unchanged geometry).
- **Batched signal emission**: `begin_signal_batch()` / `end_signal_batch()` on LevelRoot with
  depth-counted nesting. During a batch, signals are queued; on flush, brush add/remove/change
  signals are coalesced into a single `selection_changed` emission. Wired into state system
  transactions. `discard_signal_batch()` on rollback.
- **Declarative tool settings**: `HFEditorTool` now exposes `get_settings_schema()` returning an
  array of property descriptors (name, type, label, default, min, max, options). Dock
  `rebuild_tool_settings()` auto-generates CheckBox/SpinBox/LineEdit/OptionButton/ColorPickerButton
  from the schema. `get_setting()` / `set_setting()` with defaults from schema.
- **Status bar mode indicator**: dock status label now shows the active tool mode (Draw, Select,
  Extrude ▲/▼, Paint) with [dragging]/[extruding] suffix during active gestures. Updated on
  every HUD context refresh.
- **Input pass-through reorder**: external tool `dispatch_keyboard()` now runs before built-in
  keyboard shortcuts in `_handle_keyboard_input()`, allowing external tools to override keys.
- **GUT tests** for new systems: `test_keymap.gd` (16), `test_user_prefs.gd` (9),
  `test_dirty_tags.gd` (11) = 36 new tests. Total: 344 tests across 22 files.
- **Command collation** for undo/redo: consecutive similar operations (nudge, resize, paint)
  within a 1-second window are merged into a single undo entry. Prevents undo flooding during
  rapid drag/nudge sequences. Collation tags: `nudge`, `resize_brush`, `paint_brush`.
- **Transaction support** in `HFStateSystem`: `begin_transaction()` / `commit_transaction()` /
  `rollback_transaction()` for atomic multi-step operations (hollow, clip). Captures state
  snapshot on begin; restores on rollback.
- **Autosave failure notification**: threaded write errors now propagate to the UI via
  `autosave_failed` signal on LevelRoot. Dock shows a red warning label when autosave fails.
  Warning auto-hides after 30 seconds and reappears on subsequent failures.
- **Central signal registry** on LevelRoot: `brush_added`, `brush_removed`, `brush_changed`,
  `entity_added`, `entity_removed`, `selection_changed`, `paint_layer_changed`,
  `material_list_changed`, `face_selection_changed`, `state_saved`, `state_loaded`,
  `autosave_failed`. Subsystems emit these signals; UI subscribes instead of polling.
- **Material manager persistence**: `save_library()` / `load_library()` for JSON-based material
  palette save/load. Usage tracking via `record_usage()` / `release_usage()` /
  `find_unused_materials()`.
- **Entity definition system** (`hf_entity_def.gd`): data-driven `HFEntityDef` class with
  `classname`, `description`, `color`, `is_brush_entity`, `properties`, `scene_path`. Loads
  definitions from JSON (entities.json), falls back to built-in defaults. Brush entity class
  dropdown in dock populated from definitions instead of hardcoded strings.
- **Gesture tracker base class** (`hf_gesture.gd`): `HFGesture` base for encapsulated input
  gestures. Holds root, camera, positions, numeric buffer. Subclasses override `update()`,
  `commit()`, `cancel()`. Ready for incremental adoption by new tools.
- **Declarative entity property forms**: when an entity is selected, the dock auto-generates
  typed controls (LineEdit, SpinBox, CheckBox, OptionButton, ColorPickerButton, Vector3) from
  the entity definition's `properties` array. Changes write to `entity.entity_data` and sync
  with Godot's Inspector. Built-in trigger defs now include `filter_class`, `start_disabled`,
  `wait_time` properties. Inspired by QuArK's `:form` system.
- **Duplicator / instanced geometry** (`hf_duplicator.gd`): create N copies of selected
  brushes with progressive offset. `HFDuplicator` RefCounted class with `generate()`,
  `clear_instances()`, `to_dict()`/`from_dict()` serialization. Dock UI: count SpinBox,
  X/Y/Z offset, Create/Remove Array buttons in Selection Tools section (Brush tab). Undo/redo
  via state snapshot. Inspired by QuArK's duplicator system.
- **Multi-format .map export adapters**: strategy-pattern writers for map export.
  - `HFMapAdapter` base class with `format_face_line()` and `format_entity_properties()`.
  - `HFMapQuake`: Classic Quake format (existing behavior, extracted).
  - `HFMapValve220`: Valve 220 format with UV texture axes from FaceData.
  - Format selector OptionButton in dock File section.
  - Entity properties now included in .map export.
- **Formalized plugin API** (`hf_editor_tool.gd` + `hf_tool_registry.gd`): base class and
  registry for custom editor tools. External tools (ID >= 100) loaded from
  `res://addons/hammerforge/tools/` at startup. Non-breaking Phase 1: built-in tools remain
  as-is; registry dispatches to external tools only.
- **Clipping tool:** Split a brush along an axis-aligned plane into two pieces.
  - `clip_brush_by_id(brush_id, axis, split_pos)` on `hf_brush_system.gd`.
  - Auto-detect split axis from face normal via `clip_brush_at_point()`.
  - Snaps split position to grid. Copies material, brush entity class, visgroups, and group ID.
  - Keyboard shortcut: Shift+X. Clip button in Selection Tools section of Brush tab.
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
  - Wall thickness SpinBox in Selection Tools section of Brush tab.
  - Full undo/redo support via state snapshot.
- **Numeric input during drag:** Type exact dimensions while drawing or extruding brushes.
  - During base drag or height adjustment, type digits to set precise size.
  - Enter applies the value and advances/commits. Backspace edits. Escape cancels.
  - Numeric buffer displayed in the shortcut HUD during drag.
- **Brush entity conversion (Tie to Entity):** Tag brushes as brush entity classes.
  - Tie/Untie buttons in Selection Tools section (Brush tab) with class dropdown (func_detail, func_wall, trigger_once, trigger_multiple).
  - `func_detail` brushes are excluded from structural CSG bake (detail geometry).
  - `trigger_*` brushes are excluded from structural bake (collision-only volumes).
  - `brush_entity_class` meta persists in `.hflevel` saves and undo/redo state.
- **Move to Floor / Move to Ceiling:** Snap selected brushes to the nearest surface.
  - Raycasts against other brushes and physics bodies to find nearest surface.
  - Grid-snapped result. Keyboard shortcuts: Ctrl+Shift+F (floor), Ctrl+Shift+C (ceiling).
  - Buttons in Selection Tools section of Brush tab. Full undo/redo support.
- **Texture alignment Justify panel:** Quick UV alignment controls in the UV Editor section.
  - Fit, Center, Left, Right, Top, Bottom alignment modes.
  - "Treat as One" checkbox for aligning multiple selected faces as a unified surface.
  - Works with the existing face selection system.
- **Hammer gap analysis** documented in ROADMAP.md with prioritized wave plan.
- **Dock UX overhaul:** Consolidated from 8 tabs to 4 (Brush, Paint, Entities, Manage).
  - `HFCollapsibleSection` (`ui/collapsible_section.gd`) with HSeparator, indented content, persisted collapsed state.
  - **Brush tab** (was Build): shape, size, grid snap, material, operation mode, texture lock, plus contextual **Selection Tools** section (hollow, clip, move, tie, duplicator — visible when brushes selected).
  - **Paint tab** (merged FloorPaint + SurfacePaint + Materials + UV): 7 collapsible sections. UV Justify uses 3×2 grid layout.
  - **Manage tab**: Bake, Actions (floor/cuts/clear), File, Presets, History, Settings, Performance, plus Visgroups & Cordon.
  - "No LevelRoot" banner and autosave warning defined in dock.tscn.
  - Compact toolbar: single-char labels (D, S, +, -, P, ▲, ▼) with tooltips. VSeparator before extrude buttons.
  - Paint/material sync is signal-driven (instant). Form label widths standardized to 70px. +/- buttons 32px wide.
  - Tab contents built programmatically via `_build_paint_tab()`, `_build_manage_tab()`, `_build_selection_tools_section()`.
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
- **GUT unit test suite** with 344 tests across 22 test files:
  - `test_visgroup_system.gd` (18 tests): CRUD, visibility, membership, serialization.
  - `test_grouping.gd` (9 tests): group creation, meta, ungroup, regroup, serialization.
  - `test_texture_lock.gd` (10 tests): UV compensation for all projection types.
  - `test_cordon_filter.gd` (10 tests): AABB filtering, chunk collection, chunk_coord utility.
  - `test_entity_props.gd` (12 tests): entity property form defaults, roundtrip capture/restore.
  - `test_duplicator.gd` (7 tests): instance count, offset, clear, serialization, edge cases.
  - `test_map_export.gd` (19 tests): Quake/Valve220 face formats, auto-axes, projections.
  - `test_tool_registry.gd` (25 tests): registration, activation lifecycle, dispatch, deactivation.
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
- Dock consolidated from 8 tabs to 4 (Brush, Paint, Entities, Manage). Selection-dependent tools (hollow, clip, move, tie, duplicator) moved from Manage → Brush tab's contextual Selection Tools section.
- Build tab renamed to **Brush** tab; bake options and editor toggles moved to Manage tab.
- FloorPaint, SurfacePaint, Materials, and UV tabs merged into single **Paint** tab with collapsible sections.
- Manage tab trimmed: Actions section now contains only floor/cuts/clear. Toolbar uses single-char labels with tooltips.
- Paint layer/material/surface paint sync changed from 10-frame polling to signal-driven instant updates.
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
- Fixed undo collation never merging: `create_action()` was passing `can_collate` as
  `backward_undo_ops` (4th positional arg) instead of setting `merge_mode` to `MERGE_ENDS` (1).
  Undo history was flooding with one entry per nudge/resize/paint stroke. Now uses
  `merge_mode = 1` when collating and `false` for `backward_undo_ops`.
- Fixed undo collation merging across mismatched `full_state` scopes: added `full_state`
  equality check to collation eligibility. A `full_state=true` action no longer merges with
  a prior `full_state=false` run (or vice versa), preventing undo from restoring the wrong
  state scope.
- Fixed autosave warning timer crash: the timer closure assigned `null` to
  `_autosave_warning.visible` (a `bool`) when the dock was freed before the timer fired.
  Now guards with `is_instance_valid()` and skips the assignment entirely if the label is gone.
- Fixed material library `load_library()` silently remapping palette indices: empty or
  missing material entries were skipped with `continue`, compacting the array. Any data
  referencing materials by index (paint layers, brush face data) could point to the wrong
  material after reload. Now preserves `null` placeholder slots to keep indices stable.
- Fixed brush entity class dropdown becoming empty when `entities.json` contains only point
  entities: `_populate_brush_entity_classes()` now falls back to built-in defaults
  (func_detail, func_wall, trigger_once, trigger_multiple) when filtered brush defs are empty.
- Fixed `_on_tie_entity()` crash when dropdown has no items: now guards `item_count > 0` and
  `selected >= 0` before reading dropdown text, falling back to `"func_detail"`.
- Fixed duplicate arrays becoming non-removable after undo/redo or state restore:
  `restore_state()` now reapplies `duplicator_id` metadata on source brushes after rebuilding
  `_duplicators` from serialized data.
- Fixed creating a duplicate array on already-linked source brushes orphaning older groups:
  `create_duplicate_array()` now cleans up any existing duplicator that owns the same sources
  before creating the new one.
- Fixed external tools having no deactivation path when switching back to built-in tools:
  `activate_tool()` now nulls `_active_tool` after deactivating. Built-in tool selection
  (U/J keyboard shortcuts, dock toolbar button clicks) deactivates the active external tool
  via targeted `_deactivate_external_tool()` calls instead of per-frame checks.
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
- Dock UX: rewrote `dock.gd` to build Paint, Manage, and Selection Tools contents programmatically using `HFCollapsibleSection`.
- Dock UX: ~100 `@onready var` declarations changed to plain `var` (controls created in code, not in .tscn).
- Dock UX: `dock.tscn` reduced to ~320 lines (tab shells + toolbar + autosave warning; content populated by `_ready()`).
- Dock UX: collapsible sections now have HSeparator + indented content + persisted state. All 18 sections registered in `_all_sections` dict.
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
  - Signal-driven sync in `dock.gd`: replaced 17 per-frame property writes with signal handlers; paint/material/surface paint sync now fully signal-driven via LevelRoot signals; throttled perf updates (every 30 frames), flag-driven disabled hints; cached `_control_has_property()`.
  - Input decomposition in `plugin.gd`: split 260-line `_forward_3d_gui_input()` into ~50-line dispatcher + 7 focused handlers + shared `_get_nudge_direction()`.

### UX
- Dock now has 4 tabs (Brush, Paint, Entities, Manage) instead of 8 for faster navigation.
- Selection tools (hollow, clip, move, tie, duplicator) appear contextually in Brush tab when brushes are selected.
- Collapsible sections with separators, indented content, and persisted collapsed state across sessions.
- "No LevelRoot" banner at dock top guides users when no LevelRoot is found.
- Compact toolbar with single-char labels (D, S, +, -, P, ▲, ▼) and descriptive tooltips.
- Paint layer and material changes sync instantly (signal-driven, no 167ms polling delay).
- Wider +/- buttons (32px), standardized label widths (70px), UV Justify in clean 3×2 grid.
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
- Added TrenchBroom + QuArK architecture learnings document (`project_editor_learnings.md`).
- Updated ROADMAP with QuArK-inspired items: declarative entity property forms, multi-format `.map`
  export adapters, duplicator/instanced geometry, formalized plugin API, bezier patches.
- Updated SPEC entity definitions section with planned declarative property forms.
- Updated data portability doc with planned multi-format `.map` export strategy.
- Updated CONTRIBUTING, DEVELOPMENT, SPEC, MVP guide, user guide, texture/materials doc, and
  README with command collation, transactions, signals, entity defs, gestures, material persistence,
  autosave failure, and all code review bugfixes.
- Updated DEVELOPMENT test table with actual test counts: entity_props (12), duplicator (10),
  map_export (19), tool_registry (25). Total: 308 tests across 19 files.

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
