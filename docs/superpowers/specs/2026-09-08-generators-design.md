# Generators — One Description, Many Brushes

Design document. 8 September 2026.

## Problem

Three unrelated-looking gaps turn out to be the same shape of problem: describing
a structure once and getting the brushes for it.

**Hollow is the last operation that refuses a rotated brush.** The precision-cutting
wave taught clip and carve to split real geometry, and hollow was left behind
because it is not a split — it rebuilds a brush as six axis-aligned slabs computed
from `global_position` and `size`. So it still refuses a cylinder, a wedge, a
merged brush, and anything the user has rotated, and it is the only reason
`_check_axis_aligned_box()` still exists. It is also the reason you cannot make a
pipe: hollowing a cylinder is a tube, and HammerForge will not do it.

**There is no arch.** Curved openings, tunnel rings, rotundas and vaulted ceilings
are staple level geometry, and every brush editor since Worldcraft has shipped a
parametric arch for them. HammerForge has fifteen primitives and a path tool, and
the only way to an arch is to place each voussoir by hand. The radial array from
the free-transform wave gets you copies around an axis, but not the wedge-shaped
segment an arch is made of — the array can repeat a shape, not compute one.

**A radial array cannot climb.** Copies go around the axis at a fixed height, so
the one structure a designer most wants from a radial array — a spiral staircase —
is exactly the one it cannot make.

## Scope

1. **Hollow on any convex brush, at any rotation**, reusing the cutting machinery.
2. **`HFArchBuilder`** — a parametric arch that emits one brush per segment.
3. **Rise per copy** in the radial array, which turns it into a helix tool.

Out of scope: non-convex shells (every brush here is convex by construction);
hollowing with a variable wall thickness; and an interactive arch gizmo, which is
an input problem rather than a geometry one.

## Architecture

### Hollow, as a carve against itself

Hollow does not need a new algorithm. The inside of a hollow brush is the same
convex solid with every face plane pushed inward by the wall thickness, and
carving that inner solid out of the original leaves exactly the walls.

The precision-cutting wave already implements that: progressive remainder over a
set of bounding planes. Hollow supplies the planes from the brush's *own* faces,
offset inward by `wall_thickness`, and the loop is unchanged:

```
for each inset plane:
    split the remainder
    the half outside this plane is a wall — it is finished
    the half inside carries on
what survives every plane is the void, and it is discarded
```

One face gives one wall, so a box still yields six, and a cylinder yields one wall
per side facet plus a top and a bottom — a tube. The walls are watertight against
each other by construction, because each is bounded by the plane that separated it
from the next.

This lives in `HFBrushSystem.hollow_brush_by_id()` and shares
`_carve_pieces()`'s loop, which moves to `HFConvexClip.progressive_remainder()`
so hollow and carve are visibly the same operation with different planes rather
than two copies of one idea.

**Validation** falls out of the algorithm. If the remainder is empty before the
planes run out, the insets crossed each other: the wall thickness is too large for
the brush, which is what the existing check reports. The old check compared
`thickness * 2` against the smallest dimension, which is only meaningful for a
box; the new one is exact for any shape, and keeps the same message and fix hint.

`_check_axis_aligned_box()` and its last two callers are deleted with it.

### `hf_arch_builder.gd` — `HFArchBuilder`

A pure static builder beside `hf_convex_clip.gd`. Parameters in, face sets out; no
scene, no `LevelRoot`, so it tests without a level.

```
build(settings) -> Array           # one Array[FaceData] per segment
default_settings() -> Dictionary
```

Settings are radius, wall thickness, depth, arc degrees, segment count, start
angle, and the axis the arch turns about. Each segment is the voussoir between two
angles: eight vertices from the inner and outer radii at each of its two angles, at
each end of the depth, and six quad faces.

The arch is built centred on the origin in its own space and placed by the caller,
which keeps the geometry independent of where it lands.

**Winding is not left to be got right by hand.** A voussoir is convex, so every
face of it must point away from the segment's centroid, and that is checkable
rather than reasoned about. `HFConvexClip.orient_faces_outward(faces, interior)`
reverses any face whose computed normal points inward. Every generator gets its
winding from that one function instead of from careful vertex ordering, which is
the third wave running where a rebuilt face could have shipped inside out.

### Rise in the radial array

`HFDuplicator.generate_radial()` gains a `rise` parameter: the distance each copy
climbs along the rotation axis, on top of the rotation it already applies. Zero
keeps today's behaviour exactly, so nothing existing changes; a non-zero value with
a step angle gives a helix, and with a box as the source, a spiral staircase.

It joins `mode`, `axis_index` and `step_degrees` in the serialized duplicator, and
a dictionary written without it loads as zero.

### Command surfaces

Hollow keeps every surface it has. The arch gets a section in the Build tab with
its parameters and a Create button, a command palette entry, and a viewport
context-menu item; it is created centred on the current selection, or on the world
origin when nothing is selected, reusing `resolve_transform_pivot()` so it lands
where the transform commands would pivot.

## Error handling

- A wall thickness that leaves no interior is refused, with the message and fix
  hint hollow already uses.
- An arch with fewer than one segment, a non-positive radius, or a wall thickness
  at or beyond the radius is refused before anything is created.
- A zero arc angle is refused; a full 360° arc is allowed and produces a ring.
- Every existing hollow refusal that still applies is kept.

## Testing

`tests/test_arch_builder.gd` — the generator, with no scene:
- A segment count of N produces N face sets.
- Every segment is a closed solid: each edge shared by exactly two faces.
- Every face of every segment is wound clockwise from outside, against an
  independently built control.
- Segments meet: the outer arc of one shares its radial face with the next.
- Radius, thickness and depth land where they are asked for.
- A 360° arc closes; a 90° arc spans a quarter.
- Degenerate settings are refused rather than producing rubbish.

`tests/test_hollow_tool.gd` — extended, with the tests that pin the current
refusals rewritten to assert the new behaviour:
- A rotated box hollows, and the walls stay rotated.
- A cylinder hollows into a tube.
- A box still hollows into six walls, and they still tile the original.
- Wall volume plus void volume equals the original volume.
- A thickness with no room for an interior is still refused.

Integration coverage in `tests/test_generators_integration.gd`:
- Hollow walls and arch segments bake with every triangle facing outward, each
  paired with an untouched control.
- An arch survives the save format and the brush-info round trip undo uses.
- A radial array with rise climbs by the amount asked for and still closes a ring.
- Hollowing a clipped piece, and clipping an arch segment, both work.

## Risks

**Winding in a built solid.** The arch is the first generator written since the
codebase learned that rebuilt faces are where winding goes wrong.
`orient_faces_outward()` makes it structural rather than careful, and the tests
assert it at bake level with a control.

**Hollow's wall count changes for curved shapes.** A cylinder hollowed used to be
refused; now it produces one wall per facet, which for a many-sided cylinder is a
lot of brushes. The segment count is the user's existing `sides` setting, so it is
visible and controllable, but it is worth saying out loud in the documentation.

**Behaviour change.** Hollow stops refusing brushes it refuses today, so the tests
asserting those refusals are rewritten rather than deleted.

## Verification

The same three passes: build it and get the suite, `gdformat` and `gdlint` clean;
then attack it — degenerate thicknesses, single-segment arches, full rings,
hollowing shapes with many faces, cuts applied to generated geometry, closure and
winding through a real bake; then fold the findings back in and bring the
documentation in line with what shipped.
