"""Run the MCP bridge end to end: MCP client, hammerforge-mcp, listener, LevelRoot.

Starts `tools/mcp_bridge_smoke.gd` in a headless Godot, waits for the discovery
file it writes, then starts hammerforge-mcp over stdio the way an MCP client
does and talks to it through the SDK's own client. It reads status, places a
brush, sends the same change again and expects the first answer back instead
of a second brush, and checks a reused operation_id with other arguments is
refused. Then it closes that Godot and starts another under the same server, the
way an editor restart looks to an agent: the server says the editor is gone,
then refuses a change aimed at the old one, then works once status reattaches.

Needs the mcp SDK in the interpreter that runs it. The server it starts is
hammerforge_mcp straight from this checkout's source:

    python -m pip install -r requirements-ci.txt
    python tools/mcp_bridge_smoke.py --godot godot

CI runs it on one GUT shard, which already has Godot and an imported project.
"""

from __future__ import annotations

import argparse
import asyncio
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PACKAGE_SOURCE = REPO / "hammerforge_mcp" / "src"


class SmokeFailure(Exception):
    pass


def _kill_tree(process: subprocess.Popen) -> None:
    # With a wrapper script such as godot.cmd, the process here is the wrapper
    # and Godot is its child. Killing the wrapper alone leaves Godot holding the
    # project and the discovery file.
    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
        )
    else:
        process.kill()
    process.wait()


class Editor:
    """One headless Godot running the smoke listener, and its log."""

    def __init__(self, args, project: Path, work: Path, name: str) -> None:
        self.args = args
        self.project = project
        self.discovery = work / "discovery.json"
        self.artifact = work / "smoke_mcp.tscn"
        self.done = work / "done"
        self.log_path = work / f"{name}.log"
        self.process: subprocess.Popen | None = None

    def start(self) -> None:
        for stale in (self.discovery, self.done):
            stale.unlink(missing_ok=True)
        command = [
            self.args.godot,
            "--headless",
            "--path",
            str(self.project),
            "-s",
            "res://tools/mcp_bridge_smoke.gd",
            "--",
            f"--discovery={self.discovery}",
            f"--artifact={self.artifact}",
            f"--done={self.done}",
            f"--seconds={self.args.seconds:g}",
        ]
        print("mcp smoke:", " ".join(command))
        with self.log_path.open("w", encoding="utf-8") as log:
            self.process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT
            )
        if not _wait_for(self.discovery, self.process, self.args.seconds):
            raise SmokeFailure(
                f"Godot never wrote the discovery file ({self.log_path})"
            )

    def stop(self) -> None:
        if self.process is None:
            return
        self.done.write_text("done", encoding="utf-8")
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            _kill_tree(self.process)
        self.done.unlink(missing_ok=True)
        self.process = None

    def log(self) -> str:
        if not self.log_path.is_file():
            return ""
        return self.log_path.read_text(encoding="utf-8", errors="replace").strip()


def _check(condition: bool, what: str, seen: object) -> None:
    if not condition:
        raise SmokeFailure(f"{what}: got {seen!r}")


async def _round_trip(
    project: Path, discovery: Path, artifact: Path, restart
) -> list[str]:
    from mcp import Client, StdioServerParameters

    server = StdioServerParameters(
        command=sys.executable,
        args=[
            "-m",
            "hammerforge_mcp",
            "--project",
            str(project),
            "--discovery",
            str(discovery),
        ],
        # This checkout's server, not whatever version is installed.
        env={"PYTHONPATH": str(PACKAGE_SOURCE)},
    )
    report: list[str] = []
    async with Client(server) as client:
        tools = sorted(tool.name for tool in (await client.list_tools()).tools)
        _check("hf_place_brush" in tools, "the catalogue lists hf_place_brush", tools)
        report.append(f"tools: {', '.join(tools)}")

        status = (await client.call_tool("hf_get_status", {})).structured_content
        _check(status["ok"], "status answers", status)
        target = status["result"]["target"]
        _check(
            target["level_root_path"] == "LevelRoot", "status finds the level", target
        )
        report.append(
            f"attached to {status['target_id']} at revision {status['revision']}"
        )

        place = {"size": [2, 2, 2], "position": [0, 1, 0], "operation_id": "smoke-1"}
        first = (await client.call_tool("hf_place_brush", place)).structured_content
        _check(first["ok"], "place answers ok", first)
        brush = first["result"]["brush"]
        _check(
            brush["size"] == [2.0, 2.0, 2.0], "the brush has the size asked for", brush
        )
        report.append(f"placed {brush['brush_id']} at revision {first['revision']}")

        again = (await client.call_tool("hf_place_brush", place)).structured_content
        _check(again["replayed"], "a retry is replayed, not run", again)
        _check(
            again["result"] == first["result"], "the replay is the first answer", again
        )
        report.append("the retry came back from the cache")

        after = (await client.call_tool("hf_get_status", {})).structured_content
        counts = after["result"]["counts"]
        _check(counts["brushes"] == 1, "one brush after a retry", counts)

        clash = dict(place, position=[4, 1, 0])
        refused = (await client.call_tool("hf_place_brush", clash)).structured_content
        _check(
            not refused["ok"] and refused["error"]["code"] == "operation_id_conflict",
            "a reused operation_id with other arguments is refused",
            refused,
        )
        report.append("a reused operation_id with other arguments was refused")

        brush_id = brush["brush_id"]
        moved = (
            await client.call_tool(
                "hf_transform_brush", {"brush_id": brush_id, "position": [3, 1, 0]}
            )
        ).structured_content
        _check(moved["ok"], "transform answers ok", moved)
        listed = (
            await client.call_tool("hf_get_brushes", {"brush_ids": [brush_id]})
        ).structured_content
        where = listed["result"]["brushes"][0]["position"]
        _check(where == [3.0, 1.0, 0.0], "the brush is where it was moved", where)

        undone = (await client.call_tool("hf_undo", {})).structured_content
        _check(undone["ok"], "the agent can undo its own step", undone)
        _check(
            undone["result"]["undone"] == "MCP: transform brush",
            "undo takes back the move, the last step",
            undone,
        )
        listed = (
            await client.call_tool("hf_get_brushes", {"brush_ids": [brush_id]})
        ).structured_content
        where = listed["result"]["brushes"][0]["position"]
        _check(where == [0.0, 1.0, 0.0], "the brush is back where it was", where)
        report.append("moved the brush, read it back, and undid the move")

        batch = {
            "ops": [
                {
                    "tool": "hf_place_brush",
                    "params": {"size": [2, 2, 2], "position": [8, 1, 0]},
                },
                {
                    "tool": "hf_resize_brush",
                    "params": {"brush_id": "$0.brush_id", "size": [4, 2, 2]},
                },
            ]
        }
        batched = (await client.call_tool("hf_batch", batch)).structured_content
        _check(batched["ok"], "a batch with a reference answers ok", batched)
        resized = batched["result"]["results"][1]["result"]["brush"]["size"]
        _check(
            resized == [4.0, 2.0, 2.0],
            "the reference reached the batch's own brush",
            resized,
        )
        report.append("batched a place and a resize of what it placed")

        commands = (await client.call_tool("hf_list_commands", {})).structured_content
        listed_ids = [entry["command"] for entry in commands["result"]["commands"]]
        _check(
            "hollow" in listed_ids, "the editor lists its palette commands", listed_ids
        )
        resized_id = batched["result"]["results"][1]["result"]["brush"]["brush_id"]
        hollowed = (
            await client.call_tool(
                "hf_run_command",
                {
                    "command": "hollow",
                    "brush_ids": [resized_id],
                    "params": {"thickness": 0.25},
                },
            )
        ).structured_content
        _check(hollowed["ok"], "a palette command answers ok", hollowed)
        _check(
            len(hollowed["result"]["made"]) == 6
            and hollowed["result"]["removed"] == [resized_id],
            "hollow made six walls in place of the brush",
            hollowed["result"],
        )
        undone = (await client.call_tool("hf_undo", {})).structured_content
        _check(
            undone["ok"] and undone["result"]["undone"] == "MCP: hollow",
            "the agent undoes its hollow",
            undone,
        )
        report.append("listed the palette commands, hollowed a brush, and undid it")

        baked = (await client.call_tool("hf_bake", {})).structured_content
        _check(baked["ok"], "the bake answers ok", baked)
        bake_id = baked["result"]["bake_id"]
        _check(artifact.is_file(), "the bake wrote its scene", str(artifact))
        written = artifact.read_text(encoding="utf-8", errors="replace")
        _check(bake_id in written, "the scene carries its bake id", bake_id)
        status = (await client.call_tool("hf_get_status", {})).structured_content
        _check(
            status["result"]["bake_current"], "status calls the bake current", status
        )
        report.append(
            f"baked {bake_id} to {artifact.name}, and status calls it current"
        )

        # The editor goes away under the running server, and another comes up.
        old_target = status["target_id"]
        await restart("stop")
        gone = await client.call_tool("hf_get_status", {})
        code = (gone.structured_content or {}).get("error", {}).get("code")
        _check(
            gone.is_error and code == "bridge_off",
            "a closed editor is bridge_off",
            gone,
        )
        report.append("with the editor closed, status said bridge_off")
        await restart("start")
        stale = (
            await client.call_tool(
                "hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]}
            )
        ).structured_content
        _check(
            not stale["ok"] and stale["error"]["code"] == "target_changed",
            "a change aimed at the old editor is refused",
            stale,
        )
        fresh = (await client.call_tool("hf_get_status", {})).structured_content
        _check(fresh["ok"], "status attaches to the new editor", fresh)
        _check(
            fresh["target_id"] != old_target, "the new editor is a new target", fresh
        )
        landed = (
            await client.call_tool(
                "hf_place_brush", {"size": [2, 2, 2], "position": [0, 1, 0]}
            )
        ).structured_content
        _check(landed["ok"], "a change lands in the new editor", landed)
        report.append(
            "a new editor under the same server: the old target refused, "
            "then status attached and a change landed"
        )
    return report


def _wait_for(path: Path, process: subprocess.Popen, seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.is_file():
            return True
        if process.poll() is not None:
            return False
        time.sleep(0.25)
    return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--godot", default="godot", help="the Godot 4.7 executable")
    parser.add_argument("--project", type=Path, default=REPO)
    parser.add_argument("--seconds", type=float, default=120.0)
    args = parser.parse_args(argv)

    project = args.project.resolve()
    # Its own folder, not the project's discovery file: an editor open on this
    # project with the bridge on would have its file deleted by the run.
    work = project / ".godot" / "mcp_smoke"
    work.mkdir(parents=True, exist_ok=True)
    first = Editor(args, project, work, "godot")
    second = Editor(args, project, work, "godot_restarted")
    first.artifact.unlink(missing_ok=True)

    async def restart(step: str) -> None:
        # Blocking waits, off the event loop the MCP client runs on.
        if step == "stop":
            await asyncio.to_thread(first.stop)
        else:
            await asyncio.to_thread(second.start)

    try:
        first.start()
        report = asyncio.run(
            _round_trip(project, first.discovery, first.artifact, restart)
        )
    except SmokeFailure as failure:
        print(f"mcp smoke: FAILED: {failure}")
        ok = False
    else:
        for line in report:
            print(f"mcp smoke: {line}")
        ok = True
    finally:
        first.stop()
        second.stop()
    for editor in (first, second):
        if editor.log():
            print(editor.log())
    if first.discovery.exists():
        print("mcp smoke: FAILED: the discovery file outlived the listener")
        ok = False
    print("mcp smoke: passed" if ok else "mcp smoke: failed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
