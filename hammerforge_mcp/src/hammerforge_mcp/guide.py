"""The building guide, served as MCP resources (#1650).

The guide is a skill in the format coding agents load, `skills/hammerforge-building/`
beside this package: `SKILL.md` and the reference pages it links. A client that
does not load skills reads the same text here: `hammerforge://guide` is
`SKILL.md`, and `hammerforge://guide/<page>` each page under `reference/`. A
wheel carries the folder inside the package; a checkout reads it where it is.
"""

from __future__ import annotations

from pathlib import Path

SKILL = "hammerforge-building"
GUIDE_URI = "hammerforge://guide"


def guide_dir() -> Path:
    """The skill's folder: inside the package once installed, else in the checkout."""
    here = Path(__file__).resolve().parent
    packaged = here / "skills" / SKILL
    if packaged.is_dir():
        return packaged
    return here.parents[1] / "skills" / SKILL


def pages() -> dict[str, Path]:
    """Each resource URI and the file it serves, the guide first."""
    root = guide_dir()
    served = {GUIDE_URI: root / "SKILL.md"}
    for page in sorted((root / "reference").glob("*.md")):
        served[f"{GUIDE_URI}/{page.stem}"] = page
    return served


def title_of(path: Path) -> str:
    """The page's first heading, or its file name."""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem
