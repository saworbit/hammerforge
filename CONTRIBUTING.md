# Contributing

Thanks for helping improve HammerForge.

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md) — the short version
is: be kind, be specific, and assume good faith. Security problems go through
the [Security Policy](SECURITY.md) privately, **not** into a public issue.

## New here?

- [Good first issues](https://github.com/saworbit/hammerforge/labels/good%20first%20issue)
  are scoped so you don't need to understand the whole architecture first.
- [Help wanted](https://github.com/saworbit/hammerforge/labels/help%20wanted)
  is the work that most needs another pair of hands.
- `area:` labels (`build`, `paint`, `objects`, `test`, `architecture`, `docs`)
  map to the dock tabs, so you can find issues in a part of the editor you
  already use.
- [Discussions](https://github.com/saworbit/hammerforge/discussions) is the
  right place for "am I holding this wrong?" questions that aren't bug reports.

Bug reports and feature requests both have
[issue forms](https://github.com/saworbit/hammerforge/issues/new/choose) that
prompt for what's actually needed to act on them.

## Scope
- Small, focused changes are preferred.
- Large changes should start with an issue or discussion before a PR.
- Keep changes aligned with the current MVP and architecture.

## AI Assisted Contributions

Yes, you can use them. This project is built with them and it would be odd to ask
otherwise. See [AI.md](AI.md) for how and why.

The terms are the same ones I hold myself to.

- **You are the author.** Whatever produced a line, you are the one submitting it
  and you are answerable for it. That does not change.
- **Be able to explain it.** If you cannot say why a change is correct, or what it
  does when the input is empty, it is not ready for review. This is the only rule
  here that actually bites.
- **Tests have to test something.** A test that asserts nothing, or that was
  written to match the implementation rather than the requirement, is worse than
  no test.
- **Run the checks before you open the PR.** They are listed under
  [Running Checks Locally](#running-checks-locally) and they catch most of what a
  review would otherwise spend its time on.

You do not need to say whether you used an assistant on a given pull request. I am
not going to ask, and I could not verify the answer anyway. What gets reviewed is
the change.

## How To Contribute
1. Open an issue describing the problem and proposed fix.
2. Keep PRs small and limited to one topic.
3. Update docs and tests when behavior changes.
4. Run formatting, lint, and test checks before submitting (see below).

## Documentation Expectations
- Use the displayed UI names—**Build**, **Paint**, **Objects**, and **Test**—in user-facing instructions. Legacy `entity_*` and `manage_*` filenames may be named when explaining internals.
- Verify behavior claims against current code and tests. Do not copy test totals or source line counts from an older document.
- Update the README, relevant guide/spec, roadmap status, and `[Unreleased]` changelog together when a change affects users or contributors.
- Only publish aggregate test totals from a successful full CI run; include the verification date so readers can distinguish a measured snapshot from a permanent guarantee.
- You do not have to update the published totals yourself. CI measures them on every push to `main` and rewrites the five documents that quote them, so a pull request that adds tests can leave those numbers alone. To see what it would write, run `python tools/update_test_counts.py --gut-log <your test log> --check`.
- Check relative Markdown links and `git diff --check` before submitting documentation-only changes.
- Describe known limitations plainly and link the tracking issue instead of implying unfinished safety or fidelity work is complete.

## Code Expectations
- Follow the subsystem architecture (LevelRoot is the public API).
- Prefer undo actions that use stable IDs and state snapshots. Use `collation_tag` for rapid operations.
- Use transactions (`begin_transaction` / `commit_transaction`) for multi-step brush operations.
- New entity types go in `entities.json`, not hardcoded in GDScript. Project-side additions belong in `res://hammerforge_entities.json`, which overlays it. Both dock pickers read the merged result, so do not add a second load path for one of them.
- New input tools should subclass `HFGesture` for self-contained state management.
- Subscribe to LevelRoot signals instead of polling in `_process()`.
- **Keyboard shortcuts** go through `_keymap.matches("action_name", event)`, never hardcoded `KEY_*` checks. Add new default bindings in `HFKeymap._default_bindings()`. Keep the primary toolbar limited to clear, user-facing Draw/Select/Paint/More/Help actions.
- **External tools** should implement `can_activate()` for tool availability and `get_settings_schema()` for auto-generated dock UI. See `hf_editor_tool.gd` for the full API.
- **New dock sections** should use `HFCollapsibleSection.create()` and register with `_register_section()` for persisted collapse state. Use 70px label widths for form rows.
- **User-facing messages** should use `dock.show_toast(msg, level)` or `root.user_message.emit(msg, level)` instead of (or in addition to) `push_error`/`push_warning`. Level: 0=INFO, 1=WARNING, 2=ERROR.
- **Brush mutations** should call `root.tag_brush_dirty(id)` (guarded with `has_method`) so the reconciler can skip unchanged geometry.
- **Multi-brush operations** should wrap in `begin_signal_batch()` / `end_signal_batch()` (or use transactions, which batch automatically) to prevent UI thrash.
- **User preferences** (application-scoped) go in `HFUserPrefs`. **Level settings** go on LevelRoot.
- **Operations that can fail** (hollow, clip, delete, flip) should return `HFOpResult`. Use `_op_fail(msg, hint)` in brush_system to emit `user_message` and return a fail result in one call. Include an actionable `fix_hint` string so users know how to resolve the issue.
- **Destructive operations should preview before commit**: operations that permanently modify or delete geometry (carve, clip, hollow) must show a wireframe overlay preview and a `ConfirmationDialog` before executing. Pattern: (1) validate with `can_*()`, (2) call `preview.show_preview(...)`, (3) create `ConfirmationDialog`, (4) on confirmed: clear preview + commit via `HFUndoHelper`; on canceled: clear preview + `queue_free()` dialog. All lambdas must guard with `is_instance_valid(self)` and `is_instance_valid(root)`. Use `_add_confirmable_dialog(dlg)` in plugin.gd to track dialogs for teardown cleanup.
- **Bulk delete confirmation**: deleting 3+ brushes should show a confirmation dialog. Single/dual deletes remain instant to avoid friction. The dialog should remind users of Ctrl+Z availability.
- **Snapping** goes through `HFSnapSystem` (on `level_root.snap_system`). New snap modes should be added as bitmask flags in `SnapMode` enum and collected in `_collect_candidates()`.
- **Deletion cleanup** is handled automatically by `_cleanup_brush_references()` in brush_system. If you add new cross-reference types (beyond groups, visgroups, entity I/O), add cleanup logic there.
- **Viewport hints** should be added to `MODE_HINTS` in `shortcut_hud.gd`. Each mode key maps to an instructional string. Hints auto-dismiss and persist via `hf_user_prefs.gd`.
- **Prefabs** use `HFPrefab` (`hf_prefab.gd`) for capture/instantiate. Add new prefab-related UI to `ui/hf_prefab_library.gd`. Prefab instantiation should always use `begin_signal_batch()` / `end_signal_batch()`.
- **Dock tab builders**: New UI sections should be added to the appropriate builder file (`ui/paint_tab_builder.gd`, `ui/entity_tab_builder.gd`, `ui/manage_tab_builder.gd`, `ui/selection_tools_builder.gd`) rather than directly in `dock.gd`. Each builder has `build()` (creates controls) and `connect_signals()` (wires them up).
- **Registered tools** (HFEditorTool subclasses) get automatic dock settings UI via `get_settings_schema()`, keyboard dispatch via `handle_keyboard()`, and poll-based button state via `can_activate()`. Register in plugin.gd via `_tool_registry.register_tool()`. Tools that create brushes should use `self.undo_redo` (set by the registry on activation).
- **Vertex system** operations (`split_edge`, `merge_vertices`) should use `get_pre_op_snapshots()` for face snapshot undo. Edge splitting skips convexity validation (mathematically safe on convex hulls). Vertex merging validates convexity and reverts on failure.
- **Brush visual refresh**: After replacing `mesh_instance.mesh` (for example in `rebuild_preview()`), call `_sync_visual_overlays()`. Ordinary additive brushes have no topology overlay; subtractive brushes keep one red semantic overlay and brush entities keep one blue overlay. Reuse or synchronously detach fixed-name visual children before queueing deletion—never queue a child and immediately add a same-name replacement under the same parent. Hover and selection boundaries come from `hf_outline_util.gd`.
- **Grid snap changes must emit `grid_snap_applied`**: If adding a new code path that changes `grid_snap`, ensure it flows through `dock._apply_grid_snap()` or that the root's `grid_snap_changed` signal fires (which dock relays via `grid_snap_applied`). This keeps the viewport HUD indicator in sync.
- **Face winding convention**: All faces must use **CW vertex winding** as seen from outside the brush (Godot 4's front-face convention). `_compute_normal()` produces outward normals for CW faces automatically. Never negate normals manually after `ensure_geometry()`. When adding new face generators, verify normals point outward from the brush centroid.
- **A builder describes its own settings.** Adding a generator means writing the builder, giving it a `settings_schema()`, and naming it in `HFGeneratorSystem.builder_for()`. If you find yourself editing the dock to add a generator, the schema is missing a field type rather than the dock needing another member.
- **Write the general case and let the shape collapse it.** `HFConvexClip.solid_from_rings()` drops coincident corners, so a builder writes the eight-corner box once and gets a wedge where the shape pinches. Carrying the pinch through the arithmetic instead is how special cases get one axis wrong.
- **Check that a test file still loads.** GUT skips a file it cannot parse with a warning, not a failure, so deleting a helper a test calls takes that whole file out of the suite silently. `tests/test_suite_integrity.gd` catches it now; do not weaken it.
- **A generator record is a hint, not ownership.** `HFGeneratorSystem` keeps brush ids so a structure can be rebuilt, but ids are reissued as the counter moves and brushes get deleted, clipped and merged outside its knowledge. Check the brush's own `hf_generator_id` meta before acting on it. Never delete by id alone.
- **Validate before you destroy.** Anything that replaces geometry — regeneration, clip, carve, hollow — must know the replacement is buildable before removing the original, or a bad input leaves the user with nothing.
- **Build a solid, then measure its winding.** Any generator that constructs faces from scratch should finish with `HFConvexClip.orient_faces_outward(faces, interior)` rather than getting the vertex order right by hand. Every face of a convex solid points away from any interior point; that is checkable, and checking it is cheaper than the bug.
- **Do not trust an individual face normal for a boolean.** Use `HFConvexClip.outward_planes()`, which orients each plane against an interior point. Brushes store triangles, and primitive meshes contain near-degenerate ones whose computed normal is numerical noise — one of them is enough to make an inset plane face the wrong way.
- **Booleans are capped at `MAX_BOOLEAN_PLANES` distinct planes.** Cost and output both climb steeply with the plane count, and a sphere has thousands. If you add another boolean operation, check `HFConvexClip.boolean_plane_budget()` before doing the work.
- **Rebuilt faces are where winding goes wrong.** Faces carried through a transform keep their order; faces *built* — a clip's cut surface, a hull rebuild — have to be ordered deliberately, and the natural ordering of a ring of coplanar vertices is counter-clockwise about its normal, which is the opposite of what HammerForge needs. Use `HFConvexClip.sort_coplanar_cw()`; do not write a second ring sorter. A duplicate one is how Clip to Convex shipped producing entirely inside-out geometry.
- **Never leave a brush basis with a negative determinant.** Godot decides triangle winding from the composed transform, so a mirrored basis silently inverts every face on the brush — invisible in the viewport preview, obvious the moment it bakes. Mirroring is done by folding the reflection back through a reflection along one *local* axis (`R * basis * H`), which cancels the two `-1`s while leaving world vertices exactly mirrored. See `HFTransformSystem.flipped_transform()`. If you add an operation that reflects geometry, assert the winding at bake level with an untouched control beside it, as `tests/test_transform_integration.gd` does — an inverted normal is not visible in any assertion that only checks positions.
- **Polygon/path tools** create brushes via `root.brush_system.create_brush_from_info()` with a `faces` key containing serialized face data. Use `FaceData.from_dict()` / `to_dict()` for serialization. Face dicts include `winding_version: 1`; omitting this key triggers load-time migration.
- **Spawn system** (`root.spawn_system`): use `get_active_spawn()` for primary-flag-aware spawn lookup, `validate_spawn()` for physics-based validation, `auto_fix_spawn()` to apply suggested fixes, `create_default_spawn()` for fallback creation. The user-facing Test Level flow calls these automatically. Debug visualisation uses `show_validation_debug()` / `cleanup_debug()`. Spawn properties (`primary`, `angle`, `height_offset`) are defined in `entities.json` and auto-generated in the Objects dock.
- **Validation tolerances**: `HFValidationSystem` has two configurable tolerances — `weld_tolerance` (default 0.001) for vertex coincidence in welding/micro-gap detection, and `planarity_tolerance` (default 0.01) for face-plane deviation. The `_edge_key()` function used by non-manifold/open-edge topology checks uses a **fixed** 0.001 precision and must NOT be coupled to `weld_tolerance` — changing `_edge_key` precision would mask real topology issues when users raise the weld knob. Keep new spatial-hash lookups distance-based with 27-cell neighbor search (see `_cell_keys()`) rather than single-bucket — bucket boundaries silently miss valid pairs. Always call `face.ensure_geometry()` after mutating `local_verts` so normals and bounds stay in sync.
- **Incremental bake**: `bake_selected()` merges into the existing `baked_container` — never replace the container wholesale. `bake_dirty()` uses `_last_bake_success` to decide whether to clear dirty tags; failed bakes must retain all tags so they can be retried.
- **Bake preview modes**: use the `PreviewMode` enum (FULL, WIREFRAME, PROXY). Wireframe must use `ShaderMaterial` with `render_mode wireframe` — `StandardMaterial3D` has no `wireframe` property in Godot 4.7.
- **Test Level variants** (internally Quick Play): `_on_quick_play_from_camera()` and `_on_quick_play_selected_area()` must follow the same severity ≥ 2 blocking, auto-create, and fix-dialog patterns as `_on_quick_play()`. Both must restore temporary state (spawn position/angle, cordon) on both success and error paths. Use `_restore_spawn()` helper and explicit type annotations (e.g. `var old_pos: Vector3 =`) to avoid GDScript `:=` inference failures with untyped spawn references.
- **Camera yaw propagation**: write yaw to `entity_data["angle"]` (not `set_meta`). The playtest runtime reads `deg_to_rad(entity_data.get("angle", 0.0))` at `level_root.gd` line ~1979.
- Avoid adding new dependencies unless necessary.
- No editor bridge is vendored here. Install the one you use into your own `addons/` folder; `.gitignore` allowlists `addons/`, so it stays untracked. Enabling it rewrites the tracked `project.godot`, so check that file before you push.
- Never commit bridge tokens, `user://` settings, generated verification logs, editor screenshots, or local client overrides. A token belongs in an environment variable, not in a committed file.

## Running Checks Locally

### Format + Lint
```
gdformat --check addons/hammerforge/ tests/
gdlint addons/hammerforge/
python tools/check_placement_order.py
```

The last one refuses a `global_position` or `global_transform` written to a node
that is not in the tree yet. Godot writes the local transform in that case
without complaining, and the node lands shifted by whatever its container's
transform is, so parent it first and place it second. See DEVELOPMENT.md if you
need the deliberate-case escape hatch.

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

### Python and Workflow Checks
Only relevant if you touch `tools/` or `.github/workflows/`. CI runs these and
will fail the build on them.
```
pip install -r requirements-ci.txt
ruff check tools/
ruff format --check tools/
zizmor .github/workflows/
```

`actionlint` is downloaded by the workflow rather than pinned in the requirements
file, so grab the release binary if you want it locally. It runs shellcheck over
every `run:` block, which is usually what catches things.

### CI
Three jobs run on every push and pull request to `main`: **GDScript Lint and
Format**, **Workflow and Tooling Lint**, and **GUT Unit Tests**. All three have to
pass before anything can merge, and `main` takes no direct pushes from anyone.

You do not need to update the published test counts by hand. CI measures the
suite on your pull request and commits the numbers to your branch.

That commit moves your branch's head, which matters if you are waiting on the
checks before merging. Wait on the commit, never the branch: the newest run on a
branch is often the previous one, and a run that went green on the commit a
counts push replaced says nothing about what would merge. `python
tools/wait_for_ci.py <pr>` does this properly and exits non-zero if the run
fails, times out, or never appears.

## Communication
- Be clear about tradeoffs and known limitations.
- Include before/after behavior notes in PR descriptions.
- The PR template lists the checks above; tick what you ran rather than
  guessing. "I couldn't run GUT locally" is a fine thing to say — CI will.
- Reviews are on the code, not the person. See the
  [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting Security Issues
Do not open a public issue. See [SECURITY.md](SECURITY.md) — level-file
parsing, unintended file writes, secret handling, and `HFIORuntime` are the
areas most likely to matter.
