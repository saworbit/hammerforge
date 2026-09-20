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

A source git has not been told about yet is reported and not failed. The
tracked list cannot see a brand new script, so a clean verdict here says
nothing about one, and the test file for #801 kept its id only because someone
went looking afterwards. A scratch file in a working copy is not a defect
though, and failing on one would start refusing trees that are fine, so it
gets a line instead. A checkout has no untracked files, so the line never
appears in CI.

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


def ungraded(others: list[str], paths: list[str]) -> list[tuple[str, bool]]:
    """Untracked sources, and whether an id exists anywhere for each one.

    Neither passing nor failing. `check()` grades the tracked list, which a
    file git has never heard of is not in, so the verdict above is silent
    about it. The one with no id fails the moment it is staged, and that is
    worth saying before the push rather than after.

    Whether the id exists is read from both lists and not from the disk. An
    untracked source with a tracked `.uid` is already reported as an orphan,
    and telling the reader there is no id when there is one would send them
    to import a file that has been imported.
    """
    ids = set(paths) | set(others)
    return sorted(
        (path, f"{path}.uid" in ids)
        for path in others
        if path.endswith(SIDECAR_SUFFIXES) and not is_vendored(path)
    )


def tracked() -> list[str]:
    """Every path git knows about, as forward-slashed strings."""
    return _ls_files("-z")


def untracked() -> list[str]:
    """Every path on disk that git has been told nothing about.

    `--exclude-standard` applies the ignore rules, so `.godot/` and the rest
    of the generated tree stay out of it. Without `--directory` a new folder
    of scripts is listed file by file, which is what this wants.
    """
    return _ls_files("--others", "--exclude-standard", "-z")


def _ls_files(*args: str) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", *args],
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


# (name, untracked paths, tracked paths, expected (source, has id) pairs)
UNGRADED_CASES: list[tuple[str, list[str], list[str], list[tuple[str, bool]]]] = [
    # The one that happened while landing #801: written, checked, and green.
    (
        "a new script nothing has imported yet",
        ["tests/test_new.gd"],
        [],
        [("tests/test_new.gd", False)],
    ),
    (
        "a new script that has been imported carries its id",
        ["tests/test_new.gd", "tests/test_new.gd.uid"],
        [],
        [("tests/test_new.gd", True)],
    ),
    # Both halves untracked is the state to be in before committing. Both
    # halves tracked is the clean tree, and neither is mentioned here.
    ("nothing untracked is nothing to say", [], ["tests/a.gd", "tests/a.gd.uid"], []),
    # An id already in the tree is an id. Reading the disk alone would miss it
    # and send someone to import a file that is imported.
    (
        "a tracked id counts for an untracked source",
        ["tests/a.gd"],
        ["tests/a.gd.uid"],
        [("tests/a.gd", True)],
    ),
    # The mirror: this is the orphan `check()` already fails on, and it is not
    # a source, so it is not listed here as well.
    ("an untracked id is not a source", ["tests/a.gd.uid"], ["tests/a.gd"], []),
    (
        "a shader is asked the same question",
        ["addons/hammerforge/g.gdshader"],
        [],
        [("addons/hammerforge/g.gdshader", False)],
    ),
    # A working copy is full of these and none of them is the guard's business.
    (
        "scratch files that are not scripts are left alone",
        ["notes.md", "a.log"],
        [],
        [],
    ),
    ("a new vendored file is still not ours", ["addons/gut/new.gd"], [], []),
    (
        "listed in path order whatever git said",
        ["tests/b.gd", "tests/a.gd"],
        [],
        [("tests/a.gd", False), ("tests/b.gd", False)],
    ),
]


def selftest() -> int:
    failures = 0
    for name, others, paths, want in UNGRADED_CASES:
        got = ungraded(others, paths)
        if got != want:
            print(f"selftest: {name} should give {want}, got {got}")
            failures += 1
    for name, paths, want_missing, want_orphaned in CASES:
        missing, orphaned = check(paths)
        if missing != want_missing:
            print(f"selftest: {name} should miss {want_missing}, got {missing}")
            failures += 1
        if orphaned != want_orphaned:
            print(f"selftest: {name} should orphan {want_orphaned}, got {orphaned}")
            failures += 1
    total = len(CASES) + len(UNGRADED_CASES)
    if failures:
        print(f"selftest: {failures} wrong answers across {total} cases")
        return 1
    print(f"selftest: {total} cases correct")
    return 0


def report_ungraded(waiting: list[tuple[str, bool]]) -> None:
    """Say which sources the verdict above did not cover. Never a failure."""
    if not waiting:
        return
    print("\nNot graded, because git is not tracking them yet:\n")
    for path, has_id in waiting:
        print("  %s%s" % (path, "" if has_id else "   no .uid beside it"))
    if all(has_id for _path, has_id in waiting):
        print("\nBoth halves are here. Commit the .uid along with the script.\n")
        return
    print(
        "\nThe ones with no id fail this check as soon as they are staged."
        "\nImport before you commit, and add both halves:\n"
        "\n  godot --headless --import --path .\n"
    )


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
    waiting = ungraded(untracked(), paths)
    if not missing and not orphaned:
        counted = sum(
            1
            for path in paths
            if path.endswith(SIDECAR_SUFFIXES) and not is_vendored(path)
        )
        print(
            "Every one of the %d scripts and shaders git tracks has its id." % counted
        )
        report_ungraded(waiting)
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
    report_ungraded(waiting)
    return 1


if __name__ == "__main__":
    sys.exit(main())
