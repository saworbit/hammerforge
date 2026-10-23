"""Each example prompt's tool sequence in a windowed editor, with its pictures."""

import json
import re

DESCRIPTION = (
    "the example prompts, run as an agent reads them, with screenshots to look at"
)
START_SCENE = "level"
WINDOWED = True


def _ops(text: str) -> list[dict]:
    """The batch a literal agent builds from the room prompt's op lines."""
    ops = []
    for line in text.splitlines():
        found = re.match(r"\s+- [^:]+: (hf_\w+)(.*)$", line)
        if not found:
            continue
        tool, rest = found.groups()
        params: dict = {}
        operation = re.search(r"operation (\w+)", rest)
        if operation:
            params["operation"] = operation.group(1)
        for key, vec in re.findall(r"(size|position) (\[[^\]]+\])", rest):
            params[key] = json.loads(vec)
        if "snap false" in rest:
            params["snap"] = False
        ops.append({"tool": tool, "params": params})
    return ops


async def run(v):
    status = await v.call("hf_get_status")
    v.expect(status.get("ok"), "attached", status)

    text = await v.prompt(
        "block_out_room", {"width": "12", "depth": "10", "height": "4"}
    )
    ops = _ops(text)
    v.expect(len(ops) == 8, "the room prompt names eight ops", len(ops))
    batch = await v.call("hf_batch", {"ops": ops})
    v.expect(batch.get("ok"), "the room prompt's ops run as one batch", batch)
    bounds = re.search(r"focus bounds \{min: (\[[^\]]+\]), max: (\[[^\]]+\])\}", text)
    focus = {
        "bounds": {
            "min": json.loads(bounds.group(1)),
            "max": json.loads(bounds.group(2)),
        }
    }
    checked = await v.call("hf_validate")
    v.expect(
        checked.get("result", {}).get("counts", {}).get("error") == 0,
        "validate finds no errors",
        checked,
    )

    framed = await v.call(
        "hf_viewport_screenshot", {"focus": focus, "width": 960, "height": 540}
    )
    v.expect(framed.get("ok"), "a framed screenshot", framed)
    v.note("framed, look at it", v.save_image(framed, "room_framed.png"))
    plain = await v.call("hf_viewport_screenshot", {"width": 960, "height": 540})
    v.expect(plain.get("ok"), "a plain screenshot", plain)
    size = [
        plain.get("result", {}).get("width", 0),
        plain.get("result", {}).get("height", 0),
    ]
    v.expect(
        size[0] <= 960 and size[1] <= 540,
        "the plain shot shrinks to fit, never grows",
        size,
    )
    v.note("plain, look at it", v.save_image(plain, "room_plain.png"))

    listed = await v.call("hf_get_brushes", {"include_faces": False})
    v.expect(
        listed.get("ok") and listed["result"]["count"] >= 7,
        "review: the brushes list",
        listed,
    )

    baked = await v.call("hf_bake")
    v.expect(baked.get("ok"), "bake for a playtest", baked)
    v.note(
        "baked, look at it",
        v.save_image(
            await v.call(
                "hf_viewport_screenshot", {"focus": focus, "width": 960, "height": 540}
            ),
            "room_baked.png",
        ),
    )
    undone = await v.call("hf_undo")
    v.expect(
        undone.get("error", {}).get("code") == "undo_conflict",
        "undo refuses past the bake that applied the doorway",
        undone,
    )
    panel = v.order("panel")
    v.expect(
        panel["last"] == "Last: undo refused: undo_conflict", "the panel says so", panel
    )
