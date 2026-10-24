"""Record a bridge session as one JSON line per call, to play back later (#1645).

A text log is for reading. A bug an agent ran into 80 calls into a session needs
all 80 calls exactly, and the same list makes a regression test. `--record`
writes each call the server relays: the tool, its params, whether it was a change
or a read, ok or the error code, the revision before and after, how long it took,
and the ids it made, changed and removed (for a batch, the ids each op made as
well). Brush ids carry a clock reading, so a replay's are not the recording's,
and these lists are what let `replay` aim a later call at the brush the replay
made rather than the one the recording did.

The bridge's token is never written. It travels in the connection's hello and
never in a call's params, and a param that looks like a secret is dropped as
well, so a recording can be attached to a bug report as it is.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

#: Params never written, whatever tool they come with.
SECRET_KEYS = frozenset({"token", "auth", "authorization", "password", "secret"})


class Recorder:
    """Appends one JSON line per relayed call to `path`."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = self.path.open("w", encoding="utf-8")
        self._count = 0
        #: The revision the last answer named, the "before" of the next call.
        self.revision: int | None = None

    def write(
        self,
        tool: str,
        params: dict,
        *,
        mutating: bool,
        response: dict | None,
        error: str | None,
        took_ms: float,
    ) -> dict:
        """Write one call and return the line written."""
        line: dict[str, Any] = {
            "n": self._count,
            "tool": tool,
            "params": scrub(params),
            "read_only": not mutating,
            "ok": bool(response and response.get("ok")),
            "error": error,
            "revision_before": self.revision,
            "revision_after": None,
            "ms": round(took_ms, 1),
        }
        if response is not None:
            line["revision_after"] = response.get("revision")
            if not line["ok"] and error is None:
                line["error"] = (response.get("error") or {}).get("code")
            result = response.get("result") or {}
            line.update(outcome_ids(result, tool))
            if tool == "hf_batch":
                line["op_made"] = ops_made(result)
            if response.get("revision") is not None:
                self.revision = response.get("revision")
        self._file.write(json.dumps(line, sort_keys=True) + "\n")
        self._file.flush()
        self._count += 1
        return line

    def close(self) -> None:
        self._file.close()


def scrub(params: Any) -> Any:
    """`params` with any key that looks like a secret left out, at any depth."""
    if isinstance(params, dict):
        return {
            key: scrub(value)
            for key, value in params.items()
            if str(key).lower() not in SECRET_KEYS
        }
    if isinstance(params, list):
        return [scrub(value) for value in params]
    return params


#: The changes whose answer's `brush` or `entity` is one they made. Any other
#: change that answers with one changed it.
MAKES = frozenset({"hf_place_brush", "hf_place_entity"})


def outcome_ids(result: dict, tool: str) -> dict:
    """The ids a change's answer made, changed and removed, in answer order.

    A placed brush is `result.brush`, a command's pieces are `result.made`, a
    batch's are in each op's result, and an entity is named by its path.
    """
    made: list[str] = []
    changed: list[str] = []
    removed: list[str] = []
    _collect(result, tool, made, changed, removed)
    return {"made": made, "changed": changed, "removed": removed}


def ops_made(result: dict) -> list[list[str]]:
    """For a batch's answer, the ids each op made, op by op."""
    return [
        outcome_ids(op.get("result") or {}, str(op.get("tool", "")))["made"]
        for op in result.get("results") or []
        if isinstance(op, dict)
    ]


def _collect(result: Any, tool: str, made: list, changed: list, removed: list) -> None:
    if not isinstance(result, dict):
        return
    for op in result.get("results") or []:
        if isinstance(op, dict):
            inner = op.get("result") or {}
            _collect(inner, str(op.get("tool", "")), made, changed, removed)
    pieces = result.get("made")
    if isinstance(pieces, list):
        for piece in pieces:
            _add(made, _id_of(piece))
    else:
        into = made if tool in MAKES else changed
        brush = result.get("brush")
        if isinstance(brush, dict):
            _add(into, brush.get("brush_id"))
        entity = result.get("entity")
        if isinstance(entity, dict):
            _add(into, entity.get("entity"))
    for path in result.get("entities_made") or []:
        _add(made, path)
    for item in result.get("changed") or []:
        _add(changed, _id_of(item))
    for item in result.get("removed") or []:
        _add(removed, _id_of(item))
    for path in result.get("entities_removed") or []:
        _add(removed, path)
    deleted = result.get("deleted")
    if isinstance(deleted, str):
        _add(removed, deleted)


def _id_of(item: Any) -> Any:
    return item.get("brush_id") if isinstance(item, dict) else item


def _add(into: list, value: Any) -> None:
    if isinstance(value, str) and value and value not in into:
        into.append(value)


def read_recording(path: Path) -> list[dict]:
    """The calls a recording holds, in order. A blank line is skipped."""
    calls: list[dict] = []
    for number, text in enumerate(Path(path).read_text(encoding="utf-8").splitlines()):
        if text.strip():
            try:
                calls.append(json.loads(text))
            except json.JSONDecodeError as exc:
                raise ValueError(f"line {number + 1} is not JSON: {exc}") from exc
    return calls


def now_ms() -> float:
    return time.monotonic() * 1000.0
