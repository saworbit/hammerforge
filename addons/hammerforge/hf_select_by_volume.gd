@tool
extends RefCounted
## Which brushes and entities a throwaway brush picks (#1717).
##
## Draw a brush around a room and run Select Inside, Select Partly Inside, Select
## Touching or Select Column: the brushes and entities it picks become the
## selection and the throwaway brush is deleted, so the level is left as it was.
## The brush is measured as the convex solid it is, as `hf_measure` measures it,
## so a turned box picks what is in it and not what is in its bounds.
##
## - `inside`: every corner of a brush inside the volume; an entity standing in it.
## - `partly`: a brush that goes into the volume at all; an entity in it.
## - `touching`: a brush that touches or overlaps it; an entity on it or in it.
## - `column`: as `inside`, with the volume's footprint running from the bottom of
##   the level to the top, so a box drawn on one floor picks what is above and
##   below it on every floor.
##
## Only what can be seen and picked: a brush or entity a visgroup hides stays out.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFSolidMeasure = preload("hf_solid_measure.gd")

const MODES := ["inside", "partly", "touching", "column"]


## The pickable brushes and entities `volume` picks in `mode`, in level order.
static func pick(root: Node, volume: Node3D, mode: String) -> Array:
	var faces := HFSolidMeasure.world_faces(volume)
	var footprint := _footprint(faces) if mode == "column" else PackedVector2Array()
	var out: Array = []
	for node in root._iter_pick_nodes():
		if node == volume or not (node is Node3D) or not is_instance_valid(node):
			continue
		if not (node as Node3D).is_visible_in_tree():
			continue
		if _picks(node, faces, footprint, mode):
			out.append(node)
	return out


static func _picks(node: Node, faces: Array, footprint: PackedVector2Array, mode: String) -> bool:
	if node is DraftEntity:
		var at := (node as Node3D).global_position
		if mode == "column":
			return Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), footprint)
		return HFSolidMeasure.point_gap(at, faces) <= HFSolidMeasure.TOUCH
	if not (node is DraftBrush):
		return false
	var other := HFSolidMeasure.world_faces(node)
	if other.is_empty():
		return false
	match mode:
		"inside":
			for corner in _corners(other):
				if HFSolidMeasure.point_gap(corner, faces) > HFSolidMeasure.TOUCH:
					return false
			return true
		"partly":
			return HFSolidMeasure.solid_gap(other, faces) < 0.0
		"touching":
			return HFSolidMeasure.solid_gap(other, faces) <= 0.0
		"column":
			for corner in _corners(other):
				if not _in_footprint(corner, footprint):
					return false
			return true
	return false


## The volume seen from above: the hull of its corners on the ground.
static func _footprint(faces: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in _corners(faces):
		points.append(Vector2(corner.x, corner.z))
	return Geometry2D.convex_hull(points)


## Whether a corner is in the footprint or on its edge.
static func _in_footprint(corner: Vector3, footprint: PackedVector2Array) -> bool:
	var at := Vector2(corner.x, corner.z)
	if Geometry2D.is_point_in_polygon(at, footprint):
		return true
	for i in footprint.size():
		var edge_point := Geometry2D.get_closest_point_to_segment(
			at, footprint[i], footprint[(i + 1) % footprint.size()]
		)
		if at.distance_to(edge_point) <= HFSolidMeasure.TOUCH:
			return true
	return false


static func _corners(faces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in faces:
		out.append_array(HFSolidMeasure.ring(face))
	return out
