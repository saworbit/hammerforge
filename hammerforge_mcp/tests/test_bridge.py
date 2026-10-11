import pytest

from hammerforge_mcp.bridge import Bridge, BridgeError
from hammerforge_mcp.discovery import discovery_path

from .conftest import HOLD, FakeListener, failed, make_project, ok

pytestmark = pytest.mark.anyio


async def _bridge(tmp_path, responder=None):
    project = make_project(tmp_path)
    listener = await FakeListener(project, responder).start()
    return listener, Bridge(project, client_version="test")


async def test_hello_carries_the_token_and_version(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    hello = listener.hellos[0]
    assert hello["type"] == "hello"
    assert hello["bridge_version"] == 1
    assert hello["token"] == "ab" * 32
    assert hello["client"]["name"] == "hammerforge-mcp"


async def test_a_wrong_token_is_auth_failed(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    listener_token_file = discovery_path(listener.project)
    listener_token_file.write_text(
        listener_token_file.read_text().replace("ab" * 32, "cd" * 32)
    )
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert caught.value.code == "auth_failed"


async def test_bridge_off_is_a_bridge_error_that_says_how(tmp_path):
    bridge = Bridge(make_project(tmp_path), client_version="test")
    with pytest.raises(BridgeError) as caught:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    assert caught.value.code == "bridge_off"
    assert "Allow agent connections" in str(caught.value)


async def test_ids_are_strings_and_the_target_follows_status(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        await bridge.call(
            "hf_place_brush", {"size": [1, 1, 1]}, mutating=True, timeout=5
        )
    finally:
        await bridge.close()
        await listener.stop()
    status, place = listener.requests
    assert isinstance(status["id"], str)
    assert "expect_target" not in status
    assert place["expect_target"] == "1:2:3"
    assert isinstance(place["operation_id"], str) and place["operation_id"]


async def test_a_first_mutation_attaches_with_status(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert [r["method"] for r in listener.requests] == [
        "hf_get_status",
        "hf_place_brush",
    ]
    assert listener.requests[1]["expect_target"] == "1:2:3"


async def test_a_lost_response_is_retried_once_with_the_same_operation_id(tmp_path):
    seen: list[dict] = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        seen.append(request)
        if len(seen) == 1:
            return None  # the connection drops before the answer
        answer = ok(request, {"brush": {"brush_id": "b1"}})
        answer["replayed"] = True
        return answer

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        response = await bridge.call(
            "hf_place_brush", {}, mutating=True, timeout=5, operation_id="op-9"
        )
    finally:
        await bridge.close()
        await listener.stop()
    assert response["replayed"] is True
    assert [r["operation_id"] for r in seen] == ["op-9", "op-9"]
    assert listener.connections == 2


async def test_a_second_loss_gives_up(tmp_path):
    def responder(request):
        return ok(request) if request["method"] == "hf_get_status" else None

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert caught.value.code == "bridge_unavailable"


async def test_target_changed_leaves_the_target_alone(tmp_path):
    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        return failed(request, "target_changed", target="9:9:9")

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        first = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert first["error"]["code"] == "target_changed"
    assert [r.get("expect_target") for r in listener.requests[1:]] == [
        "1:2:3",
        "1:2:3",
    ]


async def test_a_slow_answer_times_out(tmp_path):
    def responder(request):
        return ok(request) if request["method"] == "hf_get_status" else HOLD

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_bake", {}, mutating=True, timeout=0.3)
    finally:
        await bridge.close()
        await listener.stop()
    assert caught.value.code == "timeout"
    assert "hf_bake" in str(caught.value)


async def test_a_timed_out_change_names_its_operation_id_and_a_repeat_reuses_it(
    tmp_path,
):
    calls: list[dict] = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        calls.append(request)
        if len(calls) == 1:
            return HOLD
        answer = ok(request)
        answer["replayed"] = True
        return answer

    listener, bridge = await _bridge(tmp_path, responder)
    params = {"size": [1, 1, 1], "position": [0, 0, 0]}
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_place_brush", params, mutating=True, timeout=0.3)
        first_id = caught.value.details["operation_id"]
        assert first_id in str(caught.value)
        again = await bridge.call("hf_place_brush", params, mutating=True, timeout=5)
        other = await bridge.call(
            "hf_place_brush",
            {**params, "position": [9, 0, 0]},
            mutating=True,
            timeout=5,
        )
    finally:
        await bridge.close()
        await listener.stop()
    assert calls[1]["operation_id"] == first_id, "the repeat reuses the id"
    assert again["operation_id"] == first_id
    assert other["operation_id"] != first_id, "a different change gets its own"


async def test_every_change_answer_carries_its_operation_id(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        response = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        status = await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert response["operation_id"] == listener.requests[-2]["operation_id"]
    assert "operation_id" not in status


async def test_an_error_frame_drops_the_connection(tmp_path):
    def responder(request):
        if request["method"] == "hf_get_status" and len(listener.requests) == 1:
            return ok(request)
        if request.get("id") == "boom":
            return None
        error = {"code": "frame_too_large", "message": "too big", "details": {}}
        return {"type": "error", "error": error}

    listener, bridge = await _bridge(tmp_path, responder)
    listener.responder = responder
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert not bridge.connected
    finally:
        await bridge.close()
        await listener.stop()
    assert caught.value.code == "frame_too_large"


async def test_a_cancelled_call_leaves_no_half_read_connection(tmp_path):
    import asyncio

    def responder(request):
        return ok(request) if request["method"] == "hf_get_status" else HOLD

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        task = asyncio.ensure_future(
            bridge.call("hf_place_brush", {}, mutating=True, timeout=30)
        )
        await asyncio.sleep(0.2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert not bridge.connected
    finally:
        await bridge.close()
        await listener.stop()


async def test_a_discovery_file_elsewhere(tmp_path):
    project = make_project(tmp_path / "project")
    listener = await FakeListener(project).start()
    moved = tmp_path / "elsewhere.json"
    discovery_path(project).rename(moved)
    bridge = Bridge(project, discovery=moved, client_version="test")
    try:
        response = await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert response["ok"] is True
