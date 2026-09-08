# Live Generators — Structures You Can Go Back and Change

Design document. 8 September 2026.

## Problem

The generators wave made it easy to produce a lot of geometry from a few numbers:
an arch is eight to sixty-four brushes, a hollowed cylinder is a tube of sixty-six
walls, a spiral stair is a dozen steps. That is the point of a generator.

But the moment a generator finishes, everything it knew is gone. An arch becomes
eight loose brushes with no memory of the radius, thickness, depth, arc or segment
count that produced them. Wanting a slightly wider arch means deleting eight
brushes, opening the Build tab, changing one number, and building it again — and
losing any materials that had been painted on the old one.

That is the wrong shape for a parameter you will almost certainly get wrong the
first time. Radius and segment count are exactly the values a designer tunes by
looking at the result, and a generator that cannot be re-run is a generator you
have to be right about in advance.

The array tools already show what the alternative looks like. `HFDuplicator`
records what it made — its sources, its count, its offset, and the brushes it
created — keeps that record on `LevelRoot`, serializes it, and can clear its own
instances again. Generated structures should have the same memory.

## Scope

1. **A record of what each generator made**, persisted with the level and through
   undo, following the duplicator's shape.
2. **Re-running a generator with new settings**, in place, preserving the
   materials that were painted on it.
3. **Detaching** a structure into plain brushes when it should stop being live.
4. The arch as the first live generator, with its dock section becoming an editor
   for the selected structure rather than only a creator.

Out of scope: making hollow and the array modes live (they have their own
records and their own shapes — this establishes the pattern first); nested
generators; and generators that depend on other geometry.

## Architecture

### `hf_generator.gd` — `HFGenerator`

A serializable record, the way `HFDuplicator` is one:

```
generator_id: String
type: String                    # "arch" for now
settings: Dictionary
placement: Transform3D
brush_ids: PackedStringArray
```

`to_dict()` and `from_dict()` round-trip it, and a dictionary missing any field
loads with that field's default so an older save opens.

### `systems/hf_generator_system.gd` — `HFGeneratorSystem`

A `RefCounted` subsystem constructed with the `LevelRoot`, like the other
twenty-two.

```
create(type, settings, placement) -> HFOpResult
regenerate(generator_id, settings) -> HFOpResult
detach(generator_id) -> bool
remove(generator_id) -> bool
generator_for_brush(brush_id) -> HFGenerator
build_faces(type, settings) -> Array
```

`build_faces()` is the one place that maps a type name to a builder, so adding a
second generator later means adding a branch there and nothing else.

Each brush a generator creates carries an `hf_generator_id` meta, which is how a
selected brush finds its generator — the same trick `duplicator_instance_of`
already uses.

**Regenerating** deletes the brushes the record names, builds new ones from the
new settings, and rewrites the record. Brushes the user has already deleted are
skipped rather than treated as an error.

**Materials survive the round trip.** Before deleting, each existing brush's
`material_override` is captured in order; after rebuilding, they are reapplied by
index. When the segment count changes, the shorter list wins and the extra
segments take the generator's default — the honest answer, since there is no
correspondence to preserve. Losing a texture pass every time a radius is nudged
would make the feature not worth using.

**Detaching** forgets the record and clears the meta, leaving ordinary brushes.
It is the escape hatch for a structure that has been edited by hand and should
stop being regenerated out from under the edits.

### Persistence

The generator records join the duplicator records in
`HFStateSystem.capture_state()` and `restore_state()`, which puts them in both the
undo snapshot and the `.hflevel` file for free, and restores the
`hf_generator_id` meta on the brushes the same way duplicator sources are
restored.

### Where a regeneration happens

Through `HFUndoHelper` like every other scene change, dispatched by method name on
`LevelRoot`:

```
create_generator(type, settings, placement)
regenerate_generator(generator_id, settings)
detach_generator(generator_id)
```

Three arguments or fewer each, so they stay on the helper's undoable path.

### Dock

The Arch section becomes context-sensitive, which is the pattern the Selection
Tools section already follows:

- With no generated brush selected it reads **Create Arch** and builds a new one.
- With a brush from an arch selected, the section loads that arch's settings into
  its controls, the button reads **Update Arch**, and a **Detach** button appears.

`set_selection_nodes()` is where that switch happens, since it is already the
dock's one selection-change hook.

## Error handling

- An unknown generator type is refused before anything is created.
- Regenerating a record that no longer exists is refused rather than crashing.
- Settings are validated by the builder that owns them, so an invalid update
  refuses and leaves the existing structure alone rather than deleting it and
  failing to replace it.
- Detaching or removing a generator that does not exist returns false.

## Testing

`tests/test_generator_system.gd`, with a shim root:
- Creating records the type, settings, placement and the brushes it made.
- Every created brush carries the generator's id.
- `generator_for_brush()` finds the generator from any of its brushes.
- Regenerating with a new radius replaces the brushes and updates the record.
- Regenerating with a different segment count changes the brush count to match.
- Materials are preserved across a regeneration at the same count, and the
  surviving prefix is preserved when the count shrinks.
- A regeneration with invalid settings refuses and leaves the structure intact.
- Detaching keeps the brushes and clears the meta and the record.
- Removing deletes both.
- Brushes deleted by hand before a regeneration are skipped.
- The record round-trips through `to_dict()`/`from_dict()`, and a dictionary
  written without the newer fields loads with defaults.

Integration coverage in `tests/test_live_generators_integration.gd`:
- Generator records survive a state capture and restore, with the brush meta.
- A regenerated arch still bakes with every triangle facing outward, against an
  untouched control.
- An arch that has been clipped can still be detached.
- Undo after a regeneration restores the previous structure.

## Risks

**Regeneration is destructive.** It deletes brushes to replace them, so a failed
build must not run at all rather than half-run. Settings are validated before
anything is deleted.

**Hand edits are lost.** A user who moves one segment of an arch and then changes
the radius loses that move. Detach is the answer, and it is offered in the same
place as Update so the choice is visible rather than discovered afterwards.

**Stale records.** Brushes can be deleted, merged or carved away outside the
generator's knowledge. The record is treated as a hint, never as a guarantee: it
is filtered against what actually exists on every use.

## Verification

The three passes again: build it and get the suite, `gdformat` and `gdlint`
clean; then attack it — regenerating after deleting brushes by hand, after
carving one, with invalid settings, with a changed segment count, across a save
and undo; then fold the findings back in and update the documentation.

## What the verification passes found

**Yellow** — built against the design above; the suite, `gdformat` and `gdlint`
all clean, and the generator system's own thirty-four cases passed on the first
run.

**Red** — one real hazard, found by asking what the record actually guarantees.
`_delete_brushes()` removed brushes by id, trusting the record's list. But brush
ids are reissued as the id counter moves, and brushes are deleted, clipped and
merged outside the generator's knowledge — so a stale entry in one record could
name a brush that by then belonged to something else, and a rebuild would quietly
delete a neighbour's geometry. Deletion now checks each brush's own
`hf_generator_id` before removing it, which makes the record's staleness genuinely
harmless rather than harmless-in-practice. The design said "the record is treated
as a hint, never as a guarantee"; the first implementation did not actually honour
that in the one place it mattered.

The adversarial pass otherwise came back clean, including regenerating after
pieces were deleted by hand, after a segment was clipped in two, with invalid
settings, across a changing segment count, and through undo and the save format.
Two hazards turned out to be already covered: the selection holding freed nodes
after an update is the same situation clip and hollow already create and handle,
and the brush cache is cleared by the existing delete path.

**Purple** — the finding was folded back in, the dock surface was pinned with
boundary tests for the contracts that matter (validate before deleting, ask the
record before switching the button, load settings without firing the controls),
and the documentation was brought in line.

Final state: **2,621 tests across 140 scripts, 2,614 passing, none failing**, with
`gdformat` and `gdlint` clean.
