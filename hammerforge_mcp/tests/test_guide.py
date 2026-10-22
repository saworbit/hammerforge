"""The building guide stays true to the tools it names (#1650).

A guide that names a renamed tool is worse than none, so every hf_* name and
every command id in it must exist. Its worked example goes through the batch
schema exactly as written, and the MCP vibe sweep runs it against a real editor.
"""

import json
import re
from pathlib import Path

import pytest
from mcp import Client

from hammerforge_mcp.catalogue import TOOLS
from hammerforge_mcp.guide import GUIDE_URI, guide_dir, pages
from hammerforge_mcp.server import build_server

from .test_server import FakeBridge, _ok

pytestmark = pytest.mark.anyio

REGISTRY = (
    Path(__file__).resolve().parents[2] / "addons/hammerforge/hf_command_registry.gd"
)


def _guide_files() -> list[Path]:
    return sorted(guide_dir().rglob("*.md"))


def _bridge_command_ids() -> set[str]:
    """The ids of registry entries an agent may run, read from the GDScript table."""
    source = REGISTRY.read_text(encoding="utf-8")
    ids = set()
    for match in re.finditer(r'"id": "([a-z0-9_]+)"', source):
        rest = source[match.end() :]
        nxt = re.search(r'"id": "', rest)
        entry = rest[: nxt.start()] if nxt else rest
        if '"bridge":' in entry:
            ids.add(match.group(1))
    return ids


def test_the_skill_has_its_name_and_description():
    text = (guide_dir() / "SKILL.md").read_text(encoding="utf-8")
    front = re.match(r"---\n(.*?)\n---\n", text, re.S)
    assert front, "SKILL.md starts with front matter"
    fields = dict(line.split(": ", 1) for line in front.group(1).splitlines())
    assert fields.get("name") == "hammerforge-building"
    assert len(fields.get("description", "")) > 80


def test_every_tool_the_guide_names_exists():
    for path in _guide_files():
        named = set(re.findall(r"\bhf_[a-z_]+", path.read_text(encoding="utf-8")))
        stale = named - set(TOOLS)
        assert not stale, f"{path.name} names {sorted(stale)}, which are not tools"


@pytest.mark.skipif(
    not REGISTRY.is_file(), reason="not inside the HammerForge repository"
)
def test_every_command_the_guide_names_exists():
    commands = _bridge_command_ids()
    assert len(commands) > 15, "the registry was read"
    for path in _guide_files():
        named = set(re.findall(r'"command":\s*"([a-z0-9_]+)"', path.read_text("utf-8")))
        stale = named - commands
        assert not stale, f"{path.name} runs {sorted(stale)}, which the bridge does not"


def test_every_link_in_the_guide_reaches_a_page():
    for path in _guide_files():
        for target in re.findall(r"\]\(([^)#:]+\.md)\)", path.read_text("utf-8")):
            assert (path.parent / target).is_file(), f"{path.name} links {target}"


async def test_the_resources_serve_the_guide_as_written():
    async with Client(build_server(FakeBridge({}))) as client:
        listed = {str(r.uri) for r in (await client.list_resources()).resources}
        assert listed == set(pages()), "a resource for the guide and each page"
        for uri, path in pages().items():
            got = await client.read_resource(uri)
            assert got.contents[0].text == path.read_text(encoding="utf-8"), uri
    assert GUIDE_URI in listed


def _example_batches() -> list[list[dict]]:
    text = (guide_dir() / "reference" / "worked-example.md").read_text("utf-8")
    blocks = re.findall(r"```json\n(.*?)\n```", text, re.S)
    return [json.loads(block)["ops"] for block in blocks]


async def test_the_worked_example_goes_through_the_batch_schema_as_written():
    batches = _example_batches()
    assert len(batches) == 3, "three batches"
    bridge = FakeBridge({"hf_batch": _ok({"results": []})})
    async with Client(build_server(bridge)) as client:
        for ops in batches:
            sent = await client.call_tool("hf_batch", {"ops": ops})
            assert sent.is_error is False, sent.content[0].text
    assert [call["params"]["ops"] for call in bridge.calls] == batches
