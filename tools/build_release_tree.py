#!/usr/bin/env python3
"""Assemble the tree that ships to users, and nothing else.

    python tools/build_release_tree.py <output-dir>

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

import shutil
import subprocess
import sys
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
RELEASE_README = """# HammerForge

Brush-based level editor for Godot 4.7+. Draw rooms, carve doorways, paint
terrain and bake to optimised meshes without leaving the Godot editor.

This is the release tree: the plugin and nothing else. Copy `addons/hammerforge`
into your project and enable **HammerForge** under
*Project > Project Settings > Plugins*.

- Documentation: https://saworbit.github.io/hammerforge/
- Source, issues and development: https://github.com/saworbit/hammerforge

Licensed under the MIT License. See `LICENSE`.
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


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip())
    dest = Path(sys.argv[1]).resolve()
    if dest.exists() and any(dest.iterdir()):
        raise SystemExit(f"refusing to build into a non-empty directory: {dest}")

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

    version = plugin_version()
    print(f"HammerForge {version}: {count + 2} files in {dest}")
    for entry in sorted(p.name for p in dest.iterdir()):
        print(f"  {entry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
