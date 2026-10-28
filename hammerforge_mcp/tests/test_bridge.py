import asyncio
from unittest.mock import AsyncMock

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


async def test_a_cancelled_call_leaves_the_connection_usable(tmp_path):
    import asyncio

    def responder(request):
        if request["method"] == "hf_place_brush":
            return HOLD
        return ok(request)

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
        after = await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert after["ok"] is True
    assert listener.connections == 1, "the same connection carried on"


async def test_status_answers_while_a_change_is_still_running(tmp_path):
    import asyncio

    def responder(request):
        return HOLD if request["method"] == "hf_bake" else ok(request)

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        bake = asyncio.ensure_future(
            bridge.call("hf_bake", {}, mutating=True, timeout=30)
        )
        await asyncio.sleep(0.1)
        status = await asyncio.wait_for(
            bridge.call("hf_get_status", {}, mutating=False, timeout=5), 2
        )
        assert status["ok"] is True
        assert not bake.done(), "the bake is still waiting"
        bake.cancel()
        with pytest.raises(asyncio.CancelledError):
            await bake
    finally:
        await bridge.close()
        await listener.stop()


async def test_answers_that_arrive_out_of_order_reach_their_own_callers(tmp_path):
    import asyncio

    held: list[dict] = []

    def responder(request):
        if request["method"] == "hf_get_status" and not held:
            return ok(request)
        if not held:
            held.append(request)
            return HOLD
        first = ok(held[0], {"which": held[0]["params"]["which"]})
        second = ok(request, {"which": request["params"]["which"]})
        return [second, first]

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        a = asyncio.ensure_future(
            bridge.call("hf_get_brushes", {"which": "a"}, mutating=False, timeout=5)
        )
        await asyncio.sleep(0.1)
        b = await bridge.call(
            "hf_get_brushes", {"which": "b"}, mutating=False, timeout=5
        )
        a = await a
    finally:
        await bridge.close()
        await listener.stop()
    assert a["result"]["which"] == "a"
    assert b["result"]["which"] == "b"


async def test_a_lost_connection_retries_every_waiting_change(tmp_path):
    import asyncio

    seen: list[dict] = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        seen.append(request)
        if listener.connections == 1:
            # Hold the first change; the second closes the connection.
            return HOLD if len(seen) == 1 else None
        return ok(request, {"op": request["operation_id"]})

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        first = asyncio.ensure_future(
            bridge.call(
                "hf_place_brush",
                {"n": 1},
                mutating=True,
                timeout=5,
                operation_id="op-a",
            )
        )
        await asyncio.sleep(0.1)
        second = await bridge.call(
            "hf_place_brush", {"n": 2}, mutating=True, timeout=5, operation_id="op-b"
        )
        first = await first
    finally:
        await bridge.close()
        await listener.stop()
    assert first["result"]["op"] == "op-a"
    assert second["result"]["op"] == "op-b"
    assert listener.connections == 2


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


@pytest.mark.parametrize("method", ["hf_undo", "hf_redo", "hf_bake"])
async def test_a_repeat_of_a_change_its_arguments_do_not_name_gets_a_new_id(
    tmp_path, method
):
    calls: list[dict] = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        calls.append(request)
        return HOLD if len(calls) == 1 else ok(request)

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call(method, {}, mutating=True, timeout=0.3)
        first_id = caught.value.details["operation_id"]
        assert first_id in str(caught.value), "the id is there to retry with"
        await bridge.call(method, {}, mutating=True, timeout=5)
        await bridge.call(method, {}, mutating=True, timeout=5, operation_id=first_id)
    finally:
        await bridge.close()
        await listener.stop()
    assert calls[1]["operation_id"] != first_id, "a second undo is not a retry"
    assert calls[2]["operation_id"] == first_id, "unless the caller says it is"


async def test_a_call_failed_by_a_drop_before_it_wrote_is_sent_once(tmp_path):
    import asyncio

    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        before = len(listener.requests)
        # Hold the write lock, so the call registers its waiter and then waits
        # to write. Another call drops the connection and opens a new one while
        # it waits: the waiter has already failed, and the new writer is there.
        await bridge._write_lock.acquire()
        task = asyncio.ensure_future(
            bridge.call("hf_get_brushes", {}, mutating=False, timeout=5)
        )
        await asyncio.sleep(0.05)
        await bridge._drop()
        await bridge._ensure_connected()
        bridge._write_lock.release()
        answer = await task
    finally:
        await bridge.close()
        await listener.stop()
    sent = [r for r in listener.requests[before:] if r["method"] == "hf_get_brushes"]
    assert answer["ok"] is True
    assert len(sent) == 1, "the retry sent it; the failed try did not"


async def test_cancelling_a_call_while_it_drops_the_connection_still_cancels(
    tmp_path,
):
    import asyncio

    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        reading = bridge._reading
        # A reader that takes a moment to stop, so the drop is still waiting on
        # it when the cancel lands.
        gate = asyncio.Event()

        async def slow_stop():
            try:
                await reading
            finally:
                await gate.wait()

        bridge._reading = asyncio.ensure_future(slow_stop())
        dropping = asyncio.ensure_future(bridge._drop())
        await asyncio.sleep(0.05)
        dropping.cancel()
        await asyncio.sleep(0)
        gate.set()
        with pytest.raises(asyncio.CancelledError):
            await dropping
    finally:
        await bridge.close()
        await listener.stop()


async def test_a_request_too_big_to_send_leaves_the_connection_up(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        with pytest.raises(BridgeError) as caught:
            await bridge.call(
                "hf_get_brushes", {"pad": "x" * (2 << 20)}, mutating=False, timeout=5
            )
        with pytest.raises(BridgeError) as not_json:
            await bridge.call(
                "hf_get_brushes", {"limit": float("nan")}, mutating=False, timeout=5
            )
        after = await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    finally:
        await bridge.close()
        await listener.stop()
    assert caught.value.code == "frame_too_large"
    assert not_json.value.code == "invalid_argument"
    assert after["ok"] is True
    assert listener.connections == 1, "nothing was sent, so nothing was dropped"
    assert all(r["method"] == "hf_get_status" for r in listener.requests)


async def test_timeout_includes_waiting_to_write_and_does_not_send_later(tmp_path):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        await bridge._write_lock.acquire()
        try:
            with pytest.raises(BridgeError) as caught:
                await asyncio.wait_for(
                    bridge.call("hf_place_brush", {}, mutating=True, timeout=0.05),
                    1,
                )
            assert caught.value.code == "timeout"
        finally:
            bridge._write_lock.release()
        after = await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        assert after["ok"] is True
        assert all(r["method"] == "hf_get_status" for r in listener.requests)
        changed = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert changed["operation_id"] != caught.value.details["operation_id"]
    finally:
        await bridge.close()
        await listener.stop()


async def test_timeout_includes_connecting(tmp_path, monkeypatch):
    bridge = Bridge(make_project(tmp_path), client_version="test")

    async def never_connect():
        await asyncio.Event().wait()

    monkeypatch.setattr(bridge, "_ensure_connected", never_connect)
    with pytest.raises(BridgeError) as caught:
        await asyncio.wait_for(
            bridge.call("hf_get_status", {}, mutating=False, timeout=0.05), 1
        )
    assert caught.value.code == "timeout"
    assert not bridge.connected


async def test_timeout_includes_a_blocked_drain(tmp_path, monkeypatch):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        original = bridge._writer.drain
        monkeypatch.setattr(
            bridge._writer, "drain", AsyncMock(side_effect=asyncio.Event().wait)
        )
        with pytest.raises(BridgeError) as caught:
            await asyncio.wait_for(
                bridge.call("hf_place_brush", {}, mutating=True, timeout=0.05), 1
            )
        assert caught.value.code == "timeout"
        assert caught.value.details["operation_id"]
        monkeypatch.setattr(bridge._writer, "drain", original)
        assert (await bridge.call("hf_get_status", {}, mutating=False, timeout=5))["ok"]
    finally:
        await bridge.close()
        await listener.stop()


async def test_cancelled_change_reuses_its_operation_id_on_retry(tmp_path):
    sent = asyncio.Event()
    changes = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        changes.append(request)
        sent.set()
        return HOLD if len(changes) == 1 else ok(request)

    listener, bridge = await _bridge(tmp_path, responder)
    task = None
    try:
        task = asyncio.create_task(
            bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        )
        await asyncio.wait_for(sent.wait(), 2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        answer = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert answer["operation_id"] == changes[0]["operation_id"]
        assert changes[1]["operation_id"] == changes[0]["operation_id"]
        assert listener.connections == 1
    finally:
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        await bridge.close()
        await listener.stop()


@pytest.mark.parametrize(
    "response",
    [
        {"type": "error", "error": "broken"},
        {"type": "response", "id": None, "ok": True, "result": {}},
        {"type": "response", "id": "r2", "ok": "yes", "result": {}},
        {"type": "response", "id": "r2", "ok": True, "result": []},
        {
            "type": "response",
            "id": "r2",
            "ok": False,
            "error": {"code": "x", "message": "x", "details": []},
        },
        {"type": "surprise"},
        {"revision": None},
        {"revision": -1},
        {"revision": 1.5},
        {"revision": True},
        {"revision": "5"},
        {"target_id": None},
        {"target_id": []},
        {"replayed": "yes"},
    ],
)
async def test_malformed_reply_fails_promptly_and_allows_reconnect(tmp_path, response):
    listener, bridge = await _bridge(tmp_path)
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        listener.responder = lambda request: {**ok(request), **response}
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_place_brush", {}, mutating=True, timeout=0.2)
        assert caught.value.code == "bad_request"
        assert caught.value.details["operation_id"]
        assert not bridge.connected
        listener.responder = lambda request: ok(request)
        assert (await bridge.call("hf_get_status", {}, mutating=False, timeout=5))["ok"]
    finally:
        await bridge.close()
        await listener.stop()


async def test_handshake_socket_closes_when_call_is_cancelled(tmp_path):
    from .conftest import write_discovery

    project = make_project(tmp_path)
    hello_seen, socket_closed = asyncio.Event(), asyncio.Event()
    handlers = []

    async def stalled_hello(reader, writer):
        handlers.append(asyncio.current_task())
        try:
            await reader.read(4096)
            hello_seen.set()
            assert await reader.read() == b""
        finally:
            writer.close()
            socket_closed.set()

    server = await asyncio.start_server(stalled_hello, "127.0.0.1", 0)
    write_discovery(project, server.sockets[0].getsockname()[1])
    bridge = Bridge(project, client_version="test")
    task = asyncio.create_task(
        bridge.call("hf_get_status", {}, mutating=False, timeout=5)
    )
    try:
        await asyncio.wait_for(hello_seen.wait(), 2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        await asyncio.wait_for(socket_closed.wait(), 0.2)
    finally:
        await bridge.close()
        server.close()
        await server.wait_closed()
        for handler in handlers:
            handler.cancel()
        await asyncio.gather(*handlers, return_exceptions=True)


async def test_late_change_reply_does_not_reattach_an_old_target(tmp_path):
    placed = asyncio.Event()
    held = []

    def responder(request):
        if request["method"] == "hf_place_brush":
            held.append(request)
            placed.set()
            return HOLD
        if not held:
            return ok(request)
        return [ok(request, target="9:9:9"), ok(held[0])]

    listener, bridge = await _bridge(tmp_path, responder)
    change = None
    try:
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        change = asyncio.create_task(
            bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        )
        await asyncio.wait_for(placed.wait(), 2)
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        await change
        assert bridge.target_id == "9:9:9"
    finally:
        if change is not None and not change.done():
            change.cancel()
            await asyncio.gather(change, return_exceptions=True)
        await bridge.close()
        await listener.stop()


async def test_reconnect_preserves_the_original_target_of_a_change(tmp_path):
    changes = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        changes.append(request)
        if len(changes) == 1:
            # A concurrent status attached elsewhere before this retry.
            bridge.target_id = "9:9:9"
            return None
        return failed(request, "target_changed", target="9:9:9")

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        answer = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert answer["error"]["code"] == "target_changed"
        assert [r["expect_target"] for r in changes] == ["1:2:3", "1:2:3"]
        assert changes[0]["operation_id"] == changes[1]["operation_id"]
    finally:
        await bridge.close()
        await listener.stop()


async def test_automatic_retry_ids_do_not_cross_targets(tmp_path):
    changes = []
    target = "1:2:3"

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request, target=target)
        changes.append(request)
        return HOLD if len(changes) == 1 else ok(request, target=target)

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        with pytest.raises(BridgeError):
            await bridge.call("hf_place_brush", {}, mutating=True, timeout=0.05)
        target = "9:9:9"
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert changes[0]["operation_id"] != changes[1]["operation_id"]
        assert changes[1]["expect_target"] == target
    finally:
        await bridge.close()
        await listener.stop()


async def test_connection_error_reports_each_waiting_changes_own_id(tmp_path):
    first_sent = asyncio.Event()
    changes = []

    def responder(request):
        if request["method"] == "hf_get_status":
            return ok(request)
        changes.append(request)
        if len(changes) == 1:
            first_sent.set()
            return HOLD
        return {"type": "error", "error": {"code": "bad_request", "message": "no"}}

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        first = asyncio.create_task(
            bridge.call(
                "hf_place_brush",
                {"n": 1},
                mutating=True,
                timeout=5,
                operation_id="first",
            )
        )
        await asyncio.wait_for(first_sent.wait(), 2)
        second = bridge.call(
            "hf_place_brush", {"n": 2}, mutating=True, timeout=5, operation_id="second"
        )
        results = await asyncio.gather(first, second, return_exceptions=True)
        assert all(isinstance(r, BridgeError) for r in results)
        assert [r.details["operation_id"] for r in results] == ["first", "second"]
    finally:
        await bridge.close()
        await listener.stop()


@pytest.mark.parametrize(
    ("welcome", "code"),
    [
        ({"type": "welcome", "bridge_version": 2}, "unsupported_bridge_version"),
        ({"type": "welcome", "bridge_version": True}, "unsupported_bridge_version"),
        ({"type": "error", "error": "bad"}, "bad_request"),
        ({"type": "unknown"}, "bad_request"),
        (b"\x00\x00\x00\x01\xff", "bad_request"),
        (b"\x7f\xff\xff\xff", "frame_too_large"),
    ],
)
async def test_refused_or_malformed_handshake_closes_its_socket(
    tmp_path, welcome, code
):
    listener, bridge = await _bridge(tmp_path)
    listener.welcome = welcome
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        assert caught.value.code == code
        await asyncio.wait_for(listener.disconnected.wait(), 2)
        assert not bridge.connected
    finally:
        await bridge.close()
        await listener.stop()


async def test_attach_timeout_sends_no_change(tmp_path):
    listener, bridge = await _bridge(tmp_path, lambda request: HOLD)
    try:
        with pytest.raises(BridgeError) as caught:
            await bridge.call("hf_place_brush", {}, mutating=True, timeout=0.05)
        assert caught.value.code == "timeout"
        assert [r["method"] for r in listener.requests] == ["hf_get_status"]
        listener.responder = lambda request: ok(request)
        answer = await bridge.call("hf_place_brush", {}, mutating=True, timeout=5)
        assert answer["operation_id"] != caught.value.details["operation_id"]
    finally:
        await bridge.close()
        await listener.stop()


async def test_late_status_answer_cannot_replace_a_newer_status_target(tmp_path):
    first_sent = asyncio.Event()
    held = []

    def responder(request):
        if not held:
            held.append(request)
            first_sent.set()
            return HOLD
        return [ok(request, target="9:9:9"), ok(held[0])]

    listener, bridge = await _bridge(tmp_path, responder)
    try:
        first = asyncio.create_task(
            bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        )
        await asyncio.wait_for(first_sent.wait(), 2)
        await bridge.call("hf_get_status", {}, mutating=False, timeout=5)
        await first
        assert bridge.target_id == "9:9:9"
    finally:
        await bridge.close()
        await listener.stop()
