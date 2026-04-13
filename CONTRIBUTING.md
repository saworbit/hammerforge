# Contributing

Thanks for helping improve HammerForge.

## Scope
- Small, focused changes are preferred.
- Large changes should start with an issue or discussion before a PR.
- Keep changes aligned with the current MVP and architecture.

## How To Contribute
1. Open an issue describing the problem and proposed fix.
2. Keep PRs small and limited to one topic.
3. Update docs and tests when behavior changes.
4. Run formatting, lint, and test checks before submitting (see below).

## Code Expectations
- Follow the subsystem architecture (LevelRoot is the public API).
- Prefer undo actions that use stable IDs and state snapshots. Use `collation_tag` for rapid operations.
- Use transactions (`begin_transaction` / `commit_transaction`) for multi-step brush operations.
- New entity types go in `entities.json`, not hardcoded in GDScript.
- New input tools should subclass `HFGesture` for self-contained state management.
- Subscribe to LevelRoot signals instead of polling in `_process()`.
- **Keyboard shortcuts** go through `_keymap.matches("action_name", event)`, never hardcoded `KEY_*` checks. Add new default bindings in `HFKeymap._default_bindings()`. Toolbar uses single-char labels with tooltips.
- **External tools** should implement `can_activate()` for tool availability and `get_settings_schema()` for auto-generated dock UI. See `hf_editor_tool.gd` for the full API.
- **New dock sections** should use `HFCollapsibleSection.create()` and register with `_register_section()` for persisted collapse state. Use 70px label widths for form rows.
- **User-facing messages** should use `dock.show_toast(msg, level)` or `root.user_message.emit(msg, level)` instead of (or in addition to) `push_error`/`push_warning`. Level: 0=INFO, 1=WARNING, 2=ERROR.
- **Brush mutations** should call `root.tag_brush_dirty(id)` (guarded with `has_method`) so the reconciler can skip unchanged geometry.
- **Multi-brush operations** should wrap in `begin_signal_batch()` / `end_signal_batch()` (or use transactions, which batch automatically) to prevent UI thrash.
- **User preferences** (application-scoped) go in `HFUserPrefs`. **Level settings** go on LevelRoot.
- **Operations that can fail** (hollow, clip, delete) should return `HFOpResult`. Use `_op_fail(msg, hint)` in brush_system to emit `user_message` and return a fail result in one call. Include an actionable `fix_hint` string so users know how to resolve the issue.
- **Destructive operations should preview before commit**: operations that permanently modify or delete geometry (carve, clip, hollow) must show a wireframe overlay preview and a `ConfirmationDialog` before executing. Pattern: (1) validate with `can_*()`, (2) call `preview.show_preview(...)`, (3) create `ConfirmationDialog`, (4) on confirmed: clear preview + commit via `HFUndoHelper`; on canceled: clear preview + `queue_free()` dialog. All lambdas must guard with `is_instance_valid(self)` and `is_instance_valid(root)`. Use `_add_confirmable_dialog(dlg)` in plugin.gd to track dialogs for teardown cleanup.
- **Bulk delete confirmation**: deleting 3+ brushes should show a confirmation dialog. Single/dual deletes remain instant to avoid friction. The dialog should remind users of Ctrl+Z availability.
- **Snapping** goes through `HFSnapSystem` (on `level_root.snap_system`). New snap modes should be added as bitmask flags in `SnapMode` enum and collected in `_collect_candidates()`.
- **Deletion cleanup** is handled automatically by `_cleanup_brush_references()` in brush_system. If you add new cross-reference types (beyond groups, visgroups, entity I/O), add cleanup logic there.
- **Viewport hints** should be added to `MODE_HINTS` in `shortcut_hud.gd`. Each mode key maps to an instructional string. Hints auto-dismiss and persist via `hf_user_prefs.gd`.
- **Prefabs** use `HFPrefab` (`hf_prefab.gd`) for capture/instantiate. Add new prefab-related UI to `ui/hf_prefab_library.gd`. Prefab instantiation should always use `begin_signal_batch()` / `end_signal_batch()`.
- **Dock tab builders**: New UI sections should be added to the appropriate builder file (`ui/paint_tab_builder.gd`, `ui/entity_tab_builder.gd`, `ui/manage_tab_builder.gd`, `ui/selection_tools_builder.gd`) rather than directly in `dock.gd`. Each builder has `build()` (creates controls) and `connect_signals()` (wires them up).
- **Registered tools** (HFEditorTool subclasses) get automatic dock settings UI via `get_settings_schema()`, keyboard dispatch via `handle_keyboard()`, and poll-based button state via `can_activate()`. Register in plugin.gd via `_tool_registry.register_tool()`. Tools that create brushes should use `self.undo_redo` (set by the registry on activation).
- **Vertex system** operations (`split_edge`, `merge_vertices`) should use `get_pre_op_snapshots()` for face snapshot undo. Edge splitting skips convexity validation (mathematically safe on convex hulls). Vertex merging validates convexity and reverts on failure.
- **Wireframe overlay refresh**: After replacing `mesh_instance.mesh` (e.g. in `rebuild_preview()`), always call `_apply_brush_entity_overlay()`, `_apply_subtract_wireframe_overlay()`, and `_apply_additive_wireframe_overlay()`. Failing to refresh overlays causes wireframe drift. Color convention: green=additive, red=subtractive, blue=entity.
- **Grid snap changes must emit `grid_snap_applied`**: If adding a new code path that changes `grid_snap`, ensure it flows through `dock._apply_grid_snap()` or that the root's `grid_snap_changed` signal fires (which dock relays via `grid_snap_applied`). This keeps the viewport HUD indicator in sync.
- **Face winding convention**: All faces must use **CW vertex winding** as seen from outside the brush (Godot 4's front-face convention). `_compute_normal()` produces outward normals for CW faces automatically. Never negate normals manually after `ensure_geometry()`. When adding new face generators, verify normals point outward from the brush centroid.
- **Polygon/path tools** create brushes via `root.brush_system.create_brush_from_info()` with a `faces` key containing serialized face data. Use `FaceData.from_dict()` / `to_dict()` for serialization. Face dicts include `winding_version: 1`; omitting this key triggers load-time migration.
- **Spawn system** (`root.spawn_system`): use `get_active_spawn()` for primary-flag-aware spawn lookup, `validate_spawn()` for physics-based validation, `auto_fix_spawn()` to apply suggested fixes, `create_default_spawn()` for fallback creation. Quick Play flow calls these automatically. Debug visualisation via `show_validation_debug()` / `cleanup_debug()`. Spawn properties (`primary`, `angle`, `height_offset`) are defined in `entities.json` and auto-generated in the Entities dock.
- **Validation tolerances**: `HFValidationSystem` has two configurable tolerances — `weld_tolerance` (default 0.001) for vertex coincidence in welding/micro-gap detection, and `planarity_tolerance` (default 0.01) for face-plane deviation. The `_edge_key()` function used by non-manifold/open-edge topology checks uses a **fixed** 0.001 precision and must NOT be coupled to `weld_tolerance` — changing `_edge_key` precision would mask real topology issues when users raise the weld knob. Keep new spatial-hash lookups distance-based with 27-cell neighbor search (see `_cell_keys()`) rather than single-bucket — bucket boundaries silently miss valid pairs. Always call `face.ensure_geometry()` after mutating `local_verts` so normals and bounds stay in sync.
- **Incremental bake**: `bake_selected()` merges into the existing `baked_container` — never replace the container wholesale. `bake_dirty()` uses `_last_bake_success` to decide whether to clear dirty tags; failed bakes must retain all tags so they can be retried.
- **Bake preview modes**: use the `PreviewMode` enum (FULL, WIREFRAME, PROXY). Wireframe must use `ShaderMaterial` with `render_mode wireframe` — `StandardMaterial3D` has no `wireframe` property in Godot 4.6.
- **Quick Play variants**: `_on_quick_play_from_camera()` and `_on_quick_play_selected_area()` must follow the same severity ≥ 2 blocking, auto-create, and fix-dialog patterns as `_on_quick_play()`. Both must restore temporary state (spawn position/angle, cordon) on both success and error paths. Use `_restore_spawn()` helper and explicit type annotations (e.g. `var old_pos: Vector3 =`) to avoid GDScript `:=` inference failures with untyped spawn references.
- **Camera yaw propagation**: write yaw to `entity_data["angle"]` (not `set_meta`). The playtest runtime reads `deg_to_rad(entity_data.get("angle", 0.0))` at `level_root.gd` line ~1979.
- Avoid adding new dependencies unless necessary.

## Running Checks Locally

### Format + Lint
```
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
```

### Unit Tests (GUT)
Tests live in `tests/` and use the [GUT](https://github.com/bitwes/Gut) framework (installed in `addons/gut/`).

Run all tests headless:
```
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

If you get "class_names not imported", run `godot --headless --import --path .` first.

### Writing Tests
- Test files go in `tests/` with the `test_` prefix (e.g. `test_my_feature.gd`).
- Extend `GutTest` and use `assert_eq`, `assert_true`, `assert_almost_eq`, etc.
- Use root shim scripts (dynamically created GDScript) to avoid circular dependency with LevelRoot. See existing tests for the pattern.
- Keep tests focused: one behavior per test function.
- For negative-path tests that trigger runtime warnings, use `HFLog.warn()` in production code and `HFLog.begin_test_capture()` / `end_test_capture()` in tests. This prevents expected warnings from polluting the test output. See `test_bevel.gd` for the pattern.

### CI
All checks (format, lint, unit tests) run automatically on push/PR to `main` via GitHub Actions.

## Communication
- Be clear about tradeoffs and known limitations.
- Include before/after behavior notes in PR descriptions.
