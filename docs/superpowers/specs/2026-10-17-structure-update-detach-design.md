# Structure Update and Detach on the agent bridge

2026-10-17. Issue #1302. Builds on the command registry
(`2026-10-17-command-registry-design.md`, #1265).

## What it is

An agent can build a structure with `hf_run_command create_arch`. Until now it
could not change one afterwards or turn one into plain brushes. It had to delete
the pieces and build again, which loses the paint, names, brush entities and
visgroups an Update keeps. Nothing an agent read even said which brushes were a
structure's pieces.

This adds two bridge commands, `update_structure` and `detach_structure`, a
`structure` key on every brush the bridge describes, and `$N.generator_id` in
`hf_batch`. Both commands are registry entries, so the palette's dispatcher runs
them too, and the context toolbar offers them when a structure piece is selected.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| How a structure is named | `params.generator_id`, required. No brush ids | Every Update gives every piece a new brush id, so a piece id goes stale after one Update. The generator id survives any number of them, and `create_arch` already answers it |
| Settings not given | Keep the structure's current value | The dock's section loads the structure's settings before you edit one field, so its Update changes only what you touched. Merging over the defaults, as `create_arch` does, would quietly reset every other field |
| Checking | `read_settings()` as for `create_arch` (unknown key, wrong type, out of range, enum by index or label), then `can_build_generator()` | The same checks and words as the dock. A refusal changes nothing and records no step |
| Refusal words | `HFGeneratorSystem.not_changed_text()`, used by the dock and the bridge | "Stairs not changed. ..." was the dock's alone. One function keeps the two from drifting |
| The dock's warnings | Not asked first. Said in the answer: `appearance_dropped`, `edits_replaced`, and a warning when the pieces did not agree where the structure is | #1265's rule: every dialog guards a change undo takes back, so the agent's call is the confirmation and `hf_undo` the way back. The dock's second press over painted faces is one of those dialogs |
| Membership on a brush | `structure: {generator_id, type, piece, settings}` or null, read through the record | An undo of a Detach restores the record, but restoring a state never takes the tag off a brush. Reading the tag alone would report a structure that no longer exists |
| Settings on every piece | Yes | An agent changing "two more steps" needs the current count, and the piece it is looking at is where it looks. A structure is a small part of most levels |
| Batch reference | `$N.generator_id`, read from the top of op N's answer | So one batch can build a structure and then detach or update it |
| Human surface | Two registry entries with interactive arms. Update rebuilds from the Structure section's settings and never makes a new structure. Detach is the dock's Detach. The toolbar's brush section shows Upd and Det when a structure piece is selected, as it shows the prefab buttons for a prefab copy | The registry describes commands a surface runs. Detach was a dock button only |
| Listing | Both entries get `settings_by_type`, since update takes the same keys per type | The agent reads one table for both |

## Pre-mortem

1. **Settings quietly reset.** Reusing `read_settings()` as is fills unset
   fields from the defaults. Guard: it takes a base, the record's settings. Test:
   change one key, every other key keeps the structure's value, an enum set by
   its label included.
2. **Stale handles.** Pieces get new ids on every Update, and a Detach undone and
   redone can leave the tag on its old pieces. Guard: commands take the generator
   id; membership is read through the record. Tests: two Updates in a row by the
   same id; Detach, undo, redo, with the listing checked at each step.
3. **Damage without the dock's warning.** Guard: the answer lists the pieces whose
   paint was dropped and the hand edits replaced, and warns when the pieces did
   not agree on where the structure is. Tests for each, and for the refused build
   leaving no step.

## Not in this change

- More than one structure per command, and a listing of structures on their own.
  `hf_get_brushes` answers both through `structure`.
- Removing a stale tag from a brush when a state is restored. The record is the
  authority (`HFGeneratorSystem` says so), and every reader here goes through it.
