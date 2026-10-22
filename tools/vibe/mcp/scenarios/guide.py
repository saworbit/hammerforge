"""The building guide's worked example, run as written against a real editor (#1650).

The guide tells an agent to build two rooms and a doorway in three batches and
says what each check should give at the end. This sends each batch from the page
exactly as it stands and checks every number its table states, so a guide whose
example no longer builds, or no longer measures what it says, fails the sweep.
"""

import json
import re
from pathlib import Path

DESCRIPTION = "the building guide's worked example: three batches, then its checks"
START_SCENE = "other"
WINDOWED = False

PAGE = (
    Path(__file__).resolve().parents[4]
    / "hammerforge_mcp/skills/hammerforge-building/reference/worked-example.md"
)


def _batches(text: str) -> list[list[dict]]:
    return [
        json.loads(b)["ops"] for b in re.findall(r"```json\n(.*?)\n```", text, re.S)
    ]


def _checks(text: str) -> list[dict]:
    """The rows of the table under "The checks": items, the field and the value."""
    rows = []
    section = text.split("## 5. The checks", 1)[-1]
    for line in section.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or cells[0] in ("Check", "") or set(cells[1]) <= {"-"}:
            continue
        items = re.findall(r"\s*(\[[^\]]*\]|[^,]+)\s*(?:,|$)", cells[1])
        rows.append(
            {
                "check": cells[0],
                "items": [i.strip() for i in items if i.strip()],
                "field": cells[2],
                "value": float(cells[3]),
            }
        )
    return rows


async def run(v):
    text = PAGE.read_text(encoding="utf-8")
    status = await v.call("hf_get_status")
    if status["result"]["target"]["level_root_path"] is None:
        made = await v.call("hf_create_starter")
        v.expect(made.get("ok"), "the loop's first step: a starter level", made)
        status = await v.call("hf_get_status")
    before = status["result"]["counts"]

    batches = _batches(text)
    v.expect(len(batches) == 3, "the page holds three batches", len(batches))
    for n, ops in enumerate(batches, 1):
        sent = await v.call("hf_batch", {"ops": ops})
        v.expect(sent.get("ok"), f"batch {n} builds as written", sent)

    after = (await v.call("hf_get_status"))["result"]["counts"]
    grown = {key: after[key] - before[key] for key in ("brushes", "pending_cuts")}
    v.expect(
        grown == {"brushes": 6, "pending_cuts": 1},
        "six brushes and a pending cut more, as the page says",
        grown,
    )

    listed = await v.call("hf_get_brushes", {"include_faces": False})
    ids = {b["name"]: b["brush_id"] for b in listed["result"]["brushes"]}
    checks = _checks(text)
    v.expect(len(checks) >= 6, "the page's checks were read", checks)
    for row in checks:
        items = []
        for item in row["items"]:
            items.append(
                json.loads(item) if item.startswith("[") else ids.get(item, item)
            )
        measured = await v.call("hf_measure", {"items": items})
        if not v.expect(measured.get("ok"), f"{row['check']}: measured", measured):
            continue
        result = measured["result"]
        if row["field"] == "gap":
            got = result["pair"]["gap"]
        elif row["field"] == "size y":
            got = result["items"][0]["bounds"]["size"][1]
        else:
            v.expect(False, f"{row['check']}: a field the scenario knows", row["field"])
            continue
        v.expect(
            abs(got - row["value"]) < 0.0001,
            f"{row['check']}: {row['field']} {row['value']:g}",
            got,
        )

    checked = await v.call("hf_validate")
    errors = [i for i in checked["result"]["issues"] if i.get("severity") == "error"]
    v.expect(checked.get("ok") and not errors, "hf_validate reports no errors", errors)
