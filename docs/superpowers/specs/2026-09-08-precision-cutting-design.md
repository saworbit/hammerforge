# Precision Cutting — Arbitrary-Plane Clip and Carve

Design document. 8 September 2026.

## Problem

Clip and carve only work on unrotated boxes.

`HFBrushSystem.clip_brush_by_id()` rebuilds a brush as two axis-aligned box
pieces, computed from `global_position` and `size`. `HFCarveSystem` does the same
with up to six box slices. Both therefore refuse anything else through
`_check_axis_aligned_box()`: a cylinder, a polygon-tool brush, a merged brush, a
beveled brush — and, since the free-transform wave shipped, any brush the user has
rotated.

That last one is a cost this project introduced last week. Rotation is now a
first-class operation, and three of the tools a level designer reaches for most
refuse to touch its results. Reset Rotation is the documented answer, but it is a
workaround for a limitation, not a feature.

The limitation is also holding back a capability that has nothing to do with
rotation. A brush-based editor's clip tool is supposed to cut along *any* plane —
that is what makes angled walls, chamfered corners and wedge-shaped rooms cheap.
Hammer has had it since 1998. HammerForge can only cut along X, Y or Z.

Both problems have one cause and one fix: neither operation knows how to split a
convex solid by an arbitrary plane.

## Scope

1. **`HFConvexClip`** — one exact, winding-correct plane/convex-solid split, with
   no dependency on the scene.
2. **Clip along any plane**, on any convex brush, at any rotation. Including a
   new **Clip to Face Plane** command, which is the cheapest way to reach an
   angled cut without a dragging gesture.
3. **Carve with any convex carver**, at any rotation, against any convex target.

Out of scope: hollow (it insets every face inward, a different algorithm, and it
keeps its guard); non-convex brushes (every brush in HammerForge is convex by
construction and the vertex system enforces it); and a click-and-drag clip-plane
gesture in the viewport, which is an input problem rather than a geometry one and
needs interactive validation this pass cannot give it.

## Architecture

### `hf_convex_clip.gd` — `HFConvexClip`

A pure static helper at the addon root, beside `hf_material_atlas.gd`. It takes
face data and a plane and returns face data. It never touches the scene tree, a
`LevelRoot`, or a brush node, which is what makes the whole wave testable without
a level.

```
split(faces, plane, epsilon) -> { front: Array, back: Array, cut: PackedVector3Array }
clip_polygon(verts, uvs, plane, keep_front, epsilon) -> { verts, uvs }
sort_coplanar_cw(verts, outward_normal) -> PackedVector3Array
cap_polygon(cut_points, outward_normal, epsilon) -> PackedVector3Array
is_axis_aligned_box(faces, epsilon) -> Dictionary
```

`front` is the half on the side the plane normal points to. Either side comes
back empty when the plane misses the solid, which is how callers detect a cut
that would do nothing.

**Splitting a face.** Each vertex is classified front, back, or on the plane
within `epsilon`. A face entirely on one side is carried over whole — the same
`FaceData` fields, a new object. A face that straddles the plane is clipped twice,
once keeping each side, by walking its edges and emitting an intersection vertex
wherever an edge crosses. This is Sutherland–Hodgman in three dimensions, and
because the input polygon is convex and planar each half comes back as a single
convex polygon.

**UVs survive the cut.** `custom_uvs` are carried through the same walk and
interpolated at each crossing by the edge parameter, so a clipped face keeps its
texture alignment exactly rather than being re-projected. Faces without custom
UVs keep their projection settings and re-project as before.

**Capping.** Every crossing vertex lies on the cut plane, so the cap is the convex
hull of those points within the plane — and for a convex solid, their ordered ring.
They are ordered by angle about the cut centroid and emitted **clockwise as seen
from outside the half being capped**, which for the front half means outside is
`-plane.normal` and for the back half `+plane.normal`. The two caps are therefore
the same ring in opposite orders.

This is the part that has to be right, and it is the same trap the free-transform
wave hit: the mathematically natural ordering of a coplanar ring is
counter-clockwise about its normal, and HammerForge needs clockwise-from-outside,
because `FaceData.triangulate()` fans straight off `local_verts` and Godot reads
front faces as clockwise. `sort_coplanar_cw()` names the convention in its
signature so no caller has to rediscover it.

**Cap material.** The cap inherits from whichever original face has the most
similar normal, matching what `_faces_from_convex_hull()` already does for
clip-to-convex. A cut surface has no natural texture of its own, and the nearest
face is the least surprising answer.

### Space

The split runs in the brush's **local** space, with the world plane transformed
into it by `global_transform.affine_inverse()`. Both halves then keep the
original brush's `global_transform` untouched, and only their face data differs.
Nothing has to be re-centred, and rotation is carried for free rather than
handled.

### Keeping boxes boxes

A brush described by explicit faces is `CUSTOM`, which drops its resize handles.
That is the right answer for a genuinely angled piece and the wrong one for the
overwhelmingly common case: an axis-aligned box cut straight down the middle,
which today produces two boxes with handles intact.

So each piece is tested after the split. `is_axis_aligned_box()` returns the
size and centre when a face set is a six-faced box aligned to the brush's own
axes, and the piece is emitted as a `BOX` with that size instead of as `CUSTOM`.
Existing clips keep behaving exactly as they do now, and a rotated box clipped
down its own axis comes back as a box too, which it never could before.

### Clip

`clip_brush_by_plane(brush_id, plane)` is the new primitive. It validates that
both halves are non-empty, splits, and creates two pieces carrying the original's
operation, material, visgroups, group id, brush entity class and I/O metadata —
the same set `clip_brush_by_id()` copies today.

`clip_brush_by_id(brush_id, axis, split_pos)` keeps its signature, its grid
snapping, its bounds check and its error strings, and builds a world plane to
hand to the new primitive. Its `_check_axis_aligned_box()` guard is removed,
because the reason for it is gone.

`clip_brush_to_face_plane(brush_id, source_brush_id, face_index)` is the new
capability: cut one brush along the plane of a selected face. With rotation in
the toolbox this is how a designer gets a chamfer or an angled wall without
typing coordinates.

### Carve

Carve's existing algorithm is already the right one — it is just written against
six axis-aligned planes. Classic progressive-remainder carving says: for each
plane of the carver, split the target; the piece outside that plane is finished,
and the piece inside continues to the next plane. What is left after every plane
is the intersection, and it is discarded.

Generalising it means running that loop over the carver's actual face planes
instead of the six sides of its AABB. `_compute_slices()` is replaced by
`_carve_pieces()` over `HFConvexClip.split()`, which makes carve work with a
rotated carver, a cylinder, a wedge, or a merged brush.

Both `_check_axis_aligned_box()` guards in carve come out. The broad-phase AABB
overlap test stays: it is a cheap rejection, not a correctness assumption.

The existing UV-offset compensation for slice pieces goes away with the boxes it
was written for. Splitting carries UVs through the clip directly, which is exact
where the compensation formula was an approximation.

## Error handling

- A plane that misses the solid returns one empty side; callers report "the cut
  plane does not pass through the brush" rather than deleting anything.
- A cut that would produce a piece thinner than `min_thickness` is dropped, as
  carve already does, so slivers do not become brushes.
- A face set that produces fewer than four faces on a side is not a solid and is
  discarded.
- Every existing `HFOpResult` message and fix hint for clip and carve is kept.
  The two that name the axis-aligned restriction are removed with the
  restriction.

## Testing

`tests/test_convex_clip.gd` — the algorithm, with no scene:
- A box split down the middle gives two halves whose volumes sum to the original.
- Both halves are closed: every edge is shared by exactly two faces.
- Every face of both halves is wound clockwise from outside, asserted against the
  piece centroid — the check the free-transform wave learned to write, with an
  unsplit control beside it.
- The cap is planar, convex, and present on both halves with opposite winding.
- A plane that misses the solid returns one empty side and one full side.
- A plane exactly on a face returns the solid whole, not a zero-thickness sliver.
- Diagonal and arbitrary-angle planes on boxes, wedges and cylinders.
- `custom_uvs` interpolate along the cut rather than resetting.
- `is_axis_aligned_box()` recognises a box and rejects a wedge and a rotated box.

`tests/test_clip_tool.gd` — extended, and the two tests that pin the current
refusals are rewritten to assert the new behaviour:
- A rotated box clips into two pieces.
- A cylinder clips into two pieces.
- An axis-aligned box still clips into two `BOX` pieces with handles.
- Clip to face plane cuts along the chosen face.
- Metadata, material, operation, visgroups and group id still carry over.

`tests/test_carve_tool.gd` — new, since carve has no dedicated suite today:
- A rotated carver carves an unrotated target.
- A cylinder carver produces pieces around the cut.
- Carved pieces are closed and correctly wound, verified through a real bake.
- Every existing refusal that still applies still fires.

## Risks

**Winding, again.** The cap is built rather than transformed, so it is the one
surface here that can arrive inside out, and nothing in the viewport shows it.
The tests assert it at bake level with a control, which is what caught the
equivalent question last time.

**Slivers.** Floating-point classification near a face plane can produce
degenerate polygons. Every vertex within `epsilon` of the plane counts as on it,
and a side needing fewer than four faces is discarded rather than emitted.

**Behaviour change.** Clip and carve stop refusing brushes they refuse today.
That is the point, but it means the two tests asserting those refusals are
deliberately rewritten — not deleted — to assert what the operations now do.

## Verification

The same three passes as the free-transform wave: build test-first and get the
suite, `gdformat` and `gdlint` clean; then attack the result deliberately —
degenerate planes, planes on faces, planes through vertices, rotated and scaled
brushes, cylinders and merged brushes, closure and winding through a real bake,
undo and save round trips; then fold the findings back in and bring the
documentation in line with what shipped.
