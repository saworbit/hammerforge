# MCP Bridge Phase 4: Hardening

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the bridge something a user can set up and trust without reading the code: a check command that says what is wrong and prints a config to paste, a user guide page, example prompts in the client, a panel line that says what the agent just did, logging that never carries the token, limits that hold together across the two languages, and a cross-process test of an editor restart.

**Architecture:** No new protocol. The Python server gains a `--check` mode, three MCP prompts and a log line per call. The editor's listener reports each finished command, and the panel shows it. The smoke test runs a second editor after the first quits. The guide page goes on the docs site.

**Tech Stack:** GDScript (Godot 4.7, GUT 9.6), Python 3.10+ with the MCP SDK 2.3.0, pytest, MkDocs.

**Spec:** `docs/superpowers/specs/2026-10-11-mcp-bridge-design.md` (phase 4: failure-mode acceptance tests, limits, logging, the user guide page, example prompts, vibe-test findings).

## Global Constraints

- Bridge version stays 1. No new frame types, no new fields an older side must read.
- The token never appears in a log line, an error message, a tool result or `--check` output.
- `hammerforge_mcp/` stays out of the Asset Library zip.
- Docs prose: short sentences, no em dashes, no " - " clauses.
- CHANGELOG: one dated line under the week's heading, under 200 characters.
- GDScript passes `tools/check_script_warnings.py`, gdformat (LF line endings after), gdlint.

## Review Focus

1. A user whose MCP client cannot find `hammerforge-mcp` on PATH (GUI apps on Windows and macOS do not read the shell's PATH). `--check` prints a config with the absolute interpreter path.
2. The editor quits or restarts under a running server. The next call says the editor is gone, and after a new editor ticks the box the server works without a restart, aimed at the new target only after `hf_get_status`.
3. A request too large to send. It is refused without dropping a connection that other calls are using.
4. The panel after a refused command. It says what was refused and why, not just "Agent connected".
5. Logs at DEBUG during a reconnect after a token change. No token in any line.

---

### Task 1: An oversized request is refused without dropping the connection

**Files:** `hammerforge_mcp/src/hammerforge_mcp/bridge.py`, `hammerforge_mcp/tests/test_bridge.py`

Today `encode_frame` raises `FrameError("frame_too_large")` inside `_send_and_wait`, and `_call_once` answers every `FrameError` by dropping the connection. A frame that was never sent says nothing about the connection.

- [x] Test: a status call, then a call whose params encode to more than 1 MiB, then a status call. The big one raises `BridgeError("frame_too_large")`, the listener saw one connection, and the last status answers.
- [x] Encode in `_call_once` before connecting, and turn a `FrameError` there into a `BridgeError` without `_drop`. `_send_and_wait` takes the bytes.
- [x] Same for `invalid_argument` (a NaN that slipped past the schema).

### Task 2: The limits agree across the two languages

**Files:** `hammerforge_mcp/tests/test_limits.py` (new)

The editor and the server each carry their own copy of the request and response limits, the batch size, the screenshot bounds and the brush read limit. A test reads the GDScript constants and the catalogue's schemas and checks they agree.

- [x] Parse `MAX_REQUEST_BYTES`, `MAX_RESPONSE_BYTES` from `hf_mcp_protocol.gd`, `BATCH_LIMIT` from `hf_mcp_dispatcher.gd`, the width and height bounds from its `_screenshot`, and the 2000 brush limit from `hf_mcp_tools.gd`. Compare with `framing.py` and the tool schemas the server lists.
- [x] Found by it: a bound placed after the bool check reached the agent's schema as pydantic's `gt` and `le`, which JSON Schema clients skip. Brush sizes, face indexes and the extrude distance showed no bounds. `Field` now comes first, and a test refuses any pydantic-only key in a tool schema.
- [x] A limits table in the guide (Task 6), checked by the same test.

### Task 3: The panel says what the agent last did

**Files:** `addons/hammerforge/mcp/hf_mcp_listener.gd`, `addons/hammerforge/ui/hf_mcp_panel.gd`, `addons/hammerforge/plugin_mcp.gd`, `tests/test_mcp_listener.gd`, `tests/test_plugin_mcp.gd`

- [x] Listener: `signal command_finished(method: String, ok: bool, code: String, ms: int)`, emitted in `_finish` for every answered request.
- [x] Panel: `show_last(method, ok, code, ms)` sets a second line: "Last: place brush, 14 ms" or "Last: undo refused: undo_conflict". Tooltip carries the same.
- [x] Plugin: connect in `setup`, disconnect in `teardown` (the enter/exit pairing rule).
- [x] Tests: a refused place through the socket shows the code; a good one shows the verb; teardown leaves no connection.

### Task 4: One log line per call, and never the token

**Files:** `hammerforge_mcp/src/hammerforge_mcp/server.py`, `bridge.py`, `hammerforge_mcp/tests/test_logging.py` (new)

- [x] INFO per tool call: method, ok or the code, revision, milliseconds. DEBUG: the params.
- [x] Test with `caplog` at DEBUG over a fake listener session: connect, a wrong-token refusal after the discovery file changes, a reconnect, a change, a timeout. No record's message or args contains the token.

### Task 5: `hammerforge-mcp --check`

**Files:** `hammerforge_mcp/src/hammerforge_mcp/server.py` (or `check.py`), `hammerforge_mcp/tests/test_check.py`

- [x] `--check` connects, calls `hf_get_status`, prints the editor, scene, level and revision, and exits 0. On failure it prints the bridge error's message (bridge off, editor exited, wrong token) and exits 1.
- [x] It then prints two snippets with absolute paths: `claude mcp add hammerforge -- <python> -m hammerforge_mcp --project <project>` and the Claude Desktop JSON block with `command` set to `sys.executable`.
- [x] Tests: against the fake listener, ok and each failure; the snippets name `sys.executable` and the project path, and no token.

### Task 6: Example prompts in the client, and the user guide page

**Files:** `hammerforge_mcp/src/hammerforge_mcp/prompts.py` (new), `server.py`, `hammerforge_mcp/tests/test_server.py`, `docs/HammerForge_Agent_Bridge.md` (new), `mkdocs.yml`, `README.md`, `docs/HammerForge_UserGuide.md`, `hammerforge_mcp/README.md`

- [x] Three MCP prompts: `block_out_room(width, depth, height)`, `review_level()` (validate, screenshot, a plain summary of what to fix), `bake_for_playtest()` (validate, bake, the Didi handoff). Each a single user message that names the tools and the conventions.
- [x] Tests: `list_prompts` lists the three; `get_prompt` fills the arguments; every tool a prompt names exists.
- [x] Guide page: what it is and what it is not; the safety model; install (from a clone, or `pip install "git+https://github.com/saworbit/hammerforge.git#subdirectory=hammerforge_mcp"`); `--check`; connecting Claude Code, Claude Desktop and any stdio client; the tools table; conventions; baking for a playtest; troubleshooting by error code; limits; the example prompts; known limits (#1028, screenshots need a display).
- [x] The catalogue test checks every tool is in the guide's table.
- [x] Verify the git install line against a local `git+file://` URL of this checkout in a fresh venv.

### Task 7: The editor restarts under a running server

**Files:** `tools/mcp_bridge_smoke.py`, `tools/mcp_bridge_smoke.gd`

- [x] After the round trip: signal the first Godot to quit, and check the next call answers `bridge_off` within a few seconds and says to tick the box.
- [x] Start a second Godot with a new discovery file at the same path. `hf_get_status` attaches; a change sent with the old target first is refused `target_changed`; after status a change lands.

### Task 8: Vibe, post-mortem, close out

- [x] Windowed editor vibe: a screenshot, plain and framed, read back as PNG and looked at. Revert any `.svg.import` the editor rewrites.
- [x] A run of each example prompt's tool sequence through the real server.
- [x] Post-mortem section in the design doc: what the pre-mortem predicted, what happened, what the reviews caught that tests did not.
- [x] Tick phase 4 on #1026 and close it, once this merges. #1031 closed it.
