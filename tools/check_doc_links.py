"""No relative link in the repository's top-level pages points at a missing file.

The docs site's `mkdocs build --strict` checks the pages under `docs/`. The pages
at the root are read on GitHub and were checked by nothing, and `ROADMAP.md`
sent readers to a gap analysis that was never in the repository (#1707).

    python tools/check_doc_links.py             check the pages
    python tools/check_doc_links.py --selftest  check that a missing file is caught
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PAGES = ["README.md", "ROADMAP.md", "CONTRIBUTING.md", "DEVELOPMENT.md", "CHANGELOG.md"]
LINK = re.compile(r"\]\(([^)\s]+)\)")


def missing_links(page: Path) -> list[str]:
    """Each relative link of `page` whose file is not there, with its line."""
    out: list[str] = []
    for number, line in enumerate(page.read_text(encoding="utf-8").splitlines(), 1):
        for found in LINK.finditer(line):
            target = found.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                continue
            path = target.split("#", 1)[0]
            if path and not (page.parent / path).exists():
                out.append(f"{page.name}:{number}: {target} is not there")
    return out


def selftest() -> int:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "here.md").write_text("x", encoding="utf-8")
        page = root / "PAGE.md"
        page.write_text(
            "[a](here.md) [b](https://example.com) [c](#top) [d](gone.md#part)\n",
            encoding="utf-8",
        )
        found = missing_links(page)
        if found != ["PAGE.md:1: gone.md#part is not there"]:
            print(f"selftest: expected only gone.md, got {found}")
            return 1
    print("selftest: the link check still catches a missing file")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    problems: list[str] = []
    for name in PAGES:
        page = REPO / name
        if page.is_file():
            problems += missing_links(page)
    for problem in problems:
        print(f"links: {problem}")
    if not problems:
        print(f"links: every relative link in {len(PAGES)} pages is there")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
