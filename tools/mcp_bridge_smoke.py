"""Run the MCP bridge end to end: MCP client, hammerforge-mcp, listener, LevelRoot.

Starts `tools/mcp_bridge_smoke.gd` in a headless Godot, waits for the discovery
file it writes, then starts hammerforge-mcp over stdio the way an MCP client
does and talks to it through the SDK's own client. It reads status, places a
brush, sends the same change again and expects the first answer back instead
of a second brush, and checks a reused operation_id with other arguments is
refused.

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


def _check(condition: bool, what: str, seen: object) -> None:
    if not condition:
        raise SmokeFailure(f"{what}: got {seen!r}")


async def _round_trip(project: Path, discovery: Path) -> list[str]:
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
    discovery = work / "discovery.json"
    done = work / "done"
    log_path = work / "godot.log"
    for stale in (discovery, done):
        stale.unlink(missing_ok=True)

    command = [
        args.godot,
        "--headless",
        "--path",
        str(project),
        "-s",
        "res://tools/mcp_bridge_smoke.gd",
        "--",
        f"--discovery={discovery}",
        f"--done={done}",
        f"--seconds={args.seconds:g}",
    ]
    print("mcp smoke:", " ".join(command))
    with log_path.open("w", encoding="utf-8") as log:
        godot = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            if not _wait_for(discovery, godot, args.seconds):
                raise SmokeFailure("Godot never wrote the discovery file")
            report = asyncio.run(_round_trip(project, discovery))
        except SmokeFailure as failure:
            print(f"mcp smoke: FAILED: {failure}")
            ok = False
        else:
            for line in report:
                print(f"mcp smoke: {line}")
            ok = True
        finally:
            done.write_text("done", encoding="utf-8")
            try:
                godot.wait(timeout=30)
            except subprocess.TimeoutExpired:
                godot.kill()
                godot.wait()
            done.unlink(missing_ok=True)
    print(log_path.read_text(encoding="utf-8", errors="replace").strip())
    if discovery.exists():
        print("mcp smoke: FAILED: the discovery file outlived the listener")
        ok = False
    print("mcp smoke: passed" if ok else "mcp smoke: failed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
