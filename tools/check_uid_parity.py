#!/usr/bin/env python3
"""Refuse a script committed without its `.uid`, or a `.uid` with no script.

    python tools/check_uid_parity.py
    python tools/check_uid_parity.py --selftest

Godot 4.4 and later give every script and shader a stable id and keep it in a
`.uid` file beside the source. Those two get a sidecar because they are plain
text with nowhere of their own to put it; a `.tscn` or a `.tres` has a header
and writes the id in there, and an imported asset keeps it in its `.import`.
That is why none of those are checked here. Godot's own guidance is that the
sidecars belong in version control and must not be ignored.

The id is what survives a rename. When it is missing, Godot writes a fresh one
on the next import, separately on each machine, so the file turns up untracked
in whoever imported last and two people can commit different values for
something that was meant to be stable. The fallback is the path, which holds
until two files swap places without either path changing.

It has already happened here. `tests/test_scoped_undo_step.gd` landed in #760
without its `.uid` and was not committed until #770, ten pull requests later,
and then only because cutting a release ran an import on a machine that
regenerated it. For that whole window the repository had one more test script
than it had ids and nothing anywhere said so. Nothing failed, nothing went red,
and the first symptom was unrelated churn in somebody else's diff.

Both directions fail. The missing id is the half that was observed. An id with
no source left is the tail of a rename or a delete that only took one of the
two, and it is the same set comparison to find, so it costs nothing to catch.

Scope is everything git tracks except the vendored trees, which are somebody
else's to keep tidy: `addons/gut` carries a leftover `menu_manager.gd.uid` from
a version of GUT that had that file, and deleting it here would only be undone
by the next upgrade.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# The plain-text sources Godot gives a sidecar id to. Adding a suffix here is a
# deliberate act, which is the point: `.tscn` and `.tres` would fail on every
# file in the tree, because theirs is in the header instead. The list cannot be
# inferred from what is checked in either, since a directory carrying no ids at
# all is exactly the state this exists to refuse and would read as consistent.
SIDECAR_SUFFIXES = (".gd", ".gdshader")

# Vendored trees. Not ours, and an upgrade would undo anything fixed in them.
VENDORED = ("addons/gut",)


def is_vendored(path: str) -> bool:
    """True for a path inside a vendored tree.

    Matched with the separator on, so `addons/gutsy/thing.gd` is ours and is
    not swallowed by the `addons/gut` entry.
    """
    return any(path == root or path.startswith(f"{root}/") for root in VENDORED)


def check(paths: list[str]) -> tuple[list[str], list[str]]:
    """Sources carrying no id, and ids whose source is gone.

    Takes the tracked list rather than walking the filesystem. A `.uid` sitting
    untracked in a working copy is the state this exists to catch, and reading
    the disk would find it and call the repository fine.
    """
    sources: set[str] = set()
    ids: set[str] = set()
    for path in paths:
        if is_vendored(path):
            continue
        if path.endswith(".uid"):
            source = path[: -len(".uid")]
            if source.endswith(SIDECAR_SUFFIXES):
                ids.add(source)
        elif path.endswith(SIDECAR_SUFFIXES):
            sources.add(path)
    return sorted(sources - ids), sorted(ids - sources)


def tracked() -> list[str]:
    """Every path git knows about, as forward-slashed strings."""
    out = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    return [path for path in out.stdout.split("\0") if path]


# (name, tracked paths, sources with no id, ids with no source)
CASES: list[tuple[str, list[str], list[str], list[str]]] = [
    ("a script with its id is clean", ["tests/a.gd", "tests/a.gd.uid"], [], []),
    # The one that actually happened, ten pull requests before anyone noticed.
    (
        "a script with no id",
        ["tests/test_scoped_undo_step.gd"],
        ["tests/test_scoped_undo_step.gd"],
        [],
    ),
    ("an id with no script", ["tests/gone.gd.uid"], [], ["tests/gone.gd"]),
    (
        "both halves of the same mistake",
        ["tests/a.gd", "tests/b.gd.uid"],
        ["tests/a.gd"],
        ["tests/b.gd"],
    ),
    (
        "a shader with its id is clean",
        ["addons/hammerforge/g.gdshader", "addons/hammerforge/g.gdshader.uid"],
        [],
        [],
    ),
    (
        "a shader carries one too",
        ["addons/hammerforge/g.gdshader"],
        ["addons/hammerforge/g.gdshader"],
        [],
    ),
    # Anything that keeps its id inside itself must not be asked for a sidecar.
    (
        "scenes and resources keep theirs in the file",
        ["addons/hammerforge/a.tscn", "addons/hammerforge/b.tres"],
        [],
        [],
    ),
    (
        "an imported asset keeps it in .import",
        ["docs/a.png", "docs/a.png.import"],
        [],
        [],
    ),
    ("plain files are not asked for one", ["README.md", "project.godot"], [], []),
    ("a vendored miss is not ours to fix", ["addons/gut/a.gd"], [], []),
    (
        "a vendored leftover is not ours either",
        ["addons/gut/menu_manager.gd.uid"],
        [],
        [],
    ),
    # `addons/gutsy` starts with `addons/gut` and is not vendored by it.
    (
        "a name that merely starts with a vendored one is ours",
        ["addons/gutsy/a.gd"],
        ["addons/gutsy/a.gd"],
        [],
    ),
    # tests/ is where it went wrong and addons/hammerforge/ is what ships, but
    # the harness and the samples are committed GDScript with the same problem.
    (
        "the harness and the samples count",
        ["tools/vibe/a.gd", "samples/b.gd"],
        ["samples/b.gd", "tools/vibe/a.gd"],
        [],
    ),
]


def selftest() -> int:
    failures = 0
    for name, paths, want_missing, want_orphaned in CASES:
        missing, orphaned = check(paths)
        if missing != want_missing:
            print(f"selftest: {name} should miss {want_missing}, got {missing}")
            failures += 1
        if orphaned != want_orphaned:
            print(f"selftest: {name} should orphan {want_orphaned}, got {orphaned}")
            failures += 1
    if failures:
        print(f"selftest: {failures} wrong answers across {len(CASES)} cases")
        return 1
    print(f"selftest: {len(CASES)} cases correct")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the detector still catches each way this goes wrong",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    paths = tracked()
    missing, orphaned = check(paths)
    if not missing and not orphaned:
        counted = sum(
            1
            for path in paths
            if path.endswith(SIDECAR_SUFFIXES) and not is_vendored(path)
        )
        print("Every one of %d tracked scripts and shaders has its id." % counted)
        return 0

    if missing:
        print("Tracked without the .uid that Godot keeps their id in:\n")
        for path in missing:
            print("  %s" % path)
        print(
            "\nGodot regenerates a missing id per machine, so this becomes a"
            "\nvalue two people can disagree about. Import and commit what"
            "\nappears:\n"
            "\n  godot --headless --import --path .\n"
        )
    if orphaned:
        print("Ids left behind by a script that is gone:\n")
        for path in orphaned:
            print("  %s.uid" % path)
        print("\nDelete them. They name a file that no longer exists.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
