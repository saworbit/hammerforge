# A partial bake over the agent bridge

2026-10-18. Issue #1317. Follows cordons on the bridge
(`2026-10-18-cordons-bridge-design.md`, #1300).

## What it is

An agent can mark out the room it is working on with cordons, but `hf_bake`
bakes the whole level through `bake_whole_level()`, setting the cordons aside as
Export Game Scene does (#1205). To look at one room, or to playtest it, the agent
rebuilds the whole map. This adds an opt-in `cordons: true` to `hf_bake` that
bakes what the active cordons take, the bake the dock's Bake makes.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Opt in | `cordons` (default false). Without it nothing changes: a whole bake, cordons set aside and put back | #1205 made the game scene whole on purpose. A cordon left on must never make it partial |
| Which bake | `root.bake()` with the same arguments `bake_whole_level()` passes on | That is the bake the dock's Bake runs. The cordon filter, the cutters that go with a cordoned brush (#1244) and the touch rule (#1206) come with it |
| Nothing to cut to | Refused with `invalid_argument` on `cordons`, before anything runs, when `partial_bake` is false: cordons off, or every cordon switched off | `bake()` would take the whole level, and the answer would call it partial |
| Where it goes | The same `<scene>_mcp.tscn` | One artifact is one last bake, and `last_bake`, `bake_current` and the root meta describe it exactly. A second path would leave a whole bake lying about that status no longer speaks for |
| Saying what it is | The root meta, the answer and `last_bake` carry `partial`. A partial one also carries `cordons`: each active cordon as `hf_get_cordons` gives it, read as the bake starts | Whatever loads the file can tell a room from the map without asking the editor |
| Entities | Every point entity goes in, as Play Selected Area exports them | The export copies `entities_node` whole, and a partial playtest has always worked this way. Brush entities are brushes and follow the cordons |
| `bake_current` | Unchanged: whether the level has moved on since the last bake | A partial bake is current for as long as the level is |

## Pre-mortem

1. **A whole bake turning partial again** (#1205). Guard: the flag defaults off, and
   only `cordons: true` reaches `bake()`. Test: the existing cordon-on test still
   writes the far box; `cordons: false` is whole too.
2. **A bake labelled partial that took the whole level.** With every cordon off,
   `bake()` takes everything. Guard: refuse when `partial_bake` is false. Tests:
   cordons off and every cordon switched off are each refused, write no file and
   leave `last_bake` as it was.
3. **The record disagreeing with the bake.** The meta could list cordons the bake
   did not use, or a whole bake could say nothing. Guard: `partial` on every bake,
   and the cordons read as the bake starts. Tests: a partial bake's file holds the
   cordoned box and not the far one, and its meta, answer and `last_bake` agree; a
   whole bake says `partial: false`.
