"""The MCP vibe harness: a real Godot editor, the real hammerforge-mcp, and a
helper plugin standing in for the user at the editor.

`run_mcp_vibe.py` drives it. Each scenario gets a fresh editor:

1. The helper (`editor_helper/`) is copied to `addons/hf_mcp_vibe/` and enabled
   in `project.godot`, which is backed up first.
2. Two scratch scenes are written to `res://vibe_mcp_scratch/`: `level.tscn`
   (a bare LevelRoot) and `other.tscn` (no level).
3. The editor starts on one of them, headless unless the scenario needs a
   picture. The helper ticks Allow agent connections through the real panel.
4. The scenario talks to the editor through hammerforge-mcp over stdio, from
   this checkout's source, and to the helper through two files in `.godot/`.
5. Whatever happens, the editor is closed, `project.godot` is put back, and the
   helper and the scratch scenes are removed. A windowed editor can rewrite
   tracked `.import` files; any it changed that were clean before are reverted.

Logs and screenshots land in `.vibe/mcp/`, which git ignores.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "tools"))

from capture_ui import prefs_change_since, prefs_fingerprint  # noqa: E402,F401

HELPER_SOURCE = Path(__file__).resolve().parent / "editor_helper"
HELPER_ADDON = REPO / "addons" / "hf_mcp_vibe"
HELPER_CFG = "res://addons/hf_mcp_vibe/plugin.cfg"
PROJECT_FILE = REPO / "project.godot"
SCRATCH = REPO / "vibe_mcp_scratch"
OUTPUT = REPO / ".vibe" / "mcp"
CMD = REPO / ".godot" / "mcp_vibe_cmd.json"
OUT = REPO / ".godot" / "mcp_vibe_out.json"
DISCOVERY = REPO / ".godot" / "hammerforge_mcp" / "discovery.json"

LEVEL = "res://vibe_mcp_scratch/level.tscn"
OTHER = "res://vibe_mcp_scratch/other.tscn"
_SCENES = {
    "level.tscn": (
        "[gd_scene load_steps=2 format=3]\n\n"
        '[ext_resource type="Script" path="res://addons/hammerforge/level_root.gd" id="1"]\n\n'
        '[node name="LevelRoot" type="Node3D"]\n'
        'script = ExtResource("1")\n'
    ),
    "other.tscn": '[gd_scene format=3]\n\n[node name="OtherScene" type="Node3D"]\n',
}


class VibeSetupError(RuntimeError):
    """The editor or the helper never came up. Not a finding: nothing ran."""


def find_godot(given: str | None) -> str:
    for candidate in (given, os.environ.get("GODOT")):
        if candidate:
            return candidate
    on_path = shutil.which("godot")
    if on_path:
        return on_path
    return "C:/Godot/godot.cmd"


def _kill_tree(process: subprocess.Popen) -> None:
    # With a wrapper such as godot.cmd, Godot is the wrapper's child.
    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
        )
    else:
        process.kill()
    process.wait()


def _modified_imports() -> set[str]:
    listed = subprocess.run(
        ["git", "-C", str(REPO), "diff", "--name-only", "--", "*.import"],
        capture_output=True,
        text=True,
        check=False,
    )
    return {line for line in listed.stdout.splitlines() if line}


def _discovery_alive() -> bool:
    """Another editor on this checkout has the bridge on. The run would delete
    its discovery file and fight it for project.godot."""
    try:
        found = json.loads(DISCOVERY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    pid = int(found.get("pid", 0))
    if pid <= 0:
        return False
    try:
        sys.path.insert(0, str(REPO / "hammerforge_mcp" / "src"))
        from hammerforge_mcp.discovery import pid_alive
    except ImportError:
        return True
    return pid_alive(pid)


class Editor:
    """One editor run: helper in, editor up, everything put back after."""

    def __init__(self, godot: str, *, windowed: bool, scene: str, name: str) -> None:
        self.godot = godot
        self.windowed = windowed
        self.scene = scene
        self.log_path = OUTPUT / f"{name}.editor.log"
        self.backup = OUTPUT / "project.godot.bak"
        self.process: subprocess.Popen | None = None
        self._imports_before: set[str] = set()
        self._next = 0

    def __enter__(self) -> Editor:
        if _discovery_alive():
            raise VibeSetupError(
                "An editor on this checkout has the Agent Bridge on. Close it, or "
                "run the vibe in a worktree of its own."
            )
        OUTPUT.mkdir(parents=True, exist_ok=True)
        if self.backup.exists():
            # A run that died before putting project.godot back.
            shutil.copyfile(self.backup, PROJECT_FILE)
        shutil.copyfile(PROJECT_FILE, self.backup)
        self._imports_before = _modified_imports()
        try:
            self._install()
            self._start()
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def _install(self) -> None:
        HELPER_ADDON.mkdir(parents=True, exist_ok=True)
        # The .gd and plugin.cfg only: a copied .uid would give two scripts one id.
        for name in ("plugin.cfg", "vibe_plugin.gd"):
            shutil.copyfile(HELPER_SOURCE / name, HELPER_ADDON / name)
        text = PROJECT_FILE.read_text(encoding="utf-8")
        hammerforge = '"res://addons/hammerforge/plugin.cfg"'
        if HELPER_CFG not in text:
            if hammerforge not in text:
                raise VibeSetupError("project.godot does not enable HammerForge")
            text = text.replace(hammerforge, f'{hammerforge}, "{HELPER_CFG}"', 1)
            PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")
        SCRATCH.mkdir(exist_ok=True)
        for name, body in _SCENES.items():
            (SCRATCH / name).write_text(body, encoding="utf-8", newline="\n")
        for stale in (CMD, OUT, DISCOVERY):
            stale.unlink(missing_ok=True)

    def _start(self) -> None:
        command = [self.godot, "--editor", "--path", str(REPO), self.scene]
        if not self.windowed:
            command.insert(1, "--headless")
        with self.log_path.open("w", encoding="utf-8") as log:
            self.process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT
            )
        self._wait(OUT.exists, 180, "the editor and the helper")
        self._wait(lambda: self.order("scene") is not None, 60, "the edited scene")
        self.order("enable")
        self._wait(DISCOVERY.exists, 15, "the bridge's discovery file")

    def _wait(self, condition, seconds: float, what: str) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                raise VibeSetupError(f"the editor exited waiting for {what}")
            if condition():
                return
            time.sleep(0.25)
        raise VibeSetupError(f"timed out waiting for {what}; see {self.log_path}")

    def order(self, op: str, **args) -> object:
        """Ask the helper to do something in the editor, and wait for its answer."""
        self._next += 1
        order_id = self._next
        order = json.dumps({"id": order_id, "op": op, **args})
        # On Windows the helper may have the file open for its read this frame.
        for _attempt in range(40):
            try:
                CMD.write_text(order, encoding="utf-8")
                break
            except PermissionError:
                time.sleep(0.05)
        else:
            raise VibeSetupError(f"could not write the order {op}")
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                data = json.loads(OUT.read_text(encoding="utf-8"))
                if data.get("id") == order_id:
                    return data.get("result")
            except (OSError, ValueError):
                pass
            time.sleep(0.1)
        raise VibeSetupError(f"the helper never answered {op}")

    def __exit__(self, *exc) -> None:
        if self.process is not None and self.process.poll() is None:
            try:
                self.order("quit")
                self.process.wait(timeout=30)
            except (VibeSetupError, subprocess.TimeoutExpired):
                _kill_tree(self.process)
        if self.backup.exists():
            shutil.copyfile(self.backup, PROJECT_FILE)
            self.backup.unlink()
        shutil.rmtree(HELPER_ADDON, ignore_errors=True)
        shutil.rmtree(SCRATCH, ignore_errors=True)
        # Where a scratch scene's level saves and autosaves its `.hflevel`.
        shutil.rmtree(REPO / ".hammerforge" / SCRATCH.name, ignore_errors=True)
        for leftover in (CMD, OUT):
            leftover.unlink(missing_ok=True)
        rewritten = sorted(_modified_imports() - self._imports_before)
        if rewritten:
            subprocess.run(
                ["git", "-C", str(REPO), "checkout", "--", *rewritten],
                capture_output=True,
                check=False,
            )
            print(f"  reverted {len(rewritten)} .import files the editor rewrote")


class Vibe:
    """What a scenario gets: the agent's tools, the user's hands, and a report."""

    def __init__(self, client, editor: Editor, name: str) -> None:
        self._client = client
        self.editor = editor
        self.name = name
        self.flagged: list[str] = []
        self.known_seen: list[str] = []

    async def call(self, tool: str, args: dict | None = None) -> dict:
        """Call a tool. The structured answer, with the raw blocks under `_blocks`."""
        result = await asyncio.wait_for(self._client.call_tool(tool, args or {}), 300)
        out = dict(result.structured_content or {})
        if not out and result.content:
            out = {"ok": False, "text": getattr(result.content[0], "text", "")}
        out["_blocks"] = result.content
        return out

    async def prompt(self, name: str, args: dict | None = None) -> str:
        got = await self._client.get_prompt(name, args or {})
        return got.messages[0].content.text

    def order(self, op: str, **args) -> object:
        return self.editor.order(op, **args)

    def expect(self, condition: bool, what: str, seen: object = None) -> bool:
        if condition:
            print(f"  ok      {what}")
        else:
            print(f"  FLAG    {what}: {_short(seen)}")
            self.flagged.append(what)
        return condition

    def known(
        self, issue: int, condition: bool, what: str, seen: object = None
    ) -> None:
        """A behaviour filed as `issue` and not fixed yet. Noted, not flagged; when
        it starts to hold, the issue may be fixed."""
        if condition:
            print(f"  ok      {what} (#{issue} may be fixed: check and close it)")
        else:
            print(f"  known   {what} (#{issue}): {_short(seen)}")
            self.known_seen.append(f"#{issue} {what}")

    def note(self, label: str, value: object) -> None:
        print(f"  note    {label}: {_short(value, 300)}")

    def save_image(self, answer: dict, filename: str) -> Path | None:
        for block in answer.get("_blocks", []):
            if getattr(block, "type", "") == "image":
                path = OUTPUT / filename
                path.write_bytes(base64.b64decode(block.data))
                return path
        return None


def _short(value: object, limit: int = 500) -> str:
    if isinstance(value, dict):
        value = {k: v for k, v in value.items() if k != "_blocks"}
    try:
        text = json.dumps(value, default=str)
    except (TypeError, ValueError):
        text = repr(value)
    return text if len(text) <= limit else text[:limit] + "..."


async def run_scenario(module, godot: str) -> Vibe:
    """One scenario in its own editor and its own server."""
    from mcp import Client, StdioServerParameters

    name = module.__name__.rsplit(".", 1)[-1]
    scene = LEVEL if getattr(module, "START_SCENE", "level") == "level" else OTHER
    windowed = bool(getattr(module, "WINDOWED", False))
    server = StdioServerParameters(
        command=sys.executable,
        args=["-m", "hammerforge_mcp", "--project", str(REPO)],
        env={**os.environ, "PYTHONPATH": str(REPO / "hammerforge_mcp" / "src")},
    )
    with Editor(godot, windowed=windowed, scene=scene, name=name) as editor:
        async with Client(server) as client:
            vibe = Vibe(client, editor, name)
            await module.run(vibe)
    return vibe
