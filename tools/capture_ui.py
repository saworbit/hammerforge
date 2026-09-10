#!/usr/bin/env python3
"""Run the editor UI capture with a crash-safe environment swap.

Capturing product shots needs tracked files temporarily changed: `project.godot`
cut back to the HammerForge plugin alone so nothing else a contributor has
enabled appears in the editor's main-screen bar, the editor layout reset so the
tab bar is not cluttered and the window geometry is reproducible, and the demo
sample scene put back afterwards because Godot saves open scenes before running
the project. Doing that by hand -- as the docs used to instruct -- leaves the
repository mutated if anything goes wrong mid-run.

This script makes the swap recoverable rather than merely careful:

  * It refuses to start if a target file already has uncommitted changes, so it
    never backs up an already-mutated file and "restores" the mutation.
  * Backups carry a marker file. If a previous run died before restoring, the
    next invocation restores from that backup first instead of stacking a second
    swap on top of it.
  * Restoration runs from a finally block, so it survives exceptions and Ctrl-C.

    python tools/capture_ui.py [--godot PATH]

Nothing here is Windows-specific except the default Godot path.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BACKUP_DIR = REPO / ".docshot-backup"
MARKER = BACKUP_DIR / "IN_PROGRESS"

# Tracked files the capture temporarily rewrites.
#
# The sample scenes are here because the editor writes them itself: Godot saves
# every modified open scene before running the project, so a demo that draws
# brushes and then hits Test Level persists those brushes into the sample. The
# next run would start from a level that is no longer empty, and the editor
# would raise a "newer on disk" dialog mid-take.
TARGETS = [
    Path("project.godot"),
    Path(".godot/editor/editor_layout.cfg"),
    Path("samples/hf_demo_empty.tscn"),
]


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=False
    ).stdout.strip()


def is_dirty(rel: Path) -> bool:
    """True when a tracked file has uncommitted changes. Untracked files (the
    editor layout is gitignored) are never 'dirty' for our purposes."""
    if not git("ls-files", "--", str(rel)):
        return False
    return bool(git("status", "--porcelain", "--", str(rel)))


def restore(reason: str) -> None:
    if not MARKER.exists():
        return
    for rel in TARGETS:
        saved = BACKUP_DIR / rel.name
        if saved.exists():
            dest = REPO / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(saved, dest)
            print(f"  restored {rel} ({reason})")
    shutil.rmtree(BACKUP_DIR, ignore_errors=True)


def prepare() -> None:
    import re

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    MARKER.write_text("capture_ui.py holds backups of the files listed here\n")
    for rel in TARGETS:
        src = REPO / rel
        if src.exists():
            shutil.copy2(src, BACKUP_DIR / rel.name)

    proj = REPO / "project.godot"
    text = proj.read_text(encoding="utf-8")
    # Named plugins would go stale the moment a contributor enabled a different
    # one. No editor bridge is vendored here, so anything beyond HammerForge is
    # local tooling and must not reach a product shot.
    text = re.sub(
        r"(?m)^enabled=PackedStringArray\(.*\)$",
        'enabled=PackedStringArray("res://addons/hammerforge/plugin.cfg")',
        text,
        count=1,
    )
    # Enable the capture plugin for this run only. It is deliberately not
    # shipped enabled: an EditorPlugin that reads an environment variable and
    # can call get_tree().quit() should not load during a contributor's normal
    # session, where a stray HF_DOCSHOT=1 would close their editor mid-work.
    text, enabled_count = re.subn(
        r"(?m)^(enabled=PackedStringArray\((?!.*hf_docshot).*?)\)$",
        r'\1, "res://addons/hf_docshot/plugin.cfg")',
        text,
        count=1,
    )
    if enabled_count != 1:
        raise SystemExit("could not enable hf_docshot in project.godot")
    proj.write_text(text, encoding="utf-8", newline="\n")

    layout = REPO / ".godot/editor/editor_layout.cfg"
    if layout.exists():
        s = layout.read_text(encoding="utf-8")
        s = re.sub(r"^dock_hsplit_1=.*$", "dock_hsplit_1=400", s, flags=re.M)
        s = re.sub(
            r"^open_scenes=.*$", "open_scenes=PackedStringArray()", s, flags=re.M
        )
        s = re.sub(r"^current_scene=.*$", 'current_scene=""', s, flags=re.M)
        # Pin the window geometry. Without this the editor restores its saved
        # position *after* anything else moves it, so a capture that measures
        # the window and then acts on those coordinates ends up pointing at
        # wherever the window used to be -- possibly another monitor. It also
        # makes output dimensions reproducible instead of depending on which
        # display the editor was last maximised on.
        s = re.sub(r"^mode=.*$", 'mode="windowed"', s, flags=re.M)
        s = re.sub(r"^position=Vector2i.*$", "position=Vector2i(0, 0)", s, flags=re.M)
        s = re.sub(r"^size=Vector2i.*$", "size=Vector2i(1920, 1080)", s, flags=re.M)
        layout.write_text(s, encoding="utf-8", newline="\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", default=os.environ.get("GODOT", r"C:\Godot\godot.cmd"))
    # The video harness drives its own editor lifecycle (it has to interleave
    # OBS and mouse control), but must not duplicate the environment swap --
    # duplicating it means duplicating the crash-safety, and one copy would rot.
    ap.add_argument(
        "--prepare-only",
        action="store_true",
        help="apply the environment swap and exit (for other harnesses)",
    )
    ap.add_argument(
        "--restore-only",
        action="store_true",
        help="undo a previous --prepare-only and exit",
    )
    args = ap.parse_args()

    if args.restore_only:
        restore("requested")
        return 0

    # Heal a previous run that died before restoring.
    if MARKER.exists():
        print("Found an unfinished capture; restoring before starting.")
        restore("stale backup")

    dirty = [str(r) for r in TARGETS if is_dirty(r)]
    if dirty:
        print(
            "Refusing to run: these tracked files already have changes:",
            file=sys.stderr,
        )
        for d in dirty:
            print(f"  {d}", file=sys.stderr)
        print(
            "Commit or stash them first, or the swap cannot be undone cleanly.",
            file=sys.stderr,
        )
        return 2

    # Suppress the onboarding card, which otherwise fills the top of the dock.
    subprocess.run(
        [
            args.godot,
            "--headless",
            "-s",
            "res://tools/prepare_editor_smoke.gd",
            "--path",
            ".",
            "--",
            "--show-welcome=false",
        ],
        cwd=REPO,
        check=False,
    )

    prepare()
    if args.prepare_only:
        print("Environment prepared. Call --restore-only when finished.")
        return 0

    try:
        env = dict(os.environ, HF_DOCSHOT="1")
        return subprocess.run(
            [args.godot, "--editor", "--path", "."], cwd=REPO, env=env, check=False
        ).returncode
    finally:
        restore("run finished")


if __name__ == "__main__":
    raise SystemExit(main())
