"""Play a recorded bridge session back against the open editor (#1645).

    python -m hammerforge_mcp replay session.jsonl [--until N] [--keep-going]
    python -m hammerforge_mcp replay session.jsonl --to-batch batch.jsonl

The changes a recording holds are sent again, in order; the reads are skipped.
A replay starts from a new starter level, so the open scene must have no level
yet, unless the recording made its own or `--here` says to play onto the level
that is open. Each call's outcome is held against the recorded one: ok or
refused, the error code, and the ids made, changed and removed. The first that
differs stops the replay and is printed with both outcomes; `--keep-going` goes
on and prints them all.

Brush ids carry a clock reading, so a brush a replay makes does not get the id
the recorded one had, and a later call that named the recorded id is sent the
replay's. Ids are matched up in answer order, the way `recording.outcome_ids`
lists them.

`--to-batch` writes the changes that built the session's level as `hf_batch`
payloads of up to 100 ops, one JSON line each, for a test to send. A refused
change, a change an undo took back and that undo, and a bake are left out; a
redone change is kept and the redo left out. Within a payload, an op names a
brush or entity an earlier op placed as "$N.brush_id" or "$N.entity", so it
works on a level whose ids are new. A payload past the first 100 ops names one
from an earlier payload by its recorded id, and each line keeps the ids its ops
made in the recording, so `replay` plays the file back as well.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from hammerforge_mcp.bridge import Bridge, BridgeError
from hammerforge_mcp.catalogue import TOOLS
from hammerforge_mcp.recording import outcome_ids, read_recording

#: The most ops one hf_batch takes, as the dispatcher's BATCH_LIMIT.
BATCH_LIMIT = 100
STARTER = "hf_create_starter"
#: The changes whose answer a later op in the same batch can name, and how: the
#: dispatcher's BATCH_REFS.
MADE_REF = {"hf_place_brush": "brush_id", "hf_place_entity": "entity"}
#: Changes that build nothing a batch file needs: a bake writes the level out,
#: and an undo or a redo is folded into what it took back or put back.
NOT_KEPT = frozenset({"hf_bake", "hf_undo", "hf_redo"})

_REF = re.compile(r"^\$(\d+)\.(\w+)$")


class ReplayError(Exception):
    """The replay could not go on: no editor, or a level open already."""


@dataclass
class Difference:
    n: int
    tool: str
    recorded: dict
    replayed: dict

    def describe(self) -> str:
        return (
            f"call {self.n} ({self.tool}) differs:\n"
            f"  recorded: {_outcome_text(self.recorded)}\n"
            f"  replayed: {_outcome_text(self.replayed)}"
        )


@dataclass
class Report:
    sent: int = 0
    differences: list[Difference] = field(default_factory=list)


def changes_of(calls: list[dict], until: int | None = None) -> list[dict]:
    """The recorded calls that change the level, up to and with call `until`."""
    picked = []
    for index, call in enumerate(calls):
        number = int(call.get("n", index))
        if until is not None and number > until:
            break
        if not call.get("read_only") and call.get("tool") in TOOLS:
            picked.append(dict(call, n=number))
    return picked


async def replay(
    bridge: Any,
    calls: list[dict],
    *,
    until: int | None = None,
    keep_going: bool = False,
    here: bool = False,
) -> Report:
    """Send the recording's changes through `bridge` and hold each against it."""
    changes = changes_of(calls, until)
    report = Report()
    if not here and not (changes and changes[0]["tool"] == STARTER):
        answer = await _send(bridge, STARTER, {})
        if not answer.get("ok"):
            code = (answer.get("error") or {}).get("code")
            raise ReplayError(
                f"could not make a starter level ({code}). Open a new empty scene, "
                "or pass --here to play onto the level that is open"
            )
    ids: dict[str, str] = {}
    for call in changes:
        tool = call["tool"]
        params = _mapped(call.get("params") or {}, ids)
        try:
            answer = await _send(bridge, tool, params)
        except BridgeError as exc:
            raise ReplayError(f"call {call['n']} ({tool}): {exc}") from exc
        report.sent += 1
        got = _outcome(answer, tool)
        recorded_made = call.get("made", call.get("recorded_made", []))
        for recorded, replayed in zip(recorded_made, got["made"], strict=False):
            ids[recorded] = replayed
        if "ok" not in call:
            # A line from --to-batch, made only of changes that were ok.
            if not got["ok"]:
                wanted = {"ok": True, "error": None, "made": len(recorded_made)}
                seen = dict(got, made=len(got["made"]))
                report.differences.append(
                    Difference(
                        call["n"], tool, dict(wanted, changed=[], removed=[]), seen
                    )
                )
                if not keep_going:
                    break
            continue
        if "made" not in call:
            # A call the recording got no answer to.
            continue
        wanted = {
            "ok": bool(call["ok"]),
            "error": None if call["ok"] else call.get("error"),
            "made": len(call["made"]),
            "changed": [ids.get(i, i) for i in call.get("changed") or []],
            "removed": [ids.get(i, i) for i in call.get("removed") or []],
        }
        seen = dict(got, made=len(got["made"]))
        if wanted != seen:
            report.differences.append(Difference(call["n"], tool, wanted, seen))
            if not keep_going:
                break
    return report


async def _send(bridge: Any, tool: str, params: dict) -> dict:
    spec = TOOLS[tool]
    return await bridge.call(tool, params, mutating=True, timeout=spec.timeout)


def _outcome(answer: dict, tool: str) -> dict:
    """What a call's answer says happened."""
    ok = bool(answer.get("ok"))
    code = (answer.get("error") or {}).get("code")
    return {
        "ok": ok,
        "error": None if ok else code,
        **outcome_ids(answer.get("result") or {}, tool),
    }


def _outcome_text(outcome: dict) -> str:
    if not outcome["ok"]:
        return f"refused: {outcome['error']}"
    parts = [f"ok, made {outcome['made']}"]
    for key in ("changed", "removed"):
        if outcome[key]:
            parts.append(f"{key} {', '.join(outcome[key])}")
    return "; ".join(parts)


def _mapped(value: Any, ids: dict[str, str]) -> Any:
    """`value` with every recorded id that has a stand-in swapped for it."""
    if isinstance(value, str):
        return ids.get(value, value)
    if isinstance(value, dict):
        return {key: _mapped(inner, ids) for key, inner in value.items()}
    if isinstance(value, list):
        return [_mapped(inner, ids) for inner in value]
    return value


def kept_changes(calls: list[dict], until: int | None = None) -> list[dict]:
    """The recorded changes that built the level the session ended with.

    The undo history is walked as the session walked it: a change that moved
    the revision is a step, an undo takes the last step off and a redo puts it
    back, and a new step drops whatever was waiting to be redone. A refused
    change, and one that changed nothing, made no step.
    """
    done: list[dict] = []
    redo: list[dict] = []
    for call in changes_of(calls, until):
        if call.get("ok") is False:
            continue
        tool = call["tool"]
        if tool == "hf_undo":
            if done:
                redo.append(done.pop())
        elif tool == "hf_redo":
            if redo:
                done.append(redo.pop())
        elif tool not in NOT_KEPT and _made_a_step(call):
            done.append(call)
            redo.clear()
    return done


def _made_a_step(call: dict) -> bool:
    before, after = call.get("revision_before"), call.get("revision_after")
    return before is None or after is None or before != after


def to_batch(calls: list[dict], *, until: int | None = None) -> list[dict]:
    """The changes that built the session's level as calls of up to BATCH_LIMIT
    ops each, a starter level on a line of its own."""
    out: list[dict] = []
    ops: list[dict] = []
    made: list[list[str]] = []
    #: An id an op in this payload placed -> the "$N.<ref>" a later op names it by.
    refs: dict[str, str] = {}

    def flush() -> None:
        if ops:
            flat = [i for each in made for i in each]
            out.append(
                {
                    "tool": "hf_batch",
                    "params": {"ops": list(ops)},
                    "recorded_made": list(dict.fromkeys(flat)),
                }
            )
            ops.clear()
            made.clear()
            refs.clear()

    for call in kept_changes(calls, until):
        tool, params = call["tool"], call.get("params") or {}
        if tool == STARTER:
            flush()
            out.append({"tool": tool, "params": params})
            continue
        if tool == "hf_batch":
            inner = params.get("ops") or []
            inner_made = call.get("op_made") or [[] for _ in inner]
        else:
            inner = [{"tool": tool, "params": params}]
            inner_made = [call.get("made") or []]
        if len(ops) + len(inner) > BATCH_LIMIT:
            flush()
        offset = len(ops)
        for index, op in enumerate(inner):
            op_params = _mapped(_shifted(op.get("params") or {}, offset), refs)
            ops.append({"tool": op["tool"], "params": op_params})
            op_made = inner_made[index] if index < len(inner_made) else []
            made.append(op_made)
            if op["tool"] in MADE_REF and len(op_made) == 1:
                refs[op_made[0]] = f"${offset + index}.{MADE_REF[op['tool']]}"
    flush()
    return out


def _shifted(value: Any, offset: int) -> Any:
    """A batch op's params with each "$N.<ref>" moved on by `offset` ops."""
    if isinstance(value, str):
        found = _REF.match(value)
        if found and offset:
            return f"${int(found.group(1)) + offset}.{found.group(2)}"
        return value
    if isinstance(value, dict):
        return {key: _shifted(inner, offset) for key, inner in value.items()}
    if isinstance(value, list):
        return [_shifted(inner, offset) for inner in value]
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="hammerforge-mcp replay",
        description="Play a session recorded with --record back against the editor.",
    )
    parser.add_argument("recording", type=Path, help="the .jsonl --record wrote")
    parser.add_argument(
        "--project",
        type=Path,
        default=Path(os.environ.get("HAMMERFORGE_PROJECT") or Path.cwd()),
        help="the Godot project folder, the one with project.godot in it",
    )
    parser.add_argument(
        "--discovery",
        type=Path,
        default=os.environ.get("HAMMERFORGE_MCP_DISCOVERY") or None,
        help="the bridge's discovery file, when it is not the project's own",
    )
    parser.add_argument("--until", type=int, help="stop after recorded call N")
    parser.add_argument(
        "--keep-going", action="store_true", help="report every difference"
    )
    parser.add_argument(
        "--here",
        action="store_true",
        help="play onto the level that is open instead of a new starter level",
    )
    parser.add_argument(
        "--to-batch",
        type=Path,
        metavar="FILE",
        help="write the changes as hf_batch payloads to FILE and send nothing",
    )
    args = parser.parse_args(argv)
    try:
        calls = read_recording(args.recording)
    except (OSError, ValueError) as exc:
        print(f"replay: {args.recording}: {exc}", file=sys.stderr)
        return 2

    if args.to_batch:
        lines = to_batch(calls, until=args.until)
        args.to_batch.write_text(
            "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines),
            encoding="utf-8",
        )
        print(f"replay: wrote {len(lines)} calls to {args.to_batch}")
        return 0

    async def run() -> Report:
        bridge = Bridge(args.project, discovery=args.discovery)
        try:
            return await replay(
                bridge,
                calls,
                until=args.until,
                keep_going=args.keep_going,
                here=args.here,
            )
        finally:
            await bridge.close()

    try:
        report = asyncio.run(run())
    except (BridgeError, ReplayError) as exc:
        print(f"replay: {exc}", file=sys.stderr)
        return 2
    for difference in report.differences:
        print(difference.describe())
    count = len(report.differences)
    print(
        f"replay: sent {report.sent} changes, "
        f"{count or 'no'} difference{'' if count == 1 else 's'}"
    )
    return 1 if report.differences else 0
