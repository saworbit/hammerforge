"""How much of the classic brush editors' tool set HammerForge covers (#1707).

Reads `docs/data/classic-editor-tools.txt`, the tools and menu actions of Hammer
and TrenchBroom by name, each mapped to HammerForge command ids, a note, `none`
or `not planned: reason`, and the command ids in `hf_command_registry.gd`, and
writes `docs/parity.md`: the share covered in each area and in all, every line
with what covers it, and what is not covered yet.

    python tools/gen_parity.py             write docs/parity.md
    python tools/gen_parity.py --check     fail when a mapped command id is gone,
                                           a line does not read, or the page is
                                           not what this would write
    python tools/gen_parity.py --selftest  check that --check still catches both

The page's date is the day it was written; `--check` reads past it.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "docs" / "data" / "classic-editor-tools.txt"
REGISTRY = REPO / "addons" / "hammerforge" / "hf_command_registry.gd"
PAGE = REPO / "docs" / "parity.md"
DATE_LINE = re.compile(r"^Generated \d{4}-\d{2}-\d{2}\.$", re.M)
ID = re.compile(r"^[a-z0-9_]+$")


@dataclass
class Line:
    area: str
    name: str
    kind: str  # "commands", "note", "none" or "not planned"
    detail: str
    ids: list[str]
    number: int


def registry_ids(path: Path = REGISTRY) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'^\t\t"id": "([a-z0-9_]+)",$', text, re.M))


def read_catalog(path: Path = CATALOG) -> tuple[list[Line], list[str]]:
    """The catalog's lines, and what is wrong with any of them."""
    lines: list[Line] = []
    problems: list[str] = []
    area = ""
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = raw.strip()
        if text.startswith("## "):
            area = text[3:].strip()
            continue
        if not text or text.startswith("#"):
            continue
        if "|" not in text:
            problems.append(f"line {number}: no | between the name and its mapping")
            continue
        name, mapping = (part.strip() for part in text.split("|", 1))
        if not area:
            problems.append(f"line {number}: {name} comes before any ## area")
            continue
        lower = mapping.lower()
        if lower == "none":
            lines.append(Line(area, name, "none", "", [], number))
        elif lower.startswith("not planned:"):
            reason = mapping.split(":", 1)[1].strip()
            if not reason:
                problems.append(f"line {number}: {name} is not planned with no reason")
            lines.append(Line(area, name, "not planned", reason, [], number))
        elif lower.startswith("note:"):
            lines.append(
                Line(area, name, "note", mapping.split(":", 1)[1].strip(), [], number)
            )
        else:
            ids = [part.strip() for part in mapping.split(",") if part.strip()]
            bad = [i for i in ids if not ID.match(i)]
            if not ids or bad:
                problems.append(
                    f"line {number}: {name} maps to {mapping!r}, not command ids"
                )
                continue
            lines.append(Line(area, name, "commands", "", ids, number))
    return lines, problems


def missing_ids(lines: list[Line], known: set[str]) -> list[str]:
    out = []
    for line in lines:
        for command in line.ids:
            if command not in known:
                out.append(
                    f"line {line.number}: {line.name} maps to `{command}`, which no command is"
                )
    return out


def _share(lines: list[Line]) -> tuple[int, int]:
    counted = [line for line in lines if line.kind != "not planned"]
    covered = [line for line in counted if line.kind in ("commands", "note")]
    return len(covered), len(counted)


def _percent(covered: int, counted: int) -> str:
    return f"{round(100 * covered / counted)}%" if counted else "n/a"


def coverage(lines: list[Line]) -> tuple[int, int]:
    return _share(lines)


def render(lines: list[Line], today: dt.date) -> str:
    areas: list[str] = []
    for line in lines:
        if line.area not in areas:
            areas.append(line.area)
    covered, counted = _share(lines)
    out = [
        "# Parity with the classic brush editors",
        "",
        "How much of the tool set of Hammer and TrenchBroom HammerForge covers, by",
        "the names of their tools and menu actions. Each is mapped to the",
        "HammerForge commands that do its job, to a note where Godot or a panel",
        "does it, or to nothing yet. A line not planned is left out of the share.",
        "",
        "This page is written by `tools/gen_parity.py` from",
        "`docs/data/classic-editor-tools.txt` and the command registry, and CI",
        "fails when it is out of date or names a command that is gone (#1707).",
        "Change the catalog, not this page.",
        "",
        f"Generated {today.isoformat()}.",
        "",
        f"**Covered: {covered} of {counted}, {_percent(covered, counted)}.**",
        "",
        "| Area | Covered | Share |",
        "|---|---|---|",
    ]
    for area in areas:
        mine = [line for line in lines if line.area == area]
        area_covered, area_counted = _share(mine)
        out.append(
            f"| {area} | {area_covered} of {area_counted} | {_percent(area_covered, area_counted)} |"
        )
    out.append("")
    for area in areas:
        out.extend([f"## {area}", "", "| Tool | HammerForge |", "|---|---|"])
        for line in (line for line in lines if line.area == area):
            out.append(f"| {line.name} | {_cell(line)} |")
        out.append("")
    uncovered = [line for line in lines if line.kind == "none"]
    out.extend(["## Not covered yet", ""])
    if uncovered:
        out.extend(f"- {line.name} ({line.area})" for line in uncovered)
    else:
        out.append("Nothing.")
    out.append("")
    return "\n".join(out)


def _cell(line: Line) -> str:
    if line.kind == "commands":
        return ", ".join(f"`{command}`" for command in line.ids)
    if line.kind == "note":
        return line.detail
    if line.kind == "not planned":
        return f"Not planned: {line.detail}"
    return "Not yet"


def _without_date(text: str) -> str:
    return DATE_LINE.sub("Generated.", text.replace("\r\n", "\n"))


def check(catalog: Path, registry: Path, page: Path) -> list[str]:
    lines, problems = read_catalog(catalog)
    problems += missing_ids(lines, registry_ids(registry))
    if problems:
        return problems
    written = page.read_text(encoding="utf-8") if page.is_file() else ""
    if _without_date(written) != _without_date(render(lines, dt.date.today())):
        return [
            f"{page.relative_to(REPO) if page.is_relative_to(REPO) else page} is out of date: run python tools/gen_parity.py"
        ]
    return []


def selftest() -> int:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        catalog = root / "tools.txt"
        registry = root / "registry.gd"
        page = root / "parity.md"
        registry.write_text('\t\t"id": "hollow",\n', encoding="utf-8")
        catalog.write_text("## Area\nMake Hollow | hollow\n", encoding="utf-8")
        lines, _ = read_catalog(catalog)
        page.write_text(render(lines, dt.date(2000, 1, 1)), encoding="utf-8")
        if check(catalog, registry, page):
            print("selftest: a current page was called stale")
            return 1
        catalog.write_text(
            "## Area\nMake Hollow | hollow\nCarve | carve\n", encoding="utf-8"
        )
        found = check(catalog, registry, page)
        if not any("carve" in problem for problem in found):
            print("selftest: a command id no registry has went unnoticed")
            return 1
        registry.write_text(
            '\t\t"id": "hollow",\n\t\t"id": "carve",\n', encoding="utf-8"
        )
        if not any(
            "out of date" in problem for problem in check(catalog, registry, page)
        ):
            print("selftest: a stale page went unnoticed")
            return 1
    print("selftest: the parity check still catches a missing id and a stale page")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.check:
        problems = check(CATALOG, REGISTRY, PAGE)
        for problem in problems:
            print(f"parity: {problem}")
        if not problems:
            lines, _ = read_catalog()
            covered, counted = coverage(lines)
            print(f"parity: {covered} of {counted} covered, the page is current")
        return 1 if problems else 0
    lines, problems = read_catalog()
    problems += missing_ids(lines, registry_ids())
    if problems:
        for problem in problems:
            print(f"parity: {problem}")
        return 1
    PAGE.write_text(render(lines, dt.date.today()), encoding="utf-8")
    covered, counted = coverage(lines)
    print(f"parity: wrote {PAGE.relative_to(REPO)}, {covered} of {counted} covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
