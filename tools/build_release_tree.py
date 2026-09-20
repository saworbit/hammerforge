#!/usr/bin/env python3
"""Assemble the tree that ships to users, and nothing else.

    python tools/build_release_tree.py <output-dir>
    python tools/build_release_tree.py --selftest

This repository is a development workspace as well as the home of the plugin.
It contains a test framework, contributor tooling and the machinery that builds
the documentation, none of which a user of HammerForge has any use for. The
Godot Asset Library installs whatever is in the repository at the commit it is
pointed at, so "the repository" and "the release" have to be different things.

What ships is the list below and nothing that is not on it. The default is
exclude: a new folder added to the repository does not reach users until
somebody puts it here deliberately.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Everything a user needs, and only that.
#
# The plugin is self-contained: the only paths it references outside its own
# folder are ones it creates inside the user's project at runtime
# (res://.hammerforge/, res://hammerforge_entities.json, res://prefabs).
#
# LICENSE and .gitignore are here because the Asset Library submission
# guidelines require the repository to carry both.
SHIP = [
    "addons/hammerforge",
    "LICENSE",
    ".gitignore",
]

# Named so the reason is recorded rather than rediscovered. These are all
# development tooling that lives in this repository for the maintainer's
# convenience; shipping them puts files in someone else's project that they did
# not ask for and cannot be expected to understand.
#
#   addons/gut          A third-party test framework. Only tests/ uses it, and
#                       tests do not ship. Worse than useless to a user: anyone
#                       who already has GUT installed would have their copy
#                       overwritten by whichever version this repository pins,
#                       which can break their own test suite.
#   addons/hf_docshot   Dev-only screenshot and demo-recording plugin. Reads an
#                       environment variable and can quit the editor.
#   tests/              Needs GUT, and tests the plugin rather than using it.
#   tools/              This script, and the rest of the build machinery.
#   docs/, overrides/   The documentation site. It is published, not installed.
#   samples/            Demo scenes for the screenshots and the video.
#   project.godot       Belongs to whoever is installing, not to us. Shipping
#   level_root.tscn     it would overwrite their project settings.
EXCLUDED_ON_PURPOSE = [
    "addons/gut",
    "addons/hf_docshot",
    "tests",
    "tools",
    "docs",
    "overrides",
    "samples",
    "project.godot",
    "level_root.tscn",
]

# A short README for the release tree. The repository's own README is written
# for GitHub and points at images under docs/, which do not ship -- copying it
# would produce a page of broken images.
#
# This one says what is true of the *tree* and nothing that is true of the
# plugin. addons/hammerforge/README.md ships in the same zip and describes the
# plugin, and two files answering "what is HammerForge and how do I enable it"
# is two files to keep in step, which this repository has already failed at once
# with a template and its copy (#789). Anything a reader would want about the
# plugin belongs over there, and the line below sends them.
#
# ADDON_README is named separately because the selftest asserts this file still
# points at it. A trim is only worth doing if it stays trimmed.
ADDON_README = "addons/hammerforge/README.md"
RELEASE_README = f"""# HammerForge release tree

This is a release tree rather than a Godot project. Copy `addons/hammerforge`
into your own project's `addons/` folder, so it ends up at
`res://addons/hammerforge/`. Nothing else here is needed to run the plugin.

If you would rather not copy anything out, the release page also carries
`hammerforge-<version>-addon.zip`, which is the plugin alone and extracts
straight into a project.

`{ADDON_README}` says what HammerForge is, how to enable it, and what it writes
into your project.

Licensed under the MIT License. See `LICENSE`.
"""


# The release branch is what the Asset Library downloads, and it downloads it as
# a *git archive* -- so `export-ignore` decides what a user actually installs.
#
# `.gitignore` and this file mean nothing inside somebody else's project, and the
# README above is written for someone who took the zip by hand. Godot's installer
# strips the `<repo>-<sha>/` wrapper and then offers everything left at the root,
# so without this a mapper installing into a fresh project gets HammerForge's
# README and HammerForge's ignore rules dropped in beside their own files.
#
# They stay in the branch: the Asset Library requires the repository to carry a
# .gitignore and a licence file, and `export-ignore` only changes what
# `git archive` emits. The hand-downloaded zip is built by `zip` from this tree
# rather than by `git archive`, so it keeps the README that explains it.
#
# LICENSE is deliberately not excluded. It is the file a reviewer is most likely
# to look for in a download, and a licence beside an addon folder is unremarkable
# where a stranger's README is not.
RELEASE_GITATTRIBUTES = """# Normalize EOL for all files that Git considers text files.
* text=auto eol=lf

# The reference map is a compressed .hflevel. text=auto guesses, and a wrong
# guess would mangle line endings inside the payload on checkout.
addons/hammerforge/data/reference_map.hflevel binary

# What the Asset Library downloads is a git archive of this branch, and these
# three have no meaning in the project it is installed into. LICENSE and addons/
# do. Set by tools/build_release_tree.py.
/.gitattributes export-ignore
/.gitignore export-ignore
/README.md export-ignore
"""


def plugin_version() -> str:
    """Read the version from plugin.cfg, so there is one source of truth."""
    cfg = (REPO / "addons/hammerforge/plugin.cfg").read_text(encoding="utf-8")
    for line in cfg.splitlines():
        if line.startswith("version="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("no version= in addons/hammerforge/plugin.cfg")


def tracked(path: str) -> list[str]:
    """Files git knows about under `path`.

    Deliberately not a filesystem walk: the working tree carries stray logs and
    scratch files, and a release should contain what is committed, not whatever
    happens to be lying around.
    """
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", path],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [f for f in out.split("\0") if f]


def check_destination(dest: Path) -> None:
    """Refuse a destination that is not somewhere a release tree belongs.

    `dest` is already resolved, so the containment test below is lexical on two
    real paths and a symlink into the repository cannot get round it.

    A path under the repository root is never a release tree. This script copies
    every tracked file of the plugin, which is hundreds of them, and it used to
    take any path at all: `--selftest`, typed on the assumption that this script
    carried the flag most of tools/ does, was read as the destination and built
    855 files into a directory of that name in the repository root. Exit 0, no
    complaint, and the next `git add -A` swept the lot into a commit (#817).
    """
    if dest.is_relative_to(REPO):
        raise SystemExit(
            f"refusing to build into the repository: {dest}\n"
            "A release tree is hundreds of copied files and this is a working"
            " tree. Name a destination outside it."
        )
    if dest.exists() and any(dest.iterdir()):
        raise SystemExit(f"refusing to build into a non-empty directory: {dest}")


def build(dest: Path) -> int:
    check_destination(dest)

    for excluded in EXCLUDED_ON_PURPOSE:
        for shipped in SHIP:
            if excluded == shipped or excluded.startswith(shipped + "/"):
                raise SystemExit(
                    f"{excluded} is both shipped and excluded; the lists disagree"
                )

    count = 0
    for entry in SHIP:
        files = tracked(entry)
        if not files:
            raise SystemExit(f"nothing tracked under {entry}; check the SHIP list")
        for rel in files:
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / rel, target)
            count += 1

    # The licence travels with the plugin folder as well as the tree root, so it
    # survives a user who installs only addons/hammerforge.
    shutil.copy2(REPO / "LICENSE", dest / "addons/hammerforge/LICENSE")
    (dest / "README.md").write_text(RELEASE_README, encoding="utf-8", newline="\n")
    (dest / ".gitattributes").write_text(
        RELEASE_GITATTRIBUTES, encoding="utf-8", newline="\n"
    )

    version = plugin_version()
    print(f"HammerForge {version}: {count + 3} files in {dest}")
    for entry in sorted(p.name for p in dest.iterdir()):
        print(f"  {entry}")
    return 0


def refuses(dest: Path) -> bool:
    """Whether check_destination() turns this path down."""
    try:
        check_destination(dest)
    except SystemExit:
        return True
    return False


def selftest() -> int:
    """Build into a throwaway directory and check the shape of what came out.

    This script decides what reaches the Asset Library and it ran in exactly one
    place, on the tag, so the earliest anyone found out it was broken was the
    release. It runs on every pull request now.

    What is checked here is that the builder does what SHIP and
    EXCLUDED_ON_PURPOSE say, not that those two lists are right. The release
    workflow checks the lists, against the built output rather than against the
    lists themselves, and that is the correct place for it: a policy check that
    reads the policy it is checking proves nothing. So the expected root below is
    derived from SHIP. Adding an entry there deliberately still passes; the
    builder dropping one, or leaving something else behind, does not.
    """
    failures = 0

    # The guard first. Every path here is one that does not exist, because an
    # existing non-empty directory is refused by the second check whether the
    # containment one is there or not, and an assertion with a second way to
    # pass says nothing about the property it is there for (#813). So the
    # repository root is not in this list: it is refused, but it would be
    # refused anyway. The first path is the one from the incident.
    for bad in (REPO / "--selftest", REPO / "build" / "release"):
        if not refuses(bad):
            print(f"selftest: a destination inside the repository was allowed: {bad}")
            failures += 1

    with tempfile.TemporaryDirectory() as tmp:
        outside = Path(tmp).resolve()
        if refuses(outside / "release"):
            print(f"selftest: an empty directory outside the repo was refused: {tmp}")
            failures += 1
        # The non-empty guard is the half that was already here. Nothing ran it.
        (outside / "occupied").mkdir()
        (outside / "occupied" / "something").write_text("", encoding="utf-8")
        if not refuses(outside / "occupied"):
            print("selftest: a non-empty destination was allowed")
            failures += 1

        dest = outside / "release"
        build(dest)

        # Derived from SHIP: "addons/hammerforge" is reached through "addons".
        # The two generated files are added because they are written rather than
        # copied, so no list mentions them.
        expected = {entry.split("/")[0] for entry in SHIP} | {
            "README.md",
            ".gitattributes",
        }
        actual = {p.name for p in dest.iterdir()}
        if actual != expected:
            print(
                f"selftest: the tree root is {sorted(actual)}, expected {sorted(expected)}"
            )
            failures += 1

        for rel in (
            "addons/hammerforge/plugin.cfg",
            "addons/hammerforge/LICENSE",
            ADDON_README,
            "LICENSE",
            "README.md",
        ):
            if not (dest / rel).is_file():
                print(f"selftest: {rel} did not reach the tree")
                failures += 1

        for rel in EXCLUDED_ON_PURPOSE:
            if (dest / rel).exists():
                print(f"selftest: {rel} is excluded on purpose and reached the tree")
                failures += 1

        # #789: the generated README was trimmed to what is true of the tree, and
        # it hands the reader to the addon's README for everything else. Without
        # this line the next person to want a sentence about the plugin in the
        # zip root has nothing telling them there is already a file for that.
        if ADDON_README not in (dest / "README.md").read_text(encoding="utf-8"):
            print(f"selftest: the generated README no longer points at {ADDON_README}")
            failures += 1

    if failures:
        print(f"selftest: {failures} wrong answers")
        return 1
    print(
        "selftest: the tree builds with the right files at its root, nothing"
        " excluded on purpose in it, a README that defers to the addon's, and a"
        " destination guard that still refuses the repository"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "dest",
        nargs="?",
        help="directory to build into. Must be outside this repository.",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="build into a temporary directory and check the shape of the tree"
        " and that the destination guard still refuses the repository",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if args.dest is None:
        parser.error("a destination directory is required")
    return build(Path(args.dest).resolve())


if __name__ == "__main__":
    raise SystemExit(main())
