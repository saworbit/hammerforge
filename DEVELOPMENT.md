# Development Guide

Last updated: April 13, 2026

This document covers local setup, codebase structure, and how to test features.

## Requirements
- Godot Engine 4.6 (stable).
- A 3D scene to host `LevelRoot`.

## Local Setup
1. Open the project in Godot.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open any 3D scene and click in the viewport to auto-create `LevelRoot`.

## Codebase Structure

```
addons/hammerforge/
  plugin.gd              EditorPlugin entry point, input routing, sticky LevelRoot discovery
  level_root.gd          Thin coordinator (~1,100 lines), delegates to subsystems
  input_state.gd         Drag/paint state machine (HFInputState)
  dock.gd + dock.tscn    UI dock (4 tabs: Brush, Paint, Entities, Manage), collapsible sections with persisted state
  shortcut_hud.gd        Context-sensitive shortcut overlay (dynamic per mode) + persistent grid size indicator with flash-on-change
  brush_instance.gd      DraftBrush node
  baker.gd               CSG -> mesh bake pipeline (per-face materials, atlas integration, snapshot-based non-blocking face bakes, convex collision shapes)
  hf_material_atlas.gd   HFMaterialAtlas: texture atlas packing for draw-call reduction
  face_data.gd           Per-face materials, UVs, paint layers, displacement
  displacement_data.gd   HFDisplacementData resource (subdivided grid, distances/offsets/alphas, sew groups)
  material_manager.gd    Shared materials palette (+ library persistence, usage tracking)
  hf_prototype_textures.gd  HFPrototypeTextures: 150 built-in SVG textures (15 patterns x 10 colors)
  face_selector.gd       Raycast face selection
  hf_extrude_tool.gd     Extrude Up/Down tool (face click + drag to extend brushes)
  hf_gesture.gd          Gesture tracker base class (update/commit/cancel pattern)
  hf_entity_def.gd       Data-driven entity definition system (JSON + built-in defaults)
  hf_duplicator.gd       Duplicator / instanced geometry (source brushes + progressive offset)
  hf_editor_tool.gd      Plugin API: base class for custom editor tools (+ poll, declarative settings)
  hf_tool_registry.gd    Plugin API: tool registration, dispatch, external tool loader
  hf_measure_tool.gd     Multi-ruler measurement tool (persistent rulers, angles, snap reference)
  hf_decal_tool.gd       Decal placement tool (raycast + surface-normal aligned Decal nodes)
  hf_polygon_tool.gd     Polygon tool (click convex verts → extrude to brush, tool_id=102)
  hf_path_tool.gd        Path tool (waypoints → corridor brushes with miter joints, stairs, railings, trim, tool_id=103)
  hf_keymap.gd           Customizable keyboard shortcuts (JSON load/save, action matching, 5 categories: Tools/Editing/Selection/Paint/Axis Lock)
  hf_user_prefs.gd       Cross-session user preferences (user://hammerforge_prefs.json)
  hf_snap_system.gd      Centralized snap (Grid/Vertex/Center modes + custom snap lines, threshold-based candidates)
  hf_prefab.gd           Reusable brush+entity groups (variants, tags, save/load .hfprefab)
  hf_op_result.gd        Lightweight operation result (ok, message, fix_hint)
  undo_helper.gd         HFUndoHelper: state-capture undo with collation (merges rapid edits into one step)
  surface_paint.gd       Per-face surface paint tool
  uv_editor.gd           UV editing dock
  highlight.gdshader     Selection highlight shader (wireframe, unshaded, alpha)
  hflevel_io.gd          Variant encoding/decoding for .hflevel
  map_io.gd              .map import/export (uses adapter pattern for multi-format support)
  prefab_factory.gd      Advanced shape generation

  data/
    example_levels.json    Built-in demo level definitions (5 levels with annotations)

  textures/prototypes/   150 SVG prototype textures ({pattern}_{color}.svg)

  map_adapters/          .map export format adapters (strategy pattern)
    hf_map_adapter.gd      Base adapter class (format_name, format_face_line, format_entity_properties)
    hf_map_quake.gd        Classic Quake format adapter
    hf_map_valve220.gd     Valve 220 format adapter (with UV texture axes)

  ui/                    Reusable UI components
    collapsible_section.gd HFCollapsibleSection: toggle-header VBoxContainer for dock sections
    hf_toast.gd            Toast notification system (auto-fading stacked messages)
    hf_welcome_panel.gd    First-run welcome panel (legacy, replaced by tutorial wizard)
    hf_tutorial_wizard.gd  Interactive 5-step tutorial wizard (signal-driven auto-advance)
    hf_shortcut_dialog.gd  Searchable shortcut reference dialog (filterable Tree with categories)
    hf_material_browser.gd Visual material browser (thumbnail grid, search, filters, favorites, drag-drop)
    hf_prefab_library.gd   Prefab library dock section (search, tags, variants, drag-drop, context menu)
    hf_prefab_overlay.gd   Prefab ghost overlay (wireframe bounding box + override markers)
    hf_context_toolbar.gd  Floating contextual mini-toolbar (context-sensitive actions, group labels per tool cluster)
    selection_tools_builder.gd  Builds Selection Tools section with domain sub-headers (Brush Modification, Positioning, Entity Binding, Duplicate Array)
    hf_hotkey_palette.gd   Searchable command palette with fuzzy search and live gray-out (Shift+?/F1/Ctrl+K)
    hf_viewport_context_menu.gd  Context menu (Space key) with context-sensitive sections and submenus
    hf_radial_menu.gd      Radial/pie menu (backtick key) with 8 tool sectors drawn via _draw()
    hf_quick_property.gd   Double-tap popup (G G/B B/R R) for grid snap, brush size, paint radius
    hf_theme_utils.gd      Static dark/light theme detection and color helpers for custom UI
    hf_history_browser.gd  Undo history browser with thumbnails, icons, and double-click navigation
    hf_coach_marks.gd      First-use tool guides (10 tools, per-tool dismissal, auto-trigger on activation)
    hf_operation_replay.gd Operation timeline with undo/redo replay (Ctrl+Shift+T toggle)
    hf_example_library.gd  Example level browser (5 built-in demos, search, annotations, one-click load)
    hf_selection_filter.gd Selection filter popover (by normal/material/similar/visgroup/type)
    paint_tab_builder.gd   Builds Paint tab sections + signal connections
    entity_tab_builder.gd  Builds Entity Properties + Entity I/O + I/O Wiring sections (all context-hidden until entity selected)
    hf_io_wiring_panel.gd  I/O wiring panel (quick wire, presets, highlight toggle, connection summary)
    manage_tab_builder.gd  Builds Manage tab sections (Bake, File, Settings, etc.)
    selection_tools_builder.gd  Builds Selection Tools section (hollow, clip, move, tie, duplicator)

  systems/               Subsystem classes (RefCounted)
    hf_grid_system.gd      Editor grid management
    hf_entity_system.gd    Entity definitions, placement, Entity I/O connections
    hf_brush_system.gd     Brush CRUD, cuts, materials, picking, hollow, clip, merge, tie/untie
    hf_drag_system.gd      Drag lifecycle, preview, axis locking
    hf_bake_system.gd      Bake orchestration (single/chunked/selected/dirty), cooperative face-bake yielding, preview modes (Full/Wireframe/Proxy), time estimate (yield-overhead-corrected), auto-connectors, collision mode partitioning (trimesh/convex/visgroup), automated occluder generation (coplanar grouping → OccluderInstance3D)
    hf_paint_system.gd     Floor + surface paint, layer CRUD
    hf_state_system.gd     State capture/restore, settings, transactions
    hf_file_system.gd      .hflevel/.map/.glTF I/O, threaded writes, autosave failure reporting
    hf_validation_system.gd Validation, dependency checks, bake issue detection (degenerate/floating/overlapping/non-planar/micro-gap/occlusion-coverage), vertex welding + planarity auto-fix
    hf_visgroup_system.gd  Visgroups (visibility groups) + brush/entity grouping
    hf_carve_system.gd     Boolean-subtract carve (progressive-remainder box slicing)
    hf_io_visualizer.gd    Entity I/O connection lines (Bézier curves, color-coded, highlight pulse)
    hf_io_presets.gd       Reusable I/O connection presets (built-in + user-saved, target tag mapping)

  hf_io_runtime.gd        Runtime I/O-to-Signal dispatcher (auto-wires entity_io_outputs to Godot signals on bake/export)
    hf_subtract_preview.gd Wireframe AABB intersection overlay for subtract brushes (debounced, pooled)
    hf_carve_preview.gd    Green wireframe preview of carve slice pieces (confirmation before commit)
    hf_clip_preview.gd     Cyan wireframe + orange plane preview of clip halves (confirmation before commit)
    hf_hollow_preview.gd   Yellow wireframe preview of hollow wall pieces (confirmation before commit)
    hf_vertex_system.gd    Vertex/edge selection, move, split, merge with convexity validation
    hf_spawn_system.gd     Player spawn lookup, validation, auto-fix, debug visualisation
    hf_prefab_system.gd    Prefab instance registry, variant cycling, live-linked propagation, overrides
    hf_displacement_system.gd  Displacement surface create/destroy/paint/sew/elevation/power
    hf_bevel_system.gd     Edge bevel (chamfer) and face inset

  paint/                 Floor paint subsystem
    hf_paint_grid.gd       Grid storage
    hf_paint_layer.gd      Layer data (bitset + material_ids + blend_weights + heightmap)
    hf_paint_layer_manager.gd  Layer management
    hf_paint_tool.gd       Paint tool input handling (routes to heightmap synth when layer has heightmap)
    hf_inference_engine.gd Inference for paint operations
    hf_geometry_synth.gd   Greedy meshing for flat floors/walls
    hf_heightmap_synth.gd  Heightmap-displaced mesh generation (SurfaceTool, per-vertex displacement)
    hf_heightmap_io.gd     Heightmap load/generate/serialize (base64 PNG, FastNoiseLite)
    hf_reconciler.gd       Stable-ID reconciliation (floors, walls, heightmap floors)
    hf_generated_model.gd  Data model (FloorRect, WallSeg, HeightmapFloor)
    hf_stroke.gd           Stroke types (brush/erase/rect/line/bucket/blend/sculpt_raise/lower/smooth/flatten)
    hf_connector_tool.gd   Ramp/stair mesh generation between layers (manual connector defs)
    hf_auto_connector.gd   Auto-detect height boundaries + generate connectors during bake
    hf_foliage_populator.gd MultiMeshInstance3D procedural scatter (height/slope filtering)
    hf_brush_to_heightmap.gd Convert selected brushes to heightmap paint layer (rasterize top faces)
    hf_scatter_brush.gd    Interactive scatter/foliage brush (circle/spline, density preview, commit)
    hf_blend.gdshader      Two-material blend shader (UV2 blend map, default colors, cell grid overlay)
```

### Architecture Conventions

- **Subsystems are RefCounted.** Each receives a `LevelRoot` reference in `_init()` and accesses container nodes and properties through `root.*`.
- **No circular preloads.** Subsystem files must not `preload("../level_root.gd")`. Use raw ints for default parameters and `root.EnumName.*` at runtime.
- **LevelRoot is the public API.** Its methods are thin one-line delegates to subsystems. External callers (`plugin.gd`, `dock.gd`) always go through `LevelRoot`.
- **Input state machine.** `HFDragSystem` owns the `HFInputState` instance. Drag state transitions are explicit (`begin_drag` -> `advance_to_height` -> `end_drag`). Extrude uses `begin_extrude` -> `end_extrude`. Modes are classified as *transient* (DRAG_BASE, DRAG_HEIGHT, EXTRUDE, SURFACE_PAINT — own temporary preview nodes) or *persistent* (VERTEX_EDIT — user-toggled, survives undo/redo). `HFInputState.is_transient_preview_mode()` encodes this distinction; plugin.gd's `version_changed` handler uses it to force-reset only transient modes.
- **Direct typed calls.** `plugin.gd` and `dock.gd` use typed references (`LevelRoot`, `DockType`) with direct method calls instead of `has_method`/`call`.
- **Wireframe color convention.** Brushes use operation-coded wireframe overlays: green for additive, red for subtractive, blue spectrum for brush entities. `_apply_additive_wireframe_overlay()` and `_apply_subtract_wireframe_overlay()` in `brush_instance.gd` must be called after any `mesh_instance.mesh` replacement (including face-preview rebuilds) to keep overlays in sync with geometry.
- **Grid snap HUD sync.** `dock.gd` emits `grid_snap_applied(value)` from both `_apply_grid_snap()` and `_on_root_grid_snap_changed()`. `plugin.gd` connects this to `_on_dock_grid_snap_applied()` which updates the HUD indicator. All grid change origins (dock UI, hotkeys, quick-property, state restore) flow through this path.
- **Sticky LevelRoot discovery.** `plugin.gd` keeps `active_root` sticky: `_edit()` does not null it when non-LevelRoot nodes are selected. `_handles()` returns true for any node when a LevelRoot exists (deep recursive search). `dock.gd` mirrors this pattern.
- **Sticky brush selection.** `plugin.gd` suppresses spurious empty `selection_changed` signals (e.g. from texture reimport) via `should_suppress_empty_selection()`. When the editor selection goes empty but `hf_selection` is still populated, the event is ignored. Intentional deselects must clear `hf_selection` *before* calling `editor_selection.clear()`. Dock paths that clear editor selection emit `selection_clear_requested` first so the plugin can clear its cache.
- **Material assignment fallback.** `dock.resolve_material_assign_action(mat_index)` is a pure helper returning `{action, method, args, toast}`. Both `_on_material_assign()` and `_on_browser_material_double_clicked()` delegate to it. When faces are selected → face assignment. When no faces but brushes are selected → whole-brush fallback. When nothing is selected → error toast. Context menu options (Apply to Faces, Apply to Whole Brush) remain explicit and do not use the fallback.
- **Collapsible sections.** Use `HFCollapsibleSection.create("Name", start_expanded)` from `ui/collapsible_section.gd` for dock sections. Each section has an HSeparator, indented content, and persisted collapsed state via user prefs. Tab contents are built programmatically in `_build_paint_tab()`, `_build_manage_tab()`, `_build_selection_tools_section()`, and `_build_entity_io_section()`. All 18 sections tracked in `_all_sections: Dictionary`.
- **Signal-driven dock sync.** Setting controls push values to LevelRoot via `toggled`/`value_changed` signal connections. Paint layers, materials, and surface paint sync instantly via `paint_layer_changed`, `material_list_changed`, and `selection_changed` signals. Perf panel updates every 30 frames; disabled hints are flag-driven. Form label widths standardized to 70px.
- **Input decomposition.** `_forward_3d_gui_input()` in `plugin.gd` is a ~50-line dispatcher that routes to focused handlers: `_handle_paint_input()`, `_handle_keyboard_input()`, `_handle_rmb_cancel()`, `_handle_select_mouse()`, `_handle_extrude_mouse()`, `_handle_draw_mouse()`, `_handle_mouse_motion()`. Shared `_get_nudge_direction()` is used by both `_forward_3d_gui_input()` and `_shortcut_input()`.
- **Brush/material caching.** `hf_brush_system.gd` uses `_brush_cache: Dictionary` for O(1) brush ID lookup, `_brush_count: int` for O(1) count, and `_material_cache: Dictionary` for material instance reuse. All CRUD methods maintain these caches.
- **Undo/redo dynamic dispatch.** The `_commit_state_action` pattern in `dock.gd` intentionally uses string method names for undo/redo -- this is the one exception to the typed-calls rule.
- **Undo/redo helper.** Use `HFUndoHelper` for editor actions to ensure consistent history and state snapshot restores. Pass a `collation_tag` for operations that fire rapidly (nudge, resize, paint) — consecutive actions with the same tag within 1 second are merged into one undo entry. Collation also requires matching `full_state` scope — a `full_state=true` action will not merge with a prior `full_state=false` run.
- **Undo/redo history binding.** HammerForge actions go into the **scene history** (not global) because `create_action()` passes `null` context and the first do/undo object is a Node (LevelRoot). Dock history UI (`_update_history_buttons`, `_on_history_undo/redo`) resolves the correct history via `_get_scene_history_id()` → `undo_redo.get_object_history_id(level_root)`. Never hard-code `EditorUndoRedoManager.GLOBAL_HISTORY` — use `_get_scene_undo_redo()` to get the `UndoRedo` object for the active scene.
- **Transactions.** For multi-step operations (hollow, clip, tie), use `state_system.begin_transaction()` / `commit_transaction()` / `rollback_transaction()` to group mutations atomically. If any step fails, `rollback_transaction()` restores the snapshot.
- **Entity definitions.** Entity types and brush entity classes are data-driven via `HFEntityDef`. Load from `entities.json` or use built-in defaults. New entity types should be added to the JSON file, not hardcoded.
- **Gesture trackers.** New tools should subclass `HFGesture` (hf_gesture.gd) to encapsulate input state. Override `update()`, `commit()`, `cancel()`. The gesture holds its own state (start position, axis lock, numeric buffer), making the tool self-contained.
- **Central signals.** Subscribe to LevelRoot signals (`brush_added`, `brush_removed`, `selection_changed`, `paint_layer_changed`, `material_list_changed`, `face_selection_changed`, `state_saved`, etc.) instead of polling. Subsystems emit these via `root.<signal>.emit(...)`. `face_selection_changed` emits only when selection actually changes (snapshot comparison in `select_face_at_screen`).
- **Autosave failure.** The `autosave_failed(error_message)` signal on LevelRoot fires when a threaded write fails. Connect to it in the dock to show user-facing warnings.
- **Toast notifications.** Use `dock.show_toast(message, level)` (0=INFO, 1=WARNING, 2=ERROR) for user-facing messages. Subsystems can also emit `root.user_message.emit(text, level)` which the dock auto-routes to the toast system.
- **Mode indicator.** Call `dock.set_mode_indicator(mode_name, stage_hint, numeric)` from `plugin.gd` to update the colored mode banner. `stage_hint` shows gesture progress (e.g. "Step 1/2: Draw base"), `numeric` shows typed input.
- **Tutorial wizard.** The interactive tutorial (`ui/hf_tutorial_wizard.gd`) replaces the static welcome panel when `show_welcome` is true. 5 steps, each listening for a LevelRoot signal (brush_added, paint_layer_changed, entity_added, bake_finished). Progress persists via `tutorial_step` in user prefs. Dock `highlight_tab()` flashes the relevant tab on each step.
- **Dynamic contextual hints.** `shortcut_hud.gd` shows per-mode viewport hints (e.g. "Click to place corner → drag to set size → release for height"). Hints auto-dismiss after 4s fade tween and persist dismissal via `is_hint_dismissed()`/`dismiss_hint()` on `hf_user_prefs.gd`. Mode key is computed from HUD context dict.
- **Searchable shortcut dialog.** `ui/hf_shortcut_dialog.gd` extends `AcceptDialog` with a search `LineEdit` and `Tree`. Categories populated from `HFKeymap.get_category()`. Replaces the static shortcuts popup.
- **Subtract preview.** `systems/hf_subtract_preview.gd` is a `RefCounted` subsystem that renders wireframe AABB intersections between additive and subtractive brushes using `ImmediateMesh` (same 12-edge box pattern as cordon). Debounced (0.15s), pooled `MeshInstance3D` (max 50). Toggle via `show_subtract_preview` on LevelRoot. Persisted in state settings. Call `destroy()` (not `clear()`) when the subsystem is no longer needed — `destroy()` immediately frees all pool nodes and the container; `clear()` only hides them.
- **Undo/redo preview cleanup.** `plugin.gd` connects to `EditorUndoRedoManager.version_changed` and calls `HFInputState._force_reset()` for transient preview modes (drag, extrude, surface paint). This cascades through `_on_input_state_force_reset` to free preview nodes. VERTEX_EDIT is excluded because `commit_action()` fires `version_changed` after every vertex operation — resetting it would desync `_vertex_mode` from `input_state.mode`. `level_root.gd _exit_tree()` also calls `subtract_preview.destroy()`, `extrude_tool.cancel_extrude()`, and `drag_system._clear_preview()` to ensure preview nodes don't outlive the tree.
- **Prefabs.** `hf_prefab.gd` (`HFPrefab`) stores brush_infos + entity_infos with centroid-relative transforms. `capture_from_selection()` computes centroid and strips brush_id/group_id. `instantiate()` assigns new IDs, offsets transforms, remaps entity I/O via name_map, and returns `entity_nodes` (Node3D refs) alongside `entity_names` for stable registration. `save_to_file()`/`load_from_file()` use JSON via `HFLevelIO` encoding. `ui/hf_prefab_library.gd` provides the dock section with ItemList and drag-and-drop (`"hammerforge_prefab"` type tag). Plugin handles drop with raycast + snap + undo/redo. `HFPrefabSystem` tracks entity membership via stable UIDs (`hf_prefab_entity_id` meta) — never scene node names. Context toolbar prefab buttons (Var▶/Push/Pull) are built at init time and toggled visible in `_apply_context()`.
- **Vertex system.** `HFVertexSystem` (`systems/hf_vertex_system.gd`) manages vertex/edge selection, movement with convexity validation, edge splitting, and vertex merging. Supports two sub-modes via the `sub_mode` property: `VertexSubMode.VERTEX` (0) and `VertexSubMode.EDGE` (1), toggled with E key. **Note:** `sub_mode` is a public property, not a setter — assign directly (`vs.sub_mode = 1`). `merge_vertices(brush_id, indices)` and `split_edge(brush_id, edge)` require explicit brush_id and selection data; `plugin.gd` provides `_vertex_merge_selected()` and `_vertex_split_selected_edge()` wrappers that resolve current selection before calling. Edge selection syncs to `selected_vertices` so `move_vertices()` works transparently for both modes. `split_edge()` inserts midpoints and skips convexity validation (mathematically guaranteed on convex hulls). `merge_vertices()` validates convexity and reverts via face snapshots on failure. Edge deduplication uses canonical vertex key pairs (`"vkey_a|vkey_b"` where a < b).
- **Polygon tool.** `HFPolygonTool` (`hf_polygon_tool.gd`, tool_id=102, KEY_P) creates arbitrary convex polygon brushes via a three-phase state machine (IDLE → PLACING_VERTS → SETTING_HEIGHT). Enforces convexity via 2D cross product on XZ plane. Constructs face data with CW winding from outside (top, bottom, N side quads) in local space relative to AABB center. Uses `create_brush_from_info()` with undo/redo via `self.undo_redo`.
- **Path tool.** `HFPathTool` (`hf_path_tool.gd`, tool_id=103, KEY_SEMICOLON) creates corridor brushes from waypoints. Each segment is an oriented-box brush (8 corners from direction + perpendicular, CW-wound faces). Miter joint brushes fill gaps at interior waypoints. All brushes share a `group_id`. Single undo action for the entire path. `path_extra` setting (None/Stairs/Railing/Trim) auto-generates additional geometry after base segments: step brushes along sloped segments, top rails + posts on both sides, or edge trim strips with material auto-assign.
- **Convert to heightmap.** `HFBrushToHeightmap` (`paint/hf_brush_to_heightmap.gd`) rasterizes brush top faces onto a grid, creating a heightmap paint layer. Dock handler `_on_heightmap_convert()` inherits `base_grid` (origin/basis) and `chunk_size` from the paint layer manager, emits `paint_layer_changed`, and calls `regenerate_paint_layers()`. Uses `level_root.grid_snap` as cell size when > 0.
- **Scatter brush.** `HFScatterBrush` (`paint/hf_scatter_brush.gd`) generates scatter transforms for circle or spline shapes with height/slope filtering. `build_preview()` creates a MultiMesh for preview. `commit()` creates a permanent `MultiMeshInstance3D`. Dock wires UI controls → `_build_scatter_settings()` → preview/commit. Spline mode populates control points from `_selection_nodes` positions.
- **I/O connection presets.** `systems/hf_io_presets.gd` manages built-in and user-saved connection presets. 6 built-in presets (Door+Light+Sound, Button→Toggle, etc.) are always available. User presets persist to `EditorInterface.get_editor_paths().get_config_dir()` in editor, `user://` fallback for tests. `apply_preset(source, preset, target_map)` maps target tags to actual entity names ("self" → source name). `save_entity_as_preset()` captures existing connections. Tests use explicit temp paths with cleanup in `after_each()`.
- **I/O wiring panel.** `ui/hf_io_wiring_panel.gd` is a `VBoxContainer` embedded in the Entities tab via `entity_tab_builder.gd`. Context-hidden (only visible when an entity is selected) and collapsed by default for progressive disclosure. Shows connection summary, outputs list, quick-wire form, and preset picker with target tag mapping. Emits `connection_added`, `preset_applied`, `highlight_toggled`. `_sync_highlight_button()` reads `_io_visualizer.highlight_connected` and uses `set_pressed_no_signal()` to avoid signal loops. Called from `set_source_entity()` and `dock.sync_wiring_highlight_state()`.
- **I/O runtime dispatcher.** `hf_io_runtime.gd` (`HFIORuntime`) translates entity I/O metadata into live Godot signals. Injected automatically by `export_playtest_scene()` and optionally by `postprocess_bake()` (when `bake_wire_io = true`). Connections are keyed by source node instance ID (not name) so duplicate source names stay isolated. Target delivery iterates all nodes sharing a name (matching `find_entities_by_name()` semantics). `wire()` is idempotent: `_disconnect_all_signals()` tears down stale lambdas; `_prune_overlapping_roots()` deduplicates scan roots by instance ID and removes descendants covered by an ancestor. `extra_scan_root_paths: Array[NodePath]` (@export) persists across scene save/reload for the bake path where the dispatcher lives under `baked_container` but entities are under a sibling node. `HFEntitySystem.fire_output()` delegates to the dispatcher via `fire_from()` when present, falls back to direct multi-target resolution otherwise.
- **Highlight Connected sync.** `hf_io_visualizer.highlight_connected` is the single source of truth. Context toolbar reads it from `state["highlight_connected"]` via `set_pressed_no_signal()`. Wiring panel syncs via `_sync_highlight_button()`. Plugin.gd handles `"highlight_connected"` action from toolbar, calls `root.set_highlight_connected()` then `dock.sync_wiring_highlight_state()`. Panel's `highlight_toggled` signal flows through dock to visualizer then toolbar state push.
- **Context hints.** Per-tab hint labels at the bottom of each dock tab update via `_update_context_hints()` in `dock.gd`. Driven by `_hints_dirty` flag alongside `_update_disabled_hints()`.
- **Face hover highlight.** `level_root.highlight_hovered_face(camera, mouse_pos, color)` performs a FaceSelector raycast and renders a semi-transparent overlay on the hit face. Used by `plugin.gd` in extrude mode when idle. Call `clear_face_hover_highlight()` when switching tools.
- **Undo/redo stability.** Prefer brush IDs and `create_brush_from_info()` for undo instead of storing Node references in history.
- **Displacement surfaces.** `HFDisplacementData` (`displacement_data.gd`) is a `Resource` storing a subdivided grid (power 2-4 → 5x5 to 17x17 vertices) with per-vertex distance offsets. `FaceData.displacement` is typed as `Resource` (not `HFDisplacementData`) to avoid circular preload. `HFDisplacementSystem` manages create/destroy/paint/sew. Paint input in `plugin.gd` uses plane intersection constrained by `_point_near_polygon_3d()` convex polygon bounds check and is gated behind `dock.is_paint_mode_enabled()` + Displacement section expanded. Continuous paint strokes capture pre-state on mouse-down and commit a single undo action on mouse-up via `_commit_disp_paint_undo()`. Dock callbacks use `_try_undoable_action()` which checks return values and only commits undo + records history on success.
- **Bevel system.** `HFBevelSystem` (`systems/hf_bevel_system.gd`) provides `bevel_edge()` (slerp arc between face pull-back directions, generates strip quads + corner cap fans + neighbor vertex updates) and `inset_face()` (centroid-based shrink with connecting side quads and collapse guard). Both are exposed via LevelRoot delegates that call `tag_brush_dirty()` on success. Dock callbacks use manual pre/post state capture for bevel_edge (batch of edges) and `_try_undoable_action()` for inset.
- **Face winding convention.** All faces use **clockwise (CW) vertex winding** as seen from outside the brush, matching Godot 4's `POLYGON_FRONT_FACE_CLOCKWISE` default. `_compute_normal()` uses `(c-a).cross(b-a)` which produces outward normals for CW faces. `triangulate()` preserves vertex order, so CW faces produce front-facing triangles. When creating new face generators, ensure vertices are CW from outside and call `ensure_geometry()` — no manual normal negation should be needed. Serialized face data includes `winding_version: 1`; old v0 data is auto-migrated on load via `_migrate_face_winding()` in `brush_instance.gd`.
- **UV transform order.** `FaceData._apply_uv_transform()` applies transforms as **rotate → scale → offset** (matching Valve 220 convention). The older order (scale+offset → rotate) is preserved in `_apply_uv_transform_v0()` solely for migrating legacy data on load. New code should never use the v0 order. When serializing, `to_dict()` writes `uv_format_version: 1` and `from_dict()` auto-migrates version 0 data.
- **Carve UV preservation.** `HFCarveSystem._copy_uv_settings_to_piece()` copies UV parameters from the original target brush to each carved slice and compensates the UV offset for the position difference. The compensation formula is `O_new = O_old + delta_2d.rotated(R) * S` where `delta_2d` is the projected position delta between the original and slice centers.
- **Non-blocking face bakes.** Face-material bakes use a two-phase snapshot-then-yield pattern. Phase 1 (synchronous): `baker.snapshot_brush_faces()` calls `ensure_geometry()`, `triangulate()`, and `_resolve_face_material()` on each brush, capturing the results as plain PackedArrays and Material refs. Phase 2 (cooperative): `baker.collect_snapshot_groups()` iterates frozen snapshots, doing world-space transforms and group appends with `process_frame` yields every `_FACE_BAKE_BATCH` (8) brushes. This guarantees a consistent scene snapshot while keeping the editor responsive. `_yield_overhead_ms` tracks idle time in yields and is subtracted from `_last_bake_duration_ms` so `estimate_bake_time()` reflects CPU work only. Material resources are referenced, not deep-cloned — in-place property mutations during the yield window will be visible in the output.
- **Material atlasing.** `HFMaterialAtlas` (`hf_material_atlas.gd`) packs `StandardMaterial3D` albedo textures into a single atlas image via shelf bin-packing. Baker integration in `bake_from_faces()`: when `use_atlas` is enabled, face UVs are checked per-face during grouping — faces with UVs outside [0,1] (tiling) go into a separate `[mat, "_tiling"]` sub-group that stays as a separate surface with hardware texture repeat, while non-tiling faces are atlased and UV-remapped. Atlas tiles have a 2px gutter (edge-pixel extension) to prevent mipmap bleed, and UV rects are inset by half a texel (clamped to 25% of tile extent so 1px textures never collapse to zero size). Only fires when 2+ materials are atlasable; single-material or all-fallback scenarios skip the atlas path entirely.
- **Collision modes.** `bake_collision_mode` on LevelRoot controls collision shape generation: 0 = legacy trimesh (ConcavePolygonShape3D), 1 = per-brush convex hulls (ConvexPolygonShape3D via `Baker.build_convex_collision_shapes()`), 2 = per-visgroup partitioned StaticBody3D nodes with convex hulls. `bake_convex_clean` deduplicates vertices (default true); `bake_convex_simplify` (0.0–1.0) applies AABB-proportional grid merge. Degeneracy guard (unique vertex count ≥ 4) always runs regardless of `convex_clean`. Mode 2 partitioning via `_partition_collision_by_visgroup()` must run *before* heightmap collision append. `_collect_brush_collision_data()` extracts real mesh vertices (not AABB corners) and filters subtractive brushes. All three settings persist in `.hflevel`.
- **Bake owner assignment.** Use `_assign_owner_recursive()` (not `_assign_owner()`) for baked geometry so all descendants get proper editor ownership. Always call it *after* the container is added to the scene tree.
- **Shader files.** Prefer standalone `.gdshader` files over inline GLSL strings in GDScript (e.g. `highlight.gdshader` for the selection wireframe shader). Use `preload("file.gdshader")` to load them.
- **Customizable keymaps.** All keyboard shortcuts go through `_keymap.matches("action_name", event)` instead of hardcoded `event.keycode == KEY_*` checks. Default bindings are defined in `HFKeymap._default_bindings()`. Users can override via `user://hammerforge_keymap.json`. Toolbar labels pull display strings from the keymap.
- **User preferences vs. level settings.** Application-scoped prefs (grid default, UI state, recent files) go in `HFUserPrefs` (`user://hammerforge_prefs.json`). Per-level settings (cordon, texture lock, materials) live on `LevelRoot` and serialize in `.hflevel`.
- **Tool poll pattern.** Override `can_activate(root)` and `get_poll_fail_reason(root)` on `HFEditorTool` to control when tools are available. Dock uses poll results to disable buttons and set tooltips. Plugin guards shortcuts with early-exit when poll fails.
- **Declarative tool settings.** External tools expose `get_settings_schema()` → Array of `{name, type, label, default, min, max, options}`. Dock auto-generates controls via `rebuild_tool_settings()`. Use `get_setting(key)` / `set_setting(key, val)` for storage.
- **Tag-based invalidation.** Call `root.tag_brush_dirty(id)` when a brush is modified; `root.tag_full_reconcile()` for structural changes (hollow, clip). Guard with `root.has_method("tag_brush_dirty")` for test shim compatibility.
- **Signal batching.** Wrap multi-brush operations in `root.begin_signal_batch()` / `root.end_signal_batch()`. Transactions do this automatically. On rollback, call `root.discard_signal_batch()` to drop queued signals without emission.
- **Operation results.** Methods that can fail (hollow, clip, delete) return `HFOpResult` with `ok`, `message`, and `fix_hint`. Use `_op_fail(msg, hint)` in brush_system to both emit `user_message` and return a fail result. Callers can check `result.ok` programmatically, but failures also auto-toast via the `user_message` signal.
- **Theme-aware UI.** All custom panels (context toolbar, coach marks, hotkey palette, operation replay, toasts, selection filter) use `HFThemeUtils` static methods (`panel_bg()`, `muted_text()`, `accent()`, etc.) instead of hardcoded colors. Each component provides a `refresh_theme_colors()` method called from `plugin.gd:_on_editor_theme_changed()`. `HFThemeUtils.is_dark_theme()` reads `interface/theme/base_color` luminance from `EditorInterface.get_editor_settings()`.
- **History browser.** `ui/hf_history_browser.gd` replaces the plain ItemList in the Manage tab History section. Records entries via `record_entry(name, version, undo_redo)` with viewport thumbnail capture. Double-click emits `navigate_requested(version)` which `dock._on_history_navigate()` handles by looping undo/redo to the target version. Undo/redo buttons are exposed via `get_undo_button()`/`get_redo_button()`. `dock._refresh_history_list()` wraps ItemList code in `if history_list:` and always calls `_update_history_buttons()`.
- **Multi-ruler measure tool.** `hf_measure_tool.gd` stores up to 20 rulers in `_measurements: Array[Dictionary]`. Shift+Click chains from last endpoint. Angles computed at shared vertices via `dir_a.angle_to(dir_b)`. Right-click sets snap reference via `HFSnapSystem.set_custom_snap_line()`. `_finish_ruler()` adjusts `_snap_ref_index` on rollover (decrement if after evicted, clear if evicted).
- **Export playtest.** `dock._on_export_playtest()` validates spawn, auto-creates if missing (with full undo via state capture before `create_default_spawn()`), bakes, calls `level_root.export_playtest_scene()` to pack baked + entities + default lighting into a `.tscn`, then launches via `play_custom_scene()`.
- **Geometry-aware snapping.** `_snap_point()` delegates to `HFSnapSystem`. Three modes (Grid=1, Vertex=2, Center=4) as a bitmask. Custom snap lines (set via `set_custom_snap_line()`) are checked alongside grid/geometry candidates. Vertex mode collects 8 box corners from all brushes; Center mode collects brush centers. Closest candidate within `snap_threshold` beats grid snap. Pass `exclude_ids` to skip the brush being dragged.
- **Reference cleanup.** `delete_brush()` calls `_cleanup_brush_references()` which strips group_id meta (+ cleans empty groups via `visgroup_system._cleanup_empty_group()`), clears visgroup membership, and calls `entity_system.cleanup_dangling_connections()` to remove I/O connections targeting the deleted node. Always fires before the node is removed from the tree.
- **Live dimensions.** `input_state.get_drag_dimensions()` returns `Vector3(W, H, D)` during DRAG_BASE/DRAG_HEIGHT; `Vector3.ZERO` otherwise. `format_dimensions()` renders as `"64 x 32 x 48"` (whole numbers omit decimals). The mode indicator banner appends dimensions to the stage hint during drag gestures.
- **Context toolbar.** `ui/hf_context_toolbar.gd` is a `PanelContainer` added to `CONTAINER_SPATIAL_EDITOR_MENU` via `plugin.gd`. It determines context via `_determine_context(state)` using a priority chain: vertex_mode > dragging > face_selected > entity_selected > brush_selected > draw_idle > NONE. Each context maps to a pre-built `HBoxContainer` section with tool buttons. The toolbar emits `action_requested(action, args)` which `plugin.gd` dispatches to existing dock/plugin methods. Auto-hint bar uses a separate `PanelContainer` child with fade-in tween. State is pushed every frame from `_update_hud_context()` via `_update_context_toolbar_state()`.
- **Command palette.** `ui/hf_hotkey_palette.gd` extends `PanelContainer`. Populated once via `populate(keymap)`. Live gray-out uses `_is_action_available(action)` which checks brush_count, entity_count, paint_mode, vertex_mode, and tool_id from the state dict. Toggle with Shift+? or F1. Emits `action_invoked(action)` which `plugin.gd` handles identically to keyboard shortcuts.
- **Marquee selection.** `plugin.gd` tracks drag start on mouse-down in Select mode. On mouse-up, if the drag exceeds a threshold, `_select_nodes_in_rect()` performs box selection for brushes/entities, or `_select_faces_in_rect()` selects faces across multiple brushes when in Face Select mode. A semi-transparent blue overlay (`_MarqueeOverlay` inner class) draws the selection rectangle during drag.
- **Selection filter.** `ui/hf_selection_filter.gd` extends `PopupPanel` (a `Window` subclass, not `Control`). Opened via Shift+F or context toolbar button. Emits `filter_applied(nodes, faces)` which `plugin.gd` handles via `_on_selection_filter_applied()` to update `hf_selection` and `face_selection`. Dynamic visgroup buttons rebuilt on each `show_for()` call.
- **Apply Last Texture.** `plugin.gd` stores `_last_picked_material_index` when Texture Picker (T) samples a face. Shift+T applies that material index to the current face or brush selection via existing `assign_material_to_selected_faces()` / `assign_material_to_whole_brushes()` methods.

### CI

The project has a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs on push and PR to `main`:
- `gdformat --check` -- verifies formatting
- `gdlint` -- checks lint rules (configured in `.gdlintrc`)
- **GUT unit + integration tests** -- 1357 tests across 74 test files (runs Godot headless)

Run locally before pushing:
```
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

### VS Code Integration

The repo includes `.vscode/tasks.json` with pre-configured GUT test tasks and problem matchers that surface failures as clickable file:line links in the Problems panel.

**Setup:** Set a `GODOT` environment variable pointing to your Godot binary:
```bash
# Linux / macOS
export GODOT=/usr/local/bin/godot

# Windows (PowerShell)
$env:GODOT = "C:\Godot\Godot_v4.6-stable_win64.exe"
```

**Available tasks** (`Ctrl+Shift+P` → "Tasks: Run Test Task"):
| Task | Description |
|------|-------------|
| GUT: Run All Tests | Full headless suite (default test task) |
| GUT: Run Current File | Runs only the open test file |
| GUT: Run Current Test Method | Runs a single method (select name first) |
| Godot: Import Project | Re-imports (fixes class_name errors) |

### Unit Tests (GUT)

Tests live in `tests/` and use the [GUT](https://github.com/bitwes/Gut) framework (installed in `addons/gut/`).

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_visgroup_system.gd` | 18 | Visgroup CRUD, visibility, membership, serialization |
| `test_grouping.gd` | 9 | Group creation, meta, ungroup, regroup, serialization |
| `test_texture_lock.gd` | 10 | UV offset/scale compensation for all projection types |
| `test_cordon_filter.gd` | 10 | AABB intersection, cordon-filtered collection, chunk_coord |
| `test_hollow_tool.gd` | 10 | Hollow creation (6 walls), thickness validation, material/operation preservation |
| `test_clip_tool.gd` | 16 | Axis splitting (X/Y/Z), size correctness, property preservation (material, visgroups, group_id, brush_entity_class), edge rejection |
| `test_brush_entity.gd` | 16 | Tie/untie entity classes, structural brush filtering, bake collection exclusion, brush info round-trip |
| `test_entity_io.gd` | 21 | Entity I/O CRUD (add/remove/get outputs), find by name, get_all_connections, serialization, default values |
| `test_justify_uv.gd` | 10 | UV justify modes (fit/center/left/right/top/bottom/stretch/tile), zero-range safety, offset accumulation |
| `test_brush_info_roundtrip.gd` | 19 | Brush info capture/restore with visgroups, group_id, brush_entity_class, material, move floor/ceiling argument safety |
| `test_face_data.gd` | 15 | FaceData to_dict/from_dict round-trip, ensure_geometry, triangulate, box_projection_axis |
| `test_paint_layer.gd` | 32 | Cell bit storage, chunk management, material IDs, blend weights, dirty tracking, heightmap, memory |
| `test_heightmap_io.gd` | 12 | Base64 encode/decode round-trip, noise generation (FastNoiseLite), determinism |
| `test_hflevel_io.gd` | 32 | Variant encode/decode (Vector2/3, Transform3D, Basis, Color), payload build/parse, full pipeline |
| `test_brush_shapes.gd` | 17 | Box face generation, normals, vertex bounds, triangulation, serialization, prism mesh, winding migration (v0→v1, round-trip) |
| `test_entity_props.gd` | 12 | Entity property form defaults (all types), roundtrip capture/restore, empty properties safety |
| `test_duplicator.gd` | 7 | Instance count, progressive offset, clear cleanup, to_dict/from_dict roundtrip, edge cases |
| `test_map_export.gd` | 19 | Quake/Valve220 face line format, auto-axes, entity property formatting, fractional coords, projections |
| `test_tool_registry.gd` | 25 | Tool registration, activate/deactivate, deactivate_current, has_active_external_tool, dispatch routing, shortcut check, external ID guard, stays-active-across-dispatch regression |
| `test_keymap.gd` | 16 | Default bindings loaded, simple/ctrl/shift/ctrl+shift key matching, modifier mismatch rejection, display string formatting, rebinding, JSON roundtrip |
| `test_user_prefs.gd` | 12 | Default values, get/set prefs, section collapsed state, recent files (add/dedup/max 10), JSON roundtrip, hint dismissed default/dismiss/roundtrip |
| `test_dirty_tags.gd` | 11 | Brush dirty tags (add/dedup), paint chunk tags, full reconcile flag, consume-clears, signal batch queue/flush/discard/nesting |
| `test_prototype_textures.gd` | 27 | Catalog constants, path generation, texture existence, material persistence (resource_path), batch loading into MaterialManager |
| `test_op_result.gd` | 15 | HFOpResult constructors, hollow/clip/delete return values, fail emits user_message, fix_hint population |
| `test_snap_system.gd` | 12 | Grid/Vertex/Center snap modes, threshold, exclude list, priority (closer geometry beats grid), empty scene fallback |
| `test_drag_dimensions.gd` | 8 | get_drag_dimensions() in all modes, format_dimensions() whole/fractional/zero |
| `test_reference_cleanup.gd` | 9 | Delete cleans group/visgroup membership, entity I/O cleanup_dangling_connections, preserves unrelated, no-crash on clean node |
| `test_bake_system.gd` | 84 | build_bake_options, structural/trigger filtering, chunk_coord, bake_dry_run, warn_bake_failure, estimate_bake_time, preview mode helpers (+ recursive chunk wireframe/proxy/multimesh/full), _last_bake_success, dirty tag retention, wireframe ShaderMaterial, postprocess connectors/navmesh, collision data collection (subtractive filter, real mesh verts, entity skip), mode 2 integration (single/chunked visgroup bodies, heightmap survival, trimesh preservation) |
| `test_bake_issues.gd` | 10 | check_bake_issues: degenerate, oversized, floating subtract, overlapping subtracts, non-manifold/open-edge, clean level, entity skip |
| `test_weld_and_planarity.gd` | 21 | Non-planar face detection (5), vertex welding + ensure_geometry refresh (3), planarity auto-fix (3), micro-gap detection (2), edge-key independence (1), boundary-straddling weld/gap/parse (3), MapIO integration (2), MapIO snap unit (2) |
| `test_quick_play_modes.gd` | 12 | Severity blocking (0/1/2), cordon save/restore, dirty tag retention patterns, camera yaw via entity_data, spawn restore after camera play, spawn restore on error path |
| `test_integration.gd` | 22 | End-to-end: brush lifecycle, paint + heightmap, entity workflow, visgroup cross-system, snap, bake cross-system, entity I/O cleanup, brush info round-trip |
| `test_shortcut_dialog.gd` | 8 | Category assignment (tools, paint, axis lock, editing), action labels (known/unknown), get_all_bindings copy safety |
| `test_tutorial_wizard.gd` | 14 | Step advancement, persistence, deferred start, resume, bake validation, no-root safety |
| `test_subtract_preview.gd` | 8 | AABB intersection math (overlapping, no-overlap, contained, partial axis), enable/disable, debounce timing |
| `test_prefab.gd` | 10 | Empty prefab, to_dict/from_dict roundtrip, transform preservation, file save/load, invalid data handling, multiple brushes, entity I/O preservation, instantiate empty |
| `test_vertex_edges.gd` | 19 | Edge extraction (12 edges for box), dedup, edge selection (additive, toggle, clear), edge world positions, edge split (vertex count, face vert count), vertex merge, sub-mode toggle, get_single_selected_edge, point-to-segment-dist-2d |
| `test_polygon_tool.gd` | 16 | Convexity validation (square, triangle, L-shape, pentagon, collinear, degenerate), face data construction (square/triangle extrusion, local space, top face normal), empty/two-point, tool metadata, settings schema |
| `test_path_tool.gd` | 15 | Segment brush construction (straight, diagonal, zero-length, center, size), miter joint construction (right angle, straight skipped, acute skipped, group_id), face data validation, face reconstruction, tool metadata |
| `test_material_browser.gd` | 24 | Thumbnail grid, palette view, null material skip, selection signals, double-click, drag data, search, pattern/color filters, favorites, hover preview, context popup |
| `test_material_integration.gd` | 28 | Brush search (_iter_pick_nodes), hover overlay mesh (normals, mutation, lifecycle), whole-brush/per-face assignment via root, face selection counting via dock, resolve_material_assign_action fallback (face→brush→error), selection_clear_requested signal, empty-selection suppression guard (reimport, intentional deselect, new selection, first select, dock clear protocol) |
| `test_context_toolbar.gd` | 20 | Context determination, label content, action signals, material thumbnails, search filtering, gray-out logic, toggle visibility |
| `test_hotkey_palette.gd` | 12 | Search filtering, action availability gray-out, key binding display, action invocation |
| `test_spawn_system.gd` | 21 | Spawn lookup, validation, auto-fix, default creation, debug viz, entity property helpers, severity ordering |
| `test_selection_features.gd` | 18 | Marquee, selection filters, Select Similar, Apply Last Texture |
| `test_io_presets.gd` | 21 | Builtin preset structure, user preset CRUD, apply with target mapping/self/delay/fire_once, save entity as preset, get target tags |
| `test_io_visualizer_enhanced.gd` | 20 | Color logic (selected/fire_once/type/default/delay), Bézier math (endpoints/midpoint/tangent), connection summary, highlight connected toggle/clear |
| `test_io_highlight_sync.gd` | 16 | Panel/toolbar sync from visualizer, set_pressed_no_signal contracts, signal emission, signal-driven integration (toolbar↔panel propagation, alternating sources) |
| `test_io_runtime.gd` | 36 | I/O-to-Signal dispatcher: wiring, method dispatch (direct/snake-case/generic/signal fallback), parameters, fire-once, user signals, multi-target fan-out, chain reactions, debug signal accuracy, rewire idempotency, duplicate source isolation, extra scan roots (transient/NodePath/overlap/descendant pruning), fire_on() static helper, HFEntitySystem.fire_output() fallback |
| `test_brush_to_heightmap.gd` | 11 | Default settings, empty input, single/multi brush conversion, height scale, cell bounds, target layer reuse, grid properties, display name, height roundtrip at non-zero origin |
| `test_scatter_brush.gd` | 14 | Default settings, circle scatter (transforms, empty/null layer, deterministic), height/slope filtering, spline scatter (basic, too few points), preview (dots, empty, wireframe), commit (creates MMI, no mesh), scale variation |
| `test_path_tool_extras.gd` | 22 | Extended schema, PathExtra defaults/options, stairs (flat/slope/step count/group id/faces), railings (basic/both sides/post count/group id), trim (basic/material/both sides/multi segment/group id), HUD lines, vertical placement, edge cases |
| `test_dock_terrain_integration.gd` | 30 | Dock heightmap convert (selection→convert→grid inheritance→chunk_size→signal→active layer→regenerate→height data), scatter settings (defaults, spline points, circle, null controls), scatter preview (circle, no layer, spline too few/stale/valid), scatter commit (empty, no mesh early return, preserves result), scatter clear (removes preview, safe when null, already-freed) |
| `test_theme_utils.gd` | 15 | Dark/light detection, panel_bg, panel_border, muted_text, primary_text, accent, success/warning/error colors, toast bg variants, make_panel_stylebox, consistency across dark/light |
| `test_perf_monitor.gd` | 5 | Entity count, vertex estimate, recommended chunk size, level health (Healthy/Consider Chunking/Optimize), level AABB |
| `test_measure_tool.gd` | 17 | Tool name/id/shortcut, initial state, ruler colors cycle, point-line distance (on-line/off-line/beyond/degenerate), finish ruler, max cap, remove last, clear all, snap ref index rollover, snap ref eviction, HUD lines (empty/with measurement) |
| `test_snap_system_custom.gd` | 6 | Custom snap line set/clear, projection onto line, snap_point with custom line, threshold, clear restores default |
| `test_history_browser.gd` | 10 | Record entry, max 30 cap, clear, undo/redo button exposure, icon/color for action types, navigate signal on double-click |
| `test_export_playtest.gd` | 3 | Export empty level, includes DirectionalLight3D, includes WorldEnvironment |
| `test_dock_history_and_playtest.gd` | 7 | history_list null by default, refresh doesn't crash when null, update_history_buttons called when null, version_changed updates buttons, spawn creation, state capture before/after spawn |
| `test_baker.gd` | 25 | Material preservation in merge (single, group-by, null-material, transform), bake_from_faces via collect_brush_face_groups + build_mesh_from_groups (single/multiple materials), _concat_surface_arrays (single, two, empty, indexed rebasing, non-indexed first + indexed second, indexed first + non-indexed second, both non-indexed stays non-indexed), convex collision shapes (single/multiple brush, degenerate skip/reject, dedup, empty input, trimesh default, face bake convex mode, snapshot hull verts, clean false, simplify) |
| `test_undo_helper.gd` | 9 | HFUndoHelper.commit without collation (fires history each time), collation first-commit fires + subsequent suppressed, different tags each fire, tag-switch resets collation, 5-arg + 6-arg collation suppression, null history callback safety |
| `test_displacement.gd` | 40 | HFDisplacementData unit (init, get/set distance, dim, displaced position, smooth, noise, dict roundtrip, alpha, sew group, offset, elevation), FaceData integration (triangulate displaced, dict roundtrip, null displacement), HFDisplacementSystem (create/destroy, has_displacement, paint raise/lower/smooth/noise/alpha, set_power resample, set_elevation, sew_all) |
| `test_bevel.gd` | 15 | Face inset (basic, height extrude, collapse guard, material inheritance, connecting sides winding), edge bevel (basic, segments, neighbor update, small radius, material inheritance), slerp utility (endpoints, midpoint, parallel, anti-parallel, quarter turn) |
| `test_occluder_generation.gd` | 13 | Occluder generation: flat mesh, chunked hierarchy (BakedChunk_* nodes), coplanar merge across chunks, plane separation, min-area filtering, idempotent re-generation, postprocess toggle (enabled/disabled), validation coverage + missing-occluder warnings |

Run all tests:
```
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Reset user prefs for a repeatable editor smoke run:
```
godot --headless -s res://tools/prepare_editor_smoke.gd --path .
godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=3
```

For editor-only coverage that headless tests cannot exercise, use:
- `res://samples/hf_editor_smoke_start.tscn`
- [`docs/HammerForge_Editor_Smoke_Checklist.md`](docs/HammerForge_Editor_Smoke_Checklist.md)

If you see "class_names not imported", run `godot --headless --import --path .` first to register GUT classes.

Configuration is in `.gutconfig.json` (test directory, prefix, exit behavior).

**Writing new tests:**
- Add files in `tests/` with the `test_` prefix and `.gd` suffix.
- Extend `GutTest`. Use `before_each()` / `after_each()` for setup/teardown.
- Use root shim scripts (dynamically created GDScript) to provide the LevelRoot interface without circular preload. See existing tests for the pattern.
- Keep tests focused: one behavior per test function.

## Materials Resources
HammerForge expects Godot material resources (`.tres` or `.material`) in the palette.

**Quick start with prototype textures:**
Click **Refresh Prototypes** in the Paint tab → Materials section to load all 150 built-in SVG textures (15 patterns x 10 colors) as `StandardMaterial3D` resources. See `docs/HammerForge_Prototype_Textures.md` for full details.

**Create a custom material:**
1. In the FileSystem dock, right-click `materials/` (or any folder).
2. Select `New Resource` -> `StandardMaterial3D` (or `ShaderMaterial`).
3. Save it as `materials/test_mat.tres`.

Then click `Add` in the Paint tab → Materials section and choose that resource.

## Manual Test Checklist

Visgroups
- Create a visgroup "walls" from the Manage tab.
- Add 2 brushes to the visgroup and toggle visibility off -- confirm those 2 brushes hide.
- Toggle visibility on -- confirm brushes reappear.
- Create a second visgroup, add a brush to both, hide one -- confirm brush is hidden.
- Save and reload `.hflevel` -- confirm visgroup names and membership persist.

Grouping
- Select 2 brushes and press Ctrl+G -- confirm a group is created.
- Click one grouped brush -- confirm all group members are selected.
- Press Ctrl+U -- confirm brushes are ungrouped and select independently.
- Save and reload -- confirm group persists.

Texture Lock
- Place a textured brush with Texture Lock enabled (Brush tab checkbox).
- Resize the brush via gizmo -- confirm UV alignment stays consistent.
- Move the brush -- confirm UVs track the movement.
- Disable Texture Lock and resize -- confirm UVs shift with the resize.

Carve UV Preservation
- Apply a grid texture to a large brush.
- Place a smaller brush overlapping it and carve (Ctrl+Shift+R).
- Inspect surviving slices -- confirm textures are seamless across slice boundaries.
- Undo -- confirm original state restored.

Cordon (Partial Bake)
- Enable cordon in the Manage tab.
- Set a small AABB around 1 of 3 brushes (or use "Set from Selection").
- Confirm yellow wireframe appears in the viewport.
- Bake -- confirm only the brush inside the cordon appears in baked output.
- Disable cordon and bake -- confirm all brushes appear.

Selection Tools (Brush tab — visible when brushes are selected)
- Select a brush and press Ctrl+H -- confirm it converts to 6 wall brushes (hollow).
- Adjust wall thickness spinner in Selection Tools before hollowing and confirm different thicknesses.
- Select a brush and press Shift+X -- confirm it splits into two brushes along the Y axis.
- During a base drag, type "64" then Enter -- confirm the brush base is 64 units.
- During height adjustment, type "32" then Enter -- confirm the brush height is 32 units.
- Select brushes, choose func_detail from dropdown in Selection Tools, click Tie -- confirm cyan tint overlay appears.
- Select tied brushes, click Untie in Selection Tools -- confirm tint is removed.
- Tie brushes as trigger_once -- confirm orange tint overlay appears.
- Bake with func_detail brushes -- confirm they are excluded from structural bake output.
- Select a brush and press Ctrl+Shift+F -- confirm it snaps to nearest surface below.
- Select a brush and press Ctrl+Shift+C -- confirm it snaps to nearest surface above.
- In Face Select Mode, select faces and use Justify Fit/Center/Left/Right/Top/Bottom.
- Select an entity, open Entity I/O section, fill Output/Target/Input, click Add -- confirm connection appears in list.
- Select the connection in the list and click Remove -- confirm it is removed.
- Select a different entity -- confirm the I/O list updates to show that entity's connections.
- Save .hflevel with entity I/O connections, reload, and confirm connections persist.

Snap Modes
- In Brush tab, click V (Vertex) toggle next to Grid Snap presets.
- Place a brush, then start drawing another near a corner of the first brush -- confirm it snaps to the exact corner.
- Click C (Center) toggle. Draw a brush near the center of an existing brush -- confirm it snaps to the center.
- Disable G (Grid) and both V and C -- confirm brush placement is unsnapped.
- Re-enable G -- confirm grid snapping resumes.

Live Dimensions
- Start drawing a brush and observe the mode indicator banner showing "Step 1/2: Draw base — W x H x D" with live updating dimensions.
- Click to advance to height stage and observe "Step 2/2: Set height — W x H x D" with height updating as you move the mouse.
- Type "64" and press Enter -- confirm the dimension display reflects the typed value.

Operation Feedback
- Select a very small brush (e.g. 4x4x4) and press Ctrl+H with wall thickness 4 -- confirm a toast appears with "Wall thickness too large" and a fix hint.
- Select a brush and press Ctrl+H with a valid thickness -- confirm success (no error toast, 6 walls created).
- Press Shift+X on a brush -- confirm success toast or appropriate error if split position is invalid.

Reference Cleanup
- Place a brush, add it to a group (Ctrl+G), then delete it. Confirm the group is automatically cleaned up.
- Place a brush, add it to a visgroup in the Manage tab, then delete the brush. Confirm the visgroup no longer lists the deleted brush.
- Create two entities with an I/O connection between them. Delete the target entity. Confirm a toast reports the removed connection count.

Carve Tool
- Place 2 overlapping brushes. Select the smaller one and press Ctrl+Shift+R. Confirm the larger brush is split into box slices around the carved volume.
- Confirm the carving brush is removed after carve.
- Confirm carved pieces preserve material, visgroups, group_id, and brush_entity_class.
- Undo the carve and confirm original brushes are restored.

Measurement Tool
- Press M to activate the measure tool. Click point A, then click point B. Confirm a line and Label3D appear showing total distance and dX/dY/dZ.
- Confirm measurement snaps to grid.
- Press Escape to clear the measurement.

Decal Tool
- Press N to activate the decal tool. Move mouse over a brush surface and confirm a semi-transparent preview decal follows the cursor.
- Click to place the decal. Confirm a Decal node is added as a child of LevelRoot.
- Confirm the decal is oriented to match the surface normal.
- Press Escape to exit decal mode and confirm preview is cleaned up.

Entity I/O Visualization
- Create two entities with an I/O connection. Enable "Show I/O Lines" in the Entities tab. Confirm colored lines appear between connected entities in the viewport.
- Select one entity and confirm its connections highlight in yellow.
- Disable "Show I/O Lines" and confirm lines disappear.

Terrain Sculpting
- On a paint layer with a heightmap, select Sculpt Raise in the Paint tab. Click and drag on the terrain. Confirm terrain raises under the cursor.
- Switch to Sculpt Lower and confirm terrain lowers.
- Switch to Sculpt Smooth and confirm jagged terrain smooths out.
- Switch to Sculpt Flatten, click (captures reference height), then drag. Confirm terrain levels to that height.
- Adjust strength, radius, and falloff spinboxes and confirm they affect sculpt behavior.

Paint Layer Rename
- In the Paint tab, select a layer and click the "R" rename button. Enter a new name. Confirm the layer list shows the new display name.
- Save and reload the .hflevel. Confirm the display name persists.

Axis Lock Visual
- Press X/Y/Z to toggle axis locks. Confirm the dock axis lock buttons (X/Y/Z) update their pressed state and color (red/green/blue).
- Click the dock axis lock buttons and confirm keyboard state matches.

Tutorial Wizard
- Delete `user://hammerforge_prefs.json` and reopen editor -- confirm tutorial wizard appears (not static welcome panel).
- Draw a brush (step 1) -- confirm tutorial auto-advances to step 2.
- Draw a Subtract brush -- confirm step 2 validates operation and advances.
- Paint floor cells -- confirm step 3 advances.
- Place an entity -- confirm step 4 advances.
- Bake -- confirm step 5 completes and tutorial shows "Complete!" message.
- Click "Dismiss Tutorial" at step 2 -- confirm wizard closes and prefs are saved.
- Reopen editor at step 3 -- confirm tutorial resumes at step 3.

Contextual Hints
- Switch to Draw tool -- confirm "Click to place corner → drag to set size → release for height" hint appears in viewport.
- Wait 4 seconds -- confirm hint fades out.
- Switch to Select tool -- confirm a different hint appears.
- Switch back to Draw -- confirm hint does NOT reappear (dismissed).
- Delete `user://hammerforge_prefs.json` -- confirm hints reappear.

Searchable Shortcut Dialog
- Press the **?** button on toolbar -- confirm searchable dialog opens (not static popup).
- Type "hollow" in the search field -- confirm only matching entries are visible.
- Clear search -- confirm all entries reappear grouped by category.
- Confirm categories: Tools, Editing, Paint, Axis Lock.

Subtract Preview
- Place an additive brush and a subtractive brush overlapping it.
- Enable "Subtract Preview" checkbox in Manage tab → Settings.
- Confirm a red wireframe appears at the AABB intersection of the two brushes.
- Move one brush -- confirm wireframe updates (with slight debounce).
- Disable the checkbox -- confirm wireframe disappears.
- Save and reload `.hflevel` -- confirm the toggle state persists.

Prefabs
- Select 2 brushes + 1 entity. In Manage tab → Prefabs, enter a name and click Save.
- Confirm `.hfprefab` file appears in `res://prefabs/`.
- Confirm the file appears in the Prefab Library list.
- Drag a prefab from the library into the viewport -- confirm brushes and entity are placed at the drop position with new IDs.
- Undo -- confirm all instantiated nodes are removed.
- Create two entities with I/O connections, select them + brushes, save as prefab, instantiate -- confirm I/O target names are remapped.

Brush workflow
- Draw an Add brush and confirm resize handles work.
- Draw a Subtract brush and apply cuts.
- Press U to enter Extrude Up, click a brush face, drag up, release -- confirm new brush appears.
- Press J to enter Extrude Down, click a brush face, drag up, release -- confirm new brush extends downward.
- Right-click during extrude drag to cancel and confirm preview is removed.
- Verify undo removes the extruded brush.

Face materials + UVs
- Click Refresh Prototypes in Paint tab → Materials section; confirm 150 prototype textures appear in palette.
- Assign a prototype texture to faces and verify preview updates with the new material.
- Add a custom material to the palette and assign it to multiple faces.
- Toggle Face Select Mode and ensure face selection only works when enabled.
- Open Paint tab → UV Editor section and drag points; confirm preview updates.

Surface paint
- Enable Paint Mode.
- In Paint tab → Surface Paint section, set `Paint Target = Surface`.
- Assign a texture to a layer and paint on a face.
- Switch layers and verify isolated weights.

Floor paint
- In Paint tab → Floor Paint section, use Brush/Erase/Rect/Line/Bucket on a layer.
- Switch brush shape between Square and Circle; confirm Square fills a box and Circle clips corners.
- Confirm live preview while dragging.

Heightmap + blend
- Paint cells on a layer, then import a heightmap (PNG/EXR) or generate noise.
- Verify displaced mesh appears under `Generated/HeightmapFloors`.
- Adjust Height Scale spinner and confirm mesh updates.
- Select Blend tool, paint blend weights on filled cells.
- Verify two-material blend shader responds to per-cell blend weights.
- Create two layers at different Y heights and generate a ramp/stair connector between them.
- Populate foliage on a heightmap layer and verify MultiMesh scatter respects height/slope.

Bake
- Bake with default settings.
- Toggle `Use Face Materials` and confirm bake output swaps to per-face materials.
- Bake with heightmap floors and confirm baked output includes heightmap meshes with trimesh collision.
- Set `bake_chunk_size > 0` and confirm the progress bar updates with chunk status.
- Run Bake Dry Run and confirm counts match expected brushes and chunks.

Validation + Settings
- Run Validate Level on a clean scene and confirm no issues.
- Create a zero-size brush and confirm Validate + Fix repairs it.
- Export settings, change grid snap or bake options, then import and confirm values restore.
- Confirm autosave history files are created under `res://.hammerforge/autosave_history` and old files are pruned.

Performance Panel
- Confirm brush count, paint memory, chunk count, and last bake time update after a bake.

Save/Load
- Save `.hflevel`.
- Reload and verify materials palette, face data, and paint layers are restored.
- Reload and verify heightmap data, material_ids, blend_weights, and height_scale persist.

Editor UX
- Toggle Draw/Select/Extrude Up/Extrude Down tools and verify shortcut HUD updates.
- Verify mode indicator banner changes color and text per tool (Draw=blue, Select=green, etc.).
- Start a brush drag and confirm mode indicator shows "Step 1/2: Draw base" then "Step 2/2: Set height".
- Type "64" during drag and confirm numeric input appears in mode indicator as "[64]".
- Press U/J and verify toolbar button toggles and HUD shows extrude shortcuts.
- In Extrude mode, hover over brush faces and confirm green/red highlight overlay appears.
- Click a face and confirm the hover highlight clears during extrude gesture.
- Save a .hflevel and confirm toast notification "Saved: filename.hflevel" appears.
- Trigger a bake error and confirm red toast notification appears.
- Press the **?** button on toolbar and confirm searchable shortcuts dialog opens with filterable keybindings.
- Select brushes and confirm "Sel: N brushes" appears with "x" clear button in footer.
- Click the "x" button and confirm selection is cleared.
- With no brushes selected, confirm "Select a brush to use these tools" hint appears in Selection Tools section.
- Delete `user://hammerforge_prefs.json` and reopen editor -- confirm tutorial wizard appears.
- Click "Dismiss Tutorial" with "Don't show again" checked -- confirm tutorial doesn't reappear.
- Confirm per-tab context hints show appropriate guidance (e.g. "Click and drag..." in Brush tab).
- Press X/Y/Z and confirm HUD shows axis lock state.
- Enable Paint Mode and verify HUD shows paint shortcuts (B/E/R/L/K).
- Press B/E/R/L/K in Paint Mode and confirm paint tool selector updates.
- Hover dock controls (snap buttons, bake options, etc.) and verify tooltips appear.
- Trigger a bake error and confirm red status text auto-clears after 5 seconds.
- Draw a Subtract brush and confirm it appears in orange-red (pending), then Apply Cuts and confirm it turns standard red.

## Troubleshooting
- If paint affects floors while trying to surface paint, set `Paint Target = Surface`.
- If previews look incorrect, delete `LevelRoot/Generated` and repaint.
- If heightmap meshes don't appear, confirm the active layer has a heightmap assigned (Import or Generate).
- If blend shader shows only one material, ensure blend weights have been painted with the Blend tool.
- Heightmap floors use a blend shader with default green/brown terrain colors and a cell grid overlay. To customize: select a HeightmapFloor MeshInstance3D, edit the ShaderMaterial, and set `material_a`/`material_b` textures or adjust `color_a`/`color_b`/`grid_opacity`.
