# Development Guide

Last updated: September 2, 2026

This document covers local setup, codebase structure, and how to test features.

## Requirements
- Godot Engine 4.7 (stable).
- A 3D scene to host `LevelRoot`.

## Local Setup
1. Open the project in Godot.
2. Enable the plugin: Project -> Project Settings -> Plugins -> HammerForge.
3. Open any 3D scene and choose **Create Starter** or **Create Empty** from the dock's empty state.

## Godot MCP Development Setup

The repository vendors `addons/godot_mcp`; each contributor keeps `.codex/config.toml` as ignored, machine-local configuration. The client reads authentication from `HAMMERFORGE_GODOT_MCP_TOKEN`; keep Codex configuration, the token, and all `user://` MCP settings outside version control. The server should remain loopback-only on port `9080` with authentication enabled. See [Install + Upgrade](docs/HammerForge_Install_Upgrade.md#project-scoped-godot-mcp-repository-contributors) for configuration and verification.

Treat `addons/godot_mcp` as vendored code: HammerForge formatting and lint commands target `addons/hammerforge` only. When deliberately updating the vendor snapshot, review it separately and record the upstream revision in the change description.

Current vendor: Godot MCP Native v1.0.8 (`2e138ed`). HammerForge keeps two local patches: bind HTTP to `127.0.0.1` unless remote access is enabled, and skip diagnostic `GDScript.reload()` of on-disk scripts (use the editor's compiled resources; rewrite relative `preload()` only when validating unsaved content).

## Codebase Structure

```
addons/hammerforge/
  plugin.gd              EditorPlugin entry point, input routing, sticky LevelRoot discovery
  plugin_commands.gd     Shared toolbar/palette/viewport/radial command dispatch
  plugin_input_router.gd Viewport keymap dispatch (delete/nudge/tools/paint/axis lock)
  plugin_vertex_input.gd Vertex/edge pick, drag, merge, and split dispatch
  plugin_hud.gd          HUD context, mode banner, and context-toolbar state
  level_root.gd          Coordinator (2,844 lines), delegates to subsystems
  input_state.gd         Drag/paint state machine (HFInputState)
  hf_selection_gesture.gd Select-mode LMB arbiter (native object selection, face marquee, gizmos)
  dock.gd + dock.tscn    UI dock (displayed as Build, Paint, Objects, Test), collapsible sections with persisted state
  dock_brush_handler.gd  Build-tab displacement/bevel/hollow/clip/tie handlers
  dock_entity_handler.gd Objects-tab property/create/I/O handlers
  dock_manage_handler.gd Test-tab bake/play/spawn/validation handlers
  dock_paint_handler.gd  Paint-tab layer/heightmap/scatter/sculpt handlers
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
  hf_snap_system.gd      Centralized snap (Grid/Vertex/Center/Edge/Perpendicular + custom snap lines, threshold-based candidates)
  hf_prefab.gd           Reusable brush+entity groups (variants, tags, save/load .hfprefab)
  hf_op_result.gd        Lightweight operation result (ok, message, fix_hint)
  undo_helper.gd         HFUndoHelper: state-capture undo with collation (merges rapid edits into one step)
  surface_paint.gd       Per-face surface paint tool
  uv_editor.gd           UV editing dock
  hf_outline_util.gd     Semantic outlines plus filled brush/entity gizmo collision helpers
  hflevel_io.gd          Variant encoding/decoding for .hflevel
  map_io.gd              .map import/export (uses adapter pattern for multi-format support)
  prefab_factory.gd      Advanced shape generation
  hf_validation.gd       HFValidation: static guards for LevelRoot containers (has_draft_containers, has_node, has_nodes, require_nodes)
  plugin_dialogs.gd      HFDialogManager: tracks ConfirmationDialogs for cleanup on plugin teardown

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
    hf_tutorial_wizard.gd  Focused 2-step Draw → Test Level guide (signal-driven auto-advance)
    hf_shortcut_dialog.gd  Searchable shortcut reference dialog (filterable Tree with categories)
    hf_material_browser.gd Visual material browser (thumbnail grid, search, filters, favorites, drag-drop)
    hf_prefab_library.gd   Prefab library dock section (search, tags, variants, drag-drop, context menu)
    hf_prefab_overlay.gd   Prefab ghost overlay (wireframe bounding box + override markers)
    hf_context_toolbar.gd  Floating contextual mini-toolbar (context-sensitive actions, group labels per tool cluster, pending-cuts buttons, bake preview toggle)
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
    manage_tab_builder.gd  Builds the displayed Test tab (legacy internal name retained for compatibility)
    selection_tools_builder.gd  Builds Selection Tools section (hollow, clip, move, tie, duplicator)
    hf_ui_factory.gd       HFUIFactory: static factory for repeated UI patterns (make_label_row/spin/check/button/option/separator)
    hf_editor_theme.gd     HFEditorTheme: editor icon/color/stylebox lookup with graceful fallbacks
    hf_undo_nav.gd         HFUndoNav: per-scene EditorUndoRedoManager navigation (history_id, scene_undo_redo, navigate_to_version)
    hf_entity_prop_utils.gd HFEntityPropUtils: collapses DraftEntity.entity_data vs Node3D meta dual-write pattern
    hf_tooltip_text.gd     HFTooltipText: static catalog of dock tooltip strings (apply_all walks the catalog)

  systems/               Subsystem classes (RefCounted)
    hf_system.gd           HFSystem: base lifecycle class (_init/destroy/clear/set_enabled/_has_nodes). Preview systems extend this.
    hf_grid_system.gd      Editor grid management
    hf_entity_system.gd    Entity definitions, placement, Entity I/O connections
    hf_brush_system.gd     Brush CRUD, cuts, materials, picking, hollow, clip, merge, tie/untie
    hf_drag_system.gd      Drag lifecycle, preview, axis locking
    hf_bake_system.gd      Bake orchestration (single/chunked/selected/dirty), cooperative face-bake yielding, preview modes (Full/Wireframe/Proxy), time estimate (yield-overhead-corrected), auto-connectors, collision mode partitioning (trimesh/convex/visgroup), automated occluder generation (coplanar grouping → OccluderInstance3D)
    hf_paint_system.gd     Floor + surface paint, layer CRUD
    hf_state_system.gd     State capture/restore (brushes, entities, floor, sun, paint, bake_preview_mode), settings, transactions
    hf_file_system.gd      .hflevel/.map/.glTF I/O, threaded writes, autosave failure reporting
    hf_validation_system.gd Validation, dependency checks, bake issue detection (degenerate/floating/overlapping/non-planar/micro-gap/occlusion-coverage), vertex welding + planarity auto-fix
    hf_visgroup_system.gd  Visgroups (visibility groups) + brush/entity grouping
    hf_carve_system.gd     Boolean-subtract carve (progressive-remainder box slicing)
    hf_io_visualizer.gd    Entity I/O connection lines (Bézier curves, color-coded, highlight pulse)
    hf_io_presets.gd       Reusable I/O connection presets (built-in + user-saved, target tag mapping)

  hf_log.gd               HFLog: test-aware warning wrapper (capture/suppress expected warnings in tests)
  hf_io_runtime.gd        Runtime I/O-to-Signal dispatcher (auto-wires entity_io_outputs to Godot signals on bake/export)
    hf_subtract_preview.gd Live CSG cut overlay for overlapping subtract/additive brushes (AABB fallback, debounced, pooled)
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

- **Subsystems are RefCounted.** Each receives a `LevelRoot` reference in `_init()` and accesses container nodes and properties through `root.*`. New subsystems should `extends "hf_system.gd"` (path-based — `extends HFSystem` fails before the editor scans `class_name` registrations) to inherit the standard lifecycle (`destroy`, `clear`, `set_enabled`, `is_enabled`, `_has_nodes`).
- **Shared UI utilities.** Use the static helpers in `ui/` instead of inlining boilerplate: `HFUIFactory.make_*` for repeated control patterns; `HFEditorTheme.find_editor_icon` / `get_editor_color` / `style_toolbar_button` for editor-themed visuals; `HFUndoNav.get_scene_undo_redo` / `navigate_to_version` for per-scene undo navigation; `HFEntityPropUtils.get_entity_data` / `set_entity_property` to paper over `DraftEntity` vs meta dual-write; `HFTooltipText.apply_all(dock)` to drive the tooltip catalog. Dock helpers like `_make_label_row` are kept as thin pass-through delegates for backwards compatibility.
- **Validation guards.** Use `HFValidation.has_draft_containers(root)`, `has_baked_container(root)`, `has_nodes(root, [...])` for compound container guards in subsystems. Single-property checks (`if not root.entities_node:`) can stay inline — same line count, less import noise.
- **Dialog tracking.** Plugin-spawned `ConfirmationDialog`/`AcceptDialog` instances must be registered with `_dialog_manager.add(dlg, base_control)` (`HFDialogManager` instance held by `plugin.gd`). It auto-removes from tracking when the dialog leaves the tree, and frees all live dialogs on plugin teardown via `_cleanup_pending_dialogs()`.
- **No circular preloads.** Subsystem files must not `preload("../level_root.gd")`. Use raw ints for default parameters and `root.EnumName.*` at runtime.
- **LevelRoot is the public API.** Its methods are thin one-line delegates to subsystems. External callers (`plugin.gd`, `dock.gd`) always go through `LevelRoot`.
- **Input state machine.** `HFDragSystem` owns the `HFInputState` instance. Drag state transitions are explicit (`begin_drag` -> `advance_to_height` -> `end_drag`). Extrude uses `begin_extrude` -> `end_extrude`. Modes are classified as *transient* (DRAG_BASE, DRAG_HEIGHT, EXTRUDE, SURFACE_PAINT — own temporary preview nodes) or *persistent* (VERTEX_EDIT — user-toggled, survives undo/redo). `HFInputState.is_transient_preview_mode()` encodes this distinction; plugin.gd's `version_changed` handler uses it to force-reset only transient modes.
- **Direct typed calls.** `plugin.gd` and `dock.gd` use typed references (`LevelRoot`, `DockType`) with direct method calls instead of `has_method`/`call`.
- **Brush visual layers.** Ordinary additive brushes use their material/tinted surface without a topology overlay. Subtract brushes keep one red semantic wireframe; brush entities keep one understated blue overlay. `DraftBrush.get_editor_outline_lines()` is the canonical hover/gizmo outline source: polyhedra keep boundaries and true creases without coplanar triangulation diagonals, while curved primitives use sparse shape-specific profiles instead of render wireframes or fallback boxes. Triangle topology is opt-in through vertex/edit tooling or Bake Preview Wireframe. `DraftBrush._sync_visual_overlays()` updates reusable semantic nodes after mesh changes and removes legacy duplicates.
- **Transient-node replacement.** Never `queue_free()` a fixed-name visual/container node and add its replacement under the same parent in the same frame. The queued node still reserves its name, so Godot auto-renames the replacement and later lookups lose it. Reuse the existing node when possible; otherwise detach it with `remove_child()` before queueing deletion and adding the replacement. Mark private lifecycle nodes with metadata when they must be recognized across reloads.
- **Baked-container ownership.** The top-level name `BakedGeometry` is reserved for HammerForge output. `HFBakeSystem.reconcile_baked_containers()` re-adopts that persisted node and conservatively migrates recognized legacy anonymous bake roots while leaving unrelated anonymous nodes untouched. Full-bake replacement and clear paths detach managed containers synchronously, then queue safe deletion, so there is always at most one canonical top-level baked container.
- **Grid snap HUD sync.** `dock.gd` emits `grid_snap_applied(value)` from both `_apply_grid_snap()` and `_on_root_grid_snap_changed()`. `plugin.gd` connects this to `_on_dock_grid_snap_applied()` which updates the HUD indicator. All grid change origins (dock UI, hotkeys, quick-property, state restore) flow through this path.
- **Bake state sync.** `dock.gd` emits `bake_state_changed(baking, success)` from `_on_bake_started()` and `_on_bake_finished()`. `plugin.gd` connects this to `_on_dock_bake_state_changed()` which refreshes the context toolbar immediately — ensuring `bake_disabled` propagates to the Bake Preview toggle and pending-cuts buttons without waiting for unrelated HUD updates. The bake preview toggle uses `_bake_preview_in_flight` to distinguish its own bake completions from external ones, and derives state from `root._last_bake_preview_mode` (persisted in undo snapshots) on undo/redo.
- **Bake and cut transactions.** Public bake entry points return a success boolean and reject overlapping work with `_bake_in_flight`. Dirty/full tags are claimed for one run and restored on failure without erasing edits that arrive while the bake is running. Commit Cuts performs its asynchronous bake before opening `EditorUndoRedoManager`, captures exact source and baked `PackedScene` snapshots, then registers immutable synchronous do/undo restores. Redo never consumes transient cutter lists, and failure leaves the prepared cutters pending. Face-material baking is only valid when no effective structural subtractor exists; pending, applied, or frozen cuts force the CSG-safe path so visual geometry and collision retain the same boolean result.
- **Sticky LevelRoot discovery.** `plugin.gd` keeps `active_root` sticky: `_edit()` does not null it when non-HammerForge nodes are selected. `_handles()` only claims the active `LevelRoot`, HammerForge brushes/entities, and entity subtrees; unrelated scene nodes remain owned by Godot's native editor. `dock.gd` mirrors sticky root discovery without broadening editor-object ownership.
- **Authoritative editor selection.** Godot's `EditorSelection` is the single source of truth for visible object selection. `_on_editor_selection_changed()` copies every state, including an empty list, into `hf_selection`; a stale plugin cache must never resurrect a visibly cleared selection. HammerForge-owned changes use `_apply_hf_selection()` with `_applying_hf_selection` to avoid feedback while rebuilding `EditorSelection`. `should_suppress_empty_selection()` is a deprecated compatibility helper that always returns `false` and must not regain suppressive behavior. After a Godot-owned click or region selection, `_finalize_native_selection()` runs deferred, maps internal preview children to their selectable owner, expands brush groups, and republishes only when that normalization changes the native result. Face Select is deliberately modal: entry switches to the built-in Select tool, turns Paint off, snapshots and clears object selection, and hides transform/resize gizmos. Manual exit restores still-valid nodes. Leaving Paint, choosing an incompatible built-in or external tool, or entering vertex edit closes the mode through the same restore path; a new Scene-tree/native object selection exits without restoring the old snapshot. Escape first clears selected faces, then exits/restores on the next press (or exits immediately when no faces are selected).
- **Material assignment fallback.** `dock.resolve_material_assign_action(mat_index)` is a pure helper returning `{action, method, args, toast}`. Both `_on_material_assign()` and `_on_browser_material_double_clicked()` delegate to it. When faces are selected → face assignment. When no faces but brushes are selected → whole-brush fallback. When nothing is selected → error toast. Context menu options (Apply to Faces, Apply to Whole Brush) remain explicit and do not use the fallback.
- **Collapsible sections.** Use `HFCollapsibleSection.create("Name", start_expanded)` from `ui/collapsible_section.gd` for dock sections. Each section has an HSeparator, indented content, and persisted collapsed state via user prefs. Tab contents are built programmatically in `_build_paint_tab()`, `_build_manage_tab()`, `_build_selection_tools_section()`, and `_build_entity_io_section()`. All 18 sections tracked in `_all_sections: Dictionary`.
- **Signal-driven dock sync.** Setting controls push values to LevelRoot via `toggled`/`value_changed` signal connections. Paint layers, materials, and surface paint sync instantly via `paint_layer_changed`, `material_list_changed`, and `selection_changed` signals. Perf panel updates every 30 frames; disabled hints are flag-driven. Form label widths standardized to 70px.
- **Viewport input ownership.** `_forward_3d_gui_input()` is an owner router, not a collection of independent handlers. A native RMB camera session is checked before scene creation, raycasts, hover, or tool dispatch. Modal UI and an already-active custom brush gizmo are next; an already-started native Object Select or HammerForge Face Select sequence is routed before paint/external/vertex tools; only then may an idle tool claim new input. Once an owner is chosen, every motion, mixed-button event, and release stays with that owner. `Alt+LMB` and idle RMB pass through to Godot. `set_input_event_forwarding_always_enabled()` keeps routing independent of editor selection, while the narrow `_handles()` contract leaves unrelated cameras, lights, and native gizmos under Godot's control.
- **Selection/gizmo arbitration.** Every ordinary Object Select LMB press is passed to Godot, which owns object click, region selection, modifier interpretation, transform/property widgets, gesture threshold, and the complete keyboard stream while a widget may own the press. This prevents Escape, Delete, or Ctrl+Arrow from also becoming a HammerForge action mid-widget. Shift therefore keeps Godot's native additive/active-selection behavior; HammerForge does not reinterpret Ctrl/Cmd as an Object Select toggle. `BrushGizmoPlugin` supplies filled collision triangles from each brush's real faces and from visible nested entity preview meshes, plus semantic collision segments. Composite entities append restrained markers for each visible null/line-only sibling; top-level visuals are converted back to entity-local space, hidden ancestors suppress all targets, and only truly geometry-less entities get the generic one-unit marker. HammerForge defers only owner/group normalization until the native result settles. Face Select alone uses the custom click/marquee path and returns `AFTER_GUI_INPUT_CUSTOM`, suppressing competing node/region selection while allowing Godot to finish gizmo cleanup. Its custom modifiers are Shift-add and Ctrl/Cmd-toggle. Custom resize handles claim explicitly through `handle_action_started`.
- **Cancellation and focus recovery.** Owner state must account for explicit cancelled releases, current button masks, and both `NOTIFICATION_APPLICATION_FOCUS_OUT` and `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. Buttonless motion clears stale Select ownership, restores vertex geometry, settles paint, and restores/freezes a stale custom-handle preview. External tools expose `recover_lost_pointer_capture()` and `cancel_pointer_capture()` through `HFToolRegistry`; Polygon height placement finalizes a missed release once and returns to editable points on focus loss. A deferred bounded finish releases the HammerForge latch if Godot never sends the matching `_commit_handle()`; `_suppress_late_handle_commit` then prevents a delayed callback from mutating the brush. Focus-loss recovery clears HammerForge's RMB/selection/transient-tool state but deliberately calls `_prepare_tool_transition(..., settle_custom_gizmo=false)`: Godot owns focus-loss settlement of its active transform/property/custom gizmo, and a competing local restore can undo a value Godot just committed. New pointer owners must provide the same one-owner/one-settlement guarantee.
- **Scale- and shape-correct resize handles.** Custom face handles measure and snap face-to-face extent in world units along the transformed local axis, then divide by that axis's world scale to update `DraftBrush.size`. The opposite face stays fixed in world space under rotated or non-uniformly scaled parents. Sphere handles couple X/Y/Z so the result remains a sphere; X/Z handles on cylinder, cone, and capsule couple the radial axes, and capsule Y is clamped to at least its diameter while retaining the opposite face. Odd-sided prism/pyramid point generation is AABB-centered and normalized so preview, outline, bake output, and handle planes share the stored size. `calculate_axis_resize()` rejects non-finite input and collapsed transform axes rather than emitting jumps or invalid geometry. A completed drag creates one undo action; no-op, cancelled, and recovered drags create none.
- **Picking contract.** Object, hover, entity, and face candidates must be `Node3D.is_visible_in_tree()` so hidden visgroup content cannot intercept the pointer. Brush AABBs are broad-phase only: `pick_face_from_ray()` resolves the actual face triangles, and `pick_node_from_ray()` compares that exact brush distance with visible entity geometry on the same normalized world ray. `LevelRoot._raycast()` uses the same exact brush face as its editor-placement fallback before the construction plane, so the empty half of a wedge/cone/custom AABB cannot select, occlude, or receive a dropped item. `_gather_visual_instances()` deliberately uses `get_children(true)` because entity previews are internal editor descendants; `_visual_pick_distance()` preserves one comparable world-ray parameter under non-uniform scale.
- **Managed selection scope.** Input forwarding is global, but HammerForge edits are not. `classify_selection_scope()` separates empty, native-only, HammerForge-only, and mixed selections. Empty/native-only keyboard commands pass through to Godot; a mixed selection is stopped with “Edit HammerForge and Godot nodes separately” so generic edits cannot bypass HammerForge IDs, caches, or undo. Apply the same guard before selection-dependent actions dispatched by the context toolbar, viewport context menu, hotkey palette, or radial menu, and expose `mixed_selection` in their state so unavailable actions do not advertise a partial edit. Global managed shortcuts also yield whenever an unrelated editor control owns keyboard focus; only the 3D viewport, the real Scene tree, or an explicitly marked HammerForge surface may dispatch them. HammerForge-only commands stay consumed even when their operation reports a no-op.
- **External-tool exclusivity.** Activating an external `HFEditorTool` calls `_prepare_tool_transition()`, exits conflicting vertex/paint state, and deactivates the previous external tool. While one is active, every mouse event is dispatched to it before built-in vertex/select/draw handling. Even when its handler returns PASS for a miss, `plugin.gd` returns immediately so the same physical event can reach Godot navigation but cannot leak into another HammerForge tool. Switching to a built-in tool or vertex mode deactivates the external tool.
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
- **First-run guide.** `ui/hf_tutorial_wizard.gd` presents the two-step Draw → Test Level path when `show_welcome` is true. It advances on `brush_added` and a successful `bake_finished`, persists `tutorial_step`, and can be reopened from Help. Dock `highlight_tab()` uses displayed tab aliases.
- **Dynamic contextual hints.** `shortcut_hud.gd` shows per-mode viewport hints (e.g. "Click to place corner → drag to set size → release for height"). Hints auto-dismiss after 4s fade tween and persist dismissal via `is_hint_dismissed()`/`dismiss_hint()` on `hf_user_prefs.gd`. Mode key is computed from HUD context dict.
- **Searchable shortcut dialog.** `ui/hf_shortcut_dialog.gd` extends `AcceptDialog` with a search `LineEdit` and `Tree`. Categories populated from `HFKeymap.get_category()`. Replaces the static shortcuts popup.
- **Subtract preview.** `systems/hf_subtract_preview.gd` is a `RefCounted` subsystem. After a 0.15s debounce it CSG-intersects each subtract DraftBrush with overlapping additives (max 8 subtractors) and shows the cut volume as a translucent mesh. Mesh AABBs are the broad-phase and the immediate wireframe fallback. Toggle via `show_subtract_preview` on LevelRoot. Call `destroy()` (not `clear()`) when the subsystem is no longer needed.
- **Undo/redo preview cleanup.** `plugin.gd` connects to `EditorUndoRedoManager.version_changed` and calls `HFInputState._force_reset()` for transient preview modes (drag, extrude, surface paint). This cascades through `_on_input_state_force_reset` to free preview nodes. VERTEX_EDIT is excluded because `commit_action()` fires `version_changed` after every vertex operation — resetting it would desync `_vertex_mode` from `input_state.mode`. `level_root.gd _exit_tree()` also calls `subtract_preview.destroy()`, `extrude_tool.cancel_extrude()`, and `drag_system._clear_preview()` to ensure preview nodes don't outlive the tree.
- **Prefabs.** `hf_prefab.gd` (`HFPrefab`) stores brush_infos + entity_infos with centroid-relative transforms. `capture_from_selection()` computes centroid and strips brush_id/group_id. `instantiate()` assigns new IDs, offsets transforms, remaps entity I/O via name_map, and returns `entity_nodes` (Node3D refs) alongside `entity_names` for stable registration. `save_to_file()`/`load_from_file()` use JSON via `HFLevelIO` encoding. `ui/hf_prefab_library.gd` provides the dock section with ItemList and drag-and-drop (`"hammerforge_prefab"` type tag). Plugin handles drop with raycast + snap + undo/redo. `HFPrefabSystem` tracks entity membership via stable UIDs (`hf_prefab_entity_id` meta) — never scene node names. Context toolbar prefab buttons (Var▶/Push/Pull) are built at init time and toggled visible in `_apply_context()`.
- **Vertex system.** `HFVertexSystem` (`systems/hf_vertex_system.gd`) manages vertex/edge selection, movement with convexity validation, edge splitting, and vertex merging. Supports two sub-modes via the `sub_mode` property: `VertexSubMode.VERTEX` (0) and `VertexSubMode.EDGE` (1), toggled with E key. **Note:** `sub_mode` is a public property, not a setter — assign directly (`vs.sub_mode = 1`). A drag begins with the picked vertex position or edge midpoint as its world anchor; `project_drag_screen_delta()` projects both screen rays onto a view-facing plane through that anchor and `update_drag_absolute()` reapplies an absolute delta to captured geometry. Axis locks instead choose a camera-facing plane containing the world axis, constrain the result to that axis, and return an invalid result for a head-on/degenerate projection rather than jumping. Plugin code must pass `root.input_state.axis_lock`, apply grid snap to the returned world delta, and cancel if motion reports LMB is no longer held. `merge_vertices(brush_id, indices)` and `split_edge(brush_id, edge)` require explicit brush_id and selection data; `plugin.gd` provides `_vertex_merge_selected()` and `_vertex_split_selected_edge()` wrappers that resolve current selection before calling. Edge selection syncs to `selected_vertices` so `move_vertices()` works transparently for both modes. `split_edge()` inserts midpoints and skips convexity validation (mathematically guaranteed on convex hulls). `merge_vertices()` validates convexity and reverts via face snapshots on failure. Edge deduplication uses canonical vertex key pairs (`"vkey_a|vkey_b"` where a < b).
- **Polygon tool.** `HFPolygonTool` (`hf_polygon_tool.gd`, tool_id=102, KEY_P) creates arbitrary convex polygon brushes via a three-phase state machine (IDLE → PLACING_VERTS → SETTING_HEIGHT). Enforces convexity via 2D cross product on XZ plane. Constructs face data with CW winding from outside (top, bottom, N side quads) in local space relative to AABB center. Uses `create_brush_from_info()` with undo/redo via `self.undo_redo`.
- **Path tool.** `HFPathTool` (`hf_path_tool.gd`, tool_id=103, KEY_SEMICOLON) creates corridor brushes from waypoints. Each segment is an oriented-box brush (8 corners from direction + perpendicular, CW-wound faces). Miter joint brushes fill gaps at interior waypoints. All brushes share a `group_id`. Single undo action for the entire path. `path_extra` setting (None/Stairs/Railing/Trim) auto-generates additional geometry after base segments: step brushes along sloped segments, top rails + posts on both sides, or edge trim strips with material auto-assign.
- **Convert to heightmap.** `HFBrushToHeightmap` (`paint/hf_brush_to_heightmap.gd`) rasterizes brush top faces onto a grid, creating a heightmap paint layer. Dock handler `_on_heightmap_convert()` inherits `base_grid` (origin/basis) and `chunk_size` from the paint layer manager, emits `paint_layer_changed`, and calls `regenerate_paint_layers()`. Uses `level_root.grid_snap` as cell size when > 0.
- **Scatter brush.** `HFScatterBrush` (`paint/hf_scatter_brush.gd`) generates scatter transforms for circle or spline shapes with height/slope filtering. `build_preview()` creates a MultiMesh for preview. `commit()` creates a permanent `MultiMeshInstance3D`. Dock wires UI controls → `_build_scatter_settings()` → preview/commit. Spline mode populates control points from `_selection_nodes` positions.
- **I/O connection presets.** `systems/hf_io_presets.gd` manages built-in and user-saved connection presets. 6 built-in presets (Door+Light+Sound, Button→Toggle, etc.) are always available. User presets persist to `EditorInterface.get_editor_paths().get_config_dir()` in editor, `user://` fallback for tests. `apply_preset(source, preset, target_map)` maps target tags to actual entity names ("self" → source name). `save_entity_as_preset()` captures existing connections. Tests use explicit temp paths with cleanup in `after_each()`.
- **I/O wiring panel.** `ui/hf_io_wiring_panel.gd` is a `VBoxContainer` embedded in the displayed Objects tab via `entity_tab_builder.gd`. Context-hidden (only visible when an entity is selected) and collapsed by default for progressive disclosure. Shows connection summary, outputs list, quick-wire form, and preset picker with target tag mapping. Emits `connection_added`, `preset_applied`, `highlight_toggled`. `_sync_highlight_button()` reads `_io_visualizer.highlight_connected` and uses `set_pressed_no_signal()` to avoid signal loops. Called from `set_source_entity()` and `dock.sync_wiring_highlight_state()`.
- **I/O runtime dispatcher.** `hf_io_runtime.gd` (`HFIORuntime`) translates entity I/O metadata into live Godot signals. Injected automatically by `export_playtest_scene()` and by `postprocess_bake()` (`bake_wire_io` defaults to true). Connections are keyed by source node instance ID (not name) so duplicate source names stay isolated. Target delivery iterates all nodes sharing a name (matching `find_entities_by_name()` semantics). `wire()` is idempotent: `_disconnect_all_signals()` tears down stale lambdas; `_prune_overlapping_roots()` deduplicates scan roots by instance ID and removes descendants covered by an ancestor. `extra_scan_root_paths: Array[NodePath]` (@export) persists across scene save/reload for the bake path where the dispatcher lives under `baked_container` but entities are under a sibling node. `HFEntitySystem.fire_output()` delegates to the dispatcher via `fire_from()` when present, falls back to direct multi-target resolution otherwise.
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
- **Shader files.** Prefer standalone `.gdshader` files over inline GLSL strings in GDScript (e.g. `editor_grid.gdshader` for the editor grid). Use `preload("file.gdshader")` to load them.
- **Customizable keymaps.** All keyboard shortcuts go through `_keymap.matches("action_name", event)` instead of hardcoded `event.keycode == KEY_*` checks. Default bindings are defined in `HFKeymap._default_bindings()`. Users can override via `user://hammerforge_keymap.json`. Toolbar labels pull display strings from the keymap.
- **User preferences vs. level settings.** Application-scoped prefs (grid default, UI state, recent files) go in `HFUserPrefs` (`user://hammerforge_prefs.json`). Per-level settings (cordon, texture lock, materials) live on `LevelRoot` and serialize in `.hflevel`.
- **Tool poll pattern.** Override `can_activate(root)` and `get_poll_fail_reason(root)` on `HFEditorTool` to control when tools are available. Dock uses poll results to disable buttons and set tooltips. Plugin guards shortcuts with early-exit when poll fails.
- **Declarative tool settings.** External tools expose `get_settings_schema()` → Array of `{name, type, label, default, min, max, options}`. Dock auto-generates controls via `rebuild_tool_settings()`. Use `get_setting(key)` / `set_setting(key, val)` for storage.
- **Tag-based invalidation.** Call `root.tag_brush_dirty(id)` for exact transform, material, UV, paint, and vertex mutations; call `root.tag_full_reconcile()` only for genuinely broad structural or bake-setting changes. `HFBrushChangeTracker` is keyed by storage-backed stable brush ID and reconciles Godot-owned gizmo/Inspector/Undo transitions, including exported nested FaceData resources, visibility, bake configuration, and cordon state. Its authoritative scan adopts valid native duplicates, repairs an accidentally reparented live brush only while it remains inside the same LevelRoot, strips copied prefab-link metadata from native copies, and never resurrects a detached/deleted node. New or deleted IDs seed/drop without duplicate tags. Guard direct system callbacks with `root.has_method("tag_brush_dirty")` for test-shim compatibility, and make no-op paths stay untagged.
- **Signal batching.** Wrap multi-brush operations in `root.begin_signal_batch()` / `root.end_signal_batch()`. Transactions do this automatically. On rollback, call `root.discard_signal_batch()` to drop queued signals without emission.
- **Operation results.** Methods that can fail (hollow, clip, delete) return `HFOpResult` with `ok`, `message`, and `fix_hint`. Use `_op_fail(msg, hint)` in brush_system to both emit `user_message` and return a fail result. Callers can check `result.ok` programmatically, but failures also auto-toast via the `user_message` signal.
- **Theme-aware UI.** All custom panels (context toolbar, coach marks, hotkey palette, operation replay, toasts, selection filter) use `HFThemeUtils` static methods (`panel_bg()`, `muted_text()`, `accent()`, etc.) instead of hardcoded colors. Each component provides a `refresh_theme_colors()` method called from `plugin.gd:_on_editor_theme_changed()`. `HFThemeUtils.is_dark_theme()` reads `interface/theme/base_color` luminance from `EditorInterface.get_editor_settings()`.
- **History browser.** `ui/hf_history_browser.gd` replaces the plain ItemList in the displayed Test tab History section. Records entries via `record_entry(name, version, undo_redo)` with viewport thumbnail capture. Double-click emits `navigate_requested(version)` which `dock._on_history_navigate()` handles by looping undo/redo to the target version. Undo/redo buttons are exposed via `get_undo_button()`/`get_redo_button()`. `dock._refresh_history_list()` wraps ItemList code in `if history_list:` and always calls `_update_history_buttons()`.
- **Multi-ruler measure tool.** `hf_measure_tool.gd` stores up to 20 rulers in `_measurements: Array[Dictionary]`. Shift+Click chains from the last endpoint; Ctrl+Click sets a snap reference through `HFSnapSystem.set_custom_snap_line()`. Plain RMB is reserved for native camera navigation. Angles are computed at shared vertices via `dir_a.angle_to(dir_b)`. `_finish_ruler()` adjusts `_snap_ref_index` on rollover (decrement if after evicted, clear if evicted).
- **Export playtest.** `dock._on_export_playtest()` validates spawn, auto-creates if missing (with full undo via state capture before `create_default_spawn()`), bakes, calls `level_root.export_playtest_scene()`, then launches via `play_custom_scene()`. The packed scene contains a player controller at the active spawn, baked output, point and brush entities, default lighting/environment, and an I/O dispatcher when needed. Recursive owner assignment preserves nested geometry/collision in the `.tscn`; reparented content preserves its global transform.
- **Geometry-aware snapping.** `_snap_point()` delegates to `HFSnapSystem`. Five modes (Grid=1, Vertex=2, Center=4, Edge=8, Perpendicular=16) form a bitmask. Custom snap lines (set via `set_custom_snap_line()`) are checked alongside grid/geometry candidates. Vertex mode collects transformed brush-AABB corners, Center collects brush centers, Edge collects AABB-edge midpoints, and Perpendicular projects the current point to the closest point on each AABB edge. The closest eligible geometry candidate within `snap_threshold` beats grid snap. Pass `exclude_ids` to skip the brush being dragged.
- **Reference cleanup.** `delete_brush()` calls `_cleanup_brush_references()` which strips group_id meta (+ cleans empty groups via `visgroup_system._cleanup_empty_group()`), clears visgroup membership, and calls `entity_system.cleanup_dangling_connections()` to remove I/O connections targeting the deleted node. Always fires before the node is removed from the tree.
- **Managed brush/entity edits.** `LevelRoot.delete_managed_nodes()`, `create_managed_duplicates()`, and `nudge_managed_nodes()` split canonical brush and `DraftEntity` paths between their owning systems while presenting one undoable editor action. Entity duplication uses captured entity info, preserves entity data plus group/visgroup membership, and assigns a unique copy name. Entity deletion removes group/visgroup membership and dangling I/O references before detaching the node. Do not route a selected `DraftEntity` through a brushes-only shortcut guard.
- **Live dimensions.** `input_state.get_drag_dimensions()` returns `Vector3(W, H, D)` during DRAG_BASE/DRAG_HEIGHT; `Vector3.ZERO` otherwise. `format_dimensions()` renders as `"64 x 32 x 48"` (whole numbers omit decimals). The mode indicator banner appends dimensions to the stage hint during drag gestures.
- **Context toolbar.** `ui/hf_context_toolbar.gd` is a `PanelContainer` added to `CONTAINER_SPATIAL_EDITOR_MENU` via `plugin.gd`. It determines context via `_determine_context(state)` using a priority chain: vertex_mode > dragging > face_selected > entity_selected > brush_selected > draw_idle > NONE, with mixed native/HammerForge selection suppressing managed selection contexts. Each context maps to a pre-built `HBoxContainer` section with tool buttons. The toolbar emits `action_requested(action, args)` which `plugin.gd` dispatches to existing dock/plugin methods. Auto-hint bar uses a separate `PanelContainer` child with fade-in tween. State is pushed every frame from `_update_hud_context()` via `HFPluginHud.update_context_toolbar_state()`.
- **Command palette.** `ui/hf_hotkey_palette.gd` extends `PanelContainer`. Populated once via `populate(keymap)`. Live gray-out uses `_is_action_available(action)` which checks brush_count, entity_count, paint_mode, vertex_mode, tool_id, and mixed-selection state from the state dict. Toggle with Shift+? or F1. Emits `action_invoked(action)` which `plugin.gd` handles through the same managed-action scope guard used by other UI surfaces.
- **Marquee selection.** Object marquee begins on clear viewport space and is delegated to Godot's native 3D viewport; `EditorSelection` receives the exact native region result before deferred HammerForge owner/group normalization. Do not approximate Godot's private widget or region hit shapes with a screen-radius guard. Object selection keeps Godot's native Shift behavior and leaves Ctrl/Cmd Godot-owned. Face Select marquee remains HammerForge-owned: after `SELECT_DRAG_THRESHOLD`, `_select_faces_in_rect()` first filters canonical visible brush faces by projected center, then calls the canonical face picker at that center and accepts the candidate only when the same brush/face is the frontmost visible hit. It uses the Shift-add/Ctrl/Cmd-toggle state captured at press and draws through `_forward_3d_force_draw_over_viewport()`. Do not reintroduce a generic “any LMB drag starts marquee” path or attach viewport drawing to a toolbar container.
- **Selection filter.** `ui/hf_selection_filter.gd` extends `PopupPanel` (a `Window` subclass, not `Control`). Opened via Shift+F or context toolbar button. Emits `filter_applied(nodes, faces)` which `plugin.gd` handles via `_on_selection_filter_applied()` to update `hf_selection` and `face_selection`. Dynamic visgroup buttons rebuilt on each `show_for()` call.
- **Apply Last Texture.** `plugin.gd` stores `_last_picked_material_index` when Texture Picker (T) samples a face. Shift+T applies that material index to the current face or brush selection via existing `assign_material_to_selected_faces()` / `assign_material_to_whole_brushes()` methods.

### CI

The project has a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs on push and PR to `main`:
- `gdformat --check` -- verifies formatting
- `gdlint` -- checks lint rules (configured in `.gdlintrc`)
- **GUT unit + integration tests** -- 1,790 tests across 104 test scripts (1,783 passing plus seven intentional no-assert safety tests; 7,855 assertions; verified in CI September 2, 2026; runs Godot headless)

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
$env:GODOT = "C:\Godot\Godot_v4.7-stable_win64.exe"
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
| `test_brush_entity.gd` | 19 | Tie/untie entity classes, structural brush filtering, bake collection exclusion, brush info round-trip, and exact Commit Cuts preparation/finalization |
| `test_entity_io.gd` | 27 | Entity I/O CRUD (add/remove/get outputs), find by name, get_all_connections, serialization, default values |
| `test_justify_uv.gd` | 10 | UV justify modes (fit/center/left/right/top/bottom/stretch/tile), zero-range safety, offset accumulation |
| `test_brush_info_roundtrip.gd` | 19 | Brush info capture/restore with visgroups, group_id, brush_entity_class, material, move floor/ceiling argument safety |
| `test_face_data.gd` | 15 | FaceData to_dict/from_dict round-trip, ensure_geometry, triangulate, box_projection_axis |
| `test_paint_layer.gd` | 32 | Cell bit storage, chunk management, material IDs, blend weights, dirty tracking, heightmap, memory |
| `test_heightmap_io.gd` | 12 | Base64 encode/decode round-trip, noise generation (FastNoiseLite), determinism |
| `test_hflevel_io.gd` | 38 | Variant encode/decode (Vector2/3, Transform3D, Basis, Color), payload build/parse, full pipeline |
| `test_brush_shapes.gd` | 37 | Box face generation, normals, vertex bounds, triangulation, serialization, centered odd-sided pyramid/prism preview+bake bounds, winding migration, sparse overlay lifecycle, material refresh, and truthful custom-face previews |
| `test_viewport_outlines.gd` | 39 | Semantic primitive/custom/subtract outlines, combined nested entity targets, top-level/hidden visibility, hover suppression, shape-aware handle sizing, odd-polygon agreement, world-snapped resize, and bounded recovery/cancel/undo behavior |
| `test_selection_gesture.gd` | 38 | Native Object Select/widget ownership, modal Face Select, scope/focus guards, runtime repair, modifiers, recovery, native duplicate/reparent handling, prefab unlinking, bake-setting invalidation, native overlay drawing, and stable-ID transform/Inspector/FaceData/undo Bake Changed reconciliation |
| `test_picking_correctness.gd` | 15 | Exact non-box face hits and placement, construction-plane fallback, internal entity preview traversal, nearest brush/entity ordering, scaled world-ray distances, hidden-visgroup exclusion, and canonical visibility-aware picking across tools |
| `test_entity_props.gd` | 12 | Entity property form defaults (all types), roundtrip capture/restore, empty properties safety |
| `test_duplicator.gd` | 7 | Instance count, progressive offset, clear cleanup, to_dict/from_dict roundtrip, edge cases |
| `test_map_export.gd` | 27 | Quake/Valve220 face formats, custom-face geometry, entity properties, brush entities, fractional coordinates, and projections |
| `test_tool_registry.gd` | 27 | Tool registration, activate/deactivate, dispatch routing, shortcut/external ID guards, exclusivity, and pointer capture cancel/recovery |
| `test_keymap.gd` | 20 | Default bindings loaded, key/modifier matching, display strings, rebinding, JSON roundtrip, and current action coverage |
| `test_user_prefs.gd` | 15 | Defaults, get/set prefs, section state, recent files, JSON roundtrip, and dismissed hints |
| `test_dirty_tags.gd` | 19 | Exact transform/material/UV/paint/vertex dirty tags, no-op suppression, floor routing, paint/full tags, consume, and batch queue/flush/discard/nesting |
| `test_prototype_textures.gd` | 27 | Catalog constants, path generation, texture existence, material persistence (resource_path), batch loading into MaterialManager |
| `test_op_result.gd` | 30 | HFOpResult constructors and operation result/failure/fix-hint contracts |
| `test_snap_system.gd` | 17 | Grid/Vertex/Center/Edge/Perpendicular snap modes, threshold, preview exclusion, priority, and empty-scene fallback |
| `test_drag_dimensions.gd` | 16 | Drag dimensions/formatting plus normalized sphere/cylinder/cone/capsule placement bounds |
| `test_bugfix_regressions.gd` | 32 | Vertex undo/projection/axis constraints, cancelled-release restoration, viewport owner routing, RMB session and lost-release recovery, narrow native-object handling, paint capture, and scene-creation safety |
| `test_vertex_system.gd` | 35 | Vertex movement/convexity/undo snapshots, exact convex-clip dirty tags, and perspective/orthographic/axis-locked drag projection |
| `test_reference_cleanup.gd` | 8 | Delete cleans group/visgroup membership and entity I/O while preserving unrelated references |
| `test_bake_system.gd` | 127 | Baked-container adoption/replacement/clear and exact snapshot restore, conservative legacy migration (chunk, face-material, heightmap), structural-cut fallback, one-pass visual/collision CSG equivalence, transformed cordon/chunk interactions, build options, dry runs, preview modes, dirty-tag concurrency, connectors/navmesh, brush entities, and mode 2 integration |
| `test_bake_issues.gd` | 10 | check_bake_issues: degenerate, oversized, floating subtract, overlapping subtracts, non-manifold/open-edge, clean level, entity skip |
| `test_weld_and_planarity.gd` | 21 | Non-planar face detection (5), vertex welding + ensure_geometry refresh (3), planarity auto-fix (3), micro-gap detection (2), edge-key independence (1), boundary-straddling weld/gap/parse (3), MapIO integration (2), MapIO snap unit (2) |
| `test_quick_play_modes.gd` | 13 | Severity blocking, cordon save/restore, dirty retention, camera yaw, and spawn restore across play/error paths |
| `test_integration.gd` | 22 | End-to-end: brush lifecycle, paint + heightmap, entity workflow, visgroup cross-system, snap, bake cross-system, entity I/O cleanup, brush info round-trip |
| `test_shortcut_dialog.gd` | 8 | Category assignment (tools, paint, axis lock, editing), action labels (known/unknown), get_all_bindings copy safety |
| `test_tutorial_wizard.gd` | 18 | Step advancement, persistence, deferred start/resume, bake validation, completion, and no-root safety |
| `test_subtract_preview.gd` | 14 | AABB math, overlapping live-CSG cut groups, enable/disable, debounce, and safe destroy |
| `test_prefab.gd` | 11 | Empty prefab, to_dict/from_dict roundtrip, transform preservation, file save/load, invalid data handling, multiple brushes, entity I/O preservation, instantiate empty |
| `test_vertex_edges.gd` | 19 | Edge extraction (12 edges for box), dedup, edge selection (additive, toggle, clear), edge world positions, edge split (vertex count, face vert count), vertex merge, sub-mode toggle, get_single_selected_edge, point-to-segment-dist-2d |
| `test_polygon_tool.gd` | 20 | Convexity/face construction, bidirectional positive height, missed-release and focus recovery, tool metadata, and settings schema |
| `test_path_tool.gd` | 16 | Segment/miter construction, face data, reconstruction, pointer lifecycle, and tool metadata |
| `test_material_browser.gd` | 24 | Thumbnail grid, palette view, null material skip, selection signals, double-click, drag data, search, pattern/color filters, favorites, hover preview, context popup |
| `test_material_integration.gd` | 28 | Brush search (_iter_pick_nodes), hover overlay mesh (normals, mutation, lifecycle), whole-brush/per-face assignment via root, face selection counting via dock, resolve_material_assign_action fallback (face→brush→error), selection-clear signaling, and the invariant that empty `EditorSelection` is never hidden by a stale plugin cache |
| `test_context_toolbar.gd` | 23 | Context determination, mixed-selection suppression, labels, actions, material thumbnails, and live refresh |
| `test_hotkey_palette.gd` | 16 | Search, action availability, mixed-selection suppression, bindings, and invocation |
| `test_spawn_system.gd` | 31 | Spawn lookup/validation/auto-fix/default creation/debug viz, property helpers, masks, and floor offsets |
| `test_selection_features.gd` | 25 | Selection filters/similar/texture actions plus dock ownership, mixed/heterogeneous guards, and disabled controls |
| `test_io_presets.gd` | 21 | Builtin preset structure, user preset CRUD, apply with target mapping/self/delay/fire_once, save entity as preset, get target tags |
| `test_io_visualizer_enhanced.gd` | 22 | Color logic (selected/fire_once/type/default/delay), Bézier math (endpoints/midpoint/tangent), connection summary, live weak selection/rename tracking, highlight connected toggle/clear |
| `test_io_highlight_sync.gd` | 16 | Panel/toolbar sync from visualizer, set_pressed_no_signal contracts, signal emission, signal-driven integration (toolbar↔panel propagation, alternating sources) |
| `test_io_runtime.gd` | 38 | I/O-to-Signal dispatcher: wiring, method dispatch (direct/snake-case/generic/signal fallback), parameters, fire-once, user signals, multi-target fan-out, chain reactions, debug signal accuracy, rewire idempotency, duplicate source isolation, extra scan roots (transient/NodePath/overlap/descendant pruning), fire_on() static helper, HFEntitySystem.fire_output() fallback |
| `test_brush_to_heightmap.gd` | 14 | Default settings, empty input, single/multi conversion, skip subtract brushes, mesh/displacement bounds, height scale, cell bounds, target layer reuse, grid properties, display name, height roundtrip |
| `test_scatter_brush.gd` | 15 | Defaults, circle/spline scatter, filters, deterministic transforms, preview, commit, and scale variation |
| `test_path_tool_extras.gd` | 24 | Extended schema/options, stairs, railings, trim including material slot zero, HUD, placement, and edge cases |
| `test_dock_terrain_integration.gd` | 30 | Dock heightmap convert (selection→convert→grid inheritance→chunk_size→signal→active layer→regenerate→height data), scatter settings (defaults, spline points, circle, null controls), scatter preview (circle, no layer, spline too few/stale/valid), scatter commit (empty, no mesh early return, preserves result), scatter clear (removes preview, safe when null, already-freed) |
| `test_theme_utils.gd` | 15 | Dark/light detection, panel_bg, panel_border, muted_text, primary_text, accent, success/warning/error colors, toast bg variants, make_panel_stylebox, consistency across dark/light |
| `test_perf_monitor.gd` | 6 | Entity count, vertex estimate, chunk recommendation, health, AABB, and empty state |
| `test_measure_tool.gd` | 22 | Tool metadata/state, rulers/distances/chaining, cap/removal, snap references, input ownership, and HUD |
| `test_snap_system_custom.gd` | 6 | Custom snap line set/clear, projection onto line, snap_point with custom line, threshold, clear restores default |
| `test_history_browser.gd` | 14 | Record/cap/clear, undo/redo controls, icon/color mapping, navigation, and history refresh |
| `test_export_playtest.gd` | 8 | Empty export, lighting/environment, player spawn/controller, nested ownership, and transform preservation |
| `test_dock_history_and_playtest.gd` | 8 | Null-safe history refresh/buttons, selection typing, version updates, spawn creation, and state capture |
| `test_baker.gd` | 26 | Material-preserving merge/face bake, indexed/non-indexed concatenation, convex collision generation, snapshots, and simplification |
| `test_undo_helper.gd` | 10 | History callbacks, collation tags/windows/scopes, dynamic method arities, and null safety |
| `test_displacement.gd` | 38 | Displacement data, FaceData triangulation/serialization, create/destroy, painting, power/elevation, noise, and sewing |
| `test_bevel.gd` | 15 | Face inset (basic, height extrude, collapse guard, material inheritance, connecting sides winding), edge bevel (basic, segments, neighbor update, small radius, material inheritance), slerp utility (endpoints, midpoint, parallel, anti-parallel, quarter turn) |
| `test_occluder_generation.gd` | 13 | Occluder generation: flat mesh, chunked hierarchy (BakedChunk_* nodes), coplanar merge across chunks, plane separation, min-area filtering, idempotent re-generation, postprocess toggle (enabled/disabled), validation coverage + missing-occluder warnings |
| `test_paint_hot_paths.gd` | 39 | `SurfacePaint.paint_at_uv` (write-through, falloff, accumulation, erase, edge clamping, layer creation), `FaceData.get_painted_albedo` (blend modes, opacity, layer stacking, resize, non-RGBA8 sources, cache hits and invalidation), and `HFPaintTool._apply_terrain_brush` (raise/lower/smooth/flatten, falloff, wrapping, clamping, dirty chunks) |

Run all tests:
```
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

Reset user prefs for a repeatable editor smoke run:
```
godot --headless -s res://tools/prepare_editor_smoke.gd --path .
godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=1
```

Measure the paint hot paths (per-texel access costs, cold-vs-cached face composite, sculpt scaling):
```
godot --headless -s res://tools/benchmark_paint_hot_paths.gd --path .
godot --headless -s res://tools/benchmark_paint_hot_paths.gd --path . -- --size=512 --repeats=5
```

Run it before and after any paint performance change and put the numbers in the PR. Note that on Godot 4.7
`Image.get_pixel()` / `set_pixel()` are *faster* than equivalent `PackedByteArray` indexing in GDScript, so
"rewrite the loop over the raw buffer" is not a reliable optimisation here — measure first.

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
- **Warning suppression**: For negative-path tests that intentionally trigger runtime warnings, use `HFLog` instead of `push_warning()` in production code. In tests, wrap the triggering call with `HFLog.begin_test_capture(["expected pattern"])` / `HFLog.end_test_capture()` and assert with `HFLog.get_captured_warnings()`. This keeps the test output clean while still verifying the warning was emitted. See `test_bevel.gd` or `test_hflevel_io.gd` for the pattern.

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
- Create a visgroup "walls" from the Test tab.
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
- Place a textured brush with Texture Lock enabled (Build tab checkbox).
- Resize the brush via gizmo -- confirm UV alignment stays consistent.
- Move the brush -- confirm UVs track the movement.
- Disable Texture Lock and resize -- confirm UVs shift with the resize.

Carve UV Preservation
- Apply a grid texture to a large brush.
- Place a smaller brush overlapping it and carve (Ctrl+Shift+R).
- Inspect surviving slices -- confirm textures are seamless across slice boundaries.
- Undo -- confirm original state restored.

Cordon (Partial Bake)
- Enable cordon in the Test tab.
- Set a small AABB around 1 of 3 brushes (or use "Set from Selection").
- Confirm yellow wireframe appears in the viewport.
- Bake -- confirm only the brush inside the cordon appears in baked output.
- Disable cordon and bake -- confirm all brushes appear.

Selection Tools (Build tab — visible when brushes are selected)
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
- In Build tab, click V (Vertex) toggle next to Grid Snap presets.
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
- Place a brush, add it to a visgroup in the Test tab, then delete the brush. Confirm the visgroup no longer lists the deleted brush.
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
- Create two entities with an I/O connection. Enable "Show I/O Lines" in the Objects tab. Confirm colored lines appear between connected entities in the viewport.
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
- Draw a brush (step 1) -- confirm the guide auto-advances to step 2.
- Run Test Level -- confirm a successful bake completes step 2 and the guide shows its completion state.
- Click "Dismiss Tutorial" at step 2 -- confirm wizard closes and prefs are saved.
- Reopen the editor at step 1 -- confirm the guide resumes at step 2 rather than restarting.

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
- Enable "Subtract Preview" checkbox in Test tab → Settings.
- Confirm a red wireframe appears at the AABB intersection of the two brushes.
- Move one brush -- confirm wireframe updates (with slight debounce).
- Disable the checkbox -- confirm wireframe disappears.
- Save and reload `.hflevel` -- confirm the toggle state persists.

Prefabs
- Select 2 brushes + 1 entity. In Test tab → Prefabs, enter a name and click Save.
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
- Confirm per-tab context hints use the displayed Build/Paint/Objects/Test names and recommend the Draw → Test Level path.
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
