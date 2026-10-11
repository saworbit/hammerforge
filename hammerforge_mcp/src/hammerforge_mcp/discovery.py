"""Finding the editor: the file the bridge writes when it is turned on."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

#: Inside a folder the editor closes to other users before writing the token.
DISCOVERY_RELATIVE = Path(".godot") / "hammerforge_mcp" / "discovery.json"

TURN_ON = (
    "In the Godot editor, open the HammerForge dock, go to the Test tab, "
    "open Agent Bridge and tick Allow agent connections (MCP)."
)


class DiscoveryError(Exception):
    """Why the server cannot reach the editor, worded as what to do about it."""


@dataclass(frozen=True)
class Discovery:
    port: int
    pid: int
    #: Kept out of repr, so a logged or printed Discovery does not show it.
    token: str = field(repr=False)
    bridge_version: int
    project_path: str
    hammerforge_version: str = ""


def discovery_path(project: Path) -> Path:
    return Path(project) / DISCOVERY_RELATIVE


def read_discovery(
    project: Path, *, path: Path | None = None, check_pid: bool = True
) -> Discovery:
    """Read the file the editor wrote. `path` overrides where to look."""
    project = Path(project)
    if path is None:
        if not (project / "project.godot").is_file():
            raise DiscoveryError(
                f"{project} is not a Godot project: it has no project.godot. "
                "Pass --project with the folder that has one, "
                "or set HAMMERFORGE_PROJECT."
            )
        path = discovery_path(project)
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise DiscoveryError(f"The HammerForge bridge is off. {TURN_ON}") from None
    try:
        data = json.loads(text)
        found = Discovery(
            port=_int(data, "port"),
            pid=_int(data, "pid"),
            token=_str(data, "token"),
            bridge_version=_int(data, "bridge_version"),
            project_path=_str(data, "project_path"),
            hammerforge_version=str(data.get("hammerforge_version", "")),
        )
    except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        raise DiscoveryError(
            f"{path} could not be read ({exc}). Untick and tick the bridge "
            "in the Test tab to write it again."
        ) from None
    if check_pid and not pid_alive(found.pid):
        raise DiscoveryError(
            f"The editor that turned the bridge on (pid {found.pid}) has exited. "
            f"Open the project again. {TURN_ON}"
        )
    return found


def _int(data: dict, key: str) -> int:
    value = data[key]
    # Godot writes every number from parsed JSON as a float; these are its own.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"{key} is not a number")
    if value != int(value):
        raise ValueError(f"{key} is not a whole number")
    return int(value)


def _str(data: dict, key: str) -> str:
    value = data[key]
    if not isinstance(value, str) or not value:
        raise TypeError(f"{key} is not a string")
    return value


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":
        return _windows_pid_alive(pid)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # It exists and belongs to someone else.
        return True
    return True


def _windows_pid_alive(pid: int) -> bool:
    import ctypes
    from ctypes import wintypes

    process_query_limited_information = 0x1000
    still_active = 259
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.GetExitCodeProcess.argtypes = [
        wintypes.HANDLE,
        ctypes.POINTER(wintypes.DWORD),
    ]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
    if not handle:
        # Access denied still means the process is there.
        return ctypes.get_last_error() == 5
    try:
        code = wintypes.DWORD()
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
            return True
        return code.value == still_active
    finally:
        kernel32.CloseHandle(handle)
