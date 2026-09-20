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

It reads whichever copy of the file a push would carry. Usually that is the one
on disk. DEVELOPMENT.md asks you to run `git update-index --skip-worktree
project.godot` so your own editor plugins can stay enabled without showing up in
`git status`, and from that moment your copy is yours alone while CI reads the
committed one. Grading the copy on disk then fails you for something that will
never reach a branch, and passes nothing CI would not also pass, so this reads
the committed blob instead whenever git has stopped watching the file (#795).
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile

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
# Which copy of the file to grade
# ---------------------------------------------------------------------------

WORKTREE = "worktree"
COMMITTED = "committed"


def _git(path: str, *args: str) -> subprocess.CompletedProcess[str] | None:
    """Run git beside `path`. None when there is no usable git here.

    UnicodeDecodeError is caught with the rest: a committed blob that will not
    decode is a question this guard cannot answer, and falling back to the copy
    on disk keeps it running instead of ending the run in a traceback.
    """
    try:
        return subprocess.run(
            ("git", "-C", os.path.dirname(os.path.abspath(path)), *args),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except (OSError, UnicodeDecodeError):
        return None


def unwatched(path: str) -> bool:
    """True when git has been told to stop looking at this file's worktree copy.

    `git ls-files -v` prefixes each path with a one-letter tag. `S` is
    skip-worktree, and any lowercase tag is assume-unchanged. Either bit is
    per-clone and cannot be committed, so either one means the copy on disk is
    local to one machine and the committed copy is what a push carries.
    """
    listed = _git(path, "ls-files", "-v", "--", os.path.basename(path))
    if listed is None or listed.returncode != 0:
        return False
    lines = listed.stdout.splitlines()
    if not lines:
        return False
    tag = lines[0][:1]
    return tag == "S" or tag.islower()


def committed_text(path: str) -> str | None:
    """`path` as of HEAD, which is what CI checks out. None if git cannot say.

    The `./` prefix is load bearing: without it git reads the path from the
    root of the repository rather than from the directory it was given, so a
    file in a subdirectory would silently resolve somewhere else.
    """
    shown = _git(path, "show", f"HEAD:./{os.path.basename(path)}")
    if shown is None or shown.returncode != 0:
        return None
    return shown.stdout


def source(path: str) -> tuple[str, str]:
    """Return (text, origin) for the copy of `path` that a push would carry.

    Falls back to the worktree whenever git cannot answer, because a guard that
    refuses to run is worse than one reading the only copy it can see.
    """
    if unwatched(path):
        text = committed_text(path)
        if text is not None:
            return text, COMMITTED
    with open(path, encoding="utf-8") as handle:
        return handle.read(), WORKTREE


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


LOCAL_ENABLE = CLEAN.replace(
    'PackedStringArray("res://addons/hammerforge/plugin.cfg")',
    'PackedStringArray("res://addons/hammerforge/plugin.cfg",'
    ' "res://addons/didi/plugin.cfg")',
)


def split_cases() -> tuple[int, int]:
    """Check which copy of the file a run grades. Returns (failures, run).

    The cases above hand a string straight to check(), so they say nothing
    about where that string came from, which is all of #795. This builds a
    throwaway repository and moves the skip-worktree bit around it, because the
    only thing worth knowing is what real git does. Returns how many cases ran
    so a skip cannot quietly shrink the tally.
    """
    probe = _git(".", "--version")
    if probe is None or probe.returncode != 0:
        print("selftest: no git here, so the committed-vs-worktree cases did not run")
        return 0, 0

    failures = 0
    ran = 0
    with tempfile.TemporaryDirectory() as root:
        target = os.path.join(root, "project.godot")

        def git(*args: str) -> int:
            done = _git(target, *args)
            return 1 if done is None or done.returncode != 0 else 0

        def expect(name: str, want_origin: str, want_clean: bool) -> int:
            text, origin = source(target)
            clean = not check(text)
            if origin == want_origin and clean == want_clean:
                return 0
            said = "clean" if clean else "rejected"
            wanted = "clean" if want_clean else "rejected"
            print(
                f"selftest: {name} should have read the {want_origin} copy and"
                f" called it {wanted}, got the {origin} copy called {said}"
            )
            return 1

        with open(target, "w", encoding="utf-8") as handle:
            handle.write(CLEAN)
        # --no-verify and commit.gpgsign=false keep a contributor's global hooks
        # and signing key out of a fixture that is about git's index, not theirs.
        for argv in (
            ("init", "-q"),
            ("config", "user.email", "guard@example.invalid"),
            ("config", "user.name", "guard"),
            ("add", "project.godot"),
            ("-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "c"),
        ):
            if git(*argv):
                print(
                    "selftest: could not build the fixture repository, so it did not run"
                )
                return 0, 0

        with open(target, "w", encoding="utf-8") as handle:
            handle.write(LOCAL_ENABLE)

        # Nothing marked: the enable on disk is the one heading for a commit,
        # and catching it there is what #277 was about.
        failures += expect("an enable on disk with nothing marked", WORKTREE, False)
        ran += 1

        # The same disk copy, with git told to stop watching it. DEVELOPMENT.md
        # asks for exactly this, and CI will never see the enable.
        if git("update-index", "--skip-worktree", "project.godot"):
            print("selftest: could not set skip-worktree, so those cases did not run")
            return failures, ran
        failures += expect("skip-worktree over a local enable", COMMITTED, True)
        ran += 1

        # assume-unchanged gets a lowercase tag and means the same thing here.
        git("update-index", "--no-skip-worktree", "project.godot")
        git("update-index", "--assume-unchanged", "project.godot")
        failures += expect("assume-unchanged over a local enable", COMMITTED, True)
        ran += 1
        git("update-index", "--no-assume-unchanged", "project.godot")

        # An enable that really is committed is CI's problem too, so the flag
        # must not turn the guard off.
        git("add", "project.godot")
        git("-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "d")
        git("update-index", "--skip-worktree", "project.godot")
        failures += expect("an enable that is committed", COMMITTED, False)
        ran += 1
        git("update-index", "--no-skip-worktree", "project.godot")

        # A file git does not track, which is what a release tree, a tarball or
        # an unpacked zip is. There is no committed copy to prefer, and asking
        # for a tag on an untracked path succeeds with nothing to say, so the
        # answer has to come off the disk rather than out of an empty reply.
        loose = os.path.join(root, "untracked.godot")
        with open(loose, "w", encoding="utf-8") as handle:
            handle.write(LOCAL_ENABLE)
        text, origin = source(loose)
        if origin != WORKTREE or not check(text):
            print(
                "selftest: an untracked file has only a disk copy,"
                f" got the {origin} copy"
            )
            failures += 1
        ran += 1

    return failures, ran


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
    split_failures, split_ran = split_cases()
    failures += split_failures
    total = len(CASES) + split_ran
    if failures:
        print(f"selftest: {failures} of {total} cases wrong")
        return 1
    print(f"selftest: {total} cases correct")
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
        text, origin = source(args.project)
    except OSError as exc:
        print(f"{args.project}: {exc}")
        return 1

    problems = check(text)
    if not problems:
        return 0
    where = args.project if origin == WORKTREE else f"{args.project} (committed)"
    for problem in problems:
        print(f"{where}: {problem}")
    if origin == WORKTREE:
        print("Keep a local enable out of the commit. See DEVELOPMENT.md.")
    else:
        print(
            "git is not watching your copy of this file, so this is the committed"
            "\nversion, the one CI reads. A local enable is not what this is about."
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())
