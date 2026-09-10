#!/usr/bin/env python3
"""Refuse a project.godot that enables anything but HammerForge.

`project.godot` is tracked, and the Godot editor rewrites it the moment you
enable a plugin. So a contributor who installs an MCP bridge, a profiler or any
other editor addon has a dirty tracked file from then on, and the enable rides
into the next commit that runs `git add -A`.

That is not hypothetical. `addons/godot_mcp` and its `MCPRuntimeProbe` autoload
sat enabled in this file for months and shipped to everyone, which is what
issue #277 was about. The pull request template asks a human to confirm the file
is clean. A checkbox is not a guard.

There is no engine-side way out. `override.cfg` looks like the answer and is
not: on Godot 4.7 an `editor_plugins/enabled` written there does not enable the
plugin in the editor, while the same value in `project.godot` does. Verified
against 4.7.stable rather than taken from the documentation, which is quiet on
the point.

    python tools/check_project_settings.py

Exits 1 and names what it found. `--selftest` checks the detector still catches
each way this goes wrong, because a guard that cannot fail is not a guard.
"""

from __future__ import annotations

import argparse
import re
import sys

# The only editor plugin this repository ships enabled. `addons/gut` runs from
# the command line and is never enabled; `addons/hf_docshot` is switched on for
# the length of a capture by tools/capture_ui.py and switched back off. Adding a
# name here is a deliberate act, which is the point.
ALLOWED_PLUGINS = ["res://addons/hammerforge/plugin.cfg"]

# HammerForge ships no autoload. One appearing here means an addon put it there.
ALLOWED_AUTOLOADS: list[str] = []

SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$")
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_/.]*)\s*=")
PACKED_RE = re.compile(r"^enabled\s*=\s*PackedStringArray\((.*)\)\s*$")
QUOTED_RE = re.compile(r'"([^"]*)"')


class ParseError(Exception):
    """The file did not look the way this guard knows how to read."""


def parse(text: str) -> tuple[list[str], list[str]]:
    """Return the enabled editor plugins and the autoload names.

    Raises ParseError rather than guessing. A guard that cannot read the file
    must not report it clean.
    """
    section = ""
    plugins: list[str] | None = None
    autoloads: list[str] = []

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue

        matched = SECTION_RE.match(line)
        if matched:
            section = matched.group(1)
            continue

        if section == "editor_plugins" and line.startswith("enabled"):
            packed = PACKED_RE.match(line)
            if not packed:
                raise ParseError(f"cannot read the enabled plugin list: {line}")
            plugins = QUOTED_RE.findall(packed.group(1))
            continue

        if section == "autoload":
            key = KEY_RE.match(line)
            if not key:
                raise ParseError(f"cannot read the autoload entry: {line}")
            autoloads.append(key.group(1))

    if plugins is None:
        raise ParseError("no [editor_plugins] enabled list found")
    return plugins, autoloads


def check(text: str) -> list[str]:
    """Return one line per problem. Empty means the file is clean."""
    try:
        plugins, autoloads = parse(text)
    except ParseError as exc:
        return [str(exc)]

    problems = []
    for plugin in plugins:
        if plugin not in ALLOWED_PLUGINS:
            problems.append(
                f"{plugin} is enabled; it is local tooling, not part of this repo"
            )
    for allowed in ALLOWED_PLUGINS:
        if allowed not in plugins:
            problems.append(
                f"{allowed} is not enabled; the plugin has to load for anyone cloning"
            )
    for name in autoloads:
        if name not in ALLOWED_AUTOLOADS:
            problems.append(f"autoload {name} is registered; HammerForge ships none")
    return problems


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------

CLEAN = """config_version=5

[application]

config/name="HammerForge"

[editor_plugins]

enabled=PackedStringArray("res://addons/hammerforge/plugin.cfg")

[physics]

3d/default_gravity=9.8
"""

# The exact shape this repository shipped before issue #277.
LEAKED_BRIDGE = """config_version=5

[autoload]

MCPRuntimeProbe="*uid://bsg12huaf1u5i"

[editor_plugins]

enabled=PackedStringArray("res://addons/hammerforge/plugin.cfg", "res://addons/godot_mcp/plugin.cfg")
"""

CASES: list[tuple[str, str, bool]] = [
    ("clean", CLEAN, True),
    ("the shape #277 was about", LEAKED_BRIDGE, False),
    (
        "a local bridge enabled",
        CLEAN.replace(
            'PackedStringArray("res://addons/hammerforge/plugin.cfg")',
            'PackedStringArray("res://addons/hammerforge/plugin.cfg", "res://addons/didi/plugin.cfg")',
        ),
        False,
    ),
    (
        "hammerforge switched off",
        CLEAN.replace('"res://addons/hammerforge/plugin.cfg"', ""),
        False,
    ),
    (
        "an autoload with nothing else wrong",
        CLEAN + '\n[autoload]\n\nSomeProbe="*res://addons/thing/probe.gd"\n',
        False,
    ),
    (
        "an empty autoload section",
        CLEAN + "\n[autoload]\n",
        True,
    ),
    (
        "an enabled list this guard cannot read",
        CLEAN.replace(
            'enabled=PackedStringArray("res://addons/hammerforge/plugin.cfg")',
            "enabled=[something new]",
        ),
        False,
    ),
    ("no editor_plugins section at all", "config_version=5\n", False),
    (
        "a plugin name that merely contains the allowed one",
        CLEAN.replace(
            '"res://addons/hammerforge/plugin.cfg"',
            '"res://addons/hammerforge_extras/plugin.cfg"',
        ),
        False,
    ),
]


def selftest() -> int:
    failures = 0
    for name, text, should_pass in CASES:
        problems = check(text)
        passed = not problems
        if passed != should_pass:
            want = "clean" if should_pass else "rejected"
            print(
                f"selftest: {name} should have been {want}, got {problems or 'clean'}"
            )
            failures += 1
    if failures:
        print(f"selftest: {failures} of {len(CASES)} cases wrong")
        return 1
    print(f"selftest: {len(CASES)} cases correct")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?", default="project.godot")
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the detector still catches each way this goes wrong",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    try:
        with open(args.project, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"{args.project}: {exc}")
        return 1

    problems = check(text)
    if not problems:
        return 0
    for problem in problems:
        print(f"{args.project}: {problem}")
    print("Keep a local enable out of the commit. See DEVELOPMENT.md.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
