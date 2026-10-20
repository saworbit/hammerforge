#!/usr/bin/env python3
"""Write the hex and triangles prototype textures, or check them against disk.

    python tools/make_prototype_patterns.py
    python tools/make_prototype_patterns.py --check
    python tools/make_prototype_patterns.py --selftest

The prototype textures under addons/hammerforge/textures/prototypes/ are one
SVG per pattern and colour. Thirteen of the patterns were drawn once and left
alone. These two did not look like their names (#1330). `hex` was 14 by 24 px
hexagons on a 28 px pitch with every other one painted the background colour,
which the Material Browser's 64 px thumbnail shows as columns of narrow ovals.
`triangles` split 24 px squares in two and coloured them so that same-coloured
halves met across the cell edge and joined into diagonal bands, a near twin of
`stripes_diagonal`.

Both are drawn here on one lattice: five columns across the 128 px tile and six
rows down it, so each repeats at the tile edge in both directions. A honeycomb
and a triangle tiling are duals, which is why one lattice serves both. The
tones are the two every other pattern in the colour family already uses, so a
palette that mixes them with `checker` or `brick` still matches. `hex` is light
cells with a dark wall between them, and `triangles` is light triangles
pointing up with the dark ones between them pointing down, each row shifted by
half a triangle so no two of one tone share an edge.

`--check` writes nothing and exits 1 when a file on disk differs from what the
script would write, so the twenty files stay reproducible. CI runs it, so a
hand edit to one of them fails there instead of being undone by the next run
of this script (#1369). `--selftest` writes the files to a scratch folder,
changes a byte of one and deletes another, and fails unless the comparison
names both. Only the standard library is used.
"""

from __future__ import annotations

import argparse
import math
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROTOTYPES = REPO / "addons" / "hammerforge" / "textures" / "prototypes"

# Every prototype is a 128 px tile, which is what the importer rasterises and
# what the thumbnail scales to 64 px.
TILE = 128

# 128 / 5 and 128 / 6 are not whole pixels. That is fine in an SVG, and it is
# the nearest pair that keeps the cells close to regular: a regular hexagon
# 25.6 px wide would be 29.6 px tall, and these are 28.4.
COLUMNS = 5
ROWS = 6
PITCH = TILE / COLUMNS  # a cell's width, and a triangle's base
ROW_HEIGHT = TILE / ROWS  # a triangle's height, and 1.5 hex radii
HEX_RADIUS = ROW_HEIGHT / 1.5  # cell centre to its top or bottom vertex
HEX_WALL = 4.0  # the dark seam between two cells, 2 px on the thumbnail

# (dark, light) for each colour: the two tones checker_<colour>.svg uses.
TONES = {
    "blue": ("#4a8db7", "#7ec8e3"),
    "brown": ("#805030", "#c8a070"),
    "cyan": ("#2090a0", "#60d8d0"),
    "green": ("#4a7c40", "#8dc26f"),
    "grey": ("#808080", "#c8c8c8"),
    "orange": ("#c47828", "#e8a848"),
    "pink": ("#c05880", "#f0a0c0"),
    "purple": ("#7040a0", "#b07ec8"),
    "red": ("#b83030", "#e87070"),
    "yellow": ("#c0a800", "#f0e060"),
}

HEADER = (
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{TILE}" height="{TILE}"'
    f' viewBox="0 0 {TILE} {TILE}">'
)

Point = tuple[float, float]


def num(value: float) -> str:
    """A coordinate with up to three decimals and no trailing zeros."""
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def rect(fill: str) -> str:
    return f'<rect width="{TILE}" height="{TILE}" fill="{fill}"/>'


def polygon(points: list[Point], fill: str) -> str:
    coords = " ".join(f"{num(x)},{num(y)}" for x, y in points)
    return f'<polygon points="{coords}" fill="{fill}"/>'


def overlaps_tile(points: list[Point]) -> bool:
    """Whether any of the shape lands inside the tile.

    The lattice is walked one cell past each edge so the picture wraps, and
    the cells that fall wholly outside are left out of the file.
    """
    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    return min(xs) < TILE and max(xs) > 0 and min(ys) < TILE and max(ys) > 0


def hex_cell(cx: float, cy: float) -> list[Point]:
    """A pointy-top cell centred at (cx, cy), inset by half a wall.

    The inset moves each edge in by the same distance rather than scaling the
    cell, so the wall is the same width on the slanted sides as on the
    vertical ones even though the cell is 4% squatter than regular.
    """
    half_width = PITCH / 2
    radius = HEX_RADIUS
    inset = HEX_WALL / 2
    slant = math.hypot(half_width, radius / 2)  # a slanted edge's length
    top = radius - inset * slant / half_width
    side_x = half_width - inset
    side_y = radius / 2 + radius * inset / (2 * half_width) - inset * slant / half_width
    return [
        (cx, cy - top),
        (cx + side_x, cy - side_y),
        (cx + side_x, cy + side_y),
        (cx, cy + top),
        (cx - side_x, cy + side_y),
        (cx - side_x, cy - side_y),
    ]


def hex_svg(dark: str, light: str) -> str:
    """Light cells on a dark ground; the ground showing between them is the wall."""
    parts = [HEADER, rect(dark)]
    for row in range(-1, ROWS + 1):
        shift = PITCH / 2 if row % 2 else 0.0
        cy = row * ROW_HEIGHT + HEX_RADIUS
        for column in range(-1, COLUMNS + 1):
            cell = hex_cell(column * PITCH + shift, cy)
            if overlaps_tile(cell):
                parts.append(polygon(cell, light))
    parts.append("</svg>")
    return "".join(parts)


def triangles_svg(dark: str, light: str) -> str:
    """Light triangles pointing up; the dark ground between them points down."""
    parts = [HEADER, rect(dark)]
    for row in range(ROWS):
        shift = PITCH / 2 if row % 2 else 0.0
        top = row * ROW_HEIGHT
        bottom = top + ROW_HEIGHT
        for column in range(-1, COLUMNS + 1):
            left = column * PITCH + shift
            triangle = [(left + PITCH / 2, top), (left + PITCH, bottom), (left, bottom)]
            if overlaps_tile(triangle):
                parts.append(polygon(triangle, light))
    parts.append("</svg>")
    return "".join(parts)


def expected_files() -> dict[Path, bytes]:
    """Every file this script owns, with what it should hold."""
    files: dict[Path, bytes] = {}
    for colour, (dark, light) in TONES.items():
        files[PROTOTYPES / f"hex_{colour}.svg"] = hex_svg(dark, light).encode()
        files[PROTOTYPES / f"triangles_{colour}.svg"] = triangles_svg(
            dark, light
        ).encode()
    return files


def differing(files: dict[Path, bytes], write: bool) -> list[Path]:
    """The files whose bytes on disk are not the ones given, written if `write`."""
    found = []
    for path, content in sorted(files.items()):
        if path.exists() and path.read_bytes() == content:
            continue
        found.append(path)
        if write:
            path.write_bytes(content)
    return found


def selftest() -> int:
    """Check that the comparison --check runs names a changed and a missing file."""
    failures = []
    with tempfile.TemporaryDirectory() as scratch:
        files = {
            Path(scratch) / path.name: content
            for path, content in expected_files().items()
        }
        if len(differing(files, write=True)) != len(files):
            failures.append("a write into an empty folder should write every file")
        if differing(files, write=False):
            failures.append("files just written should all match")
        changed, removed = sorted(files)[:2]
        content = bytearray(changed.read_bytes())
        content[len(content) // 2] ^= 1
        changed.write_bytes(bytes(content))
        removed.unlink()
        got = differing(files, write=False)
        if got != [changed, removed]:
            names = [path.name for path in got]
            failures.append(
                f"should name {changed.name} and {removed.name}, named {names}"
            )
    for failure in failures:
        print(f"selftest: {failure}")
    if failures:
        return 1
    print(f"selftest: a changed and a missing file of {len(files)} both named")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; exit 1 if a file on disk differs from what would be written",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="check that --check still notices a changed or missing file",
    )
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()

    files = expected_files()
    found = differing(files, write=not args.check)
    if args.check:
        if found:
            print("These differ from what tools/make_prototype_patterns.py writes:\n")
            for path in found:
                print(f"  {path.relative_to(REPO).as_posix()}")
            print("\nRun python tools/make_prototype_patterns.py to rewrite them.")
            return 1
        print(f"All {len(files)} generated prototype textures match.")
        return 0
    print(f"Wrote {len(found)} of {len(files)} prototype textures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
