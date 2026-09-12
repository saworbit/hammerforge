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


def is_noise(line: str) -> bool:
    return any(marker in line for marker in NOISE_MARKERS)


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
            timeout=timeout,
            cwd=REPO_ROOT,
            check=False,
        )
        output = completed.stdout + completed.stderr
        status = "flagged" if completed.returncode == 1 else "clean"
        if completed.returncode not in (0, 1):
            status = "error"
    except subprocess.TimeoutExpired as expired:
        output = (expired.stdout or "") + (expired.stderr or "")
        if isinstance(output, bytes):
            output = output.decode("utf-8", "replace")
        output += f"\n*** timed out after {timeout}s ***\n"
        status = "timeout"

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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "scenarios", nargs="*", help="scenario ids; default is all of them"
    )
    parser.add_argument(
        "--list", action="store_true", help="list the scenario ids and stop"
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

    trouble = [r for r in results if r["status"] in ("flagged", "error", "timeout")]
    if trouble:
        print()
        print("Look at: " + ", ".join(r["scenario"] for r in trouble))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
