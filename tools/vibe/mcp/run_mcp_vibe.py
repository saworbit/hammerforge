"""Run the MCP vibe scenarios: a real editor, the real server, a stand-in user.

    python tools/vibe/mcp/run_mcp_vibe.py                  # the headless ones
    python tools/vibe/mcp/run_mcp_vibe.py bake review      # named ones
    python tools/vibe/mcp/run_mcp_vibe.py --windowed       # and those that open a window
    python tools/vibe/mcp/run_mcp_vibe.py --list

Exit code 1 when something was flagged or a scenario could not run, 0 otherwise.
A behaviour already filed as an issue is reported as known and does not fail the
run. See README.md beside this file.
"""

from __future__ import annotations

import argparse
import asyncio
import importlib
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mcp_vibe  # noqa: E402

#: In the order a full sweep runs them.
SCENARIOS = [
    "basics",
    "undo",
    "room",
    "bake",
    "review",
    "entities",
    "commands",
    "structures",
    "prefabs",
    "cordons",
    "paint",
    "guide",
    "prompts",
    "views",
]


def _load(name: str):
    return importlib.import_module(f"scenarios.{name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="scenarios to run; all by default")
    parser.add_argument("--godot", help="the Godot 4.7 executable")
    parser.add_argument(
        "--windowed",
        action="store_true",
        help="also run scenarios that open an editor window (screenshots)",
    )
    parser.add_argument("--list", action="store_true", help="list the scenarios")
    args = parser.parse_args(argv)

    if args.list:
        for name in SCENARIOS:
            module = _load(name)
            window = " (opens a window)" if getattr(module, "WINDOWED", False) else ""
            print(f"{name:10} {module.DESCRIPTION}{window}")
        return 0

    unknown = [name for name in args.names if name not in SCENARIOS]
    if unknown:
        parser.error(f"no scenario called {', '.join(unknown)}; try --list")
    chosen = args.names or SCENARIOS
    godot = mcp_vibe.find_godot(args.godot)
    flagged: dict[str, list[str]] = {}
    known: dict[str, list[str]] = {}
    broken: list[str] = []
    for name in chosen:
        module = _load(name)
        if getattr(module, "WINDOWED", False) and not (args.windowed or args.names):
            print(f"== {name}: skipped, it opens a window (--windowed to run it)")
            continue
        print(f"== {name}: {module.DESCRIPTION}")
        # The editor this starts shares the developer's user:// folder, so a
        # scenario that wrote their preferences is flagged, as GUT and the
        # GDScript vibe runner flag theirs (#1626).
        prefs_before = mcp_vibe.prefs_fingerprint()
        try:
            vibe = asyncio.run(mcp_vibe.run_scenario(module, godot))
        except mcp_vibe.VibeSetupError as exc:
            print(f"  could not run: {exc}")
            broken.append(name)
            continue
        except Exception:
            traceback.print_exc()
            broken.append(name)
            continue
        prefs_change = mcp_vibe.prefs_change_since(prefs_before)
        if prefs_change:
            vibe.flagged.append(
                "the scenario changed the preferences file every checkout shares: "
                + prefs_change
            )
        if vibe.flagged:
            flagged[name] = vibe.flagged
        if vibe.known_seen:
            known[name] = vibe.known_seen

    print()
    for name, items in known.items():
        for item in items:
            print(f"known   {name}: {item}")
    for name, items in flagged.items():
        for item in items:
            print(f"FLAG    {name}: {item}")
    for name in broken:
        print(f"BROKEN  {name}")
    if not flagged and not broken:
        print("nothing new flagged")
    return 1 if flagged or broken else 0


if __name__ == "__main__":
    sys.exit(main())
