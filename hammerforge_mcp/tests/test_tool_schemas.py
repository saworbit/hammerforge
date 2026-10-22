"""The input schema of every tool, kept in tool_schemas.json for the editor's sweep.

The editor's bad values sweep (tests/test_mcp_bad_values.gd) sends each tool the
wrong kind of value for each of its inputs, straight to the editor, past the
checks this server makes. It reads the inputs from this file, so a tool or an
input added here is swept with no edit to the sweep (#1647). The file has to
say what the server says, which this test holds it to.

To write it again after changing a tool:

    HF_WRITE_TOOL_SCHEMAS=1 python -m pytest tests/test_tool_schemas.py
"""

import json
import os
from pathlib import Path

import pytest
from mcp import Client

from hammerforge_mcp.server import build_server

pytestmark = pytest.mark.anyio

SCHEMAS = Path(__file__).resolve().parents[1] / "tool_schemas.json"


async def _schemas() -> dict:
    class NoBridge:
        async def call(self, *args, **kwargs):
            raise AssertionError("no call expected")

    async with Client(build_server(NoBridge())) as client:
        return {
            tool.name: tool.input_schema for tool in (await client.list_tools()).tools
        }


def _text(schemas: dict) -> str:
    return json.dumps(schemas, indent=1, sort_keys=True) + "\n"


async def test_the_committed_tool_schemas_are_the_servers():
    text = _text(await _schemas())
    if os.environ.get("HF_WRITE_TOOL_SCHEMAS") == "1":
        SCHEMAS.write_text(text, encoding="utf-8", newline="\n")
    assert SCHEMAS.is_file(), f"{SCHEMAS.name} is missing; see this test's docstring"
    committed = SCHEMAS.read_text(encoding="utf-8")
    assert committed == text, (
        f"{SCHEMAS.name} is stale: a tool's inputs changed. Write it again with "
        "HF_WRITE_TOOL_SCHEMAS=1 python -m pytest tests/test_tool_schemas.py"
    )
