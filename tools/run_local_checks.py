#!/usr/bin/env python3
"""Run the checks CI will fail you on, and refuse to fall behind them.

    python tools/run_local_checks.py
    python tools/run_local_checks.py --check
    python tools/run_local_checks.py --selftest

CI's two lint jobs run every command in CHECKS below. DEVELOPMENT.md used to
list four of them, because the list was kept by hand and every guard added since
either appended a bullet or did not, with nothing deciding which. A contributor
could run every line the page gave them and still go red, on a check whose name
says GDScript formatting (#792, #793). No count is written down here on purpose:
a number in prose is the thing that went stale in the first place.

So the list lives here instead, as the thing you run rather than a thing you
read, and `--check` reads `.github/workflows/ci.yml` and fails if a step in
either lint job is not accounted for below. Adding a guard to CI now forces a
decision about what happens locally, rather than leaving one to be noticed.

`--check` reads the workflow the other way round too, and fails when a script
under tools/ carries a `--selftest` that no step of ci.yml runs. A detector
nobody runs reads as covered and can rot into passing, and this file's own
selftest sat unrun from #794 until #810 (#811).

Every step is accounted for, including the ones not worth running here. A skip
carries its reason, because "this is not run locally" is a fact someone has to
be able to check rather than take on trust.

The GUT suite is deliberately not in here. It is minutes rather than seconds,
it needs Godot, and DEVELOPMENT.md gives it a section of its own.
"""

from __future__ import annotations

import argparse
import ast
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

REPO = Path(__file__).resolve().parent.parent
TOOLS = REPO / "tools"
WORKFLOW = REPO / ".github" / "workflows" / "ci.yml"
SELFTEST = "--selftest"

# The jobs whose steps this file has to keep up with. The test jobs are out of
# scope on purpose: they need Godot and a downloaded engine, and nothing in
# them is a check a contributor can usefully run a second time by hand.
LINT_JOBS = ("static-checks", "tooling-checks")


class Check(NamedTuple):
    """One step of a CI lint job, and what this runner does about it."""

    step: str
    argv: tuple[str, ...]
    skip: str

    def label(self) -> str:
        return " ".join(self.argv) if self.argv else self.step


def _py(*args: str) -> tuple[str, ...]:
    """A tools/ script, run on the interpreter that is running this one.

    CI says `python3`, which is not a command on a stock Windows install.
    """
    return (sys.executable, *args)


# Keyed on the step name in ci.yml rather than on the command, because a name
# is what a red check shows you, and renaming one should send you here.
CHECKS: tuple[Check, ...] = (
    # --- static-checks: GDScript Lint & Format ---
    Check(
        "Install gdtoolkit",
        (),
        "installs the toolchain; DEVELOPMENT.md has you do this once",
    ),
    Check(
        "Check formatting",
        (
            "gdformat",
            "--check",
            "addons/hammerforge/",
            "tests/",
            "tools/",
            "hammerforge_tools/",
        ),
        "",
    ),
    Check(
        "Lint", ("gdlint", "addons/hammerforge/", "tools/", "hammerforge_tools/"), ""
    ),
    Check(
        "Check the placement-order guard still detects",
        _py("tools/check_placement_order.py", "--selftest"),
        "",
    ),
    Check("Check placement order", _py("tools/check_placement_order.py"), ""),
    Check(
        "Check the project-settings guard still detects",
        _py("tools/check_project_settings.py", "--selftest"),
        "",
    ),
    Check("Check project settings", _py("tools/check_project_settings.py"), ""),
    Check(
        "Check the CI wait grades the right commit",
        _py("tools/wait_for_ci.py", "--selftest"),
        "",
    ),
    Check(
        "Check the Asset Library guard still detects",
        _py("tools/check_assetlib_freshness.py", "--selftest"),
        "",
    ),
    Check(
        "Check the vibe runner still grades a broken scenario",
        _py("tools/vibe/run_vibe.py", "--selftest"),
        "",
    ),
    Check(
        "Check the test split still covers the suite",
        _py("tools/shard_tests.py", "--selftest"),
        "",
    ),
    Check(
        "Check the shard totals still add up",
        _py("tools/update_test_counts.py", "--selftest"),
        "",
    ),
    Check(
        "Check the dead-declaration guard still detects",
        _py("tools/check_dead_declarations.py", "--selftest"),
        "",
    ),
    Check("Check for dead declarations", _py("tools/check_dead_declarations.py"), ""),
    Check(
        "Check the uid guard still detects",
        _py("tools/check_uid_parity.py", "--selftest"),
        "",
    ),
    Check("Check uid parity", _py("tools/check_uid_parity.py"), ""),
    Check(
        "Check the release tree still ships the right files",
        _py("tools/build_release_tree.py", "--selftest"),
        "",
    ),
    Check(
        "Check the local-runner guard still detects",
        _py("tools/run_local_checks.py", "--selftest"),
        "",
    ),
    Check(
        "Check the local runner still covers CI",
        _py("tools/run_local_checks.py", "--check"),
        "",
    ),
    # --- tooling-checks: Workflow & Tooling Lint ---
    Check(
        "Install tooling",
        (),
        "installs the toolchain; DEVELOPMENT.md has you do this once",
    ),
    Check("Lint tools/", ("ruff", "check", "tools/"), ""),
    Check("Check tools/ formatting", ("ruff", "format", "--check", "tools/"), ""),
    Check(
        "Lint workflow syntax",
        (),
        "actionlint is downloaded in the job, and it skips shell linting"
        " silently when shellcheck is not on PATH, so a local run proves less"
        " than it looks like it does",
    ),
    Check(
        "Audit workflows for supply-chain risk",
        (),
        "zizmor looks advisories up over the network with the job's token",
    ),
    Check(
        "Validate the Dependabot config",
        (
            "check-jsonschema",
            "--builtin-schema",
            "vendor.dependabot",
            ".github/dependabot.yml",
        ),
        "",
    ),
)


def workflow_steps(text: str) -> list[tuple[str, str, str]]:
    """Return (job, step name, run command) for each command step of LINT_JOBS.

    Parsed rather than pattern-matched: a guard that reads the file differently
    from the way GitHub reads it can pass while CI runs something else.
    """
    import yaml

    doc = yaml.safe_load(text)
    found: list[tuple[str, str, str]] = []
    for job in LINT_JOBS:
        spec = doc.get("jobs", {}).get(job)
        if spec is None:
            raise SystemExit(f"ci.yml has no job called {job!r}; this file names it")
        for step in spec.get("steps", []):
            if "run" in step:
                found.append((job, step.get("name", "<unnamed>"), step["run"].strip()))
    return found


def workflow_commands(text: str) -> list[str]:
    """Every line of every `run:` step in ci.yml, from every job.

    Every job, not just the lint ones, because the question here is whether CI
    runs a selftest at all. Putting one in the test job would be an odd choice
    and it would still be run.
    """
    import yaml

    doc = yaml.safe_load(text)
    return [
        line
        for spec in doc.get("jobs", {}).values()
        for step in spec.get("steps", [])
        if "run" in step
        for line in step["run"].splitlines()
    ]


def accepts_selftest(source: str, where: str = "<string>") -> bool:
    """Whether a script's argparse setup defines --selftest.

    Parsed rather than grepped. A script that only mentions the flag in its
    docstring or in an error message has not got one, and a grep would put it
    on the list for good with nothing anyone could do about it.
    """
    for node in ast.walk(ast.parse(source, filename=where)):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Attribute) or node.func.attr != "add_argument":
            continue
        if any(
            isinstance(arg, ast.Constant) and arg.value == SELFTEST for arg in node.args
        ):
            return True
    return False


def unrun_selftests(text: str, tools: Path = TOOLS) -> list[str]:
    """Scripts under tools/ whose --selftest no step of ci.yml runs.

    The other direction from coverage(). That asks whether everything CI runs
    is accounted for here; this asks whether every detector in the tree is run
    by CI at all. Nothing asked that until #811, and the answer was no: this
    file shipped its own selftest in #794 and nothing ran it until #810.

    `tools` is the directory to walk, and it is a parameter so the selftest can
    hand it a throwaway one. Pointed anywhere else it reports paths relative to
    that directory's parent, which is what makes a fixture workflow able to
    name the scripts in it.
    """
    # Both on one line, rather than anywhere in the file: running a guard is
    # not running its selftest, and the step that does each is a separate line.
    # Not adjacent, so that ./tools/x.py or a trailing argument still counts.
    lines = workflow_commands(text)
    unrun = []
    for path in sorted(tools.rglob("*.py")):
        rel = path.relative_to(tools.parent).as_posix()
        if not accepts_selftest(path.read_text(encoding="utf-8"), rel):
            continue
        if not any(rel in line and SELFTEST in line for line in lines):
            unrun.append(rel)
    return unrun


def as_ci_writes_it(check: Check) -> str:
    """The check's command in the form ci.yml spells it."""
    argv = (
        ("python3", *check.argv[1:])
        if check.argv[:1] == (sys.executable,)
        else check.argv
    )
    return " ".join(argv)


def coverage(text: str) -> tuple[list[str], list[str], list[str]]:
    """What ci.yml and this file disagree about.

    Three ways, because matching the step names alone leaves the commands free
    to drift underneath them -- which is the same failure this file exists to
    stop, one layer down. A directory added to the gdformat step in ci.yml has
    to reach the copy here too.
    """
    steps = workflow_steps(text)
    by_name = {name: run for _job, name, run in steps}
    known = {check.step for check in CHECKS}
    missing = [name for _job, name, _run in steps if name not in known]
    stale = sorted(known - set(by_name))
    differs = [
        f"{check.step}\n      ci.yml: {by_name[check.step]}\n      here:   {as_ci_writes_it(check)}"
        for check in CHECKS
        if check.argv
        and check.step in by_name
        and by_name[check.step] != as_ci_writes_it(check)
    ]
    return missing, stale, differs


def check_coverage() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    try:
        missing, stale, differs = coverage(text)
        unrun = unrun_selftests(text)
    except ImportError:
        print(
            "PyYAML is needed to read ci.yml:\n\n"
            "  python -m pip install -r requirements-ci.txt\n"
        )
        return 1
    if not missing and not stale and not differs and not unrun:
        print(
            f"All {len(workflow_steps(text))} steps of CI's lint jobs are"
            " accounted for, and CI runs every selftest in tools/."
        )
        return 0
    if missing:
        print("CI runs these and this file says nothing about them:\n")
        for name in missing:
            print(f"  {name}")
        print(
            "\nAdd each one to CHECKS in tools/run_local_checks.py, either with"
            "\nthe command to run locally or with the reason it is skipped.\n"
        )
    if stale:
        print("This file names steps that ci.yml no longer has:\n")
        for name in stale:
            print(f"  {name}")
        print("\nDrop them, or fix the name if the step was renamed.\n")
    if differs:
        print("These run a different command here than they do in CI:\n")
        for line in differs:
            print(f"  {line}")
        print(
            "\nA local run that is not the CI command proves less than it looks like.\n"
        )
    if unrun:
        print("These carry a --selftest that no step of ci.yml runs:\n")
        for rel in unrun:
            print(f"  {rel}")
        print(
            "\nGive each one a step. A detector nobody runs reads as covered in"
            "\na review, and it can rot into passing on a fixture whose shape"
            "\nhas moved on. That is what this file's own selftest did, from"
            "\n#794 until #810 (#811).\n"
        )
    return 1


def keep_output_with_its_step() -> None:
    """Make stdout line buffered before any child writes to it.

    Python block buffers stdout when it is not a terminal, so redirecting a run
    to a file put every check's output at the top of the file, unlabelled, and
    every header and the summary after it: this process held its own writes
    while each child wrote straight to the fd as it ran (#808). `| tail` then
    showed the step names and hid every reason, which is the half you need.

    Do not drop this line because it reads as inert. It is what keeps a failure
    under the step that produced it, and reconfigure() flushes whatever is
    already pending on the way through.
    """
    sys.stdout.reconfigure(line_buffering=True)


def run_one(check: Check) -> tuple[str, str]:
    """Run one check that has a command. Returns (outcome, detail)."""
    try:
        done = subprocess.run(check.argv, cwd=REPO, check=False)
    except FileNotFoundError:
        return "fail", (
            f"{check.argv[0]} is not on PATH."
            " python -m pip install -r requirements-ci.txt"
        )
    if done.returncode == 0:
        return "pass", ""
    return "fail", f"exit {done.returncode}"


def run_all() -> int:
    keep_output_with_its_step()
    failed: list[tuple[Check, str]] = []
    skipped = 0
    passed = 0
    for check in CHECKS:
        if not check.argv:
            skipped += 1
            continue
        print(f"\n=== {check.step} ===")
        print(f"$ {check.label()}")
        outcome, detail = run_one(check)
        if outcome == "fail":
            failed.append((check, detail))
        else:
            passed += 1

    print("\n" + "-" * 60)
    print(f"{passed} passed, {len(failed)} failed, {skipped} not run here.")
    for check in CHECKS:
        if not check.argv:
            print(f"  not run: {check.step} -- {check.skip}")
    if failed:
        print("\nFailed here, and CI runs the same command:\n")
        for check, detail in failed:
            print(f"  {check.step} ({detail})")
        print()
        return 1
    print("\nThe GUT suite is separate, and slower:\n")
    print("  godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gexit\n")
    return 0


# A step added to ci.yml and not to CHECKS is the whole failure this guard
# exists for, so the fixture carries one. It also carries the tail of a rename,
# a step whose command has moved on without the copy here, and the three kinds
# of step that must be ignored: a `uses:`, and anything outside the lint jobs.
SELFTEST_YAML = """
jobs:
  static-checks:
    steps:
      - uses: actions/checkout@v7
      - name: Install gdtoolkit
        run: pip install -r requirements-ci.txt
      - name: Check uid parity
        run: python3 tools/check_uid_parity.py
      - name: Check the nothing guard
        run: python3 tools/check_nothing.py
  tooling-checks:
    steps:
      - name: Lint tools/
        run: ruff check tools/ hammerforge_tools/
  unit-test-shard:
    steps:
      - name: Run this shard of the suite
        run: godot --headless
"""


# The wiring guard reads a tree rather than a fixture, so it gets a throwaway
# tree too: two scripts that both define the flag, where the workflow passes it
# to one and runs the other without it. Running a guard is not running its
# selftest, and that is the half a name match would get wrong.
#
# No real script is named here on purpose. It used to name two, and then each
# assertion had a second way to be satisfied that had nothing to do with the
# property it is there for (#813). Dropping a step from this fixture left the
# guard green because the script was no longer mentioned, and renaming either
# script in tools/ failed the wiring assertion with a message about a flag,
# which is not what happened.
WIRED_GUARD = "tools/wired_guard.py"
UNWIRED_GUARD = "tools/unwired_guard.py"
WIRING_YAML = f"""
jobs:
  static-checks:
    steps:
      - name: Check the wired guard still detects
        run: python3 {WIRED_GUARD} --selftest
      - name: Run the unwired guard
        run: python3 {UNWIRED_GUARD}
"""

# A script that defines the flag, and one that only talks about it. The second
# is why this is an ast walk and not a grep. A mention in a comment or in an
# error message is not a selftest, and nothing anyone did could take it off the
# list once it was on.
DEFINES_SELFTEST = (
    "import argparse\n"
    "parser = argparse.ArgumentParser()\n"
    'parser.add_argument("--selftest", action="store_true")\n'
)
MENTIONS_SELFTEST = (
    "# Pass --selftest to check the guard still detects.\n"
    'raise SystemExit("try --selftest")\n'
)


# run_all() prints a header, then hands the same fd to a child. The child's
# output landing above the header is #808, and it only happens when stdout is
# not a terminal, so this drives a real run through a pipe rather than asserting
# on a buffering flag that is already set the other way in a terminal. The
# marker is spelt in two halves so the `$ command` line the runner echoes does
# not contain it: only the child's own stdout does.
ORDERING_PROBE = """
import sys

import run_local_checks as runner

runner.CHECKS = (
    runner.Check("Probe", (sys.executable, "-c", "print('CHILD' + '-SAID-THIS')"), ""),
)
sys.exit(runner.run_all())
"""


def ordering_probe() -> subprocess.CompletedProcess[str]:
    """A one-check run whose stdout is a pipe, which is what a redirect makes it."""
    return subprocess.run(
        [sys.executable, "-c", ORDERING_PROBE],
        cwd=REPO / "tools",
        capture_output=True,
        text=True,
        check=False,
    )


def selftest() -> int:
    failures = 0

    missing, stale, differs = coverage(SELFTEST_YAML)
    if missing != ["Check the nothing guard"]:
        print(f"selftest: an unaccounted step should be reported, got {missing}")
        failures += 1
    if "Check the nothing guard" in stale:
        print("selftest: the unaccounted step is in ci.yml, so it is not stale")
        failures += 1
    # The test job's step is outside LINT_JOBS and must not be asked for.
    if "Run this shard of the suite" in missing:
        print("selftest: a test-job step was read as a lint step")
        failures += 1
    # A `uses:` step runs no command and has nothing to account for.
    if "<unnamed>" in missing:
        print("selftest: a step with no run: was read as a command")
        failures += 1
    # Steps this file knows that the fixture does not have must come back stale,
    # or a renamed step would leave a dead entry here for good.
    if "Check formatting" not in stale:
        print("selftest: a step missing from the workflow should be reported stale")
        failures += 1
    # The fixture's `Lint tools/` has grown a directory that CHECKS has not.
    # Matching on the step name alone would call that covered.
    if not any(line.startswith("Lint tools/") for line in differs):
        print("selftest: a command that moved on without this file should be reported")
        failures += 1
    # And a step whose command still matches must not be reported as differing.
    if any(line.startswith("Check uid parity") for line in differs):
        print("selftest: an identical command was reported as differing")
        failures += 1

    # And the real file has to come back clean, or the guard is passing on a
    # fixture while CI runs something this file has never heard of.
    real = coverage(WORKFLOW.read_text(encoding="utf-8"))
    if any(real):
        print(f"selftest: ci.yml is not covered: {real}")
        failures += 1

    # A check's reason has to be readable in a log, not just on a terminal.
    probe = ordering_probe()
    lines = probe.stdout.splitlines()
    header = next((i for i, line in enumerate(lines) if line == "=== Probe ==="), -1)
    said = next((i for i, line in enumerate(lines) if line == "CHILD-SAID-THIS"), -1)
    if header < 0 or said < 0:
        # Both halves, because a probe that died has its reason on stderr and a
        # selftest that fails without one is the thing this file complains about.
        print(f"selftest: the ordering probe did not run: {lines} {probe.stderr}")
        failures += 1
    elif header > said:
        print(
            "selftest: a check's output landed above the header that announced"
            " it, so a redirected run says which steps ran and not why one"
            " failed"
        )
        failures += 1

    # The flag has to be defined, not mentioned.
    if not accepts_selftest(DEFINES_SELFTEST):
        print("selftest: a script that defines --selftest was read as having none")
        failures += 1
    if accepts_selftest(MENTIONS_SELFTEST):
        print("selftest: a script that only names --selftest was read as having one")
        failures += 1

    # And the wiring: a step that passes the flag covers a script, a step that
    # runs the same script without it does not. Both scripts are written fresh
    # into a throwaway tools/ for the length of the check, so the two answers
    # below turn on the flag and on nothing else.
    with tempfile.TemporaryDirectory() as tmp:
        throwaway = Path(tmp) / "tools"
        throwaway.mkdir()
        for rel in (WIRED_GUARD, UNWIRED_GUARD):
            (throwaway / Path(rel).name).write_text(DEFINES_SELFTEST, encoding="utf-8")
        wired = unrun_selftests(WIRING_YAML, throwaway)
    # A script no step runs at all is unrun too, so the assertion about the
    # unwired one only means what it says while the fixture still runs it.
    commands = workflow_commands(WIRING_YAML)
    if not any(UNWIRED_GUARD in line for line in commands):
        print(f"selftest: the wiring fixture no longer runs {UNWIRED_GUARD}")
        failures += 1
    if WIRED_GUARD in wired:
        print("selftest: a selftest ci.yml runs was reported unrun")
        failures += 1
    if UNWIRED_GUARD not in wired:
        print("selftest: running a guard without the flag is not running its selftest")
        failures += 1

    # The real workflow has to come back clean, or a detector in this tree is
    # sitting unrun while the guard passes on a fixture.
    unrun = unrun_selftests(WORKFLOW.read_text(encoding="utf-8"))
    if unrun:
        print(f"selftest: ci.yml runs no selftest for {unrun}")
        failures += 1

    if failures:
        print(f"selftest: {failures} wrong answers")
        return 1
    print(
        "selftest: the coverage guard answers correctly on both fixtures and"
        " ci.yml, every selftest in tools/ has a step that runs it, and a"
        " redirected run keeps each check's output under its step"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if a step of CI's lint jobs is not accounted for here,"
        " or if a selftest in tools/ is not run by ci.yml",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check the coverage guard still catches an unaccounted step,"
        " and that a redirected run keeps each check under its own step",
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if args.check:
        return check_coverage()
    return run_all()


if __name__ == "__main__":
    sys.exit(main())
