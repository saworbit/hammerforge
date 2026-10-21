# Cordons over the agent bridge

2026-10-18. Issue #1300. Builds on the bridge (`2026-10-11-mcp-bridge-design.md`)
and the cordon list with names and switches (#966, #970).

## What it is

An agent could not see, add, move, name, switch or remove a cordon, so it could
not mark out the part of a big level a partial bake takes. The level already has
the whole cordon API (`set_cordon_region`, `set_cordon_from_selection`,
`set_cordon_name`, `set_cordon_active`, `remove_cordon_region`,
`capture_cordons`, `restore_cordons`). What was missing is a bridge surface, and
an undo wrapper and `hf_batch` that can put cordons back: they are level settings
that `capture_state()` does not hold.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Tools or palette commands | Three tools: `hf_get_cordons` (a read), `hf_set_cordon` and `hf_remove_cordon` (changes, both `hf_batch` ops) | Cordons are not palette actions (`2026-10-17-command-registry-design.md`, First build); `hf_run_command` runs registry commands with an `execute()` arm. A level setting has its own tool, as the spawn has `hf_set_spawn` |
| Naming a cordon | `index`, the cordon's place in the dock's list, 0 first | The level's own API and the dock's list both index them. Names are optional and need not be unique |
| Adding | `hf_set_cordon` without `index` and with a place (`brush_ids` or `bounds`) adds one. On a level whose only cordon is the untouched default, it takes that one's place, answering `replaced_default: true` (#1367) | One tool for add and change keeps the agent's words close to the dock's Set and Add from Selection |
| Where | `brush_ids` (the box round them grown by a unit, through `set_cordon_from_selection()`, the dock's own) or `bounds: {min, max}` (the shape `hf_get_brushes` and screenshots take, corners in either order) | The dock's two ways, without a selection. A box with no size on an axis is refused: a flat cordon takes only what crosses its plane, which is never what an agent giving the same height twice means |
| Switching on | A cordon given a place is switched on, and so are cordons as a whole, as Set and Add from Selection do. `active` and `enabled`, when given, win | An agent that marks out a part means to bake it. Leaving the level's switch off would draw the cordon and bake the whole level |
| Removing | `hf_remove_cordon {index}`; the last cordon is refused, with the way to switch it off | `cordon_aabb` always holds one (`remove_cordon_region()`) |
| Answers | Every cordon tool answers the whole list, `enabled` and `partial_bake` | Indices move on a remove; the agent never has to guess one |
| Undo, one tool | A cordon-only step, both ends `restore_cordons()`: `HFUndoHelper.commit_cordons_if_changed()` | The step the dock records for its own cordon edits (`record_cordon_edit()`), and no whole-level capture for a five-field change. Since #1365 a call that moved nothing records no step, as with every bridge change, and the agent's undo chain stays on its last real step |
| Undo, batch and rollback | The dispatcher captures the cordons beside the level for every change. A refusal restores them when they moved; a batch's step adds `restore_cordons()` at both ends when they moved (`commit_completed(..., cordons_before)`) | `capture_state()` stays as it is, so no other undo step and no `.hflevel` changes |
| Telling the dock | A bridge cordon edit ends by emitting `settings_applied`; undo and redo already do through `restore_cordons()` | The dock reads cordons only then, and one spin nudge on a stale dock writes five old bounds back (#968) |
| `hf_bake` | Unchanged: it bakes the whole level, cordons set aside (#1205) | The game scene is never meant to be partial. A partial bake for the agent is a follow-up with its own contract |

## Pre-mortem

1. **Undo or rollback misses the cordons.** They are outside `capture_state()`, so
   a batch refused at a later op would keep its cordon edit, and undoing a batch
   would take back its brushes and leave its cordons. Guard: capture beside the
   level in the dispatcher, restore on refusal, both ends in a batch's step.
   Tests: a batch of a cordon edit and a refused op leaves the cordons exactly as
   before with no step; a batch of a brush and a cordon, undone and redone, puts
   both back and forth.
2. **The dock shows stale cordons and writes them back** (#968). Guard: every edit
   emits `settings_applied`. Tests: the signal fires on an edit and on its undo;
   the MCP vibe scenario reads the real dock's cordon list after the agent's edit.
3. **Index arithmetic and degenerate boxes.** One list in three properties,
   indices that shift on a remove, a last cordon that cannot go, and
   `_is_cordon_region()` letting a flat box through. Guard: only the level's
   index API, refusals before anything changes. Tests: each refusal changes
   nothing and records no step; a remove keeps names and switches on the right
   cordons.
