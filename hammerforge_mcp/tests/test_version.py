"""The server is versioned with the addon it speaks to (#1044, #1055)."""

import re
from pathlib import Path

from hammerforge_mcp import __version__

PACKAGE = Path(__file__).resolve().parent.parent
REPO = PACKAGE.parent


def _addon_version() -> str:
    cfg = (REPO / "addons" / "hammerforge" / "plugin.cfg").read_text(encoding="utf-8")
    return re.search(r'^version="([^"]+)"', cfg, re.MULTILINE).group(1)


def _fragments() -> int:
    """Changelog lines waiting in changelog.d/ to be compiled in (#917)."""
    return len(list((REPO / "changelog.d").glob("*.*.md")))


def _release_problem(version: str, changelog: str, fragments: int = 0) -> str:
    """Why a build with this version and changelog cannot be a release, or ""."""
    # From the commit after a release until the next one, main is a dev build,
    # so a report from main cannot be read as one about the release (#1044).
    # The release commit itself drops -dev (DEVELOPMENT.md step 1). It is the
    # one commit whose changelog has this version as its newest release and
    # nothing under [Unreleased] yet, so any later change gives it away (#1081).
    # A change lands as a fragment in changelog.d/ first, so one there counts.
    if version.endswith("-dev"):
        return ""
    found = re.search(
        r"^## \[Unreleased\]\n(.*?)^## \[([^\]]+)\]",
        changelog,
        re.MULTILINE | re.DOTALL,
    )
    if found is None or found.group(2) != version:
        return f"{version} is not the newest release in CHANGELOG.md"
    if fragments or re.search(r"^### ", found.group(1), re.MULTILINE):
        return f"main has changes since {version}; set the next version with -dev"
    return ""


def test_the_server_and_its_package_agree():
    text = (PACKAGE / "pyproject.toml").read_text(encoding="utf-8")
    assert (
        re.search(r'^version = "([^"]+)"', text, re.MULTILINE).group(1) == __version__
    )


def test_the_server_is_versioned_with_the_addon():
    # plugin.cfg says 0.3.3-dev on main; Python spells that 0.3.3.dev0.
    assert __version__ == _addon_version().replace("-dev", ".dev0")


def test_main_calls_itself_a_release_only_on_the_release_commit():
    changelog = (REPO / "CHANGELOG.md").read_text(encoding="utf-8")
    assert _release_problem(_addon_version(), changelog, _fragments()) == ""


RELEASE_COMMIT = """## [Unreleased]

## [0.3.3] - 2026-10-20

**Highlights**

### Week of 12 Oct 2026

## [0.3.2] - 2026-09-19
"""

AFTER_THE_RELEASE = RELEASE_COMMIT.replace(
    "## [Unreleased]\n", "## [Unreleased]\n\n### Week of 26 Oct 2026\n"
)


def test_a_release_commit_may_drop_dev():
    assert _release_problem("0.3.3", RELEASE_COMMIT) == ""


def test_a_dev_build_is_never_a_release():
    assert _release_problem("0.3.4-dev", AFTER_THE_RELEASE) == ""


def test_a_change_after_the_release_needs_the_next_dev_version():
    assert "set the next version" in _release_problem("0.3.3", AFTER_THE_RELEASE)


def test_a_fragment_after_the_release_needs_the_next_dev_version():
    assert "set the next version" in _release_problem("0.3.3", RELEASE_COMMIT, 1)


def test_a_version_the_changelog_never_released_is_not_a_release():
    assert "not the newest release" in _release_problem("0.3.4", RELEASE_COMMIT)
    assert "not the newest release" in _release_problem("0.3.3", "## [Unreleased]\n")
