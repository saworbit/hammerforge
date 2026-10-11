# MCP bridge, phase 2: the authoring loop

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent can build and change a level end to end: make a starter
level, place, move, rotate, resize, delete and extrude brushes, paint materials,
put the spawn where it wants, list what is there, and undo or redo its own steps
without touching a human's.

**Architecture:** Each tool is a `_check_<tool>` on `HFMcpDispatcher` that reads
and validates arguments and returns `{ok, scope_ids, apply}`, where `apply` is a
bound `_apply_<tool>` that only calls LevelRoot facade methods. Phase 1's
`_run_mutation()` wrapper owns the undo step for all of them. Two operations get
new facade methods the UI shares: absolute rotation and extrude by face index.
Create starter goes through the plugin, fixed to record one step.

**Tech stack:** GDScript (Godot 4.7, GUT 9.6), Python 3.10+ (`mcp>=2.3,<3`).

**Spec:** `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`, the tool
mapping table. Builds on phase 1 (`2026-10-11-mcp-bridge-phase1.md`).

## Global constraints

Phase 1's, plus:

- Brush ids only between commands, never nodes. `get_brush_info_from_node()`
  writes an id onto a brush without one, so it is not called on such a brush.
- Rotation is `EULER_ORDER_XYZ` both ways.
- Every result echoes the values applied, after snapping.
- Undo names: `MCP: transform brush`, `MCP: resize brush`, `MCP: delete brush`,
  `MCP: extrude face`, `MCP: assign material`, `MCP: set spawn`,
  `MCP: create starter`, plus phase 1's `MCP: place brush`.

## Review focus

1. **`hf_undo` after a human edit that was then undone.** It conflicts, because
   the revision moved, and the message says why. Test: commit and undo a foreign
   action on the stand-in, then `hf_undo` gives `undo_conflict`.
2. **Two agent steps then two `hf_undo`.** Both undo in order, since each
   `hf_undo` answer becomes the last agent revision. Test in the dispatcher suite.
3. **A face selector that matches two faces equally**, such as `"+y"` on a
   cylinder's top cap pieces, or a `{normal}` halfway between two faces.
   `ambiguous_face` with the candidates. Test with a box rotated 45 degrees about Y
   and `"+x"`.
4. **Resize or transform a brush in the pending cuts.** It works the same as a
   union brush and stays pending. Test.
5. **A material named the same as another.** `ambiguous_material` naming both
   ids. Test with two palette entries given the same `resource_name`.

---

### Task 1: Facade additions

**Files:**
- Modify: `addons/hammerforge/systems/hf_transform_system.gd`: add
  `func set_rotation(brush_ids: Array, rotation: Basis) -> int`. For each brush:
  `rot := rotation * draft.global_transform.basis.orthonormalized().inverse()`,
  then the same body as `rotate()` (pivot the brush centre, `local_rotation`,
  `rotated_transform`, texture lock, `_tag_dirty`). A rotation within
  `ROTATION_EPSILON` of the current one changes nothing and counts nothing.
- Modify: `addons/hammerforge/level_root.gd`: add
  `func set_brush_rotation_by_id(brush_id: String, rotation_degrees: Vector3) -> HFOpResult`
  (refuses `""`, an unknown id and a non-finite vector; builds
  `Basis.from_euler(deg_to_rad each, EULER_ORDER_XYZ)`).
- Modify: `addons/hammerforge/hf_extrude_tool.gd`: add
  `static func build_extrude_info(brush: DraftBrush, face_index: int, height: float, extrude_direction: int, snap: float, brush_id: String) -> Dictionary`
  with the body of today's `begin_extrude` face maths and `_build_brush_info`.
  `_build_brush_info()` calls it with the tool's own fields, so the pointer
  tool and the bridge build the same brush.
- Modify: `addons/hammerforge/level_root.gd`: add
  `func extrude_face_info(brush_id: String, face_index: int, distance: float) -> Dictionary`
  (empty for an unknown brush, a bad index, or a distance not in `(0, 256]`;
  mints the id with `_next_brush_id()`).
- Test: `tests/test_set_brush_rotation.gd`, `tests/test_extrude_face_info.gd`.

- [ ] **Step 1: Failing tests.** Rotation: a box set to `(0, 90, 0)` reads back
  `(0, 90, 0)` through `get_euler(EULER_ORDER_XYZ)`; setting `(10, 20, 30)` then
  `(0, 0, 0)` returns it to the identity basis; the world bounds of a 4x2x2 box at
  `(0, 90, 0)` are 2 wide on X and 4 on Z; texture lock on keeps a face's world
  UV at a vertex; an unknown id and NaN are refused with no change. Extrude: the
  top face (index 2) of a 4x2x4 box at the origin, distance 3, gives a box info
  of size `(4, 3, 4)` centred at `(0, 2.5, 0)`; the result is the same as the
  pointer tool's `end_extrude_info()` after a drag to height 3 (drive
  `begin_extrude` with a camera pointing at the top face, then set
  `_current_height` and compare); distance 0, 300 and NaN, and face 99, give `{}`.
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, plus `-gselect=test_transform` and `-gselect=test_extrude`.**
- [ ] **Step 5: Commit** `Rotate a brush to an angle, and extrude a face by index`.

### Task 2: Create starter as one step

**Files:**
- Modify: `addons/hammerforge/plugin.gd` `create_starter_level(action_name := "New HammerForge Level") -> Node`.
  With a LevelRoot already in the edited scene: today's `HFUndoHelper.commit`,
  under `action_name`. Without one: a single action that does `add_child`,
  `set_owner`, `create_new_level`, `_activate_created_level_root`, with
  `add_do_reference(root)`, and undoes `_deactivate_created_level_root` and
  `remove_child`.
- Modify: `tests/test_starter_level_rebuild.gd`: it pins two entries today.
  Rewrite it to expect one, per "tests pin the bug".
- Modify: `addons/hammerforge/mcp/hf_mcp_host.gd`: `func create_starter(action_name: String) -> Node` (default null); `plugin_mcp.gd` `EditorHost` calls the plugin.

- [ ] **Step 1: Failing test:** one entry named as given; undo removes the root;
  redo brings it back with floor, sun and spawn (#772 still holds).
- [ ] **Steps 2 to 5** as usual. Commit `Make Create Starter Level one undo step`.

### Task 3: Read tools

**Files:** `hf_mcp_dispatcher.gd`, `tests/test_mcp_dispatcher_read.gd`.

- `hf_get_brushes`: params `brush_ids` (array of strings), `bounds`
  (`{min, max}` vec3 pair; keep brushes whose world bounds intersect), `include_faces`
  (default true), `limit` (1 to 2000, default 200). Result `{brushes, total,
  truncated}` in container order: draft, pending, committed. Unknown ids in
  `brush_ids` are listed in `missing`, not an error.
- `hf_get_materials`: `{materials: [{id, name, slot}]}` from `_palette()`.
- Both are added to `READ_ONLY` and never touch the undo history.

- [ ] Tests: listing after two places gives both in order with faces; `limit: 1`
  gives `truncated: true` and `total: 2`; `include_faces: false` drops `faces`;
  `bounds` excludes a far brush; `brush_ids` with one good and one made-up id gives
  the good one and `missing`; materials lists the 150 prototypes with
  `res://addons/hammerforge/textures/prototypes/materials/...` ids on a fresh
  level; neither changes `capture_state()` or the history count.

### Task 4: Change tools

**Files:** `hf_mcp_dispatcher.gd`, `tests/test_mcp_dispatcher_edit.gd`.

Shared readers on the dispatcher: `_read_brush(root, params) -> {ok, brush}`
(`brush_id` required, `brush_not_found` otherwise, via `root.find_brush_by_id`,
refusing `""` first because the slow path matches a brush with an empty id),
`_resolve_face(brush, selector) -> {ok, index}` (int, side string, or
`{normal}`, the 0.7 and 0.001 rules from the spec), `_resolve_material(root,
value) -> {ok, slot}` (exact id, `palette:N`, or a unique case-insensitive name).

- `hf_transform_brush`: `brush_id`, `position` (optional), `rotation_degrees`
  (optional), `snap`. At least one of the two. Position via
  `set_brush_transform_by_id(id, brush.size, position)`, rotation via
  `set_brush_rotation_by_id`. Scope `[id]`.
- `hf_resize_brush`: `brush_id`, `size`, `snap`. Refuse CUSTOM with
  `unsupported_shape`. Keeps the centre, then snapping as in place. Scope `[id]`.
- `hf_delete_brush`: `brush_id`. `delete_brush_by_id()`; a failed `HFOpResult`
  is `operation_failed` with its text. Whole level (it removes I/O links aimed at
  the brush from other objects).
- `hf_extrude_face`: `brush_id`, `face`, `distance`, `snap`. Snap the distance to
  the grid. `extrude_face_info()` then `create_brush_from_info()`. Whole level.
  Result `{brush, source_brush_id, face_index}`.
- `hf_assign_material`: `brush_id`, `material`, `faces` (optional array of
  selectors; all faces when absent). Scope `[id]`.
- `hf_set_spawn`: `position` (the floor point the player stands on),
  `yaw_degrees` (optional). The active spawn, or `create_default_spawn()` when
  there is none. The entity goes at `position + (0, FEET_OFFSET +
  DEFAULT_SPAWN_HEIGHT_OFFSET, 0)`, the height `create_default_spawn()` uses, and
  yaw goes in `entity_data["angle"]`. Result: the spawn's position, yaw and
  `validate_spawn()`'s answer (`blocked`, `suggested_position`). Whole level.
- `hf_create_starter`: no params. `no_edited_scene` without a scene,
  `level_exists` with a LevelRoot. `host.create_starter(ACTION_PREFIX + "create
  starter")`. Await a frame, re-resolve the target, record the last agent
  revision. Result: the new target, spawn position, `floor_top`.

- [ ] Tests, each with `capture_state()` compared before and after a refusal:
  transform position and rotation separately and together, then read back by
  `hf_get_brushes`; resize a box and refuse a merged (CUSTOM) brush; delete, then
  undo brings it back with its id; extrude the top face by side `"+y"`, by index,
  by `{normal: [0, 1, 0]}`; `ambiguous_face` on the 45 degree box; assign a
  material to all faces, then to `["+y"]` only, by id and by name, and
  `ambiguous_material`; set spawn with and without an existing one, yaw stored,
  a spawn inside a brush reported blocked with a suggestion; create starter
  without a scene, with a level, and on an empty scene (one step, target moves).
  Save then reload for each change: `save_hflevel()` to `user://`, a fresh
  LevelRoot, `load_hflevel()`, and the same brushes, transforms, sizes and face
  materials back.

### Task 5: Undo and redo

**Files:** `hf_mcp_dispatcher.gd`, `tests/test_mcp_dispatcher_undo.gd`.

- `hf_undo`: target matches; the scene history's `get_current_action_name()`
  starts with `MCP: `; `revision() == _last_agent_revision`. Otherwise
  `undo_conflict` with `details: {top_action, revision, last_agent_revision}`, or
  `nothing_to_undo`. Then `history.undo()`, await a frame, set the last agent
  revision. Result `{undone}`.
- `hf_redo`: the mirror with `get_action_name(get_current_action() + 1)`.
- Both are mutating for the queue and the cache, and record nothing themselves.

- [ ] Tests: place then undo then redo; two places then two undos; a foreign
  action on top conflicts; a foreign action committed and undone conflicts
  (revision moved); nothing to undo on an empty history; redo with nothing ahead;
  redo after a foreign commit cleared the redo stack gives `nothing_to_redo`.

### Task 6: Python catalogue and server

**Files:** `hammerforge_mcp/src/hammerforge_mcp/{catalogue,server}.py`,
`hammerforge_mcp/tests/test_server.py`, `hammerforge_mcp/README.md`.

- Every phase 2 tool with its description (conventions on the spatial ones),
  annotations as the spec lists them, input models, and timeouts.
- `FaceSelector = int | Literal["+x", "-x", "+y", "-y", "+z", "-z"] | {normal: Vec3}`.
- Tests: the catalogue lists every tool; each mutating tool sends `mutating:
  True`; the face selector's three forms validate and pass through; the README
  table matches the catalogue (a test reads it).

### Task 7: Smoke, docs, vibe, PR

- [ ] Smoke: add transform, `hf_undo`, `hf_get_brushes` to `tools/mcp_bridge_smoke.py`.
- [ ] Docs: README tool table, `docs/features.md` tools line, ROADMAP status,
  CHANGELOG line, SPEC section.
- [ ] Vibe test in a headless editor: build a room of four walls, a floor and a
  door cut by extrude and subtract; human Ctrl+Z in the middle, then `hf_undo`
  conflicts; switch tabs; save the scene to a scratch file and reload.
- [ ] Full GUT, warnings gate, run_local_checks, pytest, smoke. Review. PR, CI, merge.
