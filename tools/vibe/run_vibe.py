#!/usr/bin/env python3
"""Run the exploratory ("vibe") scenarios and summarise what they saw.

    python tools/vibe/run_vibe.py                 # every scenario
    python tools/vibe/run_vibe.py geometry cost   # named ones
    python tools/vibe/run_vibe.py --list

This wrapper exists for one reason: GDScript has no exception handling, so a
scenario that hits a runtime error never reaches `quit()` and the engine sits
there forever. A bare `godot -s ...` therefore hangs the whole sweep on the
first mistake. Running each scenario as its own process under a timeout means
one broken scenario costs one timeout instead of the run.

Exit code is 1 when anything was flagged, 0 otherwise. A scenario that only
reproduces already-reported defects exits 0, so the code means "something new".
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = "res://tools/vibe/hf_vibe_runner.gd"

# Kept in step with SCENARIOS in hf_vibe_runner.gd. Ordered cheapest first, so a
# full sweep surfaces the quick findings before the slow ones.
SCENARIOS = [
    "geometry",
    "round-trip",
    "map-io",
    "displacement",
    "limits",
    "chaos",
    "cost",
    "transform",
    "structures",
    "cutting",
    "entities",
    "appearance",
    "persistence",
    "housekeeping",
    "terrain",
    "vertex",
    "prefabs",
    "validation",
    "settings",
    "groups",
    "materials",
    "bake",
    "previews",
    "cordon",
    "spawn",
    "lifecycle",
    "placement",
    "definitions",
    "operations",
    "draw-tools",
    "viewport-tools",
    "runtime-io",
    "prefs",
    "snapping",
    "undo-collation",
    "painted-faces",
    "status-board",
    "atlas",
    "scatter",
    "selection-filter",
    "timeline",
    "shortcut-surfaces",
    "connectors",
    "examples",
    "heightmap-io",
    "regions",
    "quick-property",
    "dock-undo",
    "dock-settings",
    "uv-defaults",
    "surface-paint",
    "dock-cordon",
    "playtest-spawn",
    "entity-props",
    "bake-materials",
    "dock-ranges",
    "brush-sides",
    "map-uv-tail",
    "material-library",
    "tool-registry",
    "uv-canvas",
    "viewport-drop",
    "change-tracker",
    "heightmap-convert",
    "numeric-entry",
    "generator-ranges",
    "outline-bounds",
    "console-log",
    "console-controls",
    "paint-grid",
    "paint-inference",
    "material-browser",
    "array-layout",
    "console-actions",
    "io-presets-panel",
    "paint-multilayer",
    "chaos-systems",
    "prefab-links",
    "validate-fix",
    "dock-undo-two",
    "io-visualizer",
    "drag-create",
    "level-scale",
    "playtest-scene",
    "bake-options",
    "visibility-workflow",
    "chaos-io",
    "material-persistence",
    "generator-geometry",
    "autosave-history",
    "level-io-types",
    "prefab-materials",
    "bake-equivalence",
    "scene-weight",
    "examples-integrity",
    "world-scale",
    "far-origin",
    "uv-justify",
    "texture-continuity",
    "two-levels",
    "build-a-room",
    "bake-chunking",
    "scale-leftovers",
    "undo-depth",
    "material-palette",
    "map-real-world",
    "scene-reopen",
    "command-surfaces",
    "op-results",
    "prefab-library",
    "brush-entities",
    "missing-files",
    "docs-truth",
    "navmesh",
    "runtime-entities",
    "ship-runtime",
    "big-level",
    "unicode-names",
    "props-and-models",
    "bake-optimisation",
    "collision-layers",
    "level-instancing",
    "lighting",
    "subtractive-bake",
    "map-quality",
    "save-as",
    "surface-response",
    "team-workflow",
    "session-leaks",
    "build-outdoors",
    "bulk-edits",
    "map-units",
    "detail-brushes",
    "gltf-export",
    "streamed-world-bake",
    "walkability",
]

# Generous: chaos runs 300 operations and cost saves eight levels. A scenario
# that exceeds this has hung rather than run long.
DEFAULT_TIMEOUT_SECONDS = 600

# The engine narrates its own startup and any third-party GDExtension narrates
# its own everything. None of it is the scenario talking.
NOISE_MARKERS = (
    "[GDEXTENSION]",
    "[GDEXT_IPC]",
    "[IPC_SERVER]",
    "[EDITOR_HOOK]",
    "Godot Engine v",
)


def find_godot() -> str | None:
    """The Godot binary, from $GODOT, the PATH, or the usual Windows spot."""
    explicit = os.environ.get("GODOT")
    if explicit:
        return explicit
    for candidate in ("godot", "godot.cmd", "godot4"):
        found = shutil.which(candidate)
        if found:
            return found
    windows_default = Path("C:/Godot/godot.cmd")
    if windows_default.exists():
        return str(windows_default)
    return None


# A GDScript error is not a finding, and a scenario that hit one did not finish
# what it set out to do. It still reaches `quit(0)`, so the process says clean
# and the summary agrees, which is worse than a failure because it is
# indistinguishable from a real pass (#739).
#
# `SCRIPT ERROR` and not the engine's broader `ERROR:`. Measured over the 142
# logs in `.vibe/`: thirteen carry an `ERROR:` line, because scenarios provoke
# engine errors on purpose -- a missing file, a refused load, a malformed
# payload are things they exist to try. Two carry a `SCRIPT ERROR`, and both
# were real defects. One of them, `status-board`, had already written the
# detector for the defect it was hitting: GDScript has no exception handling, so
# the throw unwound the scenario past its own `flag()` call.
SCRIPT_ERROR_MARKER = "SCRIPT ERROR"


def is_noise(line: str) -> bool:
    return any(marker in line for marker in NOISE_MARKERS)


def grade(output: str, returncode: int | None) -> str:
    """What a scenario's run amounts to.

    Separate from `run_scenario` so `--selftest` can drive it without Godot.
    """
    if returncode is None:
        return "timeout"
    if returncode == 1:
        status = "flagged"
    elif returncode == 0:
        status = "clean"
    else:
        return "error"
    for line in output.splitlines():
        if is_noise(line):
            continue
        if SCRIPT_ERROR_MARKER in line:
            return "script error" if status == "clean" else status + " + script error"
    return status


def run_scenario(godot: str, scenario: str, timeout: int, log_dir: Path) -> dict:
    """Run one scenario in its own process. Never raises."""
    command = [
        godot,
        "--headless",
        "-s",
        RUNNER,
        "--path",
        str(REPO_ROOT),
        "--",
        scenario,
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            # Godot writes UTF-8. Without this the default console codepage is
            # used on Windows and one non-ASCII character anywhere in a scenario's
            # output takes the whole run down with a UnicodeDecodeError, which
            # reads as the scenario having crashed.
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            cwd=REPO_ROOT,
            check=False,
        )
        output = completed.stdout + completed.stderr
        status = grade(output, completed.returncode)
    except subprocess.TimeoutExpired as expired:
        output = (expired.stdout or "") + (expired.stderr or "")
        if isinstance(output, bytes):
            output = output.decode("utf-8", "replace")
        output += f"\n*** timed out after {timeout}s ***\n"
        status = grade(output, None)

    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{scenario}.log"
    log_path.write_text(output, encoding="utf-8")

    interesting = [
        line
        for line in output.splitlines()
        if not is_noise(line)
        and ("FLAG" in line or "KNOWN" in line or "SCRIPT ERROR" in line)
    ]
    return {
        "scenario": scenario,
        "status": status,
        "log": log_path,
        "lines": interesting,
    }


def selftest() -> int:
    """Prove the grading still grades, the way the other tools/ guards do.

    A detector that has quietly stopped detecting is worse than no detector,
    because it is reported as a pass. These are the cases that matter: a script
    error must not read as clean, and an ordinary run must not read as an error.
    """
    engine_noise = "Godot Engine v4.7.stable.official - https://godotengine.org"
    script_error = "SCRIPT ERROR: Invalid call. Nonexistent function 'x' in base 'y'."
    cases = [
        ("a quiet run is clean", "    all fine\n", 0, "clean"),
        ("a flag is a flag", "  FLAG  something\n", 1, "flagged"),
        ("a script error is never clean", script_error, 0, "script error"),
        (
            "a scenario can both flag and break",
            "  FLAG  something\n" + script_error,
            1,
            "flagged + script error",
        ),
        ("a crash stays a crash", script_error, 139, "error"),
        ("a hang stays a hang", "", None, "timeout"),
        # The engine narrates its own startup, and a GDExtension narrates its
        # own everything. Grading on a marker inside somebody else's line would
        # turn every run red for a reason that is not the scenario's.
        (
            "somebody else's line is not the scenario's",
            "[GDEXTENSION] " + script_error + "\n",
            0,
            "clean",
        ),
        (
            "noise around a real one still counts",
            engine_noise + "\n" + script_error,
            0,
            "script error",
        ),
    ]
    failures = 0
    for name, output, code, expected in cases:
        actual = grade(output, code)
        if actual != expected:
            failures += 1
            print(f"FAIL {name}: expected {expected!r}, got {actual!r}")
    if failures:
        print(f"{failures} of {len(cases)} grading cases wrong")
        return 1
    print(f"run_vibe grading selftest: {len(cases)} cases OK")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "scenarios", nargs="*", help="scenario ids; default is all of them"
    )
    parser.add_argument(
        "--list", action="store_true", help="list the scenario ids and stop"
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the grading still grades, without running Godot",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"seconds per scenario (default {DEFAULT_TIMEOUT_SECONDS})",
    )
    parser.add_argument(
        "--log-dir",
        default=str(REPO_ROOT / ".vibe"),
        help="where to write per-scenario logs (default .vibe/)",
    )
    args = parser.parse_args()

    # Godot's output is UTF-8. The Windows console is cp1252, and printing a
    # scenario's line with a non-ASCII character in it takes the whole run down
    # with a UnicodeEncodeError after that scenario has already finished -- the
    # findings are in the log file and the sweep stops anyway. `run_scenario`
    # already decodes with errors="replace"; this is the other end of the same
    # pipe.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    if args.selftest:
        return selftest()

    if args.list:
        for scenario in SCENARIOS:
            print(scenario)
        return 0

    unknown = [s for s in args.scenarios if s not in SCENARIOS]
    if unknown:
        print(f"unknown scenario(s): {', '.join(unknown)}")
        print(f"available: {', '.join(SCENARIOS)}")
        return 2

    godot = find_godot()
    if not godot:
        print("Godot not found. Put it on the PATH or set $GODOT.")
        return 2

    selected = args.scenarios or SCENARIOS
    log_dir = Path(args.log_dir)
    results = []
    for scenario in selected:
        print(f"--- {scenario}")
        result = run_scenario(godot, scenario, args.timeout, log_dir)
        for line in result["lines"]:
            print(f"    {line.strip()}")
        print(f"    [{result['status']}] {result['log']}")
        results.append(result)

    print()
    print("=== summary")
    for result in results:
        print(f"  {result['scenario']:<14} {result['status']}")

    trouble = [r for r in results if r["status"] != "clean"]
    if trouble:
        print()
        print("Look at: " + ", ".join(r["scenario"] for r in trouble))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
