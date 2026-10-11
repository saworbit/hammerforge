"""The server is versioned with the addon it speaks to (#1044, #1055)."""

import re
from pathlib import Path

from hammerforge_mcp import __version__

PACKAGE = Path(__file__).resolve().parent.parent
REPO = PACKAGE.parent


def _addon_version() -> str:
    cfg = (REPO / "addons" / "hammerforge" / "plugin.cfg").read_text(encoding="utf-8")
    return re.search(r'^version="([^"]+)"', cfg, re.MULTILINE).group(1)


def test_the_server_and_its_package_agree():
    text = (PACKAGE / "pyproject.toml").read_text(encoding="utf-8")
    assert (
        re.search(r'^version = "([^"]+)"', text, re.MULTILINE).group(1) == __version__
    )


def test_the_server_is_versioned_with_the_addon():
    # plugin.cfg says 0.3.3-dev on main; Python spells that 0.3.3.dev0.
    assert __version__ == _addon_version().replace("-dev", ".dev0")


def test_main_never_calls_itself_a_release():
    # From the commit after a release until the next one, main is a dev build,
    # so a report from main cannot be read as one about the release (#1044).
    assert _addon_version().endswith("-dev")
