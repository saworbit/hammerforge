"""Screenshot views in a windowed editor, with the pictures to look at (#1040)."""

import json
import re

from scenarios.prompts import _ops

DESCRIPTION = (
    "screenshot views: look_from, a camera at the player's eye, hide and hide_cuts"
)
START_SCENE = "level"
WINDOWED = True

#: The size of every shot, small enough to look through quickly.
SIZE = {"width": 960, "height": 540}


async def run(v):
    status = await v.call("hf_get_status")
    v.expect(status.get("ok"), "attached", status)

    text = await v.prompt(
        "block_out_room", {"width": "12", "depth": "10", "height": "4"}
    )
    batch = await v.call("hf_batch", {"ops": _ops(text)})
    v.expect(batch.get("ok"), "the room is built", batch)
    results = batch.get("result", {}).get("results", [])
    ceiling = results[1]["result"]["brush"]["brush_id"] if len(results) > 1 else ""
    bounds = re.search(r"focus bounds \{min: (\[[^\]]+\]), max: (\[[^\]]+\])\}", text)
    box = {"min": json.loads(bounds.group(1)), "max": json.loads(bounds.group(2))}
    floor_top = box["min"][1] + 0.5

    framed = await v.call("hf_viewport_screenshot", {"focus": {"bounds": box}, **SIZE})
    v.expect(framed.get("ok"), "a framed shot fills the frame", framed)
    v.note("framed, look at it", v.save_image(framed, "views_framed.png"))

    from_top = await v.call(
        "hf_viewport_screenshot",
        {"focus": {"bounds": box, "look_from": "top"}, "hide": [ceiling], **SIZE},
    )
    v.expect(from_top.get("ok"), "from above with the ceiling left out", from_top)
    v.note("into the room from above", v.save_image(from_top, "views_top.png"))

    eye = await v.call(
        "hf_viewport_screenshot",
        {
            "camera": {
                "position": [0, floor_top + 1.8, 3.5],
                "look_at": [0, floor_top + 1.2, -5],
            },
            **SIZE,
        },
    )
    v.expect(eye.get("ok"), "a camera at the player's eye inside", eye)
    v.note("the doorway from inside", v.save_image(eye, "views_eye.png"))

    no_cuts = await v.call(
        "hf_viewport_screenshot",
        {"focus": {"bounds": box, "look_from": "-z"}, "hide_cuts": True, **SIZE},
    )
    v.expect(no_cuts.get("ok"), "the front with its cut left out", no_cuts)
    v.note("the front, no red block", v.save_image(no_cuts, "views_front_no_cuts.png"))

    after = await v.call("hf_get_status")
    v.expect(
        after.get("revision") == status.get("revision") + 1,
        "the shots changed nothing: only the room's one step moved the revision",
        [status.get("revision"), after.get("revision")],
    )
