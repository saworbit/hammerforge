#!/usr/bin/env python3
"""Refuse a private declaration nothing uses, and a field nothing reads.

#609 and #610 together were 66 dead declarations. Thirteen of them existed only
because five architecture tests required them by name, so the codebase had a
mechanism actively regrowing dead code. Those tests are fixed. Nothing stopped
the next list accumulating the same way.

The scan that produced those lists compared each name's total occurrence count
against its declaration count over the plugin, the suite, tools/, docs/, the
README and the CHANGELOG. That treats any mention as a caller. A doc comment
counts. A line in the CHANGELOG counts. `plugin.gd:_point_near_polygon_3d` was
dead, had no caller, and the scan missed it, because the name appears in prose
elsewhere in the repo. A gate that passes when a name is written about is a gate
that rewards writing about dead code.

So this reads GDScript and nothing else:

  * `.md` is not scanned at all.
  * Comments and string literals are removed before anything is counted, by a
    single left to right scan rather than one regex per construct. Stripping
    strings first lets an apostrophe in a comment open a literal that swallows
    the code below it; stripping comments first lets a `#` inside a literal
    open a comment that swallows the rest of the line. Both produce confident
    wrong answers, so neither is done.
  * String dispatch is load bearing here. `call_deferred("_load_hflevel...")`,
    `Callable(self, "_name")` and `&"_name"` reach a declaration by name from
    inside a literal, so literals are harvested separately and a declaration
    whose whole name is one of them is live. Whole name, not substring: prose
    inside a string does not keep anything alive.
  * A field that is written and never read has occurrences, so counting
    occurrences cannot see it. Reads are counted apart from writes.

Only underscore-prefixed declarations are in scope. A public method on an addon
is callable from a game script this repo cannot see; a private one is not.

    python tools/check_dead_declarations.py

Exits 1 and names file, line and declaration for every one that nothing uses.

A deliberate case can say so on the declaration line, or the line above it:

    # hf-allow-unused-declaration: <why>

ENGINE_VIRTUALS is every underscore-prefixed method Godot declares, so an
override the engine calls is not reported. Regenerate it after a Godot upgrade:

    godot --headless --path . -s tools/dump_engine_virtuals.gd

--selftest checks the detector still catches known-bad snippets and still passes
known-good ones, because a guard that cannot fail is not a guard.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

SCAN_ROOTS = ["addons/hammerforge", "tests", "tools", "hammerforge_tools"]

# GUT is vendored. It is not ours to prune.
SKIP_DIRS = ("addons/gut",)

ALLOW_MARKER = "hf-allow-unused-declaration"

HERE = os.path.dirname(os.path.abspath(__file__))
VIRTUALS_PATH = os.path.join(HERE, "engine_virtuals.txt")


def load_engine_virtuals() -> frozenset[str]:
    """Every virtual Godot declares, so an override the engine calls is not dead.

    A virtual override has no caller anywhere in this repo. The engine is the
    caller. Without this the guard would report `_ready` and forty others on the
    first run, and a guard whose first run is forty false positives gets turned
    off.
    """
    names = set()
    with open(VIRTUALS_PATH, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                names.add(line)
    return frozenset(names)


ENGINE_VIRTUALS = load_engine_virtuals()


def split_code_and_strings(src: str) -> tuple[str, list[str]]:
    """Return the source with comments and literals blanked, and the literals.

    Blanked rather than deleted so line numbers survive: the reported line has
    to be the line in the file.
    """
    out: list[str] = []
    literals: list[str] = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "#":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if ch in "\"'":
            quote = ch
            triple = src.startswith(quote * 3, i)
            close = quote * 3 if triple else quote
            start = i
            i += len(close)
            body: list[str] = []
            while i < n:
                if src[i] == "\\" and i + 1 < n:
                    body.append(src[i : i + 2])
                    i += 2
                    continue
                if src.startswith(close, i):
                    i += len(close)
                    break
                if not triple and src[i] == "\n":
                    # An unterminated single-line literal. Godot would not
                    # compile it; stop at the newline rather than swallowing
                    # the rest of the file.
                    break
                body.append(src[i])
                i += 1
            literals.append("".join(body))
            for c in src[start:i]:
                out.append("\n" if c == "\n" else " ")
            continue
        out.append(ch)
        i += 1
    return "".join(out), literals


DECL_PATTERNS = (
    ("func", re.compile(r"^[ \t]*(?:static[ \t]+)?func[ \t]+(_\w+)[ \t]*\(")),
    ("var", re.compile(r"^[ \t]*(?:static[ \t]+)?var[ \t]+(_\w+)\b")),
    ("const", re.compile(r"^[ \t]*const[ \t]+(_\w+)\b")),
    ("signal", re.compile(r"^[ \t]*signal[ \t]+(_\w+)\b")),
)

# `node._x` is how a method is called and how a field is reached, so the dot is
# a use, not a namespace. Only a name glued to another word is not one.
NAME = re.compile(r"(?<!\w)(_\w+)\b")
# `name =` but not `name ==`, `name !=`, `name <=`, `name >=`.
WRITE_TAIL = re.compile(r"[ \t]*(?:\+|-|\*|/|%|\*\*|\||&|\^|<<|>>)?=(?!=)")


# A scene file reaches a method by name too:
#   [connection signal="pressed" from="X" to="." method="_on_thing"]
SCENE_METHOD = re.compile(r'method\s*=\s*"([^"]+)"')


def _scan(extension: str) -> list[str]:
    found: list[str] = []
    for root in SCAN_ROOTS:
        found += glob.glob(os.path.join(root, "**", "*" + extension), recursive=True)
    out = []
    for path in sorted(set(found)):
        flat = path.replace("\\", "/")
        if any(skip in flat for skip in SKIP_DIRS):
            continue
        out.append(path)
    return out


def gd_files() -> list[str]:
    return _scan(".gd")


def scene_methods() -> set[str]:
    """Method names a `.tscn` connects a signal to.

    HammerForge builds its UI in code and has none of these today. It is here
    anyway because the cost of missing one is deleting a callback that works,
    and the whole point of a gate is that nobody re-reads its answer.
    """
    names: set[str] = set()
    for path in _scan(".tscn"):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for match in SCENE_METHOD.finditer(handle.read()):
                names.add(match.group(1))
    return names


def collect(paths: list[str]) -> tuple[dict, dict, set]:
    """Declarations, per-file stripped code, and every whole string literal."""
    decls: dict[str, list[tuple[str, int, str]]] = {}
    code: dict[str, str] = {}
    literals: set[str] = set()
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            src = handle.read()
        stripped, lits = split_code_and_strings(src)
        code[path] = stripped
        for lit in lits:
            literals.add(lit.strip())
        raw_lines = src.splitlines()
        for lineno, line in enumerate(stripped.splitlines(), start=1):
            for kind, pattern in DECL_PATTERNS:
                match = pattern.match(line)
                if not match:
                    continue
                if _allowed(raw_lines, lineno):
                    break
                decls.setdefault(match.group(1), []).append((path, lineno, kind))
                break
    return decls, code, literals


def _allowed(raw_lines: list[str], lineno: int) -> bool:
    for index in (lineno - 1, lineno - 2):
        if 0 <= index < len(raw_lines) and ALLOW_MARKER in raw_lines[index]:
            return True
    return False


def analyse(decls: dict, code: dict, literals: set) -> tuple[list, list]:
    declared_at: dict[str, set[tuple[str, int]]] = {
        name: {(path, lineno) for path, lineno, _ in sites}
        for name, sites in decls.items()
    }
    reads: dict[str, int] = {name: 0 for name in decls}
    writes: dict[str, int] = {name: 0 for name in decls}
    for path, stripped in code.items():
        for lineno, line in enumerate(stripped.splitlines(), start=1):
            for match in NAME.finditer(line):
                name = match.group(1)
                if name not in reads:
                    continue
                if (path, lineno) in declared_at[name]:
                    # The declaration is not a use of itself. Its initialiser
                    # is a write, though: `var _x = 1` writes and nothing else.
                    if WRITE_TAIL.match(line, match.end()):
                        writes[name] += 1
                    continue
                if WRITE_TAIL.match(line, match.end()):
                    writes[name] += 1
                else:
                    reads[name] += 1

    unused: list[tuple[str, int, str, str]] = []
    write_only: list[tuple[str, int, str, str]] = []
    for name, sites in sorted(decls.items()):
        if name in ENGINE_VIRTUALS or name in literals:
            continue
        path, lineno, kind = sites[0]
        if reads[name] == 0 and writes[name] == 0:
            unused.append((path, lineno, kind, name))
        elif kind == "var" and reads[name] == 0:
            write_only.append((path, lineno, kind, name))
    return unused, write_only


def report(unused: list, write_only: list) -> int:
    if not unused and not write_only:
        print("check_dead_declarations: no unused private declarations.")
        return 0
    for path, lineno, kind, name in unused:
        print("%s:%d: %s %s is never used" % (path, lineno, kind, name))
    for path, lineno, kind, name in write_only:
        print("%s:%d: %s %s is written and never read" % (path, lineno, kind, name))
    print("")
    print("%d unused, %d write-only." % (len(unused), len(write_only)))
    print("Delete it, or mark the line: # %s: <why>" % ALLOW_MARKER)
    return 1


GOOD = """
extends Node

# _point_near_polygon_3d is described here and nowhere else.
var _kept := 1
var _written_only := 0


func _ready() -> void:
	_used()
	call_deferred("_dispatched")
	_written_only = _kept


func _used() -> void:
	pass


func _dispatched() -> void:
	pass
"""

BAD = """
extends Node


func _ready() -> void:
	pass


func _point_near_polygon_3d() -> bool:
	return true
"""


def _scan_source(src: str) -> tuple[list, list]:
    stripped, lits = split_code_and_strings(src)
    decls: dict[str, list[tuple[str, int, str]]] = {}
    raw_lines = src.splitlines()
    for lineno, line in enumerate(stripped.splitlines(), start=1):
        for kind, pattern in DECL_PATTERNS:
            match = pattern.match(line)
            if match and not _allowed(raw_lines, lineno):
                decls.setdefault(match.group(1), []).append(
                    ("<selftest>", lineno, kind)
                )
                break
    return analyse(decls, {"<selftest>": stripped}, {lit.strip() for lit in lits})


def selftest() -> int:
    code, lits = split_code_and_strings("# don't stop here\nvar _x = 1\n")
    if "_x" not in code:
        print("selftest: an apostrophe in a comment swallowed the code below it")
        return 1
    code, lits = split_code_and_strings('var _s = "# not a comment"\nvar _y = 2\n')
    if "_y" not in code or "# not a comment" not in lits:
        print("selftest: a hash inside a literal was read as a comment")
        return 1
    code, _ = split_code_and_strings('var _t = """\nfunc _hidden():\n"""\nvar _z = 3\n')
    if "_hidden" in code or "_z" not in code:
        print("selftest: a triple-quoted block was not treated as one literal")
        return 1
    code, _ = split_code_and_strings('var _e = "a \\" b"\nvar _w = 4\n')
    if "_w" not in code:
        print("selftest: an escaped quote ended a literal early")
        return 1

    connected = SCENE_METHOD.findall(
        '[connection signal="pressed" from="Btn" to="." method="_on_btn_pressed"]'
    )
    if connected != ["_on_btn_pressed"]:
        print("selftest: a scene file signal connection was not read as a use")
        return 1

    unused, write_only = _scan_source(BAD)
    if not any(name == "_point_near_polygon_3d" for _, _, _, name in unused):
        print("selftest: the detector no longer catches a function with no caller")
        return 1

    unused, write_only = _scan_source(GOOD)
    if unused:
        print(
            "selftest: the detector flags live declarations: %s"
            % [n for *_, n in unused]
        )
        return 1
    if not any(name == "_written_only" for _, _, _, name in write_only):
        print("selftest: a field that is written and never read was not flagged")
        return 1

    print("selftest: detector catches the bad snippets and passes the good ones.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the detector still detects, then exit",
    )
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    decls, code, literals = collect(gd_files())
    unused, write_only = analyse(decls, code, literals | scene_methods())
    return report(unused, write_only)


if __name__ == "__main__":
    sys.exit(main())
