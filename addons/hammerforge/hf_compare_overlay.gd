extends RefCounted
## A compare drawn in the viewport (#1701): what the open level added outlined
## solid, what changed outlined twice, and what it removed drawn dashed where the
## compared file has it. Each kind has its own line as well as its own colour, so
## the meaning does not rest on colour, and the colours are `HFOverlayColors`'s,
## so High Contrast and Settings cover them.
##
## The lines sit inside the level as an internal node with no owner, so they are
## never saved, never in the undo history, and gone with `clear()`.

const HFOutlineUtil = preload("hf_outline_util.gd")
const HFLevelCompare = preload("hf_level_compare.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFOverlayColors = preload("hf_overlay_colors.gd")
@warning_ignore_restore("shadowed_global_identifier")

const NODE_NAME := "HFCompare"
## The dashes of a removed brush: this long, with a gap as long.
const DASH := 0.2
## How far out a changed brush's second outline sits, as a share of its size.
const DOUBLE := 0.04
## An entity's outline, a box this many metres a side.
const ENTITY_BOX := 0.5

var _node: Node3D = null
var _segments := {"added": 0, "changed": 0, "removed": 0}


## Draw `result`, from `HFLevelCompare.compare()`, over `root`, the open level.
func show(root: Node, result: Dictionary) -> void:
	clear()
	_segments = {"added": 0, "changed": 0, "removed": 0}
	if root == null or not is_instance_valid(root):
		return
	var added := PackedVector3Array()
	var changed := PackedVector3Array()
	var removed := PackedVector3Array()
	var brushes: Dictionary = result.get("brushes", {})
	for brush_id in brushes.get("added", []):
		var node = root.find_brush_by_id(str(brush_id))
		if node:
			added.append_array(_outline_of_node(node))
	for entry in brushes.get("changed", []):
		var node = root.find_brush_by_id(str(entry["id"]))
		if node:
			changed.append_array(_doubled(_outline_of_node(node)))
	for info in brushes.get("removed", []):
		removed.append_array(_dashed(lines_of_record(info)))
	var entities: Dictionary = result.get("entities", {})
	for entity_name in entities.get("added", []):
		var node := _entity(root, str(entity_name))
		if node:
			added.append_array(_box_at(node.global_position))
	for entry in entities.get("changed", []):
		var node := _entity(root, str(entry["name"]))
		if node:
			changed.append_array(_doubled(_box_at(node.global_position)))
	for info in entities.get("removed", []):
		removed.append_array(_dashed(_box_at(HFLevelCompare._entity_place(info))))
	if added.is_empty() and changed.is_empty() and removed.is_empty():
		return
	_node = Node3D.new()
	_node.name = NODE_NAME
	# Inside the level and never saved with it.
	root.add_child(_node, false, Node.INTERNAL_MODE_BACK)
	_node.global_transform = Transform3D.IDENTITY
	_add_lines(added, HFOverlayColors.COMPARE_ADDED)
	_add_lines(changed, HFOverlayColors.COMPARE_CHANGED)
	_add_lines(removed, HFOverlayColors.COMPARE_REMOVED)


func is_showing() -> bool:
	return _node != null and is_instance_valid(_node)


func clear() -> void:
	if _node != null and is_instance_valid(_node):
		if _node.get_parent():
			_node.get_parent().remove_child(_node)
		_node.queue_free()
	_node = null


## How many line segments of each kind are drawn: `{added, changed, removed}`.
func segments() -> Dictionary:
	return _segments.duplicate() if is_showing() else {"added": 0, "changed": 0, "removed": 0}


func _add_lines(points: PackedVector3Array, color_key: String) -> void:
	_segments[color_key.trim_prefix("color_compare_")] = int(points.size() / 2.0)
	if points.is_empty():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = HFOverlayColors.get_color(color_key)
	var lines := MeshInstance3D.new()
	lines.name = color_key.trim_prefix("color_compare_")
	lines.mesh = mesh
	lines.material_override = material
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.add_child(lines)


static func _outline_of_node(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var faces = node.get("faces")
	if faces is Array and not (faces as Array).is_empty():
		for point in HFOutlineUtil.face_boundary_lines(faces):
			out.append(node.global_transform * point)
	return out


## The edges of a brush record from the compared file, in world space: each
## face's corners in turn, as the record keeps them.
static func lines_of_record(info: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xform := HFLevelCompare._transform_of(info)
	for face in info.get("faces", []):
		if not (face is Dictionary):
			continue
		var corners: Array = Array(face.get("local_verts", []))
		for i in corners.size():
			out.append(xform * HFLevelCompare.corner(corners[i]))
			out.append(xform * HFLevelCompare.corner(corners[(i + 1) % corners.size()]))
	return out


## Each segment of `lines` cut into dashes.
static func _dashed(lines: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, lines.size() - 1, 2):
		var a := lines[i]
		var b := lines[i + 1]
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			out.append(a.lerp(b, at / length))
			out.append(a.lerp(b, minf(at + DASH, length) / length))
			at += DASH * 2.0
	return out


## `lines` and a second copy a little out from their middle.
static func _doubled(lines: PackedVector3Array) -> PackedVector3Array:
	if lines.is_empty():
		return lines
	var box := AABB(lines[0], Vector3.ZERO)
	for point in lines:
		box = box.expand(point)
	var middle := box.get_center()
	var out := lines.duplicate()
	for point in lines:
		out.append(middle + (point - middle) * (1.0 + DOUBLE))
	return out


static func _box_at(at: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in HFOutlineUtil.box_lines(Vector3.ONE * ENTITY_BOX):
		out.append(at + point)
	return out


static func _entity(root: Node, entity_name: String) -> Node3D:
	var entities = root.get("entities_node")
	if entities == null:
		return null
	return entities.get_node_or_null(NodePath(entity_name)) as Node3D
