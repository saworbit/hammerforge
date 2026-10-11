"""`hammerforge-mcp --check`: can this server reach the editor, and how to add it.

An MCP client starts the server itself and shows little of what goes wrong. This
runs the same connection by hand, says what it found in words a user can act on,
and prints the client configuration with this interpreter's absolute path, since
a client started from the desktop does not read the shell's PATH.
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path
from typing import TextIO

from hammerforge_mcp.bridge import Bridge, BridgeError

CHECK_TIMEOUT = 10.0


def _describe(status: dict) -> list[str]:
    result = status.get("result") or {}
    target = result.get("target") or {}
    counts = result.get("counts") or {}
    scene = target.get("scene_path") or target.get("scene_name") or "none open"
    level = target.get("level_root_path")
    lines = [
        "HammerForge bridge: connected",
        f"  editor: HammerForge {result.get('hammerforge_version', '?')}, "
        f"process {result.get('editor_pid', '?')}",
        f"  scene: {scene}",
    ]
    if level is None:
        lines.append(
            "  level: none in this scene. hf_create_starter makes one, "
            "or open a scene that has a LevelRoot."
        )
    else:
        lines.append(
            f"  level: {level}, revision {status.get('revision')}, "
            f"{counts.get('brushes', 0)} brushes"
        )
    busy = result.get("busy")
    if busy:
        lines.append(f"  busy: {busy} for {result.get('busy_seconds') or 0:.0f} s")
    return lines


def config_lines(project: Path, discovery: Path | None) -> list[str]:
    """How to add this server to a client, with absolute paths."""
    python = sys.executable
    args = ["-m", "hammerforge_mcp", "--project", str(project)]
    if discovery is not None:
        args += ["--discovery", str(discovery)]
    quoted = " ".join(f'"{arg}"' if " " in arg else arg for arg in args)
    desktop = {"mcpServers": {"hammerforge": {"command": python, "args": args}}}
    return [
        "",
        "To add it to Claude Code, run:",
        f'  claude mcp add hammerforge -- "{python}" {quoted}',
        "or save the block below as .mcp.json in the folder you start Claude Code in.",
        "",
        "For Claude Desktop, or another client that reads mcpServers, put this in its",
        "configuration file:",
        *("  " + line for line in json.dumps(desktop, indent=2).splitlines()),
    ]


async def _status(bridge: Bridge) -> dict:
    try:
        return await bridge.call(
            "hf_get_status", {}, mutating=False, timeout=CHECK_TIMEOUT
        )
    finally:
        await bridge.close()


def run_check(
    project: Path, discovery: Path | None = None, out: TextIO | None = None
) -> int:
    """Print what the check found and the client configuration. 0 when connected."""
    out = out or sys.stdout
    project = Path(project).resolve()
    bridge = Bridge(project, discovery=discovery)
    code = 0
    try:
        status = asyncio.run(_status(bridge))
    except BridgeError as exc:
        lines = [
            "HammerForge bridge: not reachable",
            f"  {exc.code}: {exc}",
            f"  project: {project}",
        ]
        code = 1
    else:
        lines = _describe(status)
    for line in lines + config_lines(project, discovery):
        print(line, file=out)
    return code
