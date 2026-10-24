"""DEVELOPMENT.md's codebase map names every addon script, and no script that is gone.

The map under **Codebase Structure** gives each script in `addons/hammerforge/`
a line saying what it is for. Nothing checked it, and it drifted: 24 scripts
from one soak and 34 older ones had no line (#1865). The bridge's own scripts
under `mcp/` are left out, as the map leaves them out.

A line names a script by its first word, either as a path from the addon folder
(`ui/hf_selection_info.gd`) or as a file name under the folder heading above it
(`ui/` and then `hf_toast.gd`, indented further).

    python tools/check_codebase_map.py             check the map
    python tools/check_codebase_map.py --selftest  check that a gap is caught
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PAGE = REPO / "DEVELOPMENT.md"
ADDON = "addons/hammerforge/"
HEADING = "## Codebase Structure"
# Folders under the addon whose scripts the map does not list.
LEFT_OUT = ("mcp/",)


def map_lines(page_text: str) -> list[tuple[int, str]]:
    """The lines of the map's code block, each with its line number."""
    lines = page_text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == HEADING)
    except StopIteration:
        return []
    out: list[tuple[int, str]] = []
    inside = False
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line.startswith("```"):
            if inside:
                break
            inside = True
            continue
        if not inside and line.startswith("#"):
            break
        if inside:
            out.append((index + 1, line))
    return out


def mapped_scripts(page_text: str) -> dict[str, int]:
    """Each script path the map names, from the addon folder, with its line."""
    found: dict[str, int] = {}
    folders: list[tuple[int, str]] = []
    for number, line in map_lines(page_text):
        stripped = line.strip()
        if not stripped:
            continue
        indent = len(line) - len(line.lstrip(" "))
        word = stripped.split()[0]
        while folders and folders[-1][0] >= indent:
            folders.pop()
        if word.endswith("/"):
            if word.rstrip("/") + "/" != ADDON:
                folders.append((indent, word))
            continue
        if not word.endswith(".gd"):
            continue
        path = "".join(folder for _, folder in folders) + word
        found.setdefault(path, number)
    return found


def problems(page_text: str, tracked: list[str]) -> list[str]:
    """What the map is missing and what it names that is gone."""
    scripts = sorted(
        path[len(ADDON) :]
        for path in tracked
        if path.startswith(ADDON)
        and path.endswith(".gd")
        and not path[len(ADDON) :].startswith(LEFT_OUT)
    )
    mapped = mapped_scripts(page_text)
    out = [
        f"DEVELOPMENT.md has no line for {ADDON}{path} in its Codebase Structure"
        for path in scripts
        if path not in mapped
    ]
    present = set(scripts)
    out += [
        f"DEVELOPMENT.md:{line}: {ADDON}{path} is not a script git tracks"
        for path, line in sorted(mapped.items(), key=lambda item: item[1])
        if path not in present
    ]
    return out


def tracked_scripts() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--", f"{ADDON}*.gd"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


SAMPLE = """# Page

## Codebase Structure

```
addons/hammerforge/
  plugin.gd              Entry point
  ui/hf_panel.gd         A panel named by its path
  gone.gd                A script that was deleted

  ui/                    UI
    hf_toast.gd            Toasts

  systems/               Subsystems
    hf_state.gd            State
```

## Next
  stray.gd   not in the map
"""


def selftest() -> int:
    tracked = [
        f"{ADDON}plugin.gd",
        f"{ADDON}ui/hf_panel.gd",
        f"{ADDON}ui/hf_toast.gd",
        f"{ADDON}systems/hf_state.gd",
        f"{ADDON}systems/hf_new.gd",
        f"{ADDON}mcp/hf_bridge.gd",
        "tests/test_x.gd",
    ]
    found = problems(SAMPLE, tracked)
    wanted = [
        f"DEVELOPMENT.md has no line for {ADDON}systems/hf_new.gd in its Codebase Structure",
        f"DEVELOPMENT.md:9: {ADDON}gone.gd is not a script git tracks",
    ]
    if found != wanted:
        print(f"selftest: expected {wanted}, got {found}")
        return 1
    print("selftest: the map check still catches a missing line and a gone script")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    tracked = tracked_scripts()
    found = problems(PAGE.read_text(encoding="utf-8"), tracked)
    for problem in found:
        print(f"map: {problem}")
    if not found:
        print("map: DEVELOPMENT.md names every addon script outside mcp/")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
