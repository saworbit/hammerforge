#!/usr/bin/env python3
"""Refuse a world transform written to a node that is not in the tree yet.

A Node3D outside the scene tree has no parent to measure against, so assigning
global_position or global_transform writes the local transform instead. Nothing
errors. The node simply lands wherever its container puts it, shifted by that
container's own transform, and the whole thing is invisible while LevelRoot sits
at the world origin -- which is how it usually gets exercised.

That mistake has been fixed six times now, in the draw path, the entity restore,
the map import and the baker, each time after someone hit it. The baker was the
worst: it was applying the root transform twice to geometry that ships. It was
found by a scan much like this one rather than by a bug report, which is the
argument for keeping the scan.

    python tools/check_placement_order.py

Exits 1 and names file, line and variable for every place a global_* assignment
runs before the node is parented in the same function.

A deliberate case can say so on the assignment line, or the line above it:

    # hf-allow-global-before-parent: <why>

--selftest checks the detector still catches a known-bad snippet and still
passes a known-good one, because a guard that cannot fail is not a guard.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

# tests/ is in scope as well as the addon. A fixture that places a node before
# parenting it builds the scene it is not describing, so the test passes without
# holding the property it names.
SCAN_ROOTS = ["addons/hammerforge", "tests"]

ALLOW_MARKER = "hf-allow-global-before-parent"

# Assigning any of these on an orphan writes the local transform instead.
WORLD_WRITE = re.compile(
    r"\b(?P<var>[A-Za-z_]\w*)\.global_"
    r"(?:position|transform|basis|rotation|rotation_degrees)\s*=(?!=)"
)

# The calls that put a node into the tree. add_entity, _add_brush_to_draft and
# _add_pending_cut are HammerForge's own wrappers around add_child.
PARENTED = (
    r"(?:add_child|add_sibling|add_entity|_add_brush_to_draft|_add_pending_cut)"
    r"\(\s*(?P<var>[A-Za-z_]\w*)\s*[,)]"
)
PARENT_CALL = re.compile(PARENTED)

FUNC_SPLIT = re.compile(r"\n(?=(?:static )?func )")
FUNC_NAME = re.compile(r"(?:static )?func ([A-Za-z_]\w*)")
DECLARED = re.compile(r"\bvar\s+(?P<var>[A-Za-z_]\w*)\b")


def strip_comment(line: str) -> str:
    """Drop a trailing comment, leaving anything inside a string alone."""
    quote = ""
    for i, ch in enumerate(line):
        if quote:
            if ch == "\\":
                continue
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def logical_lines(source: str) -> list:
    """Fold wrapped calls onto one line, keeping the line number they start on.

    gdformat wraps a long call across several lines, so `add_child(` and the
    node it is given are routinely not on the same physical line.
    """
    out = []
    buf = ""
    start = 0
    depth = 0
    for number, raw in enumerate(source.split("\n"), start=1):
        text = strip_comment(raw)
        if not buf:
            start = number
        buf = buf + " " + text.strip() if buf else text.strip()
        depth += text.count("(") + text.count("[") - text.count(")") - text.count("]")
        if depth <= 0:
            out.append((start, buf))
            buf = ""
            depth = 0
    if buf:
        out.append((start, buf))
    return out


def allowed_lines(source: str) -> set:
    """Line numbers covered by an allow marker, on the line or the one above."""
    covered = set()
    for number, raw in enumerate(source.split("\n"), start=1):
        if ALLOW_MARKER in raw:
            covered.add(number)
            covered.add(number + 1)
    return covered


def violations_in_source(source: str, path: str = "<memory>") -> list:
    """Every global_* write that runs before its node is parented."""
    found = []
    allow = allowed_lines(source)
    offset = 0
    for chunk in FUNC_SPLIT.split(source):
        name = FUNC_NAME.match(chunk)
        # Line number this chunk starts on, so reports point at the real file.
        base = offset
        offset += chunk.count("\n") + 1
        if not name:
            continue
        lines = logical_lines(chunk)
        declared = set()
        writes = {}
        parents = {}
        for index, (line_no, text) in enumerate(lines):
            for m in DECLARED.finditer(text):
                declared.add(m.group("var"))
            for m in WORLD_WRITE.finditer(text):
                writes.setdefault(m.group("var"), (index, line_no))
            for m in PARENT_CALL.finditer(text):
                parents.setdefault(m.group("var"), index)
        for var, (write_index, write_line) in writes.items():
            if var not in declared or var not in parents:
                continue
            if write_index >= parents[var]:
                continue
            absolute = base + write_line
            if absolute in allow:
                continue
            found.append((path, absolute, name.group(1), var))
    return found


def gd_files(roots: list) -> list:
    files = []
    for root in roots:
        files.extend(glob.glob(os.path.join(root, "**", "*.gd"), recursive=True))
    return sorted(f.replace("\\", "/") for f in files)


BAD_SNIPPET = """
func append_brush_list_to_csg(brushes: Array, target: CSGCombiner3D) -> void:
\tfor child in brushes:
\t\tvar csg_shape = PrefabFactory.create_prefab(child.shape)
\t\tcsg_shape.global_transform = child.global_transform
\t\ttarget.add_child(csg_shape)
"""

GOOD_SNIPPET = """
func place_brush(size: Vector3) -> void:
\tvar brush = _create_brush(size)
\t_add_brush_to_draft(brush)
\tbrush.global_position = Vector3.ZERO

func restore_entity_from_info(info: Dictionary) -> Node3D:
\tvar entity = DraftEntity.new()
\troot.entities_node.add_child(entity)
\tentity.global_transform = info["transform"]
\treturn entity

func wrapped_call(info: Dictionary) -> void:
\tvar entity = DraftEntity.new()
\troot.entities_node.add_child(
\t\tentity
\t)
\tentity.global_transform = info["transform"]

func deliberate(info: Dictionary) -> void:
\tvar node = Node3D.new()
\t# hf-allow-global-before-parent: measured against the parent on purpose
\tnode.global_transform = info["transform"]
\tadd_child(node)

func moves_a_node_already_in_the_tree(node: Node3D, offset: Vector3) -> void:
\tnode.global_position += offset
"""


def selftest() -> int:
    bad = violations_in_source(BAD_SNIPPET, "bad.gd")
    good = violations_in_source(GOOD_SNIPPET, "good.gd")
    ok = True
    if len(bad) != 1 or bad[0][3] != "csg_shape":
        print("selftest: the detector no longer catches the known-bad snippet")
        print("  got: %r" % (bad,))
        ok = False
    if good:
        print("selftest: the detector flags the known-good snippet")
        for path, line, func, var in good:
            print("  %s:%d %s() %s" % (path, line, func, var))
        ok = False
    if ok:
        print("selftest: detector catches the bad snippet and passes the good one.")
        return 0
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the detector still works, then exit",
    )
    parser.add_argument("paths", nargs="*", default=None, help="files or roots to scan")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    roots = args.paths if args.paths else SCAN_ROOTS
    files = []
    for entry in roots:
        if os.path.isdir(entry):
            files.extend(gd_files([entry]))
        elif entry.endswith(".gd"):
            files.append(entry.replace("\\", "/"))

    found = []
    for path in files:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            found.extend(violations_in_source(handle.read(), path))

    if not found:
        print("Placement order is clean across %d files." % len(files))
        return 0

    print("A world transform is written before the node is in the tree.")
    print("Assigning global_* to a node outside the tree writes its local")
    print("transform, so it lands shifted by its container once parented.")
    print("Parent it first, or say why with a %s comment.\n" % ALLOW_MARKER)
    for path, line, func, var in found:
        print("  %s:%d  %s()  %s" % (path, line, func, var))
    return 1


if __name__ == "__main__":
    sys.exit(main())
