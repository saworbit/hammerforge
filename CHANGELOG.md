# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]
### Added
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
