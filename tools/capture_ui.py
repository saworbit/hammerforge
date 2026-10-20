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
  * The contributor's own HammerForge prefs (`user://hammerforge_prefs.json`)
    are backed up before the onboarding card is hidden, which resets them, and
    put back with the rest (#1333). Prefs that did not exist before the run do
    not exist after it.

    python tools/capture_ui.py [--godot PATH]
    python tools/capture_ui.py --selftest

Nothing here is Windows-specific except the default Godot path.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BACKUP_DIR = REPO / ".docshot-backup"
MARKER = BACKUP_DIR / "IN_PROGRESS"


def project_name() -> str:
    text = (REPO / "project.godot").read_text(encoding="utf-8")
    found = re.search(r'(?m)^config/name="([^"]*)"', text)
    return found.group(1) if found else "hammerforge"


def prefs_path() -> Path:
    """Where Godot keeps this project's user://hammerforge_prefs.json.

    prepare_editor_smoke.gd resets it to hide the onboarding card, so without
    a backup every capture wiped the contributor's favourites, tutorial
    progress and collapsed sections (#1333).
    """
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        vendor = "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
        vendor = "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
        vendor = "godot"
    return base / vendor / "app_userdata" / project_name() / "hammerforge_prefs.json"


# Files the capture temporarily rewrites. The tracked ones are checked for
# uncommitted changes first; the prefs live outside the repository.
#
# The sample scenes are here because the editor writes them itself: Godot saves
# every modified open scene before running the project, so a demo that draws
# brushes and then hits Test Level persists those brushes into the sample. The
# next run would start from a level that is no longer empty, and the editor
# would raise a "newer on disk" dialog mid-take.
TARGETS = [
    REPO / "project.godot",
    REPO / ".godot/editor/editor_layout.cfg",
    REPO / "samples/hf_demo_empty.tscn",
    prefs_path(),
]


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=False
    ).stdout.strip()


def is_dirty(path: Path) -> bool:
    """True when a tracked file has uncommitted changes. Untracked files (the
    editor layout is gitignored) and files outside the repository (the prefs)
    are never 'dirty' for our purposes."""
    if not path.is_relative_to(REPO):
        return False
    rel = path.relative_to(REPO)
    if not git("ls-files", "--", str(rel)):
        return False
    return bool(git("status", "--porcelain", "--", str(rel)))


def shown(path: Path) -> str:
    return str(path.relative_to(REPO)) if path.is_relative_to(REPO) else str(path)


def backup() -> None:
    """Copy every target aside, and note the ones that do not exist yet.

    The note is what lets restore() remove a file the run created, rather than
    leave a contributor who had no prefs file with one.
    """
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    MARKER.write_text("capture_ui.py holds backups of the files listed here\n")
    for path in TARGETS:
        if path.exists():
            shutil.copy2(path, BACKUP_DIR / path.name)
        else:
            (BACKUP_DIR / f"{path.name}.absent").write_text("")


def restore(reason: str) -> None:
    if not MARKER.exists():
        return
    for path in TARGETS:
        saved = BACKUP_DIR / path.name
        if saved.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(saved, path)
            print(f"  restored {shown(path)} ({reason})")
        elif (BACKUP_DIR / f"{path.name}.absent").exists() and path.exists():
            path.unlink()
            print(f"  removed {shown(path)}, which did not exist before ({reason})")
    shutil.rmtree(BACKUP_DIR, ignore_errors=True)


def swap() -> None:
    """Rewrite the backed-up files for the capture."""
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


def selftest() -> int:
    """The swap puts the prefs back, whether the run finished or died."""
    import tempfile
    from unittest import mock

    failures = 0
    if prefs_path() not in TARGETS:
        print("selftest: the prefs are not among the files the capture puts back")
        failures += 1
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        (repo / "project.godot").write_text(
            'enabled=PackedStringArray("res://addons/other/plugin.cfg")\n',
            encoding="utf-8",
        )
        prefs = Path(tmp) / "app_userdata" / "hammerforge_prefs.json"
        prefs.parent.mkdir(parents=True)
        patched = {
            "REPO": repo,
            "BACKUP_DIR": repo / ".docshot-backup",
            "MARKER": repo / ".docshot-backup" / "IN_PROGRESS",
            "TARGETS": [repo / "project.godot", prefs],
        }
        with mock.patch.multiple(sys.modules[__name__], **patched):
            # A run that finishes: the editor rewrote the prefs in between.
            prefs.write_text('{"favourites": ["box"]}', encoding="utf-8")
            backup()
            prefs.write_text("{}", encoding="utf-8")
            restore("selftest")
            if prefs.read_text(encoding="utf-8") != '{"favourites": ["box"]}':
                print("selftest: a finished run did not put the prefs back")
                failures += 1
            if MARKER.exists():
                print("selftest: the marker outlived the restore")
                failures += 1
            # A run that died: the next invocation heals from the marker.
            backup()
            prefs.write_text("{}", encoding="utf-8")
            if not MARKER.exists():
                print("selftest: backup left no marker to heal from")
                failures += 1
            restore("stale backup")
            if prefs.read_text(encoding="utf-8") != '{"favourites": ["box"]}':
                print("selftest: healing a dead run did not put the prefs back")
                failures += 1
            # No prefs before the run: none after it either.
            prefs.unlink()
            backup()
            prefs.write_text("{}", encoding="utf-8")
            restore("selftest")
            if prefs.exists():
                print("selftest: a run left prefs behind that did not exist before")
                failures += 1
            if (repo / "project.godot").read_text(encoding="utf-8") != (
                'enabled=PackedStringArray("res://addons/other/plugin.cfg")\n'
            ):
                print("selftest: project.godot was not put back")
                failures += 1
    if failures:
        print(f"selftest: {failures} wrong answers")
        return 1
    print(
        "selftest: the prefs and project.godot come back after a finished run, a dead one, and one that started with no prefs"
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
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
    ap.add_argument(
        "--selftest",
        action="store_true",
        help="check the backup still puts the prefs back",
    )
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.restore_only:
        restore("requested")
        return 0

    # Heal a previous run that died before restoring.
    if MARKER.exists():
        print("Found an unfinished capture; restoring before starting.")
        restore("stale backup")

    dirty = [shown(path) for path in TARGETS if is_dirty(path)]
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

    # The onboarding reset below rewrites the prefs, so they go aside first.
    backup()

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

    swap()
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
