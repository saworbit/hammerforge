"""The editor and this server each keep their own copy of the bridge's limits.

The editor's are GDScript constants and argument checks; the server's are its
framing limits and the tool schemas an agent is shown. A schema that allows more
than the editor takes sends the agent a refusal it was told it would not get, and
one that allows less hides what the editor can do. This reads both and checks
they agree.
"""

import re
from pathlib import Path

import pytest
from mcp import Client

from hammerforge_mcp import framing
from hammerforge_mcp.server import build_server

pytestmark = pytest.mark.anyio

MCP_DIR = Path(__file__).resolve().parents[2] / "addons" / "hammerforge" / "mcp"


def _gd(name: str) -> str:
    return (MCP_DIR / name).read_text(encoding="utf-8")


def _const(source: str, name: str) -> float:
    match = re.search(rf"^const {name} := (.+)$", source, re.MULTILINE)
    assert match, f"no const {name}"
    value = match.group(1).strip()
    shifted = re.fullmatch(r"(\d+) << (\d+)", value)
    if shifted:
        return int(shifted.group(1)) << int(shifted.group(2))
    return float(value)


def _int_check(source: str, param: str) -> tuple[int, int, int]:
    """The default, minimum and maximum of a `read_int(params, "<param>", ...)`."""
    match = re.search(
        rf'read_int\(params, "{param}", false, (\d+), (\d+), (\d+)\)', source
    )
    assert match, f"no read_int for {param}"
    default, low, high = (int(group) for group in match.groups())
    return default, low, high


async def _schemas() -> dict:
    class NoBridge:
        async def call(self, *args, **kwargs):
            raise AssertionError("no call expected")

    async with Client(build_server(NoBridge())) as client:
        return {
            tool.name: tool.input_schema for tool in (await client.list_tools()).tools
        }


def _prop(schemas: dict, tool: str, name: str) -> dict:
    prop = schemas[tool]["properties"][name]
    # An optional field is anyOf [the type, null].
    for option in prop.get("anyOf", []):
        if option.get("type") != "null":
            return {**option, **{k: v for k, v in prop.items() if k != "anyOf"}}
    return prop


def test_the_frame_limits_agree():
    protocol = _gd("hf_mcp_protocol.gd")
    assert _const(protocol, "MAX_REQUEST_BYTES") == framing.MAX_REQUEST_BYTES
    assert _const(protocol, "MAX_RESPONSE_BYTES") == framing.MAX_RESPONSE_BYTES


async def test_the_tool_schemas_allow_what_the_editor_takes():
    schemas = await _schemas()
    dispatcher = _gd("hf_mcp_dispatcher.gd")
    tools = _gd("hf_mcp_tools.gd")
    protocol = _gd("hf_mcp_protocol.gd")

    ops = _prop(schemas, "hf_batch", "ops")
    assert ops["maxItems"] == _const(dispatcher, "BATCH_LIMIT")
    assert ops["minItems"] == 1

    for side in ("width", "height"):
        default, low, high = _int_check(dispatcher, side)
        prop = _prop(schemas, "hf_viewport_screenshot", side)
        assert (prop["default"], prop["minimum"], prop["maximum"]) == (
            default,
            low,
            high,
        ), side

    default, low, high = _int_check(tools, "limit")
    prop = _prop(schemas, "hf_get_brushes", "limit")
    assert (prop["default"], prop["minimum"], prop["maximum"]) == (default, low, high)

    distance = _prop(schemas, "hf_extrude_face", "distance")
    assert distance["maximum"] == _const(tools, "MAX_EXTRUDE")
    assert distance["exclusiveMinimum"] == 0

    pattern = _prop(schemas, "hf_place_brush", "operation_id")["pattern"]
    longest = int(re.search(r"\{1,(\d+)\}", pattern).group(1))
    assert longest == _const(protocol, "OPERATION_ID_MAX")


async def test_every_bound_is_in_json_schema_words():
    # pydantic writes "gt" and "le" for a bound it cannot place in the type's own
    # schema; a client reading JSON Schema skips them and never sees the bound.
    pydantic_only = {"gt", "ge", "lt", "le", "allow_inf_nan"}
    found = []

    def walk(node, path):
        if isinstance(node, dict):
            found.extend(f"{path}.{key}" for key in pydantic_only & node.keys())
            for key, value in node.items():
                walk(value, f"{path}/{key}")
        elif isinstance(node, list):
            for i, value in enumerate(node):
                walk(value, f"{path}[{i}]")

    for name, schema in (await _schemas()).items():
        walk(schema, name)
    assert found == []
