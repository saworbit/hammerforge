# MCP bridge, phase 1: contract and handshake

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent connects through `hammerforge-mcp`, authenticates, reads status
and places a brush that is one undo step, and a retry with the same
`operation_id` does not place a second one.

**Architecture:** A `TCPServer` node owned by the plugin, polled on the main
thread, hands framed JSON requests to a dispatcher. The dispatcher resolves the
target, keeps the revision and the operation cache, and runs each command through
one capture, apply, commit-or-restore wrapper on the LevelRoot facade. A Python
stdio MCP server built on `mcp` 2.x relays tool calls to it.

**Tech stack:** GDScript (Godot 4.7, GUT 9.6), Python 3.10+ (`mcp>=2.3,<3`,
pytest), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`

## Global constraints

- Godot 4.7. New scripts reference other classes through `const X = preload(...)`,
  never a bare global class name (fresh-clone parse rule).
- Every new `.gd` gets its committed `.uid` (`tools/check_uid_parity.py`).
- Zero GDScript warnings: `python tools/check_script_warnings.py --godot C:/Godot/godot.cmd`.
- gdformat and gdlint clean over `addons/hammerforge/ tests/ tools/ hammerforge_tools/`.
- ruff check and format clean over `tools/` and `hammerforge_mcp/`.
- No GUT orphans: every node a test makes is freed (`add_child_autoqfree` or
  `autoqfree`).
- Listener binds `127.0.0.1` only. The token never appears in a log line, an error
  message or a response.
- Undo action names start with `MCP: `.
- Request ids are strings. Godot parses every JSON number as a float, so an
  integer id would come back as `7.0` and miss its waiter.
- Discovery file: `res://.godot/hammerforge_mcp.json`.
- Limits: request frame at most 1 MiB, response frame at most 16 MiB, handshake
  within 5 s, operation cache 256 entries, `operation_id` 1 to 128 chars of
  `[A-Za-z0-9._:-]`.
- GitHub as saworbit through `gh` only. Prose with no em dashes and no " - "
  clauses.
- Changelog: one line under `### Week of 5 Oct 2026` (or the week the PR merges),
  checked by `tools/check_changelog.py`.

## Review focus

1. **A second client connects while the first is mid-command.** The first command
   still finishes and its response is dropped quietly. The new client's
   requests then run in order. Test in the listener suite.
2. **The edited scene has no LevelRoot, or no scene is open.** Status still
   answers with `level_root_path: null`, and place returns `no_level` or
   `no_edited_scene`. Test in the dispatcher suite.
3. **Garbage numbers**: NaN, infinity, strings, arrays of the wrong length, zero or
   negative size. Each returns `invalid_argument` naming the parameter, and the
   level is unchanged. Test in the dispatcher suite.
4. **A frame that declares 2 GiB, or arrives one byte at a time.** The first gets
   `frame_too_large` and a close. The second assembles correctly. Tests in the
   protocol suite.
5. **The listener is turned off with the discovery file present, or the editor
   quits.** The file is gone afterwards, and turning it on again gives a new port
   and token. Test in the listener suite.

---

### Task 1: Protocol helpers

**Files:**
- Create: `addons/hammerforge/mcp/hf_mcp_protocol.gd` (+ `.uid`)
- Test: `tests/test_mcp_protocol.gd`

**Interfaces (produces):**

```gdscript
class_name HFMcpProtocol extends RefCounted
const BRIDGE_VERSION := 1
const SCHEMA_VERSION := 1
const MAX_REQUEST_BYTES := 1 << 20
const MAX_RESPONSE_BYTES := 16 << 20
const ACTION_PREFIX := "MCP: "
const OPERATION_ID_MAX := 128

static func encode_frame(message: Dictionary) -> PackedByteArray
static func response_ok(id: String, result: Dictionary, revision: int, target_id: String, replayed := false) -> Dictionary
static func response_error(id: String, code: String, message: String, details: Dictionary, revision: int, target_id: String) -> Dictionary
static func error_frame(code: String, message: String, details := {}) -> Dictionary
static func fingerprint(method: String, params: Dictionary, expect_target: String) -> String
static func valid_operation_id(value) -> bool
# Argument readers return {"ok": true, "value": v} or {"ok": false, "error": {code, message, details}}
static func read_vec3(params: Dictionary, key: String, required: bool, default := Vector3.ZERO) -> Dictionary
static func read_positive_vec3(params: Dictionary, key: String, required: bool, default := Vector3.ONE) -> Dictionary
static func read_bool(params: Dictionary, key: String, default: bool) -> Dictionary
static func read_string(params: Dictionary, key: String, required: bool, default := "") -> Dictionary
static func vec3_to_array(v: Vector3) -> Array

class FrameReader extends RefCounted:
    func _init(max_bytes: int)
    func feed(bytes: PackedByteArray) -> void
    # {"status": "need_more"} | {"status": "frame", "message": Dictionary} | {"status": "error", "code": String, "message": String}
    func next() -> Dictionary
```

- [ ] **Step 1: Failing tests.** `tests/test_mcp_protocol.gd` covers:
  `encode_frame` gives a 4-byte big-endian length plus UTF-8 JSON; a frame fed
  whole, fed one byte at a time, and two frames fed in one buffer all come out
  as the same dictionaries; a declared length above `max_bytes` gives
  `frame_too_large` without waiting for the body; invalid JSON and a JSON array
  give `bad_request`; `fingerprint` is the same for dictionaries with keys in a
  different order and differs when one value differs; `valid_operation_id`
  accepts `"op-1.2:3_x"` and rejects `""`, 129 chars, `"a b"`, `5`;
  `read_vec3` rejects a missing required key, a 2-item array, a string item, NaN
  and INF (`invalid_argument` with `details.param`); `read_positive_vec3` rejects
  zero and negative components; `response_ok` and `response_error` carry
  `type: "response"`, the id, revision and target.
- [ ] **Step 2: Run, see them fail** (script missing):
  `cmd //c "C:\Godot\godot.cmd --headless -s res://addons/gut/gut_cmdln.gd --path . -gselect=test_mcp_protocol -gexit" > gut_p1.log 2>&1`
- [ ] **Step 3: Implement.** NaN and INF arrive as non-finite floats only from
  GDScript callers, since JSON cannot carry them, but a JSON number past the
  float range parses to INF, so the check is real. `FrameReader` keeps a
  `PackedByteArray`, decodes the length with `decode_u32` after swapping to big
  endian by hand (`(b0 << 24) | (b1 << 16) | (b2 << 8) | b3`), and parses with a
  `JSON` instance so bad input never prints an engine error.
- [ ] **Step 4: Run, see them pass.** Then `godot --headless --import --path .`
  so the `.uid` and class cache exist.
- [ ] **Step 5: Commit** `Add the MCP bridge's framing and argument helpers`.

### Task 2: Host, undo stand-in and dispatcher core

**Files:**
- Create: `addons/hammerforge/mcp/hf_mcp_host.gd`, `addons/hammerforge/mcp/hf_mcp_dispatcher.gd` (+ `.uid`)
- Create: `tests/mcp/mcp_undo_stand_in.gd` (+ `.uid`), a real `UndoRedo` behind the `EditorUndoRedoManager` call shape
- Test: `tests/test_mcp_dispatcher.gd`

**Interfaces (produces):**

```gdscript
class_name HFMcpHost extends RefCounted
func edited_scene_root() -> Node            # null when no scene is open
func level_root_in(scene_root: Node) -> Node
func undo_manager() -> Object               # EditorUndoRedoManager or the stand-in
func record_history(action_name: String) -> void
func editor_pid() -> int
func project_path() -> String
func hammerforge_version() -> String
func camera_pose() -> Variant               # {position, rotation_degrees, fov} or null
func next_frame() -> void                   # coroutine; awaits one process frame

class_name HFMcpDispatcher extends RefCounted
signal activity(method: String, running: bool)
const READ_ONLY := ["hf_get_status"]
const MUTATING := ["hf_place_brush"]
const OPERATION_CACHE_SIZE := 256
func _init(host: HFMcpHost)
func handle(request: Dictionary) -> Dictionary   # coroutine; returns a response dict
func revision() -> int
func current_target() -> Dictionary  # {target_id, scene_path, scene_name, level_root_path}
func is_known_method(method: String) -> bool
func runs_while_busy(method: String) -> bool     # true only for hf_get_status
```

Stand-in (tests and smoke only):

```gdscript
extends RefCounted
const SCENE_HISTORY := 1
const GLOBAL_HISTORY := 0
var scene_history := UndoRedo.new()
var global_history := UndoRedo.new()
func create_action(name: String, merge_mode := 0, _context = null, _backward := false, _mark_unsaved := true) -> void
func add_do_method(target: Object, method: StringName, ...args: Array) -> void
func add_undo_method(target: Object, method: StringName, ...args: Array) -> void
func add_do_property(target: Object, property: StringName, value) -> void
func add_undo_property(target: Object, property: StringName, value) -> void
func commit_action(execute := true) -> void
func get_object_history_id(_object: Object) -> int   # SCENE_HISTORY
func get_history_undo_redo(id: int) -> UndoRedo
func free_histories() -> void
```

Dispatcher behaviour:

- `handle()` reads `method`, `id` (string), `params` (dict, default `{}`),
  `operation_id`, `expect_target`. Unknown method: `unknown_method`. Bad shape:
  `bad_request`.
- Target: `edited_scene_root()`, then `level_root_in()`. `target_id` is
  `"%d:%d:%d" % [pid, scene id or 0, root id or 0]`. A change from the last seen
  target bumps the revision and moves the history connections (below).
- `expect_target` present and different: `target_changed` with
  `details.current` = `current_target()`. `hf_get_status` never checks it.
- Revision: connect `version_changed` on
  `undo_manager().get_history_undo_redo(get_object_history_id(root))` and on
  `get_history_undo_redo(0)`. If both are the same object, connect once. Each
  emission adds 1.
- Mutating with `operation_id`: invalid id gives `invalid_argument`. A cached
  entry with the same fingerprint returns its stored response with `replayed:
  true` and the request's own `id`. Another fingerprint gives
  `operation_id_conflict`. Successful responses go into the cache, evicting the
  oldest past 256.
- Wrapper `_run_mutation(verb, plan, apply: Callable)`: take
  `HFUndoHelper.capture_scope_or_state(root, plan.scope_ids)`, call `apply`. On
  `ok: false`, restore through `restore_brush_scope` or `restore_state` and
  answer with `details.rolled_back = true`. On success, call
  `HFUndoHelper.commit_completed(undo_manager(), root, ACTION_PREFIX + verb,
  before.state, Callable(host, "record_history"), before.scope_ids)`, then
  `await host.next_frame()`, record `_last_agent_revision`, and answer.
- `hf_get_status` result: `bridge_version`, `schema_version`,
  `hammerforge_version`, `editor_pid`, `project_path`, `target` (as
  `current_target()`), `revision`, `last_agent_revision` (null before any),
  `counts` `{brushes, entities}`, `grid_snap`, `camera`, `busy`.
- `hf_place_brush` params: `shape` (default `"box"`, names from the spec),
  `size` (positive vec3, required), `position` (vec3, required),
  `operation` (`"union"` | `"subtract"`), `snap` (default true). Snapping as
  in the spec: size to whole grid steps (at least one), lowest corner to the
  grid. Info `{shape, size, transform: Transform3D(Basis(), centre), operation,
  pending: subtract and root.pending_node != null, brush_id: root._next_brush_id()}`.
  `create_brush_from_info()` returning null gives `operation_failed`. Result:
  the brush in the spec's shape (`faces` included).

- [ ] **Step 1: Failing tests** in `tests/test_mcp_dispatcher.gd`. Each test
  builds a real `LevelRoot` (`auto_spawn_player = false`,
  `hflevel_autosave_enabled = false`, `add_child_autoqfree`) inside a scene
  root `Node3D`, a test host (inner class extending the preloaded host) whose
  `next_frame()` awaits `get_tree().process_frame`, and the stand-in, freed in
  `after_each`. Cases:
  - status without a scene: `target.target_id` ends `:0:0`, ok true.
  - status with a scene and no LevelRoot: `level_root_path` null; place gives
    `no_level`; the level count is unchanged.
  - status with a level: counts, `grid_snap`, revision an int, target ids match
    the instance ids.
  - place a box: ok; `create_brush_from_info` made one brush; the result's
    `position`, `size` and `rotation_degrees` echo what was applied; the scene
    history has one action named `MCP: place brush`; revision went up.
  - place snapping: grid 1, size `[1.2, 2.9, 3]` and position `[0.3, 1.5, 0]`
    give size `[1, 3, 3]` with the lowest corner on whole numbers; `snap: false`
    keeps the given values.
  - undo and redo through the stand-in restore and re-create the brush with the
    same `brush_id` (redo restores, it does not re-mint).
  - invalid input (NaN size, `size: [1, 2]`, `size: [0, 1, 1]`, unknown shape,
    `position: "x"`): `invalid_argument` naming the param; `capture_state()`
    equal before and after; nothing on the undo stack.
  - `operation_id` replay: the same id and params twice give one brush, the
    second response has `replayed: true` and the first's revision.
  - `operation_id` conflict: the same id with another position gives
    `operation_id_conflict`, still one brush.
  - `expect_target` stale: give a made-up target id; `target_changed`, with
    `details.current.target_id` the real one.
  - revision counts a foreign action: commit an action straight on the stand-in's
    scene history; revision goes up by exactly one.
  - failed apply rolls back: a test host whose LevelRoot subclass returns null
    from `create_brush_from_info` after adding a node; the answer is
    `operation_failed` with `rolled_back: true`, and state equals before.
- [ ] **Step 2: Run, see them fail** (`-gselect=test_mcp_dispatcher`).
- [ ] **Step 3: Implement** host base, stand-in and dispatcher.
- [ ] **Step 4: Run, see them pass.** Re-import for the new class names.
- [ ] **Step 5: Commit** `Add the MCP dispatcher with status and place brush`.

### Task 3: Listener

**Files:**
- Create: `addons/hammerforge/mcp/hf_mcp_listener.gd` (+ `.uid`)
- Test: `tests/test_mcp_listener.gd`

**Interfaces (produces):**

```gdscript
class_name HFMcpListener extends Node
enum State { OFF, LISTENING, CONNECTED, RUNNING, FAILED }
signal state_changed(state: int, detail: String)
const DISCOVERY_PATH := "res://.godot/hammerforge_mcp.json"
const HANDSHAKE_TIMEOUT_MS := 5000
var dispatcher: HFMcpDispatcher
var discovery_path := DISCOVERY_PATH
var allow_outside_editor := false     # tests and the smoke script only
func start() -> int                   # Error; OK when listening
func stop() -> void
func port() -> int
func state() -> int
```

Behaviour: `start()` refuses with `ERR_UNAVAILABLE` unless
`Engine.is_editor_hint() or allow_outside_editor`, makes a token, listens on
`127.0.0.1` port 0, writes the discovery file (the directory is made if
missing), sets 0600 where supported, and enables `_process`. `_process` accepts
connections into a pending list with a deadline, reads frames, answers the hello,
and moves an authenticated peer to active (closing the old one). Requests from the
active peer go into the queue. `hf_get_status` from the active peer is answered
at once even while busy. One queued command runs at a time through `await
dispatcher.handle()`, and the response goes to the peer that asked if it is still
connected. `stop()` closes everything, clears the queue, deletes the file, and
disables processing. `_exit_tree()` calls `stop()`.

- [ ] **Step 1: Failing tests** in `tests/test_mcp_listener.gd`. Each test makes
  a listener with `allow_outside_editor = true`, a scratch discovery path under
  `user://mcp_test/`, a dispatcher on the test host from task 2, then connects
  a `StreamPeerTCP` to `127.0.0.1:port()` and polls both sides frame by frame
  (`await get_tree().process_frame` in a bounded loop). Cases:
  - discovery file holds port, pid, a 64-hex token, `bridge_version` 1; it is
    gone after `stop()`; a second `start()` gives a new token.
  - `start()` without `allow_outside_editor` outside the editor: `ERR_UNAVAILABLE`,
    no file.
  - wrong token: an `auth_failed` error frame, then the peer is closed.
  - no hello within the timeout (set to 200 ms in the test): closed.
  - unsupported `bridge_version`: `unsupported_bridge_version` with
    `details.supported == [1]`.
  - hello, then `hf_get_status`: a response with the same string id.
  - two requests back to back: answered in order.
  - an oversized declared length: `frame_too_large`, closed.
  - a second client authenticates: the first is closed, the second works.
  - a request sent before the hello: `bad_request`, closed.
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, see them pass.**
- [ ] **Step 5: Commit** `Add the MCP listener: loopback TCP, token handshake, one command at a time`.

### Task 4: Plugin and dock

**Files:**
- Create: `addons/hammerforge/plugin_mcp.gd` (`HFPluginMcp`, static functions taking `plugin`) (+ `.uid`)
- Create: `addons/hammerforge/ui/hf_mcp_panel.gd` (`HFMcpPanel extends VBoxContainer`) (+ `.uid`)
- Modify: `addons/hammerforge/plugin.gd` (fields `_mcp_dispatcher`, `_mcp_listener`; `HFPluginMcp.setup(self)` after the dock is wired; `HFPluginMcp.teardown(self)` early in `_exit_tree`)
- Modify: `addons/hammerforge/ui/manage_tab_builder.gd` (an "Agent Bridge" collapsible section after Settings holding `dock.mcp_panel`)
- Modify: `addons/hammerforge/dock.gd` (`var mcp_panel`)
- Test: `tests/test_plugin_mcp.gd`

**Interfaces:**

```gdscript
class_name HFMcpPanel extends VBoxContainer
signal enable_toggled(enabled: bool)
func set_state(state: int, detail: String) -> void   # HFMcpListener.State
func is_enabled() -> bool

class_name HFPluginMcp extends RefCounted
static func setup(plugin: Object) -> void            # makes the dispatcher, connects the panel
static func teardown(plugin: Object) -> void         # stops and frees the listener
static func set_enabled(plugin: Object, enabled: bool) -> void
class EditorHost extends HFMcpHost                   # the real host over plugin and EditorInterface
```

- [ ] **Step 1: Failing tests** in `tests/test_plugin_mcp.gd`: the panel starts
  unchecked with state Off; toggling it emits `enable_toggled`; `set_state` per
  state writes the expected text and lamp severity; `set_enabled(plugin, true)`
  on a fake plugin with `allow_outside_editor` set through a test seam starts a
  listener (port above 0, file present) and `set_enabled(false)` removes it;
  `teardown` with the listener on leaves no file and no node.
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement.** `EditorHost.level_root_in()` calls
  `plugin._get_level_root()` when the scene root is the edited one, so discovery
  matches every other plugin path. `record_history` calls
  `plugin._record_history`. `camera_pose` reads
  `EditorInterface.get_editor_viewport_3d(0).get_camera_3d()`.
- [ ] **Step 4: Run, see them pass,** plus `-gselect=test_plugin` for the
  plugin boundary suites and `tests/test_dead_declarations` if present.
- [ ] **Step 5: Commit** `Turn the MCP bridge on from the Test tab`.

### Task 5: Python package

**Files:**
- Create: `hammerforge_mcp/pyproject.toml`, `hammerforge_mcp/README.md`
- Create: `hammerforge_mcp/src/hammerforge_mcp/{__init__,__main__,discovery,framing,bridge,catalogue,server}.py`
- Create: `hammerforge_mcp/tests/{conftest,test_framing,test_discovery,test_bridge,test_server}.py`

**Interfaces:**

```python
# framing.py
MAX_REQUEST_BYTES = 1 << 20; MAX_RESPONSE_BYTES = 16 << 20
def encode_frame(message: dict) -> bytes
async def read_frame(reader: asyncio.StreamReader, max_bytes: int) -> dict

# discovery.py
@dataclass(frozen=True)
class Discovery: port: int; pid: int; token: str; bridge_version: int; project_path: str
def discovery_path(project: Path) -> Path          # <project>/.godot/hammerforge_mcp.json
def read_discovery(project: Path) -> Discovery      # raises DiscoveryError with a fix-it message
def pid_alive(pid: int) -> bool

# bridge.py
class BridgeError(Exception): code: str
class Bridge:
    def __init__(self, project: Path, *, connect_timeout: float = 5.0)
    async def call(self, method: str, params: dict, *, mutating: bool, timeout: float,
                   operation_id: str | None = None) -> dict    # the response dict
    async def close(self) -> None

# catalogue.py
@dataclass(frozen=True)
class ToolSpec: name: str; title: str; description: str; mutating: bool; timeout: float; annotations: ToolAnnotations
TOOLS: dict[str, ToolSpec]

# server.py
def build_server(bridge: Bridge) -> MCPServer
def main(argv: list[str] | None = None) -> int
```

- [ ] **Step 1: Failing tests.** `test_framing`: round trip, split reads,
  oversize raises. `test_discovery`: missing file says how to turn the bridge on,
  a dead pid says the editor exited, a good file parses. `test_bridge` against an
  asyncio fake listener: hello carries the token; a request id is a string and
  is matched; `expect_target` is sent from the last status; a dropped connection
  after a mutating request is retried once with the same `operation_id`;
  `auth_failed` raises `BridgeError("auth_failed")`. `test_server` through
  `mcp.Client(server)`: `list_tools` gives exactly the catalogue with
  annotations; `hf_place_brush` maps an ok response to `structured_content`
  with `ok: true`; a domain error maps to `is_error` false and `ok: false`; a
  bridge failure maps to `is_error` true.
- [ ] **Step 2:** `cd hammerforge_mcp; uv run --extra test pytest -q`. They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Tests pass; `ruff check hammerforge_mcp/`, `ruff format --check hammerforge_mcp/`.
- [ ] **Step 5: Commit** `Add the hammerforge-mcp Python server`.

### Task 6: Smoke test and CI

**Files:**
- Create: `tools/mcp_bridge_smoke.gd` (+ `.uid`): a SceneTree script that builds a
  scene root and LevelRoot on its first `_process` (an `_initialize` that builds a
  LevelRoot hangs headless), starts a listener with `allow_outside_editor`, the
  stand-in, and a discovery path from `--discovery=<path>`, and quits after
  `--seconds=<n>` or when told `hf_smoke_quit`.
- Create: `hammerforge_mcp/src/hammerforge_mcp/smoke.py`: connect through the
  bridge, status, place, replay by `operation_id`, check one brush, exit 0.
- Modify: `.github/workflows/ci.yml`: the tooling job runs ruff on
  `hammerforge_mcp/` and pytest; a new `mcp-bridge-smoke` job installs Godot the
  way the shards do and runs the smoke pair.
- Modify: `tools/run_local_checks.py` `CHECKS`, `pyproject.toml` ruff include,
  `requirements-ci.txt` (`mcp==2.3.0`, `pytest==<current>`).

- [ ] **Step 1:** Run the smoke pair locally: it fails before the script exists.
- [ ] **Step 2: Implement** both halves; the pair passes locally.
- [ ] **Step 3:** `python tools/run_local_checks.py` and `--check` pass, with the
  new CI lines mirrored.
- [ ] **Step 4: Commit** `Run a cross-process bridge smoke test in CI`.

### Task 7: Docs

**Files:** `AI.md`, `DEVELOPMENT.md` (Editor Bridges section), `CONTRIBUTING.md:132`,
`README.md` (Editor bridges), `SECURITY.md` (bridge section),
`docs/HammerForge_Install_Upgrade.md:57`, `docs/features.md`, `CHANGELOG.md`,
`hammerforge_mcp/README.md`, `.github/pull_request_template.md` if it names the
old rule.

- [ ] **Step 1:** Each "no bridge here" sentence becomes the true one: HammerForge
  has its own bridge, off until you turn it on in the Test tab, loopback only,
  token in `.godot/`. The note that "Godot MCP Native" is not Didi stays.
  Third-party bridges are still not vendored, and `check_project_settings.py` still
  refuses them.
- [ ] **Step 2:** `python tools/check_changelog.py` passes; `mkdocs build --strict`
  if the docs job would run it.
- [ ] **Step 3: Commit** `Say HammerForge has its own agent bridge, off by default`.

### Task 8: Vibe test, review, PR

- [ ] **Step 1:** Open the editor on the worktree, turn the bridge on, run
  `hammerforge-mcp` under a real MCP client (the SDK's stdio `Client` from a
  script), place a brush, see it in the viewport, check one Ctrl+Z takes it away
  and the History list shows `MCP: place brush`, check the revision does not move
  on its own after the response, switch scene tabs and see `target_changed`.
  Record findings in the PR body.
- [ ] **Step 2:** Full GUT run, the warnings gate, `run_local_checks`, pytest,
  smoke.
- [ ] **Step 3:** Whole-branch review by a fresh reviewer. Fix what holds up.
- [ ] **Step 4:** Push `mcp/design`, open the PR as saworbit, wait on CI in the
  background, merge on green.
