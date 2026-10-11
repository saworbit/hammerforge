import re
from pathlib import Path

import pytest

from hammerforge_mcp.catalogue import SHAPES, TOOLS

LEVEL_ROOT = Path(__file__).resolve().parents[2] / "addons/hammerforge/level_root.gd"


def test_shapes_are_the_editors_brush_shapes():
    if not LEVEL_ROOT.is_file():
        pytest.skip("not inside the HammerForge repository")
    source = LEVEL_ROOT.read_text(encoding="utf-8")
    block = re.search(r"enum BrushShape \{(.*?)\}", source, re.S)
    assert block, "level_root.gd has no BrushShape enum"
    names = re.findall(r"^\s*([A-Z_]+)\b", block.group(1), re.M)
    editor = [name.lower() for name in names if name != "CUSTOM"]
    assert list(SHAPES) == editor


def test_every_tool_says_whether_it_changes_the_level():
    for spec in TOOLS.values():
        assert spec.annotations.read_only_hint is (not spec.mutating), spec.name
        assert spec.annotations.open_world_hint is False, spec.name
        assert spec.timeout > 0, spec.name


README = Path(__file__).resolve().parents[1] / "README.md"


def test_the_readme_table_names_every_tool():
    table = README.read_text(encoding="utf-8")
    listed = set(re.findall(r"^\| `(hf_[a-z_]+)` \|", table, re.M))
    assert listed == set(TOOLS)
