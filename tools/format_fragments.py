#!/usr/bin/env python3
"""Fold the waiting format fragments into the level format record (#1638).

    python tools/format_fragments.py --check     every fragment is readable
    python tools/format_fragments.py --compile   fold them in, for a release

A pull request that changes what a level saves adds a fragment to
`addons/hammerforge/data/format.d/`, one file each, so two never touch the same
lines. While any fragment waits, a build writes the released number plus one
(`HFLevelIO.FORMAT_VERSION`, held to it by `tests/test_format_record.gd`), and
names the fragments in each file it writes, so an older build refuses the file
rather than dropping what it does not know.

At a release, `--compile` makes that number the released one: it adds every
fragment's keys and maps to `data/format.json`, raises `released` by one, and
deletes the fragments. The build's number does not change, so nothing else has
to; the next fragment after the release raises `FORMAT_VERSION` again.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "addons" / "hammerforge" / "data"
RECORD = DATA / "format.json"
FRAGMENTS = DATA / "format.d"
FIELDS = ("what", "older_builds", "keys")


def fragments() -> list[tuple[Path, dict]]:
    """Each waiting fragment and what it holds, in name order."""
    if not FRAGMENTS.is_dir():
        return []
    out = []
    for path in sorted(FRAGMENTS.glob("*.json")):
        out.append((path, json.loads(path.read_text(encoding="utf-8"))))
    return out


def problems() -> list[str]:
    """What is wrong with the fragments, one line each."""
    found = []
    record = json.loads(RECORD.read_text(encoding="utf-8"))
    released = set(record.get("keys", []))
    for path, body in fragments():
        for field in FIELDS:
            if not body.get(field):
                found.append(f"{path.name}: no {field}")
        for key in body.get("keys", []):
            if key in released:
                found.append(f"{path.name}: {key} is released already")
    return found


def compile_fragments() -> int:
    """Fold the fragments into the record and delete them. The new number."""
    record = json.loads(RECORD.read_text(encoding="utf-8"))
    waiting = fragments()
    if not waiting:
        return int(record["released"])
    keys = set(record.get("keys", []))
    maps = list(record.get("maps", []))
    for _path, body in waiting:
        keys.update(body.get("keys", []))
        for path in body.get("maps", []):
            if path not in maps:
                maps.append(path)
    record["released"] = int(record["released"]) + 1
    record["keys"] = sorted(keys)
    record["maps"] = sorted(maps)
    RECORD.write_text(
        json.dumps(record, indent="\t") + "\n", encoding="utf-8", newline="\n"
    )
    for path, _body in waiting:
        path.unlink()
    return int(record["released"])


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--check", action="store_true", help="check the fragments")
    parser.add_argument("--compile", action="store_true", help="fold them in")
    args = parser.parse_args()
    if args.compile:
        found = problems()
        if found:
            print("\n".join(found))
            return 1
        print(f"format.json now records format {compile_fragments()}")
        return 0
    found = problems()
    for line in found:
        print(line)
    print(
        f"format.d/: {len(fragments())} fragments, {'all good' if not found else 'see above'}."
    )
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
