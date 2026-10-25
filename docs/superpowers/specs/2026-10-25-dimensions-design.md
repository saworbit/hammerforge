# Dimensions that stay in the level (#1699)

## Where measuring stands

The Measure tool draws rulers between clicked points, and they live while the
tool is open. A size that matters, a doorway's width or a jump's height, is
checked once, and a later edit changes it with nothing to say so.

## The model

A **dimension** is an entity of the editor only class `dimension`, as a note is
(#1700). So it saves with the level and its prefabs, sits in visgroups, is
selected, moved, duplicated and deleted like any entity, and never reaches a
bake, an export or a running game, because its class says `editor_only`.

Its two ends are in its `entity_data`, each one of:

- `{"brush_id", "face", "corner"}`: a brush's vertex, as the face and corner it is;
- `{"brush_id", "face", "corner", "edge": true}`: the middle of the edge from that
  corner to the next;
- `{"brush_id", "face"}`: a face's centre;
- `{"point": [x, y, z]}`: a point attached to nothing, in the dimension's own space,
  so it moves when the dimension is moved.

An end is worked out from what it is attached to whenever it is read, never
stored as a world position. So a dimension follows a brush through every move,
turn, resize and undo, with no step of its own: the undo of the move is the undo
of the dimension's change. An end whose brush, face or corner has gone, as a Clip
leaves it, is **detached**: it reads its last place, kept on the node for the
session, and the dimension is drawn amber.

## Checks

`check` is one of None, At least player width, At least player height, At most
jump height, At most step height, At least and At most, the last two against
`value`. The player's sizes are `HFPlayerMetrics`'. A dimension whose check fails
is drawn red, and Validate lists it by name with its length and what it needs.

## Making one

**K** in the Measure tool keeps the last ruler as a dimension. Each end attaches to
the vertex, edge middle or face centre of a brush it lies on, within a millimetre,
and to nothing otherwise. One undo step. **Keep Ruler as Dimension** in the
palette does the same.

## Seeing them

Every dimension is drawn over the viewport: a line between its ends, ticks at
them, and its length at the middle, white, amber or red. **Show dimensions** in
the Console's Controls hides them all, and a visgroup hides its own.

## The bridge

`hf_get_status` counts the dimensions and how many fail. `hf_list_entities` gives
a dimension's length, its check and whether it passes beside its properties.
