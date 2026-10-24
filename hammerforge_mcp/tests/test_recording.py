import json

import pytest
from mcp import Client

from hammerforge_mcp.bridge import Bridge, BridgeError
from hammerforge_mcp.recording import Recorder, read_recording, scrub
from hammerforge_mcp.replay import ReplayError, replay, to_batch
from hammerforge_mcp.server import build_server
from hammerforge_mcp.server import main as server_main

from .conftest import TOKEN, FakeListener, failed, make_project, ok

pytestmark = pytest.mark.anyio


BATCH_ANSWER = {
    "results": [
        {"tool": "hf_place_brush", "result": {"brush": {"brush_id": "brush_2"}}},
        {"tool": "hf_resize_brush", "result": {"brush": {"brush_id": "brush_2"}}},
    ]
}


def _responder(request):
    if request["method"] == "hf_place_brush":
        return ok(request, {"brush": {"brush_id": "brush_1"}})
    if request["method"] == "hf_transform_brush":
        return ok(request, {"brush": {"brush_id": "brush_1"}})
    if request["method"] == "hf_batch":
        return ok(request, BATCH_ANSWER)
    if request["method"] == "hf_delete_brush":
        return failed(request, "brush_not_found")
    return ok(request)


async def _record(tmp_path, calls):
    project = make_project(tmp_path)
    listener = await FakeListener(project, _responder).start()
    bridge = Bridge(project, client_version="test")
    path = tmp_path / "session.jsonl"
    recorder = Recorder(path)
    try:
        async with Client(build_server(bridge, recorder)) as client:
            for tool, params in calls:
                await client.call_tool(tool, params)
    finally:
        recorder.close()
        await bridge.close()
        await listener.stop()
    return path


async def test_each_call_is_one_json_line_with_its_outcome(tmp_path):
    path = await _record(
        tmp_path,
        [
            ("hf_get_status", {}),
            ("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}),
            ("hf_delete_brush", {"brush_id": "gone"}),
        ],
    )
    status, placed, refused = read_recording(path)
    assert [line["n"] for line in (status, placed, refused)] == [0, 1, 2]
    assert status["tool"] == "hf_get_status" and status["read_only"]
    assert placed["tool"] == "hf_place_brush" and not placed["read_only"]
    # What went to the editor, defaults and all.
    assert placed["params"]["size"] == [1.0, 1.0, 1.0]
    assert placed["params"]["shape"] == "box"
    assert placed["ok"] and placed["error"] is None
    assert placed["made"] == ["brush_1"]
    assert placed["revision_before"] == 5 and placed["revision_after"] == 5
    assert isinstance(placed["ms"], float)
    assert not refused["ok"] and refused["error"] == "brush_not_found"


async def test_a_moved_brush_is_changed_and_a_batch_keeps_what_each_op_made(
    tmp_path,
):
    ops = [
        {
            "tool": "hf_place_brush",
            "params": {"size": [1, 1, 1], "position": [0, 0, 0]},
        },
        {
            "tool": "hf_resize_brush",
            "params": {"brush_id": "$0.brush_id", "size": [2, 1, 1]},
        },
    ]
    path = await _record(
        tmp_path,
        [
            ("hf_transform_brush", {"brush_id": "brush_1", "position": [1, 0, 0]}),
            ("hf_batch", {"ops": ops}),
        ],
    )
    moved, batch = read_recording(path)
    assert moved["made"] == [] and moved["changed"] == ["brush_1"]
    assert batch["made"] == ["brush_2"] and batch["changed"] == ["brush_2"]
    assert batch["op_made"] == [["brush_2"], []]


async def test_the_recording_never_holds_the_token(tmp_path):
    path = await _record(
        tmp_path,
        [
            ("hf_get_status", {}),
            ("hf_place_brush", {"size": [1, 1, 1], "position": [0, 0, 0]}),
        ],
    )
    assert TOKEN not in path.read_text(encoding="utf-8")


def test_a_param_that_looks_like_a_secret_is_left_out():
    params = {"name": "door", "Token": "x", "inner": [{"password": "y", "keep": 1}]}
    assert scrub(params) == {"name": "door", "inner": [{"keep": 1}]}


async def test_a_call_the_bridge_could_not_answer_is_recorded_with_its_code(
    tmp_path,
):
    class Gone:
        async def call(self, method, params, *, mutating, timeout, operation_id=None):
            raise BridgeError("timeout", "the editor did not answer")

    path = tmp_path / "session.jsonl"
    recorder = Recorder(path)
    async with Client(build_server(Gone(), recorder)) as client:
        await client.call_tool("hf_undo", {})
    recorder.close()
    (line,) = read_recording(path)
    assert line["tool"] == "hf_undo" and not line["ok"]
    assert line["error"] == "timeout" and "made" not in line


class ScriptedBridge:
    """Answers each change in turn from `answers`, and keeps what it was sent."""

    def __init__(self, *answers: dict) -> None:
        self.answers = list(answers)
        self.sent: list[tuple[str, dict]] = []

    async def call(self, method, params, *, mutating, timeout, operation_id=None):
        assert mutating, method
        self.sent.append((method, params))
        return self.answers.pop(0)


def _answer(result=None, *, code=None):
    request = {"id": "r"}
    return failed(request, code) if code else ok(request, result or {})


def _line(n, tool, params=None, *, made=(), changed=(), error=None, read=False):
    return {
        "n": n,
        "tool": tool,
        "params": params or {},
        "read_only": read,
        "ok": error is None,
        "error": error,
        "revision_before": n,
        "revision_after": n if read or error else n + 1,
        "ms": 1.0,
        "made": list(made),
        "changed": list(changed),
        "removed": [],
    }


async def test_replay_starts_a_starter_level_and_aims_at_the_brushes_it_made():
    calls = [
        _line(0, "hf_get_status", read=True),
        _line(1, "hf_place_brush", {"size": [1, 1, 1]}, made=["brush_1"]),
        _line(2, "hf_transform_brush", {"brush_id": "brush_1"}, changed=["brush_1"]),
    ]
    bridge = ScriptedBridge(
        _answer(),
        _answer({"brush": {"brush_id": "brush_9"}}),
        _answer({"changed": ["brush_9"]}),
    )
    report = await replay(bridge, calls)
    assert [tool for tool, _ in bridge.sent] == [
        "hf_create_starter",
        "hf_place_brush",
        "hf_transform_brush",
    ]
    assert bridge.sent[2][1] == {"brush_id": "brush_9"}
    assert report.sent == 2 and report.differences == []


async def test_replay_names_the_first_call_that_differs_and_both_outcomes():
    calls = [
        _line(0, "hf_place_brush", made=["brush_1"]),
        _line(1, "hf_delete_brush", {"brush_id": "brush_1"}),
        _line(2, "hf_place_brush", made=["brush_2"]),
    ]
    bridge = ScriptedBridge(
        _answer(),
        _answer({"brush": {"brush_id": "brush_1"}}),
        _answer(code="brush_not_found"),
    )
    report = await replay(bridge, calls)
    (difference,) = report.differences
    assert difference.n == 1 and difference.tool == "hf_delete_brush"
    text = difference.describe()
    assert "call 1 (hf_delete_brush) differs" in text
    assert "recorded: ok, made 0" in text
    assert "replayed: refused: brush_not_found" in text
    assert report.sent == 2


async def test_keep_going_reports_every_difference_and_until_stops_early():
    calls = [
        _line(0, "hf_place_brush", made=["brush_1"]),
        _line(1, "hf_place_brush", made=["brush_2"]),
        _line(2, "hf_place_brush", made=["brush_3"]),
    ]
    refusals = [_answer(code="invalid_argument") for _ in range(3)]
    report = await replay(ScriptedBridge(_answer(), *refusals), calls, keep_going=True)
    assert [d.n for d in report.differences] == [0, 1, 2]
    bridge = ScriptedBridge(_answer(), *refusals)
    report = await replay(bridge, calls, until=1, keep_going=True)
    assert report.sent == 2 and len(bridge.sent) == 3


async def test_a_level_open_already_stops_the_replay_before_any_change():
    bridge = ScriptedBridge(_answer(code="level_exists"))
    with pytest.raises(ReplayError, match="--here"):
        await replay(bridge, [_line(0, "hf_place_brush", made=["brush_1"])])
    assert len(bridge.sent) == 1


async def test_here_plays_onto_the_open_level_and_a_recorded_starter_is_not_doubled():
    placed = _line(1, "hf_place_brush", made=["brush_1"])
    bridge = ScriptedBridge(_answer({"brush": {"brush_id": "brush_1"}}))
    await replay(bridge, [placed], here=True)
    assert [tool for tool, _ in bridge.sent] == ["hf_place_brush"]
    bridge = ScriptedBridge(_answer(), _answer({"brush": {"brush_id": "brush_1"}}))
    await replay(bridge, [_line(0, "hf_create_starter"), placed])
    assert [tool for tool, _ in bridge.sent] == ["hf_create_starter", "hf_place_brush"]


def test_to_batch_joins_changes_and_names_a_brush_by_the_op_that_made_it():
    calls = [
        _line(0, "hf_create_starter"),
        _line(1, "hf_get_brushes", read=True),
        _line(2, "hf_place_brush", {"size": [2, 2, 2]}, made=["brush_1"]),
        _line(3, "hf_resize_brush", {"brush_id": "brush_1"}, changed=["brush_1"]),
        _line(4, "hf_delete_brush", {"brush_id": "nope"}, error="brush_not_found"),
        _line(5, "hf_bake"),
    ]
    assert to_batch(calls) == [
        {"tool": "hf_create_starter", "params": {}},
        {
            "tool": "hf_batch",
            "params": {
                "ops": [
                    {"tool": "hf_place_brush", "params": {"size": [2, 2, 2]}},
                    {"tool": "hf_resize_brush", "params": {"brush_id": "$0.brush_id"}},
                ]
            },
            "recorded_made": ["brush_1"],
        },
    ]


def test_to_batch_leaves_out_what_an_undo_took_back_and_keeps_a_redo():
    calls = [
        _line(0, "hf_place_brush", {"at": 0}, made=["brush_1"]),
        _line(1, "hf_place_brush", {"at": 1}, made=["brush_2"]),
        _line(2, "hf_undo"),
        _line(3, "hf_place_brush", {"at": 3}, made=["brush_3"]),
        _line(4, "hf_undo"),
        _line(5, "hf_redo"),
        _line(6, "hf_undo", error="nothing_to_undo"),
    ]
    (line,) = to_batch(calls)
    assert [op["params"]["at"] for op in line["params"]["ops"]] == [0, 3]
    assert line["recorded_made"] == ["brush_1", "brush_3"]


def test_to_batch_moves_a_recorded_batch_references_and_splits_at_the_limit():
    batch = {
        "ops": [
            {"tool": "hf_place_brush", "params": {}},
            {"tool": "hf_resize_brush", "params": {"brush_id": "$0.brush_id"}},
        ]
    }
    calls = [
        _line(0, "hf_place_brush", made=["brush_1"]),
        dict(_line(1, "hf_batch", batch, made=["brush_2"]), op_made=[["brush_2"], []]),
        _line(2, "hf_transform_brush", {"brush_id": "brush_2"}, changed=["brush_2"]),
    ]
    (line,) = to_batch(calls)
    assert [op["params"] for op in line["params"]["ops"][1:]] == [
        {},
        {"brush_id": "$1.brush_id"},
        {"brush_id": "$1.brush_id"},
    ]
    many = [_line(n, "hf_set_spawn", {"position": [n, 0, 0]}) for n in range(150)]
    sizes = [len(line["params"]["ops"]) for line in to_batch(many)]
    assert sizes == [100, 50]


async def test_replay_aims_a_later_payload_at_the_brush_an_earlier_one_made():
    lines = [
        {
            "tool": "hf_batch",
            "params": {"ops": [{"tool": "hf_place_brush", "params": {}}]},
            "recorded_made": ["brush_1"],
        },
        {
            "tool": "hf_batch",
            "params": {
                "ops": [{"tool": "hf_delete_brush", "params": {"brush_id": "brush_1"}}]
            },
            "recorded_made": [],
        },
    ]
    placed = {
        "results": [
            {"tool": "hf_place_brush", "result": BATCH_ANSWER["results"][0]["result"]}
        ]
    }
    bridge = ScriptedBridge(_answer(), _answer(placed), _answer())
    report = await replay(bridge, lines)
    assert bridge.sent[2][1]["ops"][0]["params"] == {"brush_id": "brush_2"}
    assert report.sent == 2 and report.differences == []
    # Every change in a batch file was ok in the session, so a refusal differs.
    bridge = ScriptedBridge(_answer(), _answer(code="batch_failed"))
    report = await replay(bridge, lines[:1])
    (difference,) = report.differences
    assert "replayed: refused: batch_failed" in difference.describe()


def test_replay_to_batch_from_the_command_line_writes_lines_replay_reads(tmp_path):
    recording = tmp_path / "session.jsonl"
    recording.write_text(
        json.dumps(_line(0, "hf_place_brush", made=["brush_1"])) + "\n",
        encoding="utf-8",
    )
    out = tmp_path / "batch.jsonl"
    assert server_main(["replay", str(recording), "--to-batch", str(out)]) == 0
    (line,) = read_recording(out)
    assert line["tool"] == "hf_batch"
