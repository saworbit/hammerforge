# Placing a prefab from the library over the agent bridge

2026-10-18. Issue #1301. Builds on the command registry
(`2026-10-17-command-registry-design.md`, #1265) and follows the structure
commands (`2026-10-17-structure-update-detach-design.md`, #1302).

## What it is

An agent could change a placed prefab (`cycle_variant`, `propagate_prefab`) but
not place one: placing is a drag from the Prefab Library into the viewport, and
the bridge has no mouse. This adds `place_prefab` to `hf_run_command`, and the
library's prefabs to `hf_list_commands` so the agent can find them.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Naming a prefab | `params.prefab`, the library file's name without `.hfprefab`, matched against what the library folder holds | The library lists files by that name. A name is never joined into a path, so `../x` names nothing |
| Finding prefabs | The `place_prefab` entry in `hf_list_commands` carries `prefabs`: each one's name, variants, tags and brush and entity counts | The way `create_arch` carries `settings_by_type`. No new tool, and the listing already needs no level open |
| Where | `position` (required) is where the prefab's centre goes, `rotation_degrees` (Euler XYZ) turns it about that centre | The centre is what a prefab's records are relative to and what a drop puts on the hit point |
| How it is turned | The copy's frame `F = Transform3D(turn, position)` and every piece placed at `F * record` | That is exactly what variant switching and propagation measure back (`_instance_frame()`: node times record inverse) and rebuild with. Any other composition would make the first variant switch un-turn or walk the copy |
| Snapping | None on the bridge | `create_arch` places exactly too. The drop snaps because a mouse hit lands anywhere; an agent's coordinate is deliberate |
| Variant and link | `variant` (default the base), checked against the file's variants; `linked` (default false) | What the library offers by hand: a drop places the base unlinked, Save Linked makes linked copies |
| One placement | `HFPrefabSystem.place()` instantiates and records the copy. The drop, the viewport menu and the bridge all call it | The issue asks for the drop's placement. Fresh names and ties come from `instantiate()` as they already do |
| Undo | One `MCP: place prefab` step through the change wrapper | The whole-level capture holds the palette and the prefab records, so the slots a prefab appends and its record go back with it |
| Human surface | `place_prefab` is a registry entry with an arm: Place Selected Prefab in the viewport's Space menu puts the prefab selected in the library at the point under the cursor, through the drop's own code | The registry describes commands a surface runs, and placing without a drag is worth having |
| Library folder in tests | `HFMcpCommands.prefab_dir`, `res://prefabs` by default | Tests and the vibe scenario point it at a scratch folder and never touch the developer's library (#1304) |

## Pre-mortem

1. **A turned copy that variant switching un-turns or walks.** Guard: place at
   `F * record`, the form `_apply_variant()` uses. Test: place turned, cycle the
   variant, propagate; the copy keeps its turn and centre.
2. **Reaching outside the library, or into the real one from a test.** Guard: the
   name is looked up in the folder's listing, never made into a path; tests set
   `prefab_dir` to `user://`. Tests: `../` and an unknown name are refused with
   the names the library has; nothing is written under `res://prefabs`.
3. **Undo that leaves something behind.** A prefab can append palette slots and
   always adds a prefab record and entity uids. Guard: one whole-level step.
   Test: a prefab whose material the level lacks grows the palette; `hf_undo`
   puts the palette, records and brushes back, and `hf_redo` brings them all
   back. The bridge sweep runs it in every state.
4. **The drop changing on the way.** The drop moves onto `place()`. Guard: its
   undo step keeps its name, and `tests/test_dock_undo_coverage.gd`'s inventory
   follows the function it moved to.
