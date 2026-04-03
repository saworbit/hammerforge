# Roadmap

Last updated: April 3, 2026

This roadmap is a directional plan. Items may change based on user feedback.
Priorities are informed by a Hammer Editor gap analysis — see GAP_ANALYSIS.md for details.

## Done (Wave 1 -- Hammer-Inspired Quick Wins)
- Visgroups (visibility groups) with per-group show/hide and dock UI.
- Brush/entity grouping with Ctrl+G/U and group-aware selection.
- Texture lock (UV alignment preserved on move/resize).
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
- Texture alignment panel: Justify (Fit/Center/Left/Right/Top/Bottom), Treat-as-One for multi-face.
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
- Carve tool (HFCarveSystem, progressive-remainder box slicing, Ctrl+Shift+R).
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

## Next (Wave 2c remaining)
- Displacement sewing (stitch adjacent heightmap edges to share vertices).
- Material atlasing for large scenes.

## Future (Wave 3 -- Polish)
- Merge tool (combine two adjacent brushes into one convex brush).
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
