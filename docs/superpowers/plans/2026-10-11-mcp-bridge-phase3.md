# MCP bridge, phase 3: bake, validate, screenshot, batch

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent can bake the level to a scene file it hands to Didi, check the
level for problems, look at it, and make several changes as one step. The two
gaps the phase 1 review left for here are closed.

**Architecture:** Bake and screenshot are queued commands that await frames, so
the dispatcher runs them like create starter: not through the undo wrapper,
since a bake and a picture change no authoring state. Validate is a read. Batch
is the wrapper around several of the existing checks and applies, with one
capture and one commit. The Python bridge gets a reader task so status can pass
a running command, and the listener writes large answers a piece per frame.

**Spec:** `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md`: Bake,
Screenshot and Artifact identity; the tool table rows for `hf_bake`,
`hf_validate`, `hf_viewport_screenshot`, `hf_batch`; Known gaps after phase 1.

## Global constraints

Phases 1 and 2's, plus:

- A bake writes `<scene dir>/<scene name>_mcp.tscn`, or
  `res://hammerforge_mcp_bake.tscn` for a scene never saved, and never touches
  `<scene>_game.tscn`.
- The exported scene root carries `hammerforge_bake` metadata:
  `{bake_id, source_revision, target_id, baked_at}`.
- `bake()` with a mask of 0 uses the level's own collision layer, so the bridge
  passes 0.
- A bake records no undo step and does not move the revision.
- The screenshot never moves the editor camera.
- Batch: 1 to 100 ops, each one of the seven wrapper tools, one
  `MCP: batch (N ops)` step, all or nothing.

## Review focus

1. **A scene tab switch while a bake awaits.** After the await the target is
   checked again, and the answer is `target_changed` with nothing exported.
2. **A bake the dock started first.** `bake_busy`, and the dock's bake carries on.
3. **A batch whose third op refers to a brush the second op made**
   (`"$1.brush_id"`). It works, and a reference to a later op or to an op that made
   no brush is refused before anything changes.
4. **A screenshot in a headless editor.** `screenshot_unavailable`, not a crash
   and not an empty image.
5. **Status during a ten second bake from Python.** It answers at once with
   `busy: "hf_bake"`.

---

### Task 1: Export metadata and the bake tool

- `LevelRoot.export_game_scene(path, metadata := {})` and
  `export_playtest_scene(path, include_debug_rig := true, metadata := {})`: when
  `metadata` is not empty, `scene_root.set_meta("hammerforge_bake", metadata)`
  before packing. Test: export with metadata, load the PackedScene, read the meta.
- Host: `notify_file_written(path)` (the editor's `EditorFileSystem.update_file`).
- Dispatcher `_bake(id)`: `bake_busy` while `is_bake_in_flight()`; capture
  target and revision; collect `user_message` texts while it runs; `await
  root.bake(true, false, 0)`; check the target again; `bake_failed` with the
  status name from `get_last_bake_status()`; export to the artifact path with
  the metadata; `export_failed` if packing fails; remember `_last_bake`.
- Status gains `last_bake` and `bake_current` (last bake succeeded, its
  `source_revision` is the current revision, same target).
- Tests: a bake of a placed box writes the file with the metadata and leaves the
  undo history and revision alone; `bake_current` true, then false after a place;
  a stand-in level whose `bake()` returns false gives `bake_failed`; a scene
  switch during the await gives `target_changed` and no file; a busy bake gives
  `bake_busy`.

### Task 2: Validate

- Tools `_read_validate(root, params)`: `check_bake_issues()`,
  `spawn_system.layout_issues()` and `validate_level(false).findings`, each as
  `{type, severity: "info" | "warning" | "error", message, brush_id?, entity?, fix?}`,
  with `node` turned into a brush id or an entity path, and duplicates dropped.
  Counts by severity.
- Status gains `validation` counts, worked out once per revision and not while
  a command runs.
- Tests: an empty level reports the missing spawn; a degenerate brush is an
  error naming its id; a clean starter level with a room has no errors; the read
  changes nothing.

### Task 3: Screenshot

- Host: `viewport_3d()` and `screenshot_parent()`.
- Dispatcher `_screenshot(id, params)`: width 64 to 1920 and height 64 to 1080
  (1280x720 by default); `focus` is `{brush_ids}` or `{bounds}`. Without focus,
  await `RenderingServer.frame_post_draw` and read the editor viewport's image,
  scaled to fit. With focus, a temporary `SubViewport` with the editor viewport's
  `World3D` and its own `Camera3D`, looking along the editor camera's direction
  and backed off to fit the bounds; two `frame_post_draw`, read, free. PNG,
  base64.
- `screenshot_unavailable` when there is no viewport or the image is empty
  (headless).
- Python: the answer becomes an `ImageContent` block, and the structured content
  keeps everything but the image data.
- Tests: headless gives `screenshot_unavailable`; the fit maths as a pure
  function (bounds and fov in, camera position out); the Python mapping of an
  image answer.

### Task 4: Batch

- Dispatcher `_batch(id, params)`: `ops` is a list of `{tool, params}`, 1 to 100,
  each tool one of the seven wrapper tools. Capture the whole level; for each op,
  replace any string `"$N.brush_id"` in its params (at any depth) with op N's
  brush id, N earlier than this op; check, refuse, or apply; on any refusal or
  failure restore and answer `batch_failed` with `{index, error}`; on success one
  `commit_completed()` named `MCP: batch (N ops)`.
- Tests: three places and a transform of the first by reference is one step and
  undoes in one; op 3 of 4 failing leaves the level as before and the history
  empty; a forward reference and a reference to a delete's result are refused;
  101 ops is refused; an unknown tool inside is refused.

### Task 5: The two gaps from phase 1

- Listener: a per-connection outbox. `_send` appends; `_process` writes with
  `put_partial_data` until the outbox is empty. A refusal closes the connection
  once its outbox is empty. Tests: a 5 MiB answer to a client reading a little
  per frame arrives whole and the editor keeps processing frames meanwhile.
- Python bridge: one reader task per connection hands each response to the
  waiter registered under its id; writes share a lock; `hf_get_status` does not
  wait for a running call. A lost connection fails every waiter, and each is
  retried once as now. Tests: status answers while a held bake is running; two
  waiters both get their own answers; a lost connection with two waiters retries
  both.

### Task 6: Python, docs, smoke, vibe, PR

- Catalogue: `hf_bake` (900 s, mutating for the queue, not destructive),
  `hf_validate` (read), `hf_viewport_screenshot` (read, 60 s), `hf_batch`
  (destructive, ops typed by tool).
- Smoke: bake headless and check the artifact's metadata; batch with a reference.
- Docs: README table, the Didi handoff (artifact path and the metadata to check),
  features, ROADMAP, SPEC, CHANGELOG.
- Vibe: a real editor, not headless, if screen control is allowed; otherwise a
  headless editor for bake, validate and batch, and say plainly that the
  screenshot was only checked headless.
