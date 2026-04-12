# Roadmap

Last updated: April 12, 2026

This roadmap is a directional plan. Items may change based on user feedback.
Priorities are informed by a Hammer Editor gap analysis — see GAP_ANALYSIS.md for details.

## Done (Wave 1 -- Hammer-Inspired Quick Wins)
- Visgroups (visibility groups) with per-group show/hide and dock UI.
- Brush/entity grouping with Ctrl+G/U and group-aware selection.
- Texture lock (UV alignment preserved on move/resize/rotation).
- Cordon (partial bake) with AABB filter and wireframe visualization.
- GUT unit test suite (47 tests) with CI integration.

## Done (Dock UX Overhaul)
- Consolidated 8 tabs to 4 (Brush, Paint, Entities, Manage).
- Collapsible sections with separators, indented content, persisted collapsed state.
- Selection tools (hollow, clip, move, tie, duplicator) contextually shown in Brush tab.
- Compact toolbar (single-char labels with tooltips, VSeparator before extrude).
- Signal-driven paint/material/surface paint sync (replaced 10-frame polling).
- UV Justify 3×2 grid layout. Standardized 70px label widths, 32px +/- buttons.
- "No LevelRoot" banner and autosave warning defined in dock.tscn.
- Sticky LevelRoot discovery (deep recursive search, no re-selection needed).
- Manage tab trimmed: Actions has only floor/cuts/clear.

## Done (Code Quality Audit)
- Comprehensive duck-typing removal across baker, file system, plugin, and dock (~30 sites total).
- Fully signal-driven dock sync (settings, paint layers, materials, surface paint).
- Input handler decomposed from 260-line monolith into 7 focused handlers.
- O(1) brush ID lookup and material instance caching.
- Extracted shared methods: chunk deserialization, chunk collection, heightmap model building.
- Fixed O(n²) region index capture.
- Persistent cordon mesh (no per-call ImmediateMesh allocation).
- External highlight shader (no inline GLSL).
- Named constants for magic numbers; bounded loops.

## Done (Wave 2a -- Core Hammer Tools)
- Hollow tool (convert solid brush to hollow room with configurable wall thickness). Ctrl+H.
- Numeric input during drag (precise dimensions while drawing or extruding).
- Brush entity conversion (Tie to Entity / Untie): tag brushes as func_detail, trigger volumes, func_wall, etc.
- Texture alignment panel: Justify (Fit/Center/Left/Right/Top/Bottom/Stretch/Tile), Treat-as-One for multi-face.
- Move to Floor / Move to Ceiling (snap selection to nearest surface below/above). Ctrl+Shift+F/C.

## Done (Wave 2b -- Structural Tools)
- Clipping tool (split brushes along axis-aligned plane). Shift+X.
- Entity I/O system (Source-style input/output connections with parameter, delay, fire-once).
- Entity I/O dock UI (collapsible section in Entities tab with connection list).
- Brush entity visual indicators (color-coded overlays: cyan = func_detail, orange = triggers).

## Done (TrenchBroom-Inspired Architecture Improvements)
- Command collation: nudge/resize/paint undo entries merge within 1-second window.
- Transaction support: begin/commit/rollback for atomic multi-step operations (hollow, clip).
- Autosave failure notification: red warning label in dock when threaded writes fail.
- Central signal registry: 10 new signals on LevelRoot (brush/entity lifecycle, I/O, selection).
- Material manager persistence: save/load library to JSON, usage tracking, find unused.
- Entity definition system: data-driven HFEntityDef from JSON, replaces hardcoded brush entity classes.
- Gesture tracker base class: HFGesture for self-contained input gestures (ready for incremental adoption).

## Done (QuArK-Inspired Features)
- Declarative entity property forms: dock auto-generates typed controls from entity definition `properties` array.
- Duplicator / instanced geometry: create N copies with progressive offset, undo/redo, serialization.
- Multi-format `.map` export adapters: Classic Quake + Valve 220 via strategy-pattern writers.
- Formalized plugin API: `HFEditorTool` base class + `HFToolRegistry` for custom tools (external tools from `tools/`).

## Done (Blender-Inspired Architecture Improvements)
- Customizable keymaps: all shortcuts data-driven via `HFKeymap` JSON. Toolbar labels auto-update.
- User preferences: cross-session prefs (grid default, recent files, UI state) in `user://hammerforge_prefs.json`.
- Gesture poll system: `can_activate()` / `get_poll_fail_reason()` on tools. Buttons gray out when unavailable.
- Tag-based reconciler invalidation: dirty tags on brushes/paint for selective rebuild.
- Batched signal emission: multi-brush ops coalesce signals. Wired into transactions.
- Declarative tool settings: external tools expose schema; dock auto-generates UI controls.
- Status bar mode indicator: live mode/state display in dock footer.
- Input pass-through reorder: external tools can override built-in keyboard shortcuts.
- 36 new tests (keymap, user prefs, dirty tags). Total at time of wave: 344 tests across 22 files.

## Done (UX Intuitiveness Overhaul)
- Mode indicator banner: color-coded tool/stage/numeric display between toolbar and tabs.
- Toast notification system: transient messages for save/load/export/bake results and errors.
- Readable toolbar labels: icon + text (Draw, Select, Add, Sub, Paint, Ext Up, Ext Dn).
- Inline disabled hints: "Select a brush to use these tools" and face selection hints.
- First-run welcome panel: 5-step quick-start guide with "Don't show again" persistence.
- Context-sensitive next action hints: per-tab guidance labels that update based on scene state.
- Shortcuts quick-reference popup: "?" toolbar button lists all keybindings from keymap.
- Face hover highlight for extrude: semi-transparent green/red overlay on hovered faces.
- Clear selection button: "x" button in footer for visible deselect action.
- `user_message` signal on LevelRoot for subsystem-to-dock notification routing.

## Done (Built-in Prototype Textures)
- 150 SVG prototype textures (15 patterns x 10 colors) ship with the plugin for instant greyboxing.
- "Refresh Prototypes" button in Paint tab → Materials section for one-click palette population.
- `HFPrototypeTextures` static catalog class with query, load, and batch-load API.
- HTML preview page (`docs/prototype_textures_preview.html`) for browsing all textures.
- GUT tests (27 cases) and dedicated documentation.

## Done (FreeCAD-Inspired Improvements)
- Operation result reporting: `HFOpResult` return values with actionable fix hints on hollow/clip/delete. Failures auto-toast via `user_message`.
- Geometry-aware snap system: `HFSnapSystem` with Grid/Vertex/Center modes. Closest geometry candidate within threshold beats grid snap. G/V/C toggle buttons in dock.
- Live dimensions during drag: mode indicator banner shows real-time W x H x D during DRAG_BASE and DRAG_HEIGHT.
- Reference cleanup on deletion: deleting brushes auto-strips group/visgroup membership and cleans dangling entity I/O connections with toast notification.
- 44 new tests (op_result, snap_system, drag_dimensions, reference_cleanup). Total: 413 tests across 27 files.

## Done (Usability & Feature Upgrade)
- Bake failure toast notifications with contextual error messages.
- Silent failure logging across paint system (~20 guard clauses now emit warnings).
- Entity definition load error reporting (JSON parse, malformed entries, fallback).
- Paint layer rename UI (display_name field, "R" button, dialog, serialized in .hflevel).
- Axis lock visual indicator (color-coded X/Y/Z toggle buttons in dock, bidirectional sync).
- Entity I/O viewport visualization (colored ImmediateMesh lines, green/orange/yellow, throttled).
- Measurement/ruler tool (HFMeasureTool, tool_id=100, M key, distance + dX/dY/dZ decomposition).
- Terrain sculpting brushes (Raise/Lower/Smooth/Flatten, configurable strength/radius/falloff).
- Dock decomposition into 4 tab builder files (paint, entity, manage, selection tools).
- Baker test coverage (18 tests covering all public methods and structural filtering).
- Carve tool (HFCarveSystem, progressive-remainder box slicing, Ctrl+Shift+R, UV-preserving slice pieces).
- Decal/overlay system (HFDecalTool, tool_id=101, N key, raycast placement, live preview).
- Integration test suite (22 end-to-end tests across 8 categories).
- 99 new tests. Total: **512 tests across 30 files**.

## Done (UX Feature Wave — Tutorial, Hints, Subtract Preview, Prefabs)
- **Dynamic contextual hints**: viewport overlay hints per tool mode (draw, select, extrude, paint) with auto-fade tween and per-hint dismissal persistence via user prefs.
- **Searchable shortcut dialog**: `HFShortcutDialog` replaces static popup. Filterable Tree with categories (Tools, Editing, Paint, Axis Lock). Built from keymap data.
- **Interactive tutorial wizard**: `HFTutorialWizard` 5-step guided walkthrough (Draw → Subtract → Paint → Entity → Bake) with signal-driven auto-advance, validation, progress bar, and persistent resume.
- **Real-time subtract preview**: `HFSubtractPreview` system shows wireframe AABB intersection overlays between additive and subtractive brushes. Debounced rebuild, pooled MeshInstance3D, toggle in Settings.
- **Prefabs / reusable brush groups**: `HFPrefab` captures brush + entity selections as centroid-relative groups. Save/load `.hfprefab` JSON files. `HFPrefabLibrary` dock section with drag-and-drop instantiation. Entity I/O remapping on instantiate.
- 56 new tests (shortcut_dialog, tutorial_wizard, subtract_preview, prefab, user_prefs additions). Total: **568 tests across 34 files**.

## Done (Vertex Editing + Polygon Tool + Path Tool)
- **Vertex editing enhancements**: edge sub-mode (E key), edge selection/split/merge, wireframe overlay with color-coded selection/hover.
  - `split_edge()` inserts midpoint vertex (Ctrl+E). `merge_vertices()` merges to centroid (Ctrl+W).
  - Edge wireframe overlay in plugin.gd with ImmediateMesh PRIMITIVE_LINES pass.
  - New keymap bindings: `vertex_edge_mode`, `vertex_merge`, `vertex_split_edge`.
- **Polygon tool** (`hf_polygon_tool.gd`, tool_id=102, KEY_P): click convex vertices on ground plane, auto-close or Enter, drag height, creates brush with undo/redo. Convexity enforced via 2D cross product.
- **Path tool** (`hf_path_tool.gd`, tool_id=103, KEY_SEMICOLON): click waypoints, Enter to finalize, builds oriented-box segment brushes with miter joints at corners. Auto-grouped via shared group_id.
- Tool registry updated to pass `EditorUndoRedoManager` to tools on activation.
- `HFEditorTool` base class gains `undo_redo` member for brush-creating tools.
- 50 new tests (vertex_edges 19, polygon_tool 16, path_tool 15). Total: **622 tests across 38 files**.

## Done (Visual Texture Browser)
- **Visual material browser** (`HFMaterialBrowser`): thumbnail grid replacing text-only ItemList. 64px cells, 5 columns, actual SVG preview thumbnails.
- **Search and filters**: live text search, pattern dropdown (15 + All), color swatch row (10 buttons + All), view toggle (Prototypes / Palette / Favorites).
- **Favorites**: right-click to star materials. Favorites view filters to starred only.
- **Hover preview**: temporarily applies hovered material to selected faces in viewport.
- **Texture Picker** (T key): eyedropper raycasts to face under cursor, reads `material_idx`, sets as current browser selection.
- **Context menu**: Apply to Selected Faces, Apply to Whole Brush, Toggle Favorite, Copy Name.
- **Drag-and-drop**: thumbnails emit `hammerforge_material` drag data with preview, matching existing entity/preset pattern.
- "Load Prototypes" renamed to "Refresh Prototypes".

## Done (Player Spawn System + Quick Play Overhaul)
- **HFSpawnSystem** subsystem: spawn lookup with primary-flag priority, physics-based validation (floor raycast, capsule collision, headroom, below-map), auto-fix to suggested position, default spawn creation from brush centroid.
- **Quick Play validation flow**: pre-flight spawn check before every bake+play. Critical issues show fix dialog. Warnings toast and proceed. Missing spawn auto-creates a safe default.
- **Debug visualisation**: green/red capsule, floor/ceiling rays (ImmediateMesh), floor disc, collision sphere. Auto-cleanup timer or persistent toggle ("Preview Spawn Debug" in Manage tab).
- **Manage tab → Spawn section**: Validate Spawn, Create Default Spawn, Preview Spawn Debug toggle.
- **player_start entity** enhanced with `primary`, `angle`, `height_offset` properties. Color changed to cyan.
- **Playtest FPS controller** updated with `player_start_position` / `player_start_rotation_y` exports.
- 21 new tests. Total: **685 tests across 41 files**.

## Done (Smart Contextual Toolbar + Command Palette)
- **Floating context toolbar** (`HFContextToolbar`): appears in the 3D viewport with context-sensitive buttons (brush ops, face UV tools, entity quick-edit, shape picker, axis locks, vertex tools). Auto-shows/hides based on selection and tool state.
- **Auto-mode hint bar**: blue overlay during brush drawing shows current Add/Subtract mode with one-click toggle.
- **Command palette** (`HFHotkeyPalette`): searchable action list (Shift+? or F1) with live gray-out for unavailable actions. Filters by name or binding, Enter to execute.
- **Dock convenience methods**: `_apply_material_to_whole_brush()` and `_on_face_assign_material()` for toolbar-initiated material assignment.
- 32 new tests (context_toolbar 20, hotkey_palette 12). Total: **726 tests across 43 files**.

## Done (Improved Selection & Multi-Select)
- **Marquee / box selection**: drag-to-select brushes, entities, and faces in viewport. Semi-transparent blue overlay rectangle. Works in both Select mode and Face Select mode.
- **Selection filter popover** (`HFSelectionFilter`): bulk selection by normal (Walls/Floors/Ceilings), by material, Select Similar (faces by material+normal, brushes by size), by visgroup (dynamic buttons), by type (Detail/Structural).
- **Apply Last Texture** (Shift+T): rapid texture painting after using Texture Picker (T).
- **Select Similar hotkey** (Shift+S): quick-invoke similar face/brush selection from viewport.
- **Selection Filters hotkey** (Shift+F): opens filter popover at mouse position.
- **Enhanced status bar**: combined selection count badge ("Sel: 3 brushes, 5 faces").
- **Context toolbar**: new Sim/Last/Flt buttons, descriptive labels ("N brushes selected", "N faces on M brushes").
- **Command palette**: 3 new actions with live gray-out.
- 18 new tests (selection_features). Total: **753 tests across 44 files**.

## Done (Prefab & Group Enhancements — Reuse & Iteration Speed)
- **Prefab variants**: Multiple configurations per `.hfprefab` (e.g., wooden/metal/ornate door). Cycle on instances with Ctrl+Shift+V. Add via right-click library menu.
- **Live-linked prefabs**: "Save Linked" for bi-directional sync. Push instance changes to source. Propagate source to all linked instances with override preservation.
- **Enhanced prefab browser**: Search bar, tag filtering dropdown, variant count badges, right-click context menu (Add Variant, Edit Tags, Delete), Save Linked button.
- **Quick group-to-prefab**: Ctrl+Shift+P or Pfb context toolbar button for instant save with auto-generated name.
- **Prefab ghost overlay**: Cyan wireframe bounding box on hover over prefab instance nodes. Orange override markers.
- **HFPrefabSystem subsystem**: Instance registry with stable entity UIDs (not scene names), variant cycling, override tracking, state serialization with node re-tagging, propagation.
- **Prefab tags**: Comma-separated tags in `.hfprefab` files for categorization and search.
- **Stability fixes** (Apr 2026): GDScript inferred-type compilation errors, undo/redo node re-tagging, entity UID stability, dynamic toolbar prefab buttons, vertex system API corrections (context toolbar + hotkey palette), test orphan cleanup.
- 24 new tests. Total: **777 tests across 45 files**.

## Done (Bake & Quick Play Optimizations — Faster Feedback Loops)
- **Bake Selected**: bake only selected brushes, merging output into existing baked container.
- **Bake Changed**: bake only dirty-tagged brushes since last successful bake. Dirty tags survive failed bakes.
- **Bake preview modes**: Full / Wireframe / Proxy toggle. Wireframe uses `ShaderMaterial` with `render_mode wireframe`. Proxy uses unshaded semi-transparent material.
- **Bake time estimate**: ratio-based extrapolation from last bake duration. "Chunking recommended" tip for >500 brushes.
- **Bake issue detection**: degenerate brush (sev=2), oversized (sev=1), floating subtract (sev=1), overlapping subtracts (sev=1). Structured severity/message dicts via `HFValidationSystem.check_bake_issues()`.
- **Play from Camera**: temporary spawn teleport to editor camera with yaw propagation via `entity_data["angle"]`. Full restore on both success and error paths. Undo/redo support.
- **Play Selected Area**: temporary cordon from selection AABB. Cordon state saved/restored on both success and severity ≥ 2 error paths.
- Both new Quick Play modes share severity ≥ 2 blocking, auto-create, and fix-dialog patterns with standard Quick Play.
- 30 new tests (bake_system, bake_issues, quick_play_modes). Total: **807 tests across 47 files**.

## Done (I/O Connections & Entity Polish — Make Wiring Delightful)
- **Smart auto-routing**: Bézier curved connection lines with arrowheads, parallel route offset (0.3 units per route), color-coded by output type (cyan=OnTrigger, red=OnDamage, yellow=OnUse, green=OnOpen, magenta=OnBreak, orange=OnTimer). Fire-once pulses brighter; delayed connections dim proportionally.
- **I/O wiring panel** (`HFIOWiringPanel`): embedded in Entities tab with connection summary, outputs list, quick-wire form (output/target dropdown/input/param/delay/fire-once), and preset picker with target tag mapping.
- **Connection presets** (`HFIOPresets`): 6 built-in presets (Door+Light+Sound, Button→Toggle, Alarm Sequence, Pickup+Remove, Damage+Break, Timer Lights). Save entity connections as reusable user presets. Target tags map to actual names at apply time. User presets persist to editor config directory.
- **Highlight Connected**: toggle to pulse-highlight all linked entities (SphereMesh overlays with animated alpha). Summary label in context toolbar. Cross-UI sync between context toolbar and wiring panel via `set_pressed_no_signal()`.
- Context toolbar entity section gains HL toggle button and IOSummary label.
- 57 new tests (io_presets 21, io_visualizer_enhanced 20, io_highlight_sync 16). Total: **845 tests across 49 files**.

## Done (Learning & Discovery Aids — Lower the Onboarding Wall)
- **Coach marks** (`HFCoachMarks`): first-use floating step-by-step guides for 10 advanced tools (Polygon, Path, Carve, Vertex Edit, Extrude, Clip, Hollow, Measure, Decal, Surface Paint). Auto-triggered when tools are activated via keyboard, command palette, or context toolbar. Per-tool "Don't show again" persisted via user prefs.
- **Operation replay timeline** (`HFOperationReplay`): compact horizontal timeline of up to 20 recent operations with color-coded icons by action type. Hover for detail + elapsed time, click Replay to undo/redo to that history point. Toggle with Ctrl+Shift+T. Records undo versions and drives `UndoRedo.undo()`/`redo()`.
- **Enhanced command palette** (Ctrl+K): fuzzy search with subsequence matching (word-boundary and consecutive-char bonuses). "Did you mean: ..." suggestion label when no exact match. Caps at 5 fuzzy results. Ctrl+K added as toggle shortcut alongside Shift+?/F1.
- **Example library** (`HFExampleLibrary`): 5 built-in demo levels (Simple Room, Corridor with Doorway, Jump Puzzle Platforms, Hollowed Building, Simple Arena). Difficulty badges, tags, searchable browser, "Study This" annotations. Load clears current scene and instantiates from JSON definitions. Manage tab section (collapsed by default).
- 63 new tests across 4 files (coach_marks, operation_replay, fuzzy_search, example_library). Total: **944 tests across 54 files**.

## Done (Terrain & Organic Enhancements — Brush-to-Terrain Pipeline)
- **Convert Selection to Heightmap** (`HFBrushToHeightmap`): select brushes → rasterize top faces → create sculptable heightmap paint layer. Inherits `base_grid` origin/basis and `chunk_size` from the manager. Emits `paint_layer_changed` and triggers `regenerate_paint_layers()`. Dock button in Paint tab → Heightmap section.
- **Foliage & Scatter brush** (`HFScatterBrush`): circle and spline shapes, density/radius/height/slope filtering, scale variation, align-to-normal, deterministic seeding. Preview via MultiMesh (Dots/Wireframe/Full). Commit as permanent `MultiMeshInstance3D`. Full dock UI with mesh picker, shape selector, Preview/Scatter/Clear buttons. Spline mode uses selected node positions as control points.
- **Path tool extras**: auto-generate stairs (step brushes along sloped segments), railings (top rails + posts on both sides), and trim strips (edge strips with material auto-assign) along path tool paths. New `path_extra` setting (None/Stairs/Railing/Trim) with 8 additional parameters. Color-coded preview lines.
- **Dock integration tests** (`test_dock_terrain_integration.gd`): 30 tests covering full heightmap convert pipeline, scatter handlers, settings wiring, and layer lookups using real `LevelRoot` (with `auto_spawn_player=false`).
- 77 new tests across 4 files. Total: **974 tests across 55 files**.

## Done (Quality-of-Life & Polish — Small but Add Up)
- **Dark/Light Theme Sync** (`HFThemeUtils`): static helper class for theme-aware colors. All custom UI panels (context toolbar, coach marks, hotkey palette, operation replay, toasts, selection filter) replace hardcoded colors with theme-aware calls. Each gains `refresh_theme_colors()` called from `_on_editor_theme_changed()`.
- **Undo History Browser** (`HFHistoryBrowser`): replaces the plain ItemList in History section. Up to 30 entries with color-coded icons and 80x48 viewport thumbnails. Hover for enlarged preview, double-click to navigate undo history. Integrated undo/redo buttons.
- **Measurement Tool Improvements** (`HFMeasureTool`): persistent multi-ruler system (max 20, cycling colors). Shift+Click chains rulers. Angle display at shared vertices. Right-click to set snap reference line via `HFSnapSystem`. A key toggles align mode. Enhanced HUD with ruler count and alignment status.
- **Snap System Custom Lines** (`HFSnapSystem`): `set_custom_snap_line()` / `clear_custom_snap_line()` API for the measure tool's snap reference feature.
- **Performance Monitor Enhancement**: Entity Count, Vertex Estimate, Recommended Chunk Size, Health summary (green/yellow/red) with ProgressBar. New `level_root` helpers: `get_entity_count()`, `get_total_vertex_estimate()`, `get_recommended_chunk_size()`, `get_level_health()`.
- **One-Click Export Playtest Build**: Validates spawn, bakes, packs scene (baked + entities + default lighting), launches via `play_custom_scene()`. Auto-created spawns are undoable. New `level_root.export_playtest_scene()`.
- 117 new tests across 7 files. Total: **1091 tests across 62 files**.

## Done (Displacement & Bevel — Source-Style Terrain Sculpting)
- **Displacement surfaces** (`HFDisplacementData` + `HFDisplacementSystem`): Source Engine-style subdivided face grids on quad brush faces. Power 2-4 (5x5 to 17x17 vertices). Per-vertex distance offsets along face normal. Paint modes: Raise, Lower, Smooth, Noise, Alpha with quadratic falloff brush. Sew adjacent displacements along shared boundary vertices. Elevation scale and power resampling via bilinear interpolation. Integrates into `face.triangulate()` → `baker.bake_from_faces()` pipeline with per-vertex normals. Serializes in `.hflevel` via `to_dict()`/`from_dict()`.
- **Edge bevel (chamfer)** (`HFBevelSystem`): replace sharp edges with configurable segments (1-16) approximating a rounded profile. Slerp arc interpolation between face pull-back directions. Generates bevel strip quads, corner cap triangle fans at endpoints, and updates all neighboring face vertices for manifold topology. Requires vertex/edge mode with an edge selected.
- **Face inset** (`HFBevelSystem`): shrink a face inward by configurable distance, create connecting side quads. Optional height extrude along normal. Collapse guard rejects degenerate insets.
- **Dock UI**: Displacement collapsible section (create/destroy, power/elevation, paint mode dropdown, radius/strength, smooth/noise/sew, sew group). Bevel collapsible section (segments/radius for edge bevel, distance/height for face inset).
- **Full undo/redo**: all operations use `_try_undoable_action()` with return-value checking and `record_history()`. Continuous paint strokes capture pre-state on mouse-down and commit single undo action on mouse-up.
- **Plugin displacement paint input**: raycast plane intersection constrained by convex polygon bounds check. Paint gated behind paint mode enabled + Displacement section expanded.
- 55 new tests across 2 files (test_displacement 40, test_bevel 15). Total: **1172 tests across 69 files**.

## Done (Material Atlasing — Draw-Call Reduction)
- **Material atlas** (`HFMaterialAtlas`): shelf bin-packing of albedo textures into single atlas (up to 4096x4096). 2px gutter padding with edge-pixel extension. Half-texel UV inset. Per-face tiling detection splits hardware-repeat faces into separate surfaces. Baker `bake_from_faces()` integration with `remap_uv()`. `bake_use_atlas` LevelRoot property + dock checkbox + state persistence.
- 26 new tests. Total: **1203 tests across 70 files**.

## Done (Merge Tool — Brush Combination)
- **Merge brushes** (`HFBrushSystem.merge_brushes_by_ids()`): combine 2+ selected brushes into one CUSTOM brush. Full Transform3D pipeline (local→world→merged local), per-brush material_override as per-face material_idx. Ctrl+Shift+M keybinding, context toolbar Mrg button, command palette entry.
- 23 new tests. Total: **1226 tests across 71 files**.

## Done (Better Terrain Integration — Auto-Connectors)
- **Auto-connector system** (`hf_auto_connector.gd`): auto-detect cross-layer height boundaries during bake. 4-directional neighbor scan, 6-part canonical dedupe key (handles corners/T-junctions), flood-fill grouping, ramp/stairs/auto mode selection. Connectors include CollisionShape3D for navmesh parsing. Selection-only bakes skip connectors.
- **Bake pipeline integration**: `postprocess_bake()` with `selection_only` flag. `_append_auto_connectors()` creates meshes + collision shapes. Version-safe `_set_parsed_geometry_type()` static helper for Godot 4.6 navmesh property rename.
- **Dock UI**: Auto Connectors checkbox, Mode dropdown (Ramp/Stairs/Auto), Step H and Width spinboxes in Manage tab Bake section.
- 44 new tests (27 auto_connector + 17 bake_system integration). Total: **1270 tests across 73 files**.

## Done (Automated Culling — Runtime Occlusion from Brush Geometry)
- **Occluder generation bake pass** (`hf_bake_system.gd`): scans baked `MeshInstance3D` nodes (including inside `BakedChunk_*` intermediary nodes), groups coplanar triangles by normal (5° threshold) and plane distance (0.1 unit threshold), emits `OccluderInstance3D` with `ArrayOccluder3D` per group exceeding minimum area. Idempotent — re-bake replaces previous occluders.
- **Configurable thresholds**: `bake_generate_occluders` toggle and `bake_occluder_min_area` (default 4.0 world units²) on LevelRoot. Dock checkbox + SpinBox in Manage tab → Bake section. Settings persist in `.hflevel`.
- **Validation integration**: `check_occlusion_coverage()` runs inside `check_bake_issues()`. Reports missing-occluder warnings (enabled but empty) and coverage stats (occluder count + % of baked AABB surface).
- 13 new tests (`test_occluder_generation.gd`): flat mesh, chunked hierarchy, coplanar merge, plane separation, min-area filter, idempotency, postprocess toggle, validation. Total: **1283 tests across 75 files**.

## Done (Visual System Status — Classic Editor Feedback)
- **Operation-coded wireframe colors**: green wireframe overlay for additive brushes, red for subtractive (existing), blue spectrum for brush entities (func_detail/trigger/func_wall/other). New `_apply_additive_wireframe_overlay()` mirrors subtract overlay. Both overlays refresh on face-preview mesh rebuilds.
- **Grid size viewport indicator**: persistent "Grid: N" label in shortcut HUD with `%g` exact formatting. Flash-on-change (bright yellow-white → fade 0.6s) via tween.
- **Grid size hotkeys** (`[` / `]`): halve/double grid snap. Registered as `grid_decrease` / `grid_increase` in keymap (user-remappable). Clamped 0.125–512.
- **Signal-driven HUD sync**: `grid_snap_applied` signal on dock ensures all grid change origins (SpinBox, snap buttons, quick-property, hotkeys, state restore) update the HUD.
- **Test cleanup fixes**: resource leak fixes in test_brush_to_heightmap, test_context_toolbar, test_selection_features. Orphan/leak shutdown errors eliminated.
- Total: **1370 tests**, full suite passes in 91.7s.

## Future (Wave 3 -- Polish)
- Multiple simultaneous cordons.
- Multi-tool presets for common workflows.
- Additional bake pipelines (merge strategies, export helpers).
- Snap-to-edge and snap-to-perpendicular modes for the snap system.
- Preference packs (e.g. "Speedrunner", "Precision") for one-click workflow presets.
- Formalized plugin API (`HFEditorPlugin` base class for custom tool scripts with menu/toolbar hooks).
- Per-project entity definition files (game pak separation — different entity sets per project).
- Bezier patch editing (control-point-grid surfaces as first-class brush type).

## Out of Scope (for now)
- Real-time CSG of full scenes.
- Arbitrary mesh editing inside the editor.
- 3D skybox preview (Godot uses WorldEnvironment natively).
- In-editor physics simulation (Godot has a built-in physics debugger).
