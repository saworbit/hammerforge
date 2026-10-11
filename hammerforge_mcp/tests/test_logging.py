import dataclasses
import logging

import pytest
from mcp import Client

from hammerforge_mcp import catalogue
from hammerforge_mcp.bridge import Bridge
from hammerforge_mcp.discovery import discovery_path
from hammerforge_mcp.server import build_server

from .conftest import HOLD, TOKEN, FakeListener, failed, make_project, ok

pytestmark = pytest.mark.anyio

OTHER_TOKEN = "cd" * 32


def _responder(request):
    if request["method"] == "hf_delete_brush":
        return failed(request, "brush_not_found")
    if request["method"] == "hf_bake":
        return HOLD
    return ok(request)


async def test_each_call_is_one_line_with_its_outcome(tmp_path, caplog):
    project = make_project(tmp_path)
    listener = await FakeListener(project, _responder).start()
    bridge = Bridge(project, client_version="test")
    caplog.set_level(logging.INFO, logger="hammerforge_mcp")
    try:
        async with Client(build_server(bridge)) as client:
            await client.call_tool(
                "hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}
            )
            await client.call_tool("hf_delete_brush", {"brush_id": "b"})
    finally:
        await bridge.close()
        await listener.stop()
    lines = [r.getMessage() for r in caplog.records if r.name == "hammerforge_mcp"]
    placed = [line for line in lines if line.startswith("hf_place_brush")]
    refused = [line for line in lines if line.startswith("hf_delete_brush")]
    assert len(placed) == 1 and "ok at revision 5" in placed[0], lines
    assert len(refused) == 1 and "refused: brush_not_found" in refused[0], lines
    assert all(line.endswith(" ms") for line in placed + refused)


async def test_no_log_line_carries_the_token(tmp_path, caplog, monkeypatch):
    project = make_project(tmp_path)
    listener = await FakeListener(project, _responder).start()
    bridge = Bridge(project, client_version="test")
    # Every logger, at the most it says, the SDK's own included.
    caplog.set_level(logging.DEBUG)
    try:
        async with Client(build_server(bridge)) as client:
            await client.call_tool("hf_get_status", {})
            await client.call_tool(
                "hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}
            )
            await client.call_tool("hf_delete_brush", {"brush_id": "b"})
            # The editor restarts with a new token; the server still has the old
            # connection, drops it, and its reconnect is refused.
            file = discovery_path(project)
            file.write_text(file.read_text().replace(TOKEN, OTHER_TOKEN))
            await bridge._drop()
            refused = await client.call_tool("hf_get_status", {})
            assert refused.is_error
            file.write_text(file.read_text().replace(OTHER_TOKEN, TOKEN))
            # A change that times out.
            quick = dataclasses.replace(catalogue.TOOLS["hf_bake"], timeout=0.3)
            monkeypatch.setitem(catalogue.TOOLS, "hf_bake", quick)
            slow = await client.call_tool("hf_bake", {})
            assert slow.is_error
    finally:
        await bridge.close()
        await listener.stop()
    assert len(caplog.records) > 5, "the run logged something to look through"
    for record in caplog.records:
        text = record.getMessage() + " " + repr(record.args)
        assert TOKEN not in text, record.name
        assert OTHER_TOKEN not in text, record.name
