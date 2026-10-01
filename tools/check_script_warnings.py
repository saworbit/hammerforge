#!/usr/bin/env python3
"""Fail if a script under addons/hammerforge/ has a GDScript warning.

    python tools/check_script_warnings.py
    python tools/check_script_warnings.py --selftest
    python tools/check_script_warnings.py --godot C:/Godot/godot.cmd

Godot 4.7 turns off every GDScript warning for scripts under addons/ by
default (`debug/gdscript/warnings/directory_rules`). So a warning in this
plugin is invisible to whoever writes it and to anyone who installs it, until a
project opts addons back in. Then the warnings Godot treats as errors, such as
a type inferred from a Variant, stop scripts loading at all. There were 440
warnings, seven of them that kind, before #836.

This writes an override.cfg that opts addons in and raises every warning Godot
turns on by default to an error, loads every plugin script through
tools/check_script_warnings.gd, and removes the override again. Godot reads
warning levels once at startup, which is why this needs a file and a second
process rather than a setting changed from inside the check. It refuses to run
over an override.cfg it did not write.

A warning that is deliberate gets `@warning_ignore` and a reason beside it.

The project must have been imported first, as CI does, or every script that
names a global class fails for a reason that has nothing to do with warnings.

--selftest writes a script with an integer division and one without into a
scratch directory, and checks that the first fails and the second loads.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OVERRIDE = REPO / "override.cfg"
CHECKER = "res://tools/check_script_warnings.gd"

# Every warning Godot 4.7 turns on at level 1. The checker fails on any warning
# still at 1, so a newer Godot adding one says so rather than slipping past.
WARNINGS = (
    "unassigned_variable",
    "unassigned_variable_op_assign",
    "unused_variable",
    "unused_local_constant",
    "unused_private_class_variable",
    "unused_parameter",
    "unused_signal",
    "shadowed_variable",
    "shadowed_variable_base_class",
    "shadowed_global_identifier",
    "unreachable_code",
    "unreachable_pattern",
    "standalone_expression",
    "standalone_ternary",
    "incompatible_ternary",
    "unsafe_void_return",
    "static_called_on_instance",
    "missing_tool",
    "redundant_static_unload",
    "redundant_await",
    "assert_always_true",
    "assert_always_false",
    "integer_division",
    "narrowing_conversion",
    "int_as_enum_without_cast",
    "int_as_enum_without_match",
    "enum_variable_without_default",
    "empty_file",
    "deprecated_keyword",
    "confusable_identifier",
    "confusable_local_declaration",
    "confusable_local_usage",
    "confusable_capture_reassignment",
    "confusable_temporary_modification",
    "property_used_as_function",
    "constant_used_as_function",
    "function_used_as_property",
)


def override_text() -> str:
    lines = ["[debug]", "", 'gdscript/warnings/directory_rules={"res://addons": 1}']
    lines += ["gdscript/warnings/%s=2" % name for name in WARNINGS]
    return "\n".join(lines) + "\n"


def run_checker(godot: str, dirs: list[str]) -> subprocess.CompletedProcess:
    if OVERRIDE.exists():
        sys.exit("%s already exists and is not this script's to replace." % OVERRIDE)
    OVERRIDE.write_text(override_text(), encoding="utf-8", newline="\n")
    try:
        argv = [godot, "--headless", "--path", str(REPO), "-s", CHECKER]
        if dirs:
            argv += ["--", *dirs]
        return subprocess.run(
            argv, capture_output=True, text=True, encoding="utf-8", errors="replace"
        )
    finally:
        OVERRIDE.unlink()


def report(result: subprocess.CompletedProcess) -> None:
    """The checker's own lines, and each parse error with the line it names."""
    lines = (result.stdout + result.stderr).splitlines()
    for i, line in enumerate(lines):
        if line.startswith("warnings: "):
            print(line)
        elif line.startswith("SCRIPT ERROR"):
            print(line)
            if i + 1 < len(lines):
                print(lines[i + 1])


def selftest(godot: str) -> int:
    scratch = Path(tempfile.mkdtemp(prefix=".hf_warning_selftest_", dir=REPO))
    try:
        (scratch / "bad").mkdir()
        (scratch / "good").mkdir()
        body = "extends RefCounted\n\n\nfunc half(n: int) -> int:\n\treturn %s\n"
        (scratch / "bad" / "half.gd").write_text(
            body % "n / 2", encoding="utf-8", newline="\n"
        )
        (scratch / "good" / "half.gd").write_text(
            body % "n >> 1", encoding="utf-8", newline="\n"
        )
        res = "res://" + scratch.name
        bad = run_checker(godot, [res + "/bad"])
        good = run_checker(godot, [res + "/good"])
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    failures = []
    if bad.returncode == 0 or "half.gd" not in bad.stderr:
        failures.append(
            "an integer division loaded, so the override did not reach Godot"
        )
    if good.returncode != 0:
        failures.append("a clean script failed:\n" + good.stdout + good.stderr)
    for failure in failures:
        print("selftest: " + failure)
    if not failures:
        print("selftest: a script with a warning fails to load and a clean one loads")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--godot", default=os.environ.get("GODOT", "godot"), help="the Godot binary"
    )
    parser.add_argument(
        "--selftest", action="store_true", help="check the check detects a warning"
    )
    args = parser.parse_args()
    if args.selftest:
        return selftest(args.godot)
    result = run_checker(args.godot, [])
    report(result)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
