"""`hammerforge-mcp --check`: can this server reach the editor, and how to add it.

An MCP client starts the server itself and shows little of what goes wrong. This
runs the same connection by hand, says what it found in words a user can act on,
and prints the client configuration with this interpreter's absolute path, since
a client started from the desktop does not read the shell's PATH.
"""

from __future__ import annotations

import asyncio
import json
import shlex
import subprocess
import sys
from pathlib import Path
from typing import TextIO

from hammerforge_mcp import __version__
from hammerforge_mcp.bridge import Bridge, BridgeError

CHECK_TIMEOUT = 10.0
INSTALL = (
    "git+https://github.com/saworbit/hammerforge.git{ref}#subdirectory=hammerforge_mcp"
)


def _release(version: str) -> str:
    """A version as the addon spells it: the server's 0.3.3.dev0 is 0.3.3-dev."""
    return version.strip().removeprefix("v").replace(".dev0", "-dev")


def _version_lines(editor: str) -> list[str]:
    """This server's version, and the install line for the editor's own when the
    two are apart. The server is versioned with the addon, and an install line
    with no tag takes main's whatever addon the user has (#1055).
    """
    lines = [f"  server: hammerforge-mcp {__version__}"]
    if editor in ("", "?") or _release(editor) == _release(__version__):
        return lines
    ref = "" if editor.endswith("-dev") else f"@v{editor}"
    lines.append(
        f"  This is not the server for HammerForge {editor}. Install that one:"
    )
    lines.append(f'    pip install "{INSTALL.format(ref=ref)}"')
    return lines


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
        *_version_lines(str(result.get("hammerforge_version") or "?")),
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


def _command_line(words: list[str]) -> str:
    """Words as this platform's shell reads them back."""
    if sys.platform == "win32":
        return subprocess.list2cmdline(words)
    return shlex.join(words)


def config_lines(project: Path, discovery: Path | None) -> list[str]:
    """How to add this server to a client, with absolute paths."""
    python = sys.executable
    args = ["-m", "hammerforge_mcp", "--project", str(project)]
    if discovery is not None:
        args += ["--discovery", str(discovery)]
    desktop = {"mcpServers": {"hammerforge": {"command": python, "args": args}}}
    claude = ["claude", "mcp", "add", "--transport", "stdio", "hammerforge", "--"]
    return [
        "",
        "To add it to Claude Code, run:",
        "  " + _command_line([*claude, python, *args]),
        "or, if that will not run in your shell, save the block below as .mcp.json",
        "in the project's root. It holds this machine's paths, so keep it out of git.",
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
    if discovery is not None:
        # A client starts the server in a folder of its own choosing.
        discovery = Path(discovery).resolve()
    # An observer, so a check never cuts off an agent that is working (#1060).
    bridge = Bridge(project, discovery=discovery, observer=True)
    code = 1
    try:
        status = asyncio.run(_status(bridge))
    except BridgeError as exc:
        lines = [
            "HammerForge bridge: not reachable",
            f"  {exc.code}: {exc}",
            f"  project: {project}",
        ]
    else:
        if status.get("ok"):
            lines = _describe(status)
            code = 0
        else:
            error = status.get("error") or {}
            lines = [
                "HammerForge bridge: connected, but status was refused",
                f"  {error.get('code', '?')}: {error.get('message', '')}",
            ]
    # A configuration for a folder that is not a Godot project would only start
    # a server that cannot find the editor.
    if (project / "project.godot").is_file():
        lines += config_lines(project, discovery)
    for line in lines:
        print(line, file=out)
    return code
