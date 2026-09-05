# Roadmap

Last updated: September 3, 2026

This roadmap is a directional plan. Items may change based on user feedback.

## Done (Viewport Visual Clarity and Lifecycle Safety)

- Removed the always-on additive triangle wireframe; normal brushes now read as simple solid forms.
- Replaced topology-based hover boxes with concise structural edges, centralized box-selection outlines, and added accurate face-boundary selection for custom brushes.
- Made subtract/entity overlays reusable and cleaned leaked drag-history visuals from older sessions.
- Reconciled persisted baked geometry and prevented repeated bakes from accumulating anonymous duplicate containers.

Priorities are informed by a Hammer Editor gap analysis — see GAP_ANALYSIS.md for details.

## Done (Wave 1 -- Hammer-Inspired Quick Wins)
- Visgroups (visibility groups) with per-group show/hide and dock UI.
- Brush/entity grouping with Ctrl+G/U and group-aware selection.
- Texture lock (UV alignment preserved on move/resize/rotation).
- Cordon (partial bake) with AABB filter and wireframe visualization.
- GUT unit test suite (47 tests) with CI integration.

## Done (Dock UX Overhaul)
- Consolidated 8 tabs to 4 (now displayed as Build, Paint, Objects, Test).
- Collapsible sections with separators, indented content, persisted collapsed state.
- Selection tools (hollow, clip, move, tie, duplicator) contextually shown in the Build tab.
- Compact toolbar (single-char labels with tooltips, VSeparator before extrude).
- Signal-driven paint/material/surface paint sync (replaced 10-frame polling).
- UV Justify 3×2 grid layout. Standardized 70px label widths, 32px +/- buttons.
- "No LevelRoot" banner and autosave warning defined in dock.tscn.
- Sticky LevelRoot discovery (deep recursive search, no re-selection needed).
- Test tab trimmed: Actions has New Level/floor/cuts/clear.

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
- Entity I/O dock UI (collapsible section in the Objects tab with connection list).
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
- Geometry-aware snap system: `HFSnapSystem` with Grid, Vertex, Center, Edge, and Perpendicular modes. Closest geometry candidate within threshold beats grid snap. G/V/C/E/P toggle buttons in the dock.
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
- **Real-time subtract preview**: `HFSubtractPreview` CSG-intersects overlapping additive/subtract DraftBrushes and shows the cut volume; AABB wireframes remain as fallback.
- **Prefabs / reusable brush groups**: `HFPrefab` captures brush + entity selections as centroid-relative groups. Save/load `.hfprefab` JSON files. `HFPrefabLibrary` dock section with drag-and-drop instantiation. Entity I/O remapping on instantiate.
- 56 new tests (shortcut_dialog, tutorial_wizard, subtract_preview, prefab, user_prefs additions). Total: **568 tests across 34 files**.

## Done (Vertex Editing + Polygon Tool + Path Tool)
- **Vertex editing enhancements**: edge sub-mode (E key), edge selection/split/merge, wireframe overlay with color-coded selection/hover.
  - `split_edge()` inserts midpoint vertex (Ctrl+E). `merge_vertices()` merges to centroid (Ctrl+W).
  - Edge wireframe overlay in plugin.gd with ImmediateMesh PRIMITIVE_LINES pass.
  - New keymap bindings: `vertex_edge_mode`, `vertex_merge`, `vertex_split_edge`.
- **Polygon tool** (`hf_polygon_tool.gd`, tool_id=102, KEY_P): place the first convex vertex on an exact visible surface or the forward construction plane, continue from that horizontal placement plane through the shared snap pipeline, auto-close or Enter, drag height, and create a brush with undo/redo. Convexity is enforced via 2D cross product.
- **Path tool** (`hf_path_tool.gd`, tool_id=103, KEY_SEMICOLON): place the first waypoint through the shared exact-surface raycast and snap pipeline, continue from its horizontal placement plane, then press Enter to build oriented-box segment brushes with miter joints at corners. Brushes are auto-grouped via a shared group_id.
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
- **Debug visualisation**: green/red capsule, floor/ceiling rays (ImmediateMesh), floor disc, collision sphere. Auto-cleanup timer or persistent toggle ("Preview Spawn Debug" in the Test tab).
- **Test tab → Spawn section**: Validate Spawn, Create Default Spawn, Preview Spawn Debug toggle.
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
- **I/O wiring panel** (`HFIOWiringPanel`): embedded in the Objects tab with connection summary, outputs list, quick-wire form (output/target dropdown/input/param/delay/fire-once), and preset picker with target tag mapping.
- **Connection presets** (`HFIOPresets`): 6 built-in presets (Door+Light+Sound, Button→Toggle, Alarm Sequence, Pickup+Remove, Damage+Break, Timer Lights). Save entity connections as reusable user presets. Target tags map to actual names at apply time. User presets persist to editor config directory.
- **Highlight Connected**: toggle to pulse-highlight all linked entities (SphereMesh overlays with animated alpha). Summary label in context toolbar. Cross-UI sync between context toolbar and wiring panel via `set_pressed_no_signal()`.
- Context toolbar entity section gains HL toggle button and IOSummary label.
- 57 new tests (io_presets 21, io_visualizer_enhanced 20, io_highlight_sync 16). Total: **845 tests across 49 files**.

## Done (Learning & Discovery Aids — Lower the Onboarding Wall)
- **Coach marks** (`HFCoachMarks`): first-use floating step-by-step guides for 10 advanced tools (Polygon, Path, Carve, Vertex Edit, Extrude, Clip, Hollow, Measure, Decal, Surface Paint). Auto-triggered when tools are activated via keyboard, command palette, or context toolbar. Per-tool "Don't show again" persisted via user prefs.
- **Operation replay timeline** (`HFOperationReplay`): compact horizontal timeline of up to 20 recent operations with color-coded icons by action type. Hover for detail + elapsed time, click Replay to undo/redo to that history point. Toggle with Ctrl+Shift+T. Records undo versions and drives `UndoRedo.undo()`/`redo()`.
- **Enhanced command palette** (Ctrl+K): fuzzy search with subsequence matching (word-boundary and consecutive-char bonuses). "Did you mean: ..." suggestion label when no exact match. Caps at 5 fuzzy results. Ctrl+K added as toggle shortcut alongside Shift+?/F1.
- **Example library** (`HFExampleLibrary`): 5 built-in demo levels (Simple Room, Corridor with Doorway, Jump Puzzle Platforms, Hollowed Building, Simple Arena). Difficulty badges, tags, searchable browser, "Study This" annotations. Load clears current scene and instantiates from JSON definitions. Test tab section (collapsed by default).
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
- **Measurement Tool Improvements** (`HFMeasureTool`): persistent multi-ruler system (max 20, cycling colors). Shift+Click chains rulers. Angle display at shared vertices. Ctrl+Click sets a snap reference line via `HFSnapSystem` while plain RMB remains available for camera navigation. A key toggles align mode. Enhanced HUD with ruler count and alignment status.
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
- **Dock UI**: Auto Connectors checkbox, Mode dropdown (Ramp/Stairs/Auto), Step H and Width spinboxes in the Test tab Bake section.
- 44 new tests (27 auto_connector + 17 bake_system integration). Total: **1270 tests across 73 files**.

## Done (Automated Culling — Runtime Occlusion from Brush Geometry)
- **Occluder generation bake pass** (`hf_bake_system.gd`): scans baked `MeshInstance3D` nodes (including inside `BakedChunk_*` intermediary nodes), groups coplanar triangles by normal (5° threshold) and plane distance (0.1 unit threshold), emits `OccluderInstance3D` with `ArrayOccluder3D` per group exceeding minimum area. Idempotent — re-bake replaces previous occluders.
- **Configurable thresholds**: `bake_generate_occluders` toggle and `bake_occluder_min_area` (default 4.0 world units²) on LevelRoot. Dock checkbox + SpinBox in Test → Bake. Settings persist in `.hflevel`.
- **Validation integration**: `check_occlusion_coverage()` runs inside `check_bake_issues()`. Reports missing-occluder warnings (enabled but empty) and coverage stats (occluder count + % of baked AABB surface).
- 13 new tests (`test_occluder_generation.gd`): flat mesh, chunked hierarchy, coplanar merge, plane separation, min-area filter, idempotency, postprocess toggle, validation. Total: **1283 tests across 75 files**.

## Done (Visual System Status — Classic Editor Feedback)
- **Operation-coded wireframe colors (superseded by the July 2026 clarity pass)**: this release originally added green wireframe to additive brushes plus red/blue semantic overlays. Additive wireframe was later removed after user feedback; subtract/entity cues remain, and hover/selection now use structural edges only.
- **Grid size viewport indicator**: persistent "Grid: N" label in the shortcut HUD. Whole numbers print as integers; fractional snaps print through `String.num()` with the padding zeros trimmed, since GDScript has no `%g`. Flash-on-change (bright yellow-white → fade 0.6s) via tween.
- **Grid size hotkeys** (`[` / `]`): halve/double grid snap. Registered as `grid_decrease` / `grid_increase` in keymap (user-remappable). Clamped 0.125–512.
- **Signal-driven HUD sync**: `grid_snap_applied` signal on dock ensures all grid change origins (SpinBox, snap buttons, quick-property, hotkeys, state restore) update the HUD.
- **Test cleanup fixes**: resource leak fixes in test_brush_to_heightmap, test_context_toolbar, test_selection_features. Orphan/leak shutdown errors eliminated.
- Total: **1370 tests**, full suite passes in 91.7s.

## Done (Error Prevention & Forgiveness — Non-Destructive Defaults)
- **Carve geometry preview** (`HFCarvePreview`): green wireframe overlay shows resulting slice pieces before committing. Confirmation dialog with Cancel to abort. Both hotkey and context toolbar paths covered.
- **Clip geometry preview** (`HFClipPreview`): cyan wireframe for resulting halves + semi-transparent orange split plane quad. Confirmation dialog before commit.
- **Hollow geometry preview** (`HFHollowPreview`): yellow wireframe shows 6 wall pieces before commit. Supports real-time thickness updates. Confirmation dialog on both dock button and hotkey paths.
- **Bulk delete confirmation**: 3+ brush deletes prompt confirmation ("Delete N brushes? This can be undone with Ctrl+Z"). Single/dual brush deletes remain instant.
- **Dialog lifecycle safety**: `_pending_dialogs` tracking in plugin.gd with auto-free on teardown. All confirmed callbacks guard `is_instance_valid(root)` against scene-change invalidation.

## Done (Onboarding & Test Quality)
- **New HammerForge Level** template button in Test → Actions. One-click creation of floor + DefaultSun (DirectionalLight3D) + player spawn. Fully undoable via `capture_sun_info()` / `restore_sun_info()` in state system. DefaultSun is duplicated into Test Level / Export Playtest scenes; fallback PlaytestSun yaw corrected from -30 to +30.
- **HFLog test-aware warning wrapper** (`hf_log.gd`): `HFLog.warn()` replaces `push_warning()` at 15 negative-path sites. Tests use `begin_test_capture()` / `end_test_capture()` / `get_captured_warnings()` to suppress expected warnings and assert they were emitted. Eliminates trailing WARNING noise from the test suite.
- **README onboarding**: Godot version requirement line, Quick Start GIF placeholder, bolded upgrade link.

## Done (Code-Quality Utilities — Simplification Phase 1)
- **Eight shared utility classes extracted** from the dock + plugin monoliths to reduce duplication and improve testability. None change runtime behavior; all existing call sites delegate. Parse-clean throughout (`godot --check-only` exit 0).
  - `HFSystem` (`systems/hf_system.gd`): base lifecycle class for subsystems (`_init(root)`, `destroy`, `clear`, `set_enabled`, `is_enabled`, `_has_nodes`). Four preview systems migrated.
  - `HFUIFactory` (`ui/hf_ui_factory.gd`): UI control factory — `make_label_row/spin/check/button/option/separator/spin_row/section_header`. Dock `_make_*` helpers delegate; 100+ call sites flow through it. Two tab builders migrated to call directly.
  - `HFValidation` (`hf_validation.gd`): null/structure guards for LevelRoot containers (`is_valid_root`, `has_draft_containers`, `has_entity_container`, `has_baked_container`, `has_node`, `has_nodes`, `require_nodes`).
  - `HFEditorTheme` (`ui/hf_editor_theme.gd`): editor icon/color/stylebox lookup with graceful fallbacks (`find_editor_icon`, `has_editor_icon`, `get_editor_icon`, `get_editor_color`, `resolve_stylebox`, `style_toolbar_button`).
  - `HFUndoNav` (`ui/hf_undo_nav.gd`): per-scene `EditorUndoRedoManager` navigation (`get_scene_history_id`, `get_scene_undo_redo`, `navigate_to_version`).
  - `HFEntityPropUtils` (`ui/hf_entity_prop_utils.gd`): collapses `DraftEntity.entity_data` vs `Node3D.meta` dual-write (`get_entity_data`, `get_entity_type`, `set_entity_property`, `set_entity_vec3_axis`, `coerce_default`, `find_definition`).
  - `HFTooltipText` (`ui/hf_tooltip_text.gd`): static catalog of 100+ tooltip strings keyed by dock control-property name. `dock._apply_all_tooltips` reduced from ~200 lines to 3.
  - `HFDialogManager` (`plugin_dialogs.gd`): tracks confirmation dialogs with auto-removal on `tree_exiting` and bulk `cleanup()` on plugin teardown.
- **dock.gd reduction**: 7,001 → 6,692 lines (–309, –4.4%). plugin.gd: –4 lines (responsibility separation rather than LOC).
- **75+ new test cases across 8 files**: `test_ui_factory`, `test_hf_validation`, `test_hf_system`, `test_hf_undo_nav`, `test_entity_prop_utils`, `test_hf_tooltip_text`, `test_hf_dialog_manager`, `test_hf_editor_theme`.

## Done (Subtract preview, project entities, map faces — August 2026)
- Subtract preview iterates DraftBrushes and mesh bounds.
- `res://hammerforge_entities.json` overlays plugin entity definitions.
- `.map` import/export of non-axis-aligned brushes uses CUSTOM faces.

## Done (Runtime export and entity reliability — September 2026)
- Playtest export now creates a playable scene with a player at the selected spawn, recursively owned nested geometry/collision, default lighting, and auto-wired entity I/O.
- Export preserves world transforms when content is reparented into the packed playtest scene.
- Foliage and scatter MultiMeshes preserve container-local placement instead of shifting when their parent is transformed.
- Brush-entity I/O survives bake/export and cleanup, including `func_detail` and trigger post-processing.
- Validation accepts valid alternate `Entities` containers, and polygon/path tools retain height and trim material settings.

## Done (Registry collapse, signal batching, snap-to-edge — August 2026)
- `BrushManager` no longer owns or frees brush nodes; the system cache is the live list.
- `create_brushes_from_infos`, `delete_brushes_by_id`, `nudge_brushes_by_id`, and `delete_managed_nodes` wrap `begin_signal_batch()` / `end_signal_batch()`.
- Snap-to-edge mode (bit 8) with a dock Edges toggle.

## Done (Core-Loop Freeze — August 2026)
- Default product is Draw → material → entity → bake → Test Level.
- Power-user overlays (radial menu, coach marks, operation replay) are opt-in.
- Brush cache is the brush-list authority; `BrushManager` writes are null-safe.
- Dead code removed: welcome panel, unused `BrushPrefab`, `debug_heightmap`, archived quadrant view.
- Subtract preview remained opt-in and now uses a live CSG cut overlay with an AABB wireframe fallback.
- Core characterization tests added for `HFBrushSystem`, `HFPaintSystem`, overlay prefs, and empty baker merge.
- Docs and `plugin.cfg` updated to match the code. Wave 3 features stay deferred.

## Done (Paint Hot Paths — September 2026)
Investigation of [#39](https://github.com/saworbit/hammerforge/issues/39). The issue proposed replacing
`Image.get_pixel()` / `set_pixel()` loops with `PackedByteArray` indexing. Benchmarking on Godot 4.7
showed the opposite: over 65,536 texels, `get_pixel` costs 2.20 ms against 6.68 ms for four packed byte
reads, and `set_pixel` costs 1.85 ms against 4.44 ms for four packed byte writes. A packed rewrite of the
composite measured ~7x slower, so it was not shipped. What landed instead:

- **Composite memoisation**: `FaceData.get_painted_albedo()` caches its result keyed on `max_size`, layer
  count, and per layer the texture identity/size, blend mode, opacity, and a content hash of the weight
  image. Hashing a 256x256 weight image costs 0.071 ms against 61.7 ms for the composite. `rebuild_preview()`
  fires from 27 call sites, including once per surface-paint sample, and previously recomposited every
  painted face of the brush each time. `invalidate_painted_albedo()` is the escape hatch.
- **Surface paint crash fix**: `SurfacePaint.paint_at_uv()` called Godot 3's `Image.lock()` / `unlock()`,
  aborting the function before writing. Every surface paint stroke was silently discarded.
- **Composite input safety**: the source texture image is copied (and decompressed when VRAM-compressed)
  before resize, so `Texture2D.get_image()` results are never mutated in place.
- **`tools/benchmark_paint_hot_paths.gd`**: reproducible measurements for all three areas.
- 39 new tests in `tests/test_paint_hot_paths.gd`, covering three paths that had none. Suite total: **1,829 tests across 105 files**.

Still open from #39: a sculpt-smooth stamp scales as the brush area. At 256x256 it costs 0.54 ms at
radius 8 and 2.2 ms at radius 16 (interactive), but 8.8 ms at radius 32 and 35.0 ms at radius 64. Fixing
the large-radius case needs a different algorithm (separable blur or a dirty-rect pass), not a faster
per-texel loop.

## Done (PBR Material Atlasing — September 2026)
Closes [#24](https://github.com/saworbit/hammerforge/issues/24). `HFMaterialAtlas` only ever inspected
`albedo_texture`, so a material's normal, roughness, metallic, and emission maps were dropped during a
bake with **Material Atlas** on.

- **Parallel channel atlases**: each PBR slot that at least one packed material supplies gets its own
  atlas built over the *same* placements as albedo, so the existing remapped UVs address all of them.
  Slots nobody uses are skipped entirely and cost nothing.
- **Flat tiles for non-suppliers**: a material without a map for a slot contributes a constant tile —
  its own `roughness` / `metallic` scalar written to every colour channel (so it reads the same through
  any `TextureChannel` selector), a flat tangent-space normal, or its emission tint. Mixing mapped and
  unmapped materials in one atlas is safe.
- **Honest refusal instead of silent corruption**: the atlas material holds one multiplier and one
  channel selector per slot. When suppliers disagree — on `normal_scale`, on `roughness_texture_channel`,
  on a multiplier that would distort the constant tiles — the slot is recorded in
  `AtlasResult.skipped_channels` with a reason and left out. Albedo still atlases.
- **Emission neutrality follows the operator**: Godot's default `EMISSION_OP_ADD` adds the tint to the
  map, so black is the identity there; `EMISSION_OP_MULTIPLY` needs white. Getting this backwards was
  caught by a test before it shipped.
- **Gutter fill rewritten natively**: `blit_rect` / `fill_rect` over the tile's edge rows and columns
  replaces the per-texel `get_pixel` / `set_pixel` loop — 11x faster on a 128px tile, and it now runs
  once per atlas rather than once.
- `tools/benchmark_bake_atlas.gd` keeps both measurements reproducible.
- **Skips are reported, not just recorded**: every dropped slot also emits an `HFLog.warn()` naming the
  slot and the reason, so the editor log says what happened. A supplied texture that cannot be read drops
  the whole slot rather than substituting a flat tile and shipping a bake that looks subtly wrong.
- **`HFLog.warn()` fixed along the way**: routing skips through it exposed that `_capture_warning()`
  passed a null default to `Engine.get_meta()`, which fails rather than defaulting. Every warning in the
  running editor printed "Method/function failed" beside it.
- 32 new tests in `tests/test_material_atlas_pbr.gd` plus 6 in `tests/test_hf_log.gd`. Suite total:
  **1,867 tests across 107 files**.

Not covered: `ORMMaterial3D` is still rejected whole (it was never atlased, so nothing regressed).
Packing it would mean composing occlusion/roughness/metallic into one texture, which needs per-texel
channel swizzling — the one operation with no native `Image` equivalent.

## Done (HammerForge Console — September 2026)
Nothing in the editor named HammerForge. The left dock's tab read **"Dock"** and carried no icon, the
settings were split between a collapsed *Settings* section and an *Advanced Bake* section, and warnings
went only to Godot's shared Output panel. There was nowhere to ask "is this level in a state I can bake
and run".

- **A main screen**, in the switcher beside 2D / 3D / Script, wearing the mark. That row is the only
  part of the editor chrome that draws a plugin icon: Godot 4.7's bottom panel is text-only, and a
  docked control's icon lives on the `EditorDock` wrapper behind `force_show_icon`. The switcher draws
  the icon at its texture size, so `docs/brand/build.py` emits a 32px `hf_mark_editor.svg` for it.
- **Status board** (`hf_status_board.gd`): eight checks as red / amber / green lamps — level root,
  geometry budget, bake freshness, level check, material palette, player spawn, autosave, session log.
  Each names what was measured, the threshold it is measured against, and the one action that resolves
  it. Grey means "not measured", never a fault. `evaluate()` is pure, so every threshold is tested
  without an editor. Lamps carry a drawn glyph as well as a hue.
- **Controls tab** (`ui/hf_console_controls.gd`): every switch on one screen, grouped Viewport / Bake /
  Safety net, captioned, and searchable by caption as well as by name. Written *through* the dock's own
  controls, so the dock's handlers stay in charge of side effects and the two surfaces cannot disagree.
- **Log tab** (`hf_console_log.gd`, `ui/hf_console_log_view.gd`): HammerForge's own messages, capped at
  600 entries with repeat collapsing, BBCode escaping, and a deferred append from the bake thread pool.
  `HFLog.warn()` and `LevelRoot`'s `user_message` signal both feed it. Level counts double as the filter.
- **Viewport lamp** (`ui/hf_status_strip.gd`): the overall severity and summary in the 3D toolbar, on a
  slower beat, reading the Console's own evaluation. A main screen is not visible while you build.
- **Costs nothing idle**: the poll stops when the Console is off screen, only the visible tab is redrawn,
  and the two reads that walk every brush and face run on a slower beat or on **Re-check**.
- **Shortcut HUD layout faults found alongside**: it had never been laid out — a zero-minimum `Control`
  in a `BoxContainer` toolbar, drawing seven lines out of a zero-width slot with six painted over by the
  viewport and the seventh across the context toolbar; three labels sharing one `MarginContainer` rect;
  and `%g`, which GDScript does not have, printing `Grid: %g` for every fractional snap.
- 129 new tests across `test_console_log.gd`, `test_status_board.gd`, `test_console_panel.gd`, and
  `test_shortcut_hud_layout.gd`, including drift guards that fail if a Controls switch stops addressing a
  property `dock.gd` or `level_root.gd` declares. Total: **2,200 tests across 125 scripts**.
- `tools/hf_console_preview.gd` renders the three tabs to PNGs so a layout change can be judged without
  opening the editor.

## Future (Wave 3 -- Polish)
- Multiple simultaneous cordons.
- Multi-tool presets for common workflows.
- Additional bake pipelines (merge strategies, export helpers).
- Preference packs (e.g. "Speedrunner", "Precision") for one-click workflow presets.
- Formalized plugin API (`HFEditorPlugin` base class for custom tool scripts with menu/toolbar hooks).
- Bezier patch editing (control-point-grid surfaces as first-class brush type).

## Future (Simplification Phase 2 — Continued Code-Quality Work)
The May 2026 simplification phase 1 landed shared utilities and migrated low-risk call sites. The following items continue that initiative but each requires a dedicated session with interactive UI/bake validation, or a profiling pass, before landing safely.

### Continued dock.gd decomposition
The current 5,475-line file is still dominated by `_on_*` signal handlers wired to dock-internal state.
- Split into per-tab handler files: `dock_brush_handler.gd` (done), `dock_paint_handler.gd` (done), `dock_entity_handler.gd` (done), `dock_manage_handler.gd` (Test-tab bake/play done), and `dock_visgroup_handler.gd` (visgroups, grouping, and cordon done). Target dock.gd shell at ~1,500 lines.
- File dialogs and import/export callbacks delegate to `dock_file_handler.gd`; settings and `LevelRoot` signal lifecycle delegate to `dock_connections.gd`.
- Consolidate the entity-properties UI builder and the external-tool-settings UI builder (both schema-driven; share ~100 lines of dispatch logic).
- Migrate `paint_tab_builder.gd` (50 call sites) and `manage_tab_builder.gd` (58 call sites) from `dock._make_*` to direct `HFUIFactory` calls. Mechanical churn — wait until shared with another tab-builder change.

### plugin.gd decomposition (Phase 3b)
Current: 2,506 lines. Remaining work is concentrated in other coordinator responsibilities:
- `_forward_3d_gui_input` and native RMB camera ownership now live in `plugin_viewport_input.gd` (`HFPluginViewportInput`).
- Floor, surface, and displacement paint input now lives in `plugin_paint_input.gd` (`HFPluginPaintInput`).
- Draw, extrude, motion, face hover, and prefab hover now live in `plugin_pointer_tools.gd` (`HFPluginPointerTools`).
- Native object/Face Select pointer arbitration and face marquee picking now live in `plugin_selection_input.gd` (`HFPluginSelectionInput`).
- EditorSelection synchronization, managed-owner normalization, native group expansion, and mixed-selection action guards now live in `plugin_selection_state.gd` (`HFPluginSelectionState`).
- Power-user overlay lifecycle, vertex rendering, marquee drawing, quick-property behavior, and coach-mark routing now delegate to `plugin_overlays.gd` (`HFPluginOverlays`).
- `_handle_keyboard_input` now delegates to `plugin_input_router.gd` (`HFPluginInputRouter.handle_keyboard`).
- Numeric draw/extrude dimension parsing, live preview, and commit now delegate to `plugin_numeric_input.gd` (`HFPluginNumericInput`).
- `_dispatch_viewport_action` is a thin wrapper around `HFPluginCommands.execute`.
- `_on_context_toolbar_action` and `_on_hotkey_palette_action` now route through `plugin_commands.gd` (`HFPluginCommands.execute`).
- Undoable delete, duplicate, nudge, group/ungroup, hollow, merge, vertical move, clip, and carve execution now lives in `plugin_edit_actions.gd` (`HFPluginEditActions`).
- Entity, brush-preset, prefab, and material viewport drag-and-drop handling now lives in `plugin_drop_handler.gd` (`HFPluginDropHandler`).
- `_handle_vertex_input` now delegates to `plugin_vertex_input.gd` (`HFPluginVertexInput.handle`).
- `_update_hud_context` and `_update_context_toolbar_state` now delegate to `plugin_hud.gd` (`HFPluginHud`).

Completion is responsibility-based rather than tied to an arbitrary line count. This phase is done when `plugin.gd` owns EditorPlugin lifecycle, composition, LevelRoot discovery, undo-manager wiring, and short high-level coordination; cohesive input, overlay, command, HUD, selection, dialog, and tool behavior lives in focused modules; remaining large workflows are not hidden behind artificial pass-through layers; and boundary tests protect the extracted responsibilities. The current line count is a progress indicator, not an acceptance threshold.

### Runtime system boundary in level_root.gd (Phase 3a, complete)
- Export templates eagerly initialize only the brush, entity, bake, paint, and file core needed to load and run levels.
- Twenty editor-only services are loaded dynamically only when `Engine.is_editor_hint()` or the `editor` feature is present. This keeps drawing, grid, snap, selection, preview, prefab-authoring, validation, undo, displacement, bevel, and related authoring graphs out of exported games.
- Headless editor tests retain the complete tool graph, with focused export-playtest coverage guarding the runtime boundary.

### Risk-focused test gaps
The current suite covers 2,226 tests across 126 scripts, including the large brush, bake, paint, vertex, baker, brush-instance, and map-I/O systems. Remaining work is concentrated in failure semantics and scale-sensitive paths rather than wholly untested systems:
- crash-safe destination replacement and truthful manual-save completion ([#33](https://github.com/saworbit/hammerforge/issues/33), [#51](https://github.com/saworbit/hammerforge/issues/51));
- quoted `.map` property round-trips ([#32](https://github.com/saworbit/hammerforge/issues/32));
- non-blocking threaded merge/finalization ([#35](https://github.com/saworbit/hammerforge/issues/35));
- PBR material fidelity and paint export coverage ([#24](https://github.com/saworbit/hammerforge/issues/24), [#39](https://github.com/saworbit/hammerforge/issues/39)).

### Apply HFValidation broadly
Currently applied to two `HFBrushSystem` methods as demonstration. Roughly 300 inline `if not root.<container>:` patterns remain across `hf_brush_system`, `hf_paint_system`, `hf_bake_system`, `hf_entity_system`, `baker`. Single-property guards are 1-line either way; the win is centralization. Apply opportunistically when touching each system, not as a bulk sweep.

### Performance enhancements (Phase 4) — needs profiling first
- **Mesh pooling**: `SubtractPreview`, bake preview, extrude preview, and now Carve/Clip/Hollow previews all create/destroy `MeshInstance3D` nodes frequently. A shared pool with `acquire()`/`release()` could reduce GC pressure. Needs profiling to confirm allocation hotspots.

## Out of Scope (for now)
- Real-time CSG of full scenes.
- Arbitrary mesh editing inside the editor.
- 3D skybox preview (Godot uses WorldEnvironment natively).
- In-editor physics simulation (Godot has a built-in physics debugger).
