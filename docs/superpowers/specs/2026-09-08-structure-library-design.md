# Structure Library — More Generators, and Fewer Places to Add One

Design document. 8 September 2026.

## Problem

The live-generator wave built a type table and put one thing in it:

```gdscript
static func known_types() -> PackedStringArray:
    return PackedStringArray([TYPE_ARCH])
```

Its own test says `"update this test deliberately when a second generator lands"`.
This is that.

Two problems sit behind that single entry, and only one of them is "we need more
generators".

**The dock cannot afford a second generator.** The Arch section is six named
`SpinBox` members on `dock.gd`, six named rows built by hand, a load function
listing the six by name, and a create function reading the six by name. A second
generator with different settings means all four of those again. A fourth means
four of everything. The cost of adding a generator is not the builder — the arch
builder is 150 lines of arithmetic that tests without a scene — it is the dock.

**Two structures a level needs constantly are missing.** Straight stairs are the
most common piece of built geometry in a level after the box, and there is no
generator for them; a flight of twelve is twelve brushes placed by hand, each one
an offset of the last, each offset an opportunity to be a unit out. Spiral stairs
are worse: the roadmap's answer today is a radial array with a rise, which repeats
one shape around an axis but cannot compute the wedge a tread actually is — the
same limitation that made the arch worth building.

And a third problem, found while looking at the first two:

**Moving a structure and then updating it moves it back.** `regenerate()` builds
at `record.placement`, which is written once, at creation. Create an arch on the
world origin, drag it into a doorway, decide the radius is wrong, press Update —
and the arch rebuilds at the origin. This is a real defect in the shipped wave.
It has to be fixed here, because the whole premise of a live generator is that you
change your mind after seeing it in place.

## Scope

1. **Settings schemas.** Each builder declares its own settings — key, label,
   range, default, tooltip — and the dock builds its controls from that. One
   section serves every generator type.
2. **Three new generators**: straight stairs, spiral stairs, and a dome.
3. **Relocation.** A structure that has been moved rebuilds where it now is.
4. **A hand-edit warning.** Say how many pieces have been changed before Update
   rebuilds over them.

Out of scope: making hollow and the array modes live (still their own shapes);
nested generators; an interactive gizmo for any of this.

## Architecture

### Settings schemas

Every builder gains a static `settings_schema()` returning an ordered array of
field descriptions:

```gdscript
{
    "key": "radius",
    "label": "Radius",
    "type": "float",          # "float", "int", "bool" or "enum"
    "min": 1.0, "max": 4096.0, "step": 1.0,
    "default": 128.0,
    "tooltip": "Outer radius of the arch",
}
```

`HFGeneratorSystem.settings_schema(type)` dispatches to the builder, beside
`default_settings()`, `validate()` and `build_faces()`. `default_settings()` can
then be derived from the schema rather than written twice.

The schema is a description, not a validator. Ranges keep a `SpinBox` sensible;
`validate()` remains the authority on whether settings can actually be built,
because the interesting refusals are relationships between fields — a wall
thicker than its radius, an arc too coarse to stay convex — and no per-field range
expresses those.

> Amended 2026-09-11 (#336, #338): the ranges are enforced.
> `HFGeneratorSchema.check_ranges()` holds a caller that never saw the dock to
> the schema's own maximums, and refuses a non-finite number, because a NaN
> passes every comparison a builder makes. `validate()` is still the authority
> on the relationships between fields.

### The dock's Structure section

The Arch section becomes the **Structure** section: a type dropdown, controls
built from the selected type's schema, and the Create/Update and Detach buttons
that are already there.

- Changing the type rebuilds the control rows from the new schema.
- Selecting a piece of a generated structure selects its type in the dropdown,
  loads its settings, and switches the button to **Update**.
- The named `arch_*_spin` members go away. Controls live in a dictionary keyed by
  setting name, which is what makes one section serve four generators.

`Ctrl+Shift+A` keeps its action id (`create_arch`) so existing custom keymaps
still resolve, and builds whatever type the section currently shows.

### `HFStairsBuilder` — a straight flight

`width`, `tread` (the run of one step), `rise` (the height of one step),
`steps`, `fill`, `tread_thickness`.

Two fill modes, because they are different structures:
- **Solid** — step *i* is a box from the base up to its own top. A staircase you
  cannot see under, which is what most level stairs are.
- **Open** — step *i* is a slab of `tread_thickness` at its own height. Floating
  treads.

Built about its own centre and extruded along X, so the run climbs +Y along +Z.

### `HFSpiralStairsBuilder` — a flight around an axis

`inner_radius`, `outer_radius`, `steps`, `degrees_per_step`, `rise`,
`tread_thickness`, `start_degrees`, `center_post`.

Each tread is an annular wedge — the arch's voussoir, lying flat. A step spanning
half a turn or more is not convex, so `degrees_per_step` is capped the same way
the arch's is. The optional centre post is one octagonal prism spanning the full
climb, which is what stops a spiral stair looking like a stack of floating
wedges.

### `HFDomeBuilder` — a hemisphere in rings

`radius`, `wall_thickness`, `rings`, `segments`, `arc_degrees`, `sweep_degrees`.

The construction has to be chosen carefully. Four points on a sphere at two
latitudes and two longitudes are **not coplanar**, so the obvious "one panel per
patch of sphere" is not a brush — every brush here is a convex solid with planar
faces.

Rings solve it. Bound each ring by two horizontal planes rather than by the
sphere, and a panel becomes the piece between two horizontal planes, two meridian
planes through the axis, and the outer and inner conical surfaces. The four outer
corners of that piece are coplanar — the frustum band of a cone is a planar
surface between two of its rulings — so every face of the panel is a plane, and
the panel is a proper convex brush. A dome is faceted rather than smooth, which is
what a brush dome is anyway.

Near the top the inner sphere falls below the ring, and the inner face collapses
onto the axis. Faces whose vertices collapse to fewer than three distinct points
are dropped, and the top ring's panels are wedges rather than boxes. Winding, as
everywhere, is settled by `orient_faces_outward()` against the interior point
rather than by the order the corners were written.

Brush count is `rings × segments`, so it is capped and refused with the real
number rather than being allowed to produce nine hundred brushes.

### Relocation and hand edits

The record gains a signature per brush, taken when the brush is made:

```
brush_signatures: { brush_id: {"origin": Vector3, "geometry": String} }
```

`origin` is where the piece was put. `geometry` is a rounded hash of shape, size
and face vertices — what the piece *is*, independent of where it is.

Two questions become answerable, and they are different questions:

**Has the structure been moved?** If every surviving piece has moved by the same
delta, the structure was moved as a unit. That delta folds into
`record.placement` before rebuilding, so the structure rebuilds where it now is.
If the pieces have moved by *different* deltas they were moved individually,
which is a hand edit and not a relocation, and the placement stays put.

**Have pieces been edited?** A piece whose geometry hash differs from its recorded
one has been changed — vertex-dragged, clipped, bevelled, resized. That count is
what the section shows: *"3 pieces have been edited — Update will rebuild over
them."* Update still proceeds, because the user asked; the warning is so that
Detach is a choice made rather than a lesson learned.

Rounding is to a thousandth, so a save/load round trip through the float
formatting does not read as an edit.

## Error handling

Unchanged in shape: an unknown type is refused, invalid settings are refused
before anything is deleted, and every refusal names the number that was wrong and
suggests one that would not be. New refusals: a dome above its panel cap, a
spiral step too coarse to stay convex, a centre post with no radius to occupy.

## Testing

Per builder, in `tests/test_stairs_builder.gd`, `tests/test_spiral_stairs_builder.gd`
and `tests/test_dome_builder.gd`: the piece count follows the settings; the
geometry spans the size it claims; every face of every piece points away from that
piece's interior; each refusal fires on its own boundary and not one step inside
it; and the schema's defaults are exactly `default_settings()`.

In `tests/test_generator_system.gd`: every known type builds, validates, and has a
schema whose keys match its defaults; signatures are recorded on creation; a
uniform move relocates and a mixed move does not; edited pieces are counted and
an untouched structure counts zero; and a structure of every type survives a
capture and restore.

In the integration suite: one structure of each type bakes with every triangle
facing outward, against an untouched control brush; a moved structure rebuilds in
its new place; and the dock's section is driven by the schema rather than by named
members.

## Risks

**The dock rewrite has no headless proof.** Controls built from a schema cannot be
clicked in a test run. It is pinned the way the previous waves pinned dock
behaviour — boundary tests that read the source for the contracts that matter —
and the smoke checklist covers what only a human can see.

**Relocation could fire when it should not.** A structure whose pieces happen to
share a delta after individual edits would be relocated. The delta is only taken
when *every* surviving piece agrees, which is the condition that means "moved as a
unit", and a structure with one piece is the degenerate case: moving that one
piece is both a relocation and the whole structure, and treating it as a
relocation is the answer that surprises least.

**More types, more validation surface.** Each builder owns its own refusals, so
the cost is per builder rather than shared, and the type table stays the only
place that knows they all exist.

## Verification

The three passes, as before. Yellow: build it, get the suite, `gdformat` and
`gdlint` clean. Red: attack it — a dome at the pole, a spiral of one step, a
staircase of zero rise, a relocated structure that has also been edited, a type
switched mid-edit, every new structure through save, undo and bake. Purple: fold
the findings back in, pin the boundaries, and bring the documentation into line.

## What the verification passes found

**Yellow** — built against the design above. The dome geometry was right on the
first run, planarity included, which is the part I expected to iterate on: the
ring construction either produces planar faces or it does not, and measuring it
settled the question rather than arguing it. Two mistakes were mine and both were
in the tests — `HFOpResult`'s hint field is `fix_hint`, and a `:=` cannot infer
through an untyped return.

**Red** — three findings, one of them older and larger than this wave.

*Choosing a type was answered by ignoring it.* `on_structure_type_changed()`
finished by re-deriving the section from the selection — which still held a piece
of the old structure, so picking **Dome** while an arch segment was selected put
the dropdown straight back on **Arch**. The only way to build a dome would have
been to click empty space first. A dropdown choice is a decision, not a query, and
it now sets the section directly.

*A reopened level could have cried wolf.* The hand-edit warning compares a hash of
what each piece is against what it was. Pieces come back out of the save format
rebuilt from serialized floats, and if that round trip moved a vertex by a hair,
every structure in every reopened level would have claimed it had been edited by
hand — and a warning that is always on is a warning nobody reads. It survives the
round trip, and there is now a test that says so for every type, because this is
the kind of thing that would be found by a user and not by me.

*Two test files, 121 tests, had been dark for two waves.* The generators wave
deleted `HFBrushSystem._check_axis_aligned_box()` when hollow stopped needing it,
and left five call sites behind in `tests/test_transform_integration.gd` and
`tests/test_transform_system.gd`. GDScript resolves a static call at parse time, so
both files failed to load — and GUT skips a file it cannot load with a *warning*,
not a failure. The totals came out slightly smaller and entirely plausible, and I
reported them as passing at the end of two waves. The tests are rewritten against
what replaced the guard, and `tests/test_suite_integrity.gd` now fails the suite
when any test file will not load, which is the check that would have caught it the
day it happened.

The adversarial pass otherwise came back clean: a dome of one ring reaching the
pole, a dome swept the other way round, the thinnest shell the ranges allow, a
spiral of one tread, a flat fan, a structure moved and edited at once, a stranger
brush planted in a record, and a record saved before signatures existed.

**Purple** — the findings were folded back in, the dock surface was pinned with
boundary tests for the contracts that matter (the dock names no generator setting
of its own; a type choice does not consult the selection; validation precedes
deletion), the smoke checklist gained the two sections only a human can walk, and
the documentation was brought into line.

Final state: **2,809 tests across 147 scripts, 2,802 passing, none failing**, with
`gdformat` and `gdlint` clean. 107 of those tests are new; 81 are ones that had
stopped running.
