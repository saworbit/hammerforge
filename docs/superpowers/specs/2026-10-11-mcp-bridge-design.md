# MCP bridge

Approved 2026-10-11. Built from `HammerForge_MCP_Spec.md` v0.3 (the "source
spec"). This document is the mapping and protocol appendix that spec asks for in
sections 10 and 12, plus every place where reading the code changed one of its
assumptions.

## What it is

An agent that speaks MCP drives a live HammerForge session in the Godot editor.
It can build a level, change it, look at it, bake it and hand the baked scene
to Didi. Three layers:

```
MCP client (stdio)
   |
hammerforge-mcp (Python, mcp SDK 2.x, top-level hammerforge_mcp/ package)
   |  TCP 127.0.0.1, length-prefixed JSON, token auth
HFMcpListener (Node owned by plugin.gd, polled in _process, main thread only)
   |
HFMcpDispatcher (RefCounted: target, revision, operation cache, one handler per tool)
   |
LevelRoot facade and HFUndoHelper
```

## Decisions

Decided by Shane on 2026-10-11:

- The Python server lives in a top-level `hammerforge_mcp/` package with its own
  `pyproject.toml`. It is not in the Asset Library zip. Users run it with
  `uvx --from git+https://github.com/saworbit/hammerforge#subdirectory=hammerforge_mcp hammerforge-mcp`.
- `hf_bake` writes `<scene dir>/<scene name>_mcp.tscn`, overwritten on each
  agent bake, and never touches the user's own `<scene>_game.tscn`.
- Every command runs through one wrapper: capture, run the facade call, then
  `HFUndoHelper.commit_completed()` or restore (approach A below).

Decided from evidence, with the reasoning kept here:

| Topic | Source spec | This design | Why |
|---|---|---|---|
| Bake artifact | "Calls existing `bake()`" and returns output paths | Bake, then `export_game_scene()` to the `_mcp.tscn` path | `bake()` writes no file. It only builds `BakedGeometry` nodes. The one file writer is Export Game Scene (`dock_manage_handler.gd` `_bake_game_scene`). |
| Scene revision | "monotonic scene revision" | A counter the dispatcher keeps, bumped by `version_changed` on the scene's own `UndoRedo` and on the global one | Nothing in the repo counts revisions. `UndoRedo.get_version()` falls on undo. A probe showed undo A then commit C gives the same version as committing B, so no version tuple can stand in. `version_changed` fires on every commit, undo, redo and merge. |
| Top action check | "top action matches the expected name pattern" | `UndoRedo.get_current_action_name().begins_with("MCP: ")` on the scene history | No repo code reads action names yet. The 4.7 API has the call. |
| Create starter | "uses existing `create_starter_level` path" | Same path, fixed to record one undo step | It records two when no LevelRoot exists ("Create HammerForge Level", then "New HammerForge Level"), though its comment says one (`tests/test_starter_level_rebuild.gd` confirms two). |
| Return values | not covered | Handlers call the facade directly and read the result | `HFUndoHelper.commit()` discards the method's return value and silently does nothing when the method is missing. |
| Material ids | "Catalogue of valid material IDs" | `resource_path` of the palette material, or `palette:<slot>` for one saved inside the scene | A face stores an int palette slot, and removing a palette entry renumbers every face. |
| Extrude | "Selector: face index, normal or side" | New `LevelRoot.extrude_face_info(brush_id, face_index, distance)` shared with the Extrude tool | Extrude only exists as a pointer gesture. It adds a new box on the face and leaves the source brush alone, and the tool description says so. |
| Rotation | "Rotation is degrees, Euler XYZ" | New `LevelRoot.set_brush_rotation_by_id()` through `HFTransformSystem.set_rotation()` | Only relative per-axis rotation exists. "Euler XYZ" means Godot's `EULER_ORDER_XYZ`, used both ways so `hf_get_brushes` round-trips. |
| Resize | "Change size" | Refused on CUSTOM brushes with `unsupported_shape` | `DraftBrush._update_visuals` keeps a CUSTOM brush's faces, so a new size changes nothing (merged, clipped, bevelled and polygon brushes). |
| Scene switch | "rejected if the target no longer matches" | Checked against `EditorInterface.get_edited_scene_root()` on every command | Nothing listens for a scene tab change. `plugin.active_root` goes stale until the next selection change. |
| Hollow, clip, merge | "expose only if stable" | Deferred | They are undoable, but none returns the new brush ids, and the UI clip has a defect (see Found along the way). |
| Discovery file | `res://.hammerforge_mcp.json` | `res://.godot/hammerforge_mcp/discovery.json`, in a folder closed to other users | It holds the token. Godot's default `.gitignore` covers `.godot/`, and an export never includes it. A project-root file is one `git add .` from being committed. |
| Exports | "must not be present in exported games" | Never instantiated outside the editor, and guarded | There is no export filter. Every editor script under `addons/hammerforge/` already ships inside a game export unused, `plugin.gd` and the dock included. The listener refuses to start unless `Engine.is_editor_hint()`, and only `plugin.gd` creates it. |
| MCP revision | "2026-07-28 is the reference" | 2026-07-28, through `mcp>=2.3,<3` | The 2.3.0 SDK speaks it and answers `server/discover` on stdio. It falls back to 2025-11-25 for older clients. |

## Approach

Three ways to run a command were weighed:

- **A. One wrapper (chosen).** Each tool is a handler that checks its arguments
  and target first, then the wrapper takes `capture_scope_or_state()`, calls the
  facade method directly, and reads its real result. Success commits with
  `commit_completed()` under the name `MCP: <verb>`. Failure restores the captured
  state. `hf_batch` is the same wrapper around several handlers. Validate + Fix
  and the displacement edits already work this way, and redo restores the
  recorded result, so brush ids survive it.
- **B. `HFUndoHelper.commit()` by method name**, like the toolbar. It loses return
  values, redo re-runs the method and re-mints ids, and it has no way to say
  "failed, nothing changed".
- **C. The UI paths** (dock handlers, `plugin_commands`). They read selection, the
  active tool and dock widgets, which the source spec rules out.

## Components

### GDScript, `addons/hammerforge/mcp/`

- `hf_mcp_protocol.gd`, `class_name HFMcpProtocol`. Pure statics: frame encode
  and decode, envelope builders, error codes, argument readers (`read_vec3`,
  `read_finite`, `read_string`), canonical fingerprinting. No scene access.
- `hf_mcp_listener.gd`, `class_name HFMcpListener extends Node`. `TCPServer` on
  `127.0.0.1` port 0, polled in `_process` (Godot sockets are non-blocking, so
  there are no threads). Handshake, frame buffer, FIFO queue, one command at a
  time, discovery file write and delete, status signal for the dock.
- `hf_mcp_dispatcher.gd`, `class_name HFMcpDispatcher extends RefCounted`. Target
  resolution, revision, `operation_id` cache, the approach-A wrapper, and the three
  tools that do not go through it: create starter, undo, redo. It talks to the
  editor through a host object and never holds a node across commands, only ids.
- `hf_mcp_tools.gd`, `class_name HFMcpTools extends RefCounted`. Each tool's
  argument checks (`_check_<tool>` returning `{ok, scope_ids, apply}`), its facade
  calls (`_apply_<tool>`), the reads, and brushes and the palette as plain data.
  Split out in phase 2, when the dispatcher passed 1,200 lines.
- `hf_mcp_host.gd`, `class_name HFMcpHost extends RefCounted`. The seam between the
  dispatcher and the editor: edited scene root, level root lookup, undo manager,
  history callback, starter creation, viewport, collision mask. `plugin.gd` builds
  the real one. Tests build one with a stand-in undo manager.

### Plugin and dock

- `plugin.gd` creates the dispatcher once per editor session and the listener
  only when the user turns it on. It frees the listener in `_exit_tree` before the
  dock goes. The dispatcher outlives a listener restart, so the operation cache
  lasts the editor session as the source spec asks.
- The dock's Test tab, Settings section, gets an "Allow agent connections (MCP)"
  check box, a status lamp and one line of status: Off, Listening on :53121,
  Agent connected, Running: place brush. It is never saved, so the listener is off
  after every editor start.

### Python, `hammerforge_mcp/`

```
hammerforge_mcp/
  pyproject.toml         hammerforge-mcp, requires-python >=3.10, mcp>=2.3,<3
  README.md
  src/hammerforge_mcp/
    __init__.py, __main__.py
    discovery.py         read and check .godot/hammerforge_mcp/discovery.json
    framing.py           length-prefixed JSON, limits
    bridge.py            asyncio client: handshake, correlation, reconnect, retry
    catalogue.py         tool names, descriptions, input models, annotations, timeouts
    server.py            MCPServer wiring, result mapping, CLI
  tests/                 pytest: framing, discovery, bridge against a fake listener,
                         server through the SDK's in-process Client
```

## Bridge protocol (bridge_version 1)

### Discovery

On enable the listener writes `res://.godot/hammerforge_mcp/discovery.json`:

```json
{"bridge_version": 1, "port": 53121, "pid": 4242, "token": "<64 hex chars>",
 "project_path": "C:/games/arena/", "hammerforge_version": "0.3.2",
 "started_at": "2026-10-11T09:30:00"}
```

The token is 32 bytes from `Crypto.generate_random_bytes()`, new on every enable.
The file is deleted on disable and in `_exit_tree`. Before the token is written,
the `hammerforge_mcp/` folder is closed to everyone but the user: mode 0700 where
the platform has unix permissions, and on Windows its inherited access rules are
replaced with the user alone (`icacls /inheritance:r /grant:r`), since a project
at the root of a drive inherits read access for every local user. Closing the
folder rather than the file matters: a file opened before a chmod keeps its
handle, but nobody can open anything in a folder they cannot search. If the
folder cannot be closed (a chmod refused or not read back as 0700, no
`USERNAME`, a failed `icacls`), no token is written and the listener goes to
FAILED naming the folder (#1109). The threat
model is other users on the machine, not other processes of the same user, and
the docs say so.

`--discovery <file>` (or `HAMMERFORGE_MCP_DISCOVERY`) points the server at a
discovery file elsewhere. The smoke test uses it so it never touches the file of
an editor open on the same project.

`hammerforge-mcp --project <path>` (or `HAMMERFORGE_PROJECT`) reads the file.
It refuses a file whose pid is not running ("the editor that wrote this has
exited; turn the bridge on again") and re-reads it on every reconnect, since a
restart changes port and token.

### Framing

Each frame is a 4-byte unsigned big-endian length, then that many bytes of UTF-8
JSON holding one object. Limits: a request at most 1 MiB, a response at most
16 MiB (a 1920x1080 PNG screenshot in base64 fits). The Python codec rejects
non-finite numbers and more than 64 nested containers on reads and writes, and
maps invalid UTF-8, serialization and nesting failures to bridge errors without
echoing the payload. A frame over the limit
gets a `frame_too_large` error and the connection is closed.

### Handshake

The first frame must arrive within 5 seconds:

```json
{"type": "hello", "bridge_version": 1, "token": "...",
 "client": {"name": "hammerforge-mcp", "version": "0.1.0"}}
```

The reply is `welcome` or an `error` frame, and the connection is closed after an
error:

```json
{"type": "welcome", "bridge_version": 1, "hammerforge_version": "0.3.2",
 "schema_version": 1, "editor_pid": 4242, "project_path": "C:/games/arena/"}
```

Codes: `auth_failed` (token compared over its whole length),
`unsupported_bridge_version` (details list the versions the listener speaks),
`bad_request`. One authenticated client at a time. A second one that
authenticates replaces the first, which is how a Python reconnect after a dropped
socket gets back in. A hello with `"role": "observer"` is let in beside it
instead, up to four at once; an observer gets status and a `bad_request` for
anything else. `hammerforge-mcp --check` connects as one (#1060).

### Requests and responses

```json
{"type": "request", "id": "r7", "method": "hf_place_brush",
 "params": {...}, "operation_id": "b1f0...", "expect_target": "4242:1234:5678"}

{"type": "response", "id": "r7", "ok": true, "result": {...},
 "revision": 12, "target_id": "4242:1234:5678", "replayed": false}

{"type": "response", "id": "r7", "ok": false,
 "error": {"code": "brush_not_found", "message": "...", "details": {...}},
 "revision": 12, "target_id": "4242:1234:5678"}
```

`id` is the client's and is echoed. `method` must be in the catalogue, or the
response is `unknown_method`. Every response carries the revision and target at
the time it was written.

### Error codes

Domain errors come back as a successful MCP tool result whose structured content
is `{"ok": false, "error": {...}}`, as the source spec asks. Protocol and
internal errors become `isError` results.

| Code | Kind | Meaning |
|---|---|---|
| `no_edited_scene` | domain | No scene is open in the editor |
| `no_level` | domain | The edited scene has no LevelRoot |
| `level_exists` | domain | `hf_create_starter` on a scene that already has one |
| `target_changed` | domain | `expect_target` is not the current target. Call `hf_get_status` |
| `brush_not_found` | domain | No brush with that id |
| `entity_not_found` | domain | No entity at that path among the level's entities |
| `face_not_found` | domain | The face selector matched nothing |
| `ambiguous_face` | domain | Two faces tie for a side or normal selector |
| `unsupported_shape` | domain | Resize on a CUSTOM brush |
| `unknown_material` / `ambiguous_material` | domain | Material id or name not in the palette, or two names match |
| `invalid_argument` | domain | A parameter failed validation. `details.param` names it |
| `operation_failed` | domain | The facade refused. The message is its `HFOpResult` text |
| `operation_id_conflict` | domain | Same `operation_id`, different arguments |
| `undo_conflict` / `redo_conflict` | domain | The top action is not ours, or the revision moved |
| `nothing_to_undo` / `nothing_to_redo` | domain | Empty stack |
| `bake_busy` / `bake_failed` / `export_failed` | domain | Bake states |
| `screenshot_unavailable` | domain | No rendering viewport (headless editor) |
| `no_bake` | domain | A screenshot asked for `show: "baked"` and the level has no baked geometry |
| `batch_failed` | domain | `details.index` and `details.error` name the op that failed |
| `busy` | domain | A command arrived while another still runs (only after a listener restart; the listener queues otherwise). `details.busy` names it |
| `bad_request`, `unknown_method`, `frame_too_large`, `auth_failed`, `unsupported_bridge_version` | protocol | |
| `internal_error` | protocol | A handler returned something that is not a result. Logged with the request |

## Execution contract

### Target

`target_id` is `"<editor pid>:<edited scene root instance id>:<LevelRoot instance
id or 0>"`. Godot object ids carry a validator, so they are not reused while the
editor runs. `hf_get_status` returns it with the scene path, scene name and the
LevelRoot's path in the scene.

The Python server attaches. It sends `expect_target` on every request with the
target from the last `hf_get_status` or successful `hf_create_starter`. If the
current target differs, the command fails with `target_changed` and the current
target in `details`. The server does not follow it on its own: the agent calls
`hf_get_status`, which re-attaches. A reconnect resends the original target with
the original operation id. Ordinary replies cannot reattach a target; status
and starter replies update it only when newer than the last attachment reply,
so an out-of-order reply cannot replace a more recent attachment.

### Revision

A non-negative integer for the listener's life. It goes up by one on every
`version_changed` from the target scene's `UndoRedo` and from the global history's
(`EditorUndoRedoManager.get_history_undo_redo()`), and on every target change.
Since #1353 the pending cuts `hf_bake` applies go in as a step of the agent's
own, `MCP: apply pending cuts`, so the agent's undo chain reaches past the bake.
It never goes down. Every response carries it.

A mutating command waits one process frame after it commits before it reads the
revision. Deferred work the commit sets off (`plugin_undo_events` queues a brush
reconcile) then lands before the number is reported, not after.

Edits that never reach an undo history do not move it. Those are scripts and tool
scripts writing to nodes directly. The docs say so.

### Queue

Commands run one at a time in arrival order on the main thread. A command that
awaits (`hf_bake`, `hf_viewport_screenshot`) holds the queue until it finishes.
`hf_get_status` is the one exception: it is answered at once even while another
command is running, and says `busy: "<method>"`.

Turning the listener off and on while a bake awaits gives it a fresh queue while
the dispatcher is still inside the bake. The dispatcher refuses anything but
status with `busy` until it is out, so two commands never run at once.

### operation_id

Every mutating request may carry one: 1 to 128 characters from
`[A-Za-z0-9._:-]`. The Python server makes a UUID for any mutating call that
lacks one, and reuses it when it resends after a lost response. It also reuses
the id of a sent change left without an answer, including a cancelled call or a
malformed reply, when the same change and arguments are asked for on the same
target. An unsent change and a change on another target get fresh ids. Not for
`hf_undo`, `hf_redo` and `hf_bake`: their arguments do not say which change they
are, so a second undo gets a new id and undoes
another step. A caller that means a retry passes the id the timeout gave.

The dispatcher keeps the last 256 successful mutating responses keyed by
`operation_id`, with a fingerprint of `{method, params, expect_target}`
(`JSON.stringify(..., "", true).sha256_text()` on the parsed values, so
formatting does not matter).

- Same id and fingerprint: the cached response comes back with `replayed: true`
  and its original revision. Nothing runs.
- Same id, different fingerprint: `operation_id_conflict`.
- Same id while the first is still queued or running: it waits for that result.
- A failed command is not cached. It changed nothing, so running it again is safe.
- A replayed `hf_bake` answer has `current` worked out again, so an old bake is
  never handed on as the level's.

The cache belongs to the dispatcher, so it survives turning the listener off and
on, and lasts the editor session.

### Commit and failure

```
handler.check(params)            -> error, or a plan. Nothing touched yet
before := capture_scope_or_state(root, plan.scope_ids)
result := handler.apply(plan)    -> facade calls, no undo
if result failed:
    restore before (restore_brush_scope or restore_state)
    respond ok:false, details.rolled_back = true
else:
    commit_completed(undo, root, "MCP: <verb>", before, record_history, scope_ids)
    await one frame, read revision
    respond ok:true
```

`commit_completed()` uses merge mode 0, so an MCP action never merges into a
human's. It fires the plugin's history callback, so MCP actions appear in the
dock's History list and the Operation Replay timeline under their `MCP: ` names.
If a restore itself fails, the response says `rolled_back: false` and lists the
brush ids that differ from before, which is the "report exactly what changed" the
source spec asks for.

### Undo and redo

`hf_undo` runs only when all of these hold, and otherwise returns `undo_conflict`
(or `nothing_to_undo`) and does nothing:

1. The target matches.
2. The scene history's `get_current_action_name()` starts with `MCP: `.
3. The current revision equals the revision the dispatcher returned for the last
   successful mutating agent command, `hf_undo` and `hf_redo` included.

It then calls `undo()` on the scene history's `UndoRedo`, as the dock's own Undo
button does. `hf_redo` is the mirror: the action at `get_current_action() + 1`
must start with `MCP: `.

Rule 3 means a human edit, even one the human then undid, ends the agent's undo
chain. That is the conservative reading of "does not reverse unrelated human
edits": a human undo is an edit too. A move to another scene or level ends it as
well: the dispatcher forgets the agent's last revision when the target changes,
and after each step's frame it keeps the revision only if the editor is still on
the level the step was meant for.

Known limit (#1028): the step goes through the history's own `UndoRedo`, as the
dock's Undo button does, because 4.7 gives a script no way to ask
`EditorUndoRedoManager` to undo. The manager does not hear about it, so after an
`hf_undo` the user's Ctrl+Shift+Z cannot redo the agent's step; `hf_redo` and the
dock's Redo can. The dispatcher calls the plugin's own version-changed handler
after a step so previews and the brush tracker still catch up.

## Tool mapping

Spatial conventions, stated in every spatial tool's description: Godot Y-up,
metres, world space. `size` is full extents. Rotation is degrees, Euler order
XYZ (`EULER_ORDER_XYZ`). Positions are brush centres. With `snap` on (the
default), size snaps to whole grid steps, at least one, and an unrotated brush's
lowest corner snaps to the grid so its faces sit on grid lines, as a drawn brush's
do. A rotated brush snaps its centre. Every result echoes the values actually
applied.

Brush shapes are `BrushShape` names in lower case: `box`, `cylinder`, `sphere`,
`cone`, `wedge`, `pyramid`, `prism_tri`, `prism_pent`, `ellipsoid`, `capsule`,
`torus`, `tetrahedron`, `octahedron`, `dodecahedron`, `icosahedron`.

Face selectors: an int index; a side `"+x" | "-x" | "+y" | "-y" | "+z" | "-z"`
(world axis); or `{"normal": [x, y, z]}`. A side or normal picks the face whose
world normal has the largest dot product with it, which must exceed 0.7. A tie
within 0.001 is `ambiguous_face`, with the candidates in `details`. Box faces
are stored +X, -X, +Y, -Y, +Z, -Z in local space.

A brush in a result:

```json
{"brush_id": "1234_5", "name": "", "shape": "box", "operation": "union",
 "pending": false, "committed": false,
 "position": [0, 1.5, 0], "rotation_degrees": [0, 0, 0], "size": [4, 3, 4],
 "bounds": {"min": [-2, 0, -2], "max": [2, 3, 2]},
 "material_id": null,
 "faces": [{"index": 0, "normal": [1, 0, 0], "center": [2, 1.5, 0],
            "material_id": "res://.../proto_grid_gray.tres", "material_name": "proto_grid_gray"}]}
```

| Tool | Facade call | Checks before anything changes | Undo | Result |
|---|---|---|---|---|
| `hf_get_status` | `get_brush_count`, entity count, `grid_snap`, editor camera, the last `hf_validate`'s counts (never worked out here, #1048), `HFPlayerMetrics.standing()` | none | none | identity, target, revision, counts, grid, last bake, `bake_current`, validation counts and `validation_revision`, `player`, camera, `busy` |
| `hf_create_starter` | `plugin.create_starter_level("MCP: create starter")`, made one step | an edited scene; no LevelRoot in it (`level_exists`) | the plugin method's single action, named `MCP: create starter` | new target, spawn position, floor top |
| `hf_place_brush` | `create_brush_from_info({shape, size, transform, operation, pending, brush_id: root._next_brush_id(), sides, name})`, then `set_brush_rotation_by_id()` for `rotation_degrees` and `assign_material_to_whole_brushes(slot, [id])` when a material is given (#1039) | shape known; size finite and positive; position finite; sides 5 to 64 on a cylinder or cone, 3 to 64 on a pyramid; material resolves | wrapper, whole level, `MCP: place brush` | the brush; `snapped` only when snapping moved it, with `requested` (#1038) |
| `hf_transform_brush` | `set_brush_transform_by_id(id, size, position)` and `set_brush_rotation_by_id(id, degrees)` (new) | brush exists; at least one of position or rotation; finite | wrapper, scope `[id]`, `MCP: transform brush` | the brush |
| `hf_resize_brush` | `set_brush_transform_by_id(id, size, position)` | brush exists; not CUSTOM; size finite and positive | wrapper, scope `[id]`, `MCP: resize brush` | the brush |
| `hf_delete_brush` | `delete_brush_by_id(id)` (`HFOpResult`) | brush exists | wrapper, whole level (it also removes I/O links aimed at the brush), `MCP: delete brush` | `{deleted: id}` |
| `hf_extrude_face` | `extrude_face_info(id, face, distance)` (new), then `create_brush_from_info(info)` | brush and face exist; distance finite, positive, at most 256 | wrapper, whole level, `MCP: extrude face` | the new brush and its source |
| `hf_assign_material` | `assign_material_to_faces_by_id(id, faces, slot)` or `assign_material_to_whole_brushes(slot, [id])` | brush; faces; material in the palette | wrapper, scope `[id]`, `MCP: assign material` | the brush |
| `hf_get_materials` | `get_materials()`, `get_material_names()` | level | none | `[{id, name, slot}]` |
| `hf_set_spawn` | `spawn_system.get_active_spawn()` or `create_default_spawn()`, then `global_position` and yaw; `validate_spawn()` for the answer | level; position finite | wrapper, whole level, `MCP: set spawn` | spawn position, feet, yaw, `facing`, validation (blocked, suggested position as feet, #1034) |
| `hf_place_entity` | a `DraftEntity` with the definition's defaults, a preset's values and the given properties, `add_entity()`, then its transform (#1051) | a point entity class (a definition with a node `class`, not `player_start`); position finite; each property declared and of its type; preset known | wrapper, whole level, `MCP: place entity` | the entity |
| `hf_get_entities` | `entities_node` children | level | none | `[{entity, entity_class, name, position, rotation_degrees, properties, outputs}]` |
| `hf_transform_entity` | the entity's `global_transform` (#1082) | an entity at that path, not the spawn; position or rotation, finite | wrapper, whole level, `MCP: transform entity` | the entity |
| `hf_set_entity_properties` | `set_entity_properties(entity, values)` (#1082), on every brush of a brush entity (#1105) | entity as above, or a `brush_id` whose brush has a brush entity class, never both; each property declared by the class and of its type; preset known | wrapper, whole level for an entity, scope the entity's brushes for a brush entity, `MCP: set entity properties` | the entity, or the brush |
| `hf_delete_entity` | `delete_entities_by_paths([path])`, which also drops the wires aimed at it (#1082) | entity as above | wrapper, whole level, `MCP: delete entity` | `{deleted: path}` |
| `hf_add_entity_output` | `add_entity_output(entity, output, target, input, parameter, delay, fire_once)` (#1083) | entity as above, or a `brush_id` whose brush has a brush entity class (#1098), never both; the output declared by its class; the input declared by every node answering to the target name, if any does; delay zero or more | wrapper, whole level, `MCP: add entity output` | the entity with its outputs, or the brush |
| `hf_remove_entity_output` | `remove_entity_output(source, index)` (#1096) | a source as for `hf_add_entity_output`; index a whole number below its output count | wrapper, whole level, `MCP: remove entity output` | the entity with its outputs, or the brush |
| `hf_set_brush_entity` | `tie_brushes_to_entity(brush_ids, class, name)` (#1098), one tie and one entity for every id (#1105); `untie_brushes_from_entity(brush_ids)` for class `none` | one or more solid brushes, each once; a class the definitions mark `is_brush_entity`, or `none` with no name and every brush an entity; name not blank, or the one name the brushes share kept | wrapper, scope `brush_ids`, `MCP: set brush entity` | `{brushes}`, each with `brush_entity` |
| `hf_batch` | each op's `apply` inside one wrapper | 1 to 100 ops; each op is place, transform, resize, delete, extrude, assign material, set spawn, or place, transform, set properties of, delete, wire or unwire an entity, or set a brush entity; `$N.brush_id` and `$N.entity` name what op N made; each op's `check` passes (checked in order, against the state the earlier ops leave) | wrapper, whole level, `MCP: batch (N ops)` | results in order |
| `hf_bake` | `root.bake(true, false, mask)` run from a dispatcher-owned object and watched each frame (a coroutine waiting inside a freed LevelRoot never resumes, so a closed tab answers `target_changed` instead of hanging), then `export_game_scene(path, {bake meta})` (new optional metadata argument), then `EditorFileSystem.update_file(path)` | level; `not is_bake_in_flight()` | none of its own (files and baked nodes are not authoring state); the pending cuts it applies go in first as one step, `MCP: apply pending cuts` (#1353) | `bake_id`, `source_revision`, `revision`, `current`, artifact path (res:// and absolute), status, warnings (`user_message` at warning level and up), duration |
| `hf_validate` | `check_bake_issues()`, `spawn_system.layout_issues()`, `validate_level(false).findings` | level | none | issues `[{type, severity, message, brush_id?, other_brush_id?, entity?, fix?}]` and counts; one per type, message and brush or entity |
| `hf_get_brushes` | `get_brush_info_from_node()` over draft, pending and committed brushes, faces via `FaceData.normal_through()` and the vertex mean | level; filters valid | none | brushes, `total`, `truncated` |
| `hf_undo` / `hf_redo` | the scene history's `UndoRedo.undo()` / `redo()` | the three undo rules | the editor's own | the action name undone or redone |
| `hf_viewport_screenshot` | no focus: `get_editor_viewport_3d(0).get_texture().get_image()`; focus or `camera`: a temporary `SubViewport` sharing the editor viewport's `World3D`, its own `Camera3D` framed on the bounds' projected corners from `look_from` or the editor's heading, or placed where `camera` says; `hide` and `hide_cuts` move those brushes' drawings to render layer 20, which that camera does not draw, for the two frames (#1040); `show: "baked"` moves every brush there, leaving the baked geometry (#1084); freed after | a rendering viewport; width 64 to 1920, height 64 to 1080 (a plain shot shrinks to fit, never grows) | none | PNG base64, size, revision, camera, `show`, and `bake_current` for a baked shot. The editor camera is never moved, so nothing needs restoring |

`hf_get_brushes` filters: `brush_ids`, `bounds` (`{min, max}`, intersecting),
`include_faces` (default true), `limit` (default 200, at most 2000).

`hf_batch` references: a string parameter `"$N.brush_id"` is replaced with the
`brush_id` result of op N, so a batch can place a brush and then change it. The
Python server checks each op's params against the same schema as the tool alone,
and refuses a key that tool does not take.

`get_brush_info_from_node()` writes an id onto a brush that has none (a read that
writes). Handlers only ever read brushes that already have ids. A brush without
one is reported with `brush_id: null` and never passed to it.

`hf_bake` metadata on the exported scene root, under `hammerforge_bake`:
`{bake_id, source_revision, target_id, baked_at}`. Didi can check the artifact it
loads is the bake it was told about.

`bake_current` is true only when the last bake succeeded, its `source_revision`
equals the current revision, and the target has not changed. An edit that is then
undone still moves the revision, so it reads false. That is conservative and
documented.

### New facade methods

These go on LevelRoot or a subsystem because the UI or tests can use them too,
not only the bridge:

- `LevelRoot.set_brush_rotation_by_id(brush_id, rotation_degrees: Vector3) -> HFOpResult`
  via `HFTransformSystem.set_rotation(brush_ids, basis) -> int`: one relative
  rotation about the brush centre, from the current basis to the target, through
  the same path as `rotate()` (texture lock included).
- `LevelRoot.extrude_face_info(brush_id, face_index, distance) -> Dictionary`
  via a static `HFExtrudeTool.build_extrude_info(brush, face_index, height, direction, snap, brush_id)`
  that the tool's own `_build_brush_info` calls too. Empty on failure.
- `LevelRoot.export_game_scene(path, metadata := {})` and the matching argument on
  `export_playtest_scene`: when not empty, set as `hammerforge_bake` meta on the
  scene root before packing.
- `plugin.create_starter_level(action_name := "New HammerForge Level")`: one undo
  step whether or not a LevelRoot existed.

## Python server

Tools are registered on `MCPServer` with fixed names, descriptions carrying the
spatial conventions, Pydantic input models and `ToolAnnotations`
(`read_only_hint` on the five read-only tools: status, get brushes, get
materials, validate, screenshot; `destructive_hint` on delete, batch, undo and
redo; `idempotent_hint` on transform, resize, assign material and set spawn,
which set absolute values; `open_world_hint=False` everywhere). Each tool returns a hand-built
`CallToolResult` annotated as `Annotated[CallToolResult, OutputModel]`, so the
SDK publishes an `outputSchema` and still lets the screenshot add an
`ImageContent` block. Domain errors set `structured_content={"ok": false, ...}`
with a one-line text summary. Bridge, protocol and internal errors set
`is_error=True`.

Per-tool timeouts: 30 s by default, 900 s for `hf_bake`, 60 s for the screenshot.
The budget starts before attaching and connecting, includes waiting for the
write lock and drain, and is shared with the one reconnect. Expiry removes the
waiter so a call still waiting to write is never sent later. Cancellation does
not close a healthy shared connection or roll back an edit already sent.
A quiet socket during a known long call is not treated as dead.

The Python reader checks response and error envelopes before handing them to
callers. Malformed frames fail all waiters promptly and the connection is
dropped; errors for sent changes include each caller's own operation id.
Failed, cancelled and malformed handshakes close their socket before returning.

Lost response: the server reconnects (re-reading the discovery file) and resends
once with the same `operation_id`. The listener's cache answers it if the first
attempt committed, and runs it if it did not.

## Testing

1. **Dispatcher tests (GUT).** A real LevelRoot and a stand-in undo manager that
   wraps a real `UndoRedo` (an `EditorUndoRedoManager` cannot be built outside
   the editor), so undo and redo actually run. They cover each tool's success
   path, failure leaving state unchanged, `operation_id` replay and conflict,
   revision moves, undo rules, batch rollback, and save then reload for every
   authoring tool (`capture_hflevel` round trip).
2. **Listener tests (GUT).** The listener on port 0 inside the test, a
   `StreamPeerTCP` client in the same process: framing, size limits, handshake,
   bad token, request correlation, queueing, `hf_get_status` while busy, discovery
   file written and removed.
3. **Python tests (pytest).** Framing and discovery units, the bridge against a
   fake asyncio listener (lost response, reconnect, retry with the same id), and
   the MCP server through the SDK's in-process `Client`.
4. **Bridge smoke (CI).** `tools/mcp_bridge_smoke.gd` hosts the listener and
   dispatcher in a headless Godot. The Python server's smoke client connects, says
   hello, reads status, places a brush, replays it by `operation_id`, undoes it.
   This is the phase 1 round trip.
5. **Vibe tests.** The real editor, the real `hammerforge-mcp`, and an MCP client
   building rooms. They check `hf_undo` against human Ctrl+Z, scene tab switches,
   a long bake and screenshots by eye. Findings become GUT tests or issues.

Acceptance tests the source spec names, and where each lives:

| Case | Layer |
|---|---|
| Lost response and retry | pytest bridge, dispatcher replay |
| Scene switch while queued | dispatcher (host swaps scene root between check and apply), vibe |
| Undo after a human edit conflicts | dispatcher (an action committed outside the dispatcher) |
| Invalid input leaves state unchanged | dispatcher, every tool, `capture_state()` compared before and after |
| Stale bake not reported as current | dispatcher (bake, edit, status) |
| Batch all-or-nothing | dispatcher (op 3 of 4 fails, state equals before, nothing on the undo stack) |

## Phases and pull requests

1. **Contract and handshake.** Protocol, listener, dispatcher core (target,
   revision, cache, wrapper), `hf_get_status` and `hf_place_brush` (box only) as
   the trivial mutation, the dock toggle, the Python package with bridge and those
   two tools, pytest and the smoke test in CI, and the docs that say "no bridge
   here" corrected.
2. **Core authoring loop.** Every shape for place, transform, resize, delete,
   extrude, assign material, set spawn, get brushes, get materials, undo, redo,
   create starter, and the facade methods, with save and reload tests.
3. **Bake, validate, screenshot, batch.** The Didi handoff documented with a real
   artifact.
4. **Hardening.** Failure-mode acceptance tests, limits, logging, the user guide
   page, example prompts, vibe-test findings.

## Pre-mortem

Three months on, the bridge is unused. The likeliest reasons, and what this
design does about each:

1. **`hf_undo` always conflicts.** Something bumps the revision after the response
   (a deferred reconcile that commits, a selection change in some history).
   The design waits a frame before reading the revision, counts only two
   histories, and has a vibe test of place then undo in the real editor before
   phase 2 lands.
2. **Agents build nonsense** because a convention is ambiguous: centre or corner,
   Euler order, what extrude does. Every description states the conventions, every
   result echoes the applied values, and a test places a brush and reads it back
   unchanged.
3. **The token leaks into git.** The file lives under `.godot/`, never in logs or
   errors, and a test checks it is deleted on disable.
4. **A stale discovery file** points at a dead editor after a crash. The server
   checks the pid and says what to do.
5. **The editor stalls.** `capture_state()` is 39 ms at 900 brushes and runs once
   per command, a bake yields frames, and the Python timeouts are per tool.
6. **Existing behaviour breaks** in the refactors (extrude info, starter undo,
   export metadata). Existing tests cover the paths, and the source-grepping tests
   are checked before moving any line.
7. **The SDK moves.** It is pinned below 3, and CI pins the exact version.
8. **A held node goes stale.** `restore_state()` rebuilds brushes, so the
   dispatcher keeps ids, never nodes, between commands.
9. **Batch leaves half a change.** Batch only allows ops whose effects
   `capture_state()` covers: brushes, entities and face materials. Not settings,
   cordons, the palette or baked meshes.
10. **CI goes red for reasons unrelated to the bridge**: GUT orphans, warnings,
    uid parity, dead declarations, changelog format. All of them are run locally
    before every push.
11. **A scene closes mid-bake.** The first version awaited the bake inside the
    LevelRoot and checked the target after the await. A coroutine waiting inside a
    freed node never resumes, so that check never ran and the bridge stopped
    answering; the phase 3 review caught it. The bake now runs from an object the
    dispatcher holds, which watches it and the level each frame and answers
    `target_changed` when the level goes.
12. **The cross-process smoke test is flaky** (ports, timing). It waits on the
    discovery file with a deadline and reports what it saw.

## Found along the way

- UI Clip reads `info["center"]`, which `get_brush_info_from_node()` never sets,
  so the default split is always y = 0 (`plugin_edit_actions.gd:542`,
  `dock_brush_handler.gd:1597`). Filed separately.
- `LevelRoot.clip_brush_at_point()` calls `brush_system.clip_brush_at_point()`,
  which does not exist, and nothing calls it. Filed separately.
- `create_new_level()` only gave the floor, sun and spawn an owner when it made
  them. A LevelRoot taken out of the tree and put back (an undo, then a redo, of
  Create Starter) keeps its pieces but loses their owners, so the redone level's
  floor, sun and spawn were not saved with the scene. Fixed in phase 2: it owns
  them every time.

## Known gaps after phase 1

Both closed in phase 3. From the phase 1 review, left for then because nothing
before bake and screenshots could reach them:

- **Status during a long command.** The listener answers `hf_get_status` at once
  while a command runs, but the Python bridge holds one lock for the whole
  connection, so a status call from the agent waits behind the command. Phase 3
  gives the bridge a reader task that hands each response to the waiter with its
  id, and lets status through the lock.
- **Large answers block the editor while they send.** `StreamPeerTCP.put_data()`
  waits until every byte is written, so a client that stops reading a 16 MiB
  screenshot holds the main thread. Phase 3 queues outgoing bytes per connection
  and writes them with `put_partial_data()` from `_process`.

## Phase 4: hardening

- `hammerforge-mcp --check` runs the connection once, says what it found in a
  user's words, and prints the Claude Code and Claude Desktop configuration with
  `sys.executable`, since a client started from the desktop does not read the
  shell's PATH.
- Three MCP prompts: `block_out_room` (works out every size and centre, snap
  off), `review_level`, `bake_for_playtest`.
- The listener emits `command_finished(method, ok, code, ms)`; the panel shows
  the last one. The server logs one line per call; a test reads every log record
  of a session with a reconnect and a timeout for the token.
- A request too big to send, or not JSON, is refused before the connection is
  touched, so other calls on it carry on.
- A test reads the GDScript limits and the tool schemas and checks they agree. It
  found that a bound placed after the bool check reached the agent's schema as
  pydantic's own `gt` and `le`, which JSON Schema clients skip: brush sizes, face
  indexes and the extrude distance showed no bounds.
- The smoke test closes its Godot under a running server and starts another.

## Post-mortem

What the pre-mortem predicted, and what happened.

- **`hf_undo` always conflicts (1).** It did not, because the design waited a
  frame and counted two histories. The vibe runs checked it in the real editor.
  What it missed was the other direction: a direct `UndoRedo.undo()` leaves the
  editor's Ctrl+Shift+Z behind (#1028), shared with the dock's own Undo button.
  Left open, documented.
- **Agents build nonsense (2).** Every result echoes the applied values, and the
  room prompt now does the arithmetic. Snapping still changes a size an agent
  asked for, and the answer says so, but an agent has to read it.
- **The token leaks (3).** It did not, and a test now reads every log record.
- **A scene closes mid-bake (11).** The design was wrong. A coroutine waiting in
  a freed node never resumes, so the check after the await never ran. The phase 3
  review found it; the test that was meant to cover it kept the old level alive
  and passed for the wrong reason.
- **Batch leaves half a change (9).** It did once: rollback keyed on an op having
  succeeded, not on one having run, so a first op that changed the level and then
  failed kept its change. The review found it.

What the reviews caught that the tests did not: the bake hang, the batch rollback,
a bake applying cuts without moving the revision, a retry of an undo replaying an
old answer, a request sent twice after a reconnect, and two commands at once after
a listener restart. Every one was a path where two things happen in an order the
tests did not try. Two of the first tests written for those fixes passed on the
old code; each new test was run against the old code before it counted.

What the vibe runs caught: a headless editor never sends `frame_post_draw`, so the
first screenshot code hung the queue. No GUT test could see it.

What the cross-language check caught: the schema bounds no client could read.

## After landing: what testing found

Installed from GitHub into a fresh project, then used by an agent to build a
121-brush castle, which was played and reviewed outside the bridge. Filed as
#1033 to #1051.

- **The bake hands over less than the editor shows.** The starter's floor is a CSG
  box the bake leaves out, so the exported scene has no ground beyond the brushes
  (#1042). Test Level runs the scene file and has it, and lights a level
  differently from Export Playtest Build (#1047).
- **The agent builds blind to the player.** It is never told the player's size,
  step or eye height (#1045), and nothing checks brush-built stairs, ramps or
  openings against them (#1046). The castle's wall-walk could not be seen over and
  its stair risers were over the step limit.
- **Status is not as cheap or as available as designed.** It runs Validate after
  every change (#1048), and it queues behind a bake read in the same frame, while
  the bake holds the main thread (#1049). The pre-mortem's "a bake yields frames"
  held only sometimes.
- **The answers mislead in small ways.** `hf_set_spawn` suggests node positions
  for a feet argument (#1034), snapping moves odd-sized brushes without saying so
  (#1038), and orientation conventions are undocumented (#1041).
- **Missing tools:** material, rotation and sides on place (#1039, which the
  design table promised), a chosen screenshot view (#1040), and lights (#1051).
- **HammerForge itself:** four built-in shapes fail Validate (#1035), the level box
  ignores rotation (#1036), micro-gap findings name no brush (#1037), brushes
  have internal names (#1050), prototype texture imports reimport on first open
  (#1043), main reports 0.3.2 (#1044), and a script quitting the editor logs an
  error (#1033).

## Resolved, 11 October

Every issue in the list above was closed the same day: fixed in PRs #1062 to #1076,
except #1033, which is the Godot editor itself (it logs that error whenever a
script quits it with anything selected). Point entities, a chosen screenshot
view, an observer connection for `--check`, and Validate's traversal checks came
in with them.

## Follow-ups, 12 October

The 11 October sweep filed #1081 to #1087; all were fixed on 12 October in PRs
#1089 to #1094. Entities placed earlier can be moved, retuned, deleted and wired
(`hf_transform_entity`, `hf_set_entity_properties`, `hf_delete_entity`,
`hf_add_entity_output`, and `$N.entity` in a batch), a screenshot can show the
bake alone (`show: "baked"`), a placed brush can be named, round brushes take
their segments from `sides`, and Validate measures turned stairs. The first
baked screenshot showed an unpainted level baking see-through once it had a
cut (#1092): the CSG bake gave a bare brush the editor's translucent preview.
Still open then: brush entities (#1098), removing a wire (#1096), and spirals
of boxes in Validate (#1095). All three landed later that day in #1101 and
#1102: `hf_set_brush_entity`, a `brush_id` source on both output tools,
`hf_remove_entity_output`, and `brush_entity` on every brush answer. Validate's
first spiral rule asked that neither box's middle lie inside the other; tight
spirals cover the next tread's middle, so it skipped to every other tread and
warned on a walkable stair. It now asks that neither outline lie wholly inside
the other.

A third pass the same day (#1110 to #1120) gave `hf_set_brush_entity`
`brush_ids` and `entity_class: "none"` to untie, and `hf_set_entity_properties`
a `brush_id` (#1105); a brush entity's properties now go on every brush of it
through `LevelRoot.entity_property_nodes()`, from the dock too (#1113), and untie
drops its wires and properties (#1112). `hf_extrude_face` on a slope or a round
side used to answer ok with an upright slab sunk into the brush; the box now
lies on the face (#1107). The listener no longer writes the token when the
folder stays open to others (#1109).

## Out of scope for v1

Hollow, clip, merge, carve, entities other than the spawn (point entities came
after, #1051, and editing and wiring them, #1082 and #1083), paint, cordons, generators, prefabs, bake profiles, streaming bake progress, more than one LevelRoot
per scene, and Streamable HTTP.
