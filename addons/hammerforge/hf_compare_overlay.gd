extends RefCounted
## A compare drawn in the viewport (#1701): what the open level added outlined
## solid, what changed outlined twice, and what it removed drawn dashed where the
## compared file has it. Each kind has its own line as well as its own colour, so
## the meaning does not rest on colour, and the colours are `HFOverlayColors`'s,
## so High Contrast and Settings cover them.
##
## The lines sit inside the level as an internal node with no owner, so they are
## never saved, never in the undo history, and gone with `clear()`.
##
## The brushes that did not change are faded, so what changed stands out in a
## level of hundreds (#1864). The fade is set on the rendering server alone, on
## the instance each brush draws its mesh through: the brush, its mesh node and
## its materials are not touched, so nothing of it is saved or in the history.

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
## How far the unchanged brushes fade unless the preferences say otherwise: 0 not
## at all, 1 out of sight.
const DEFAULT_FADE := 0.7

var _node: Node3D = null
var _segments := {"added": 0, "changed": 0, "removed": 0}
## The brushes that did not change, by id, faded again whenever their nodes are.
var _fade_ids: Array = []
## The brush nodes faded now, to bring back on `clear()`.
var _faded: Array[WeakRef] = []
var _fade := DEFAULT_FADE


## Draw `result`, from `HFLevelCompare.compare()`, over `root`, the open level,
## with the brushes that did not change faded by `fade`.
func show(root: Node, result: Dictionary, fade := DEFAULT_FADE) -> void:
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
	_fade = clampf(fade, 0.0, 1.0)
	_fade_ids = Array(brushes.get("same", []))
	refresh_fade(root)


func is_showing() -> bool:
	return _node != null and is_instance_valid(_node)


func clear() -> void:
	if _node != null and is_instance_valid(_node):
		if _node.get_parent():
			_node.get_parent().remove_child(_node)
		_node.queue_free()
	_node = null
	_unfade()
	_fade_ids = []


## Fade the unchanged brushes again, as `root` holds them now. An undo that
## rebuilt one made a new node, which starts unfaded.
func refresh_fade(root: Node) -> void:
	_unfade()
	if not is_showing() or root == null or not is_instance_valid(root):
		return
	for brush_id in _fade_ids:
		var brush: Node = root.find_brush_by_id(str(brush_id))
		if brush != null and _draw_fade(brush, _fade):
			_faded.append(weakref(brush))


## A new strength for the fade, as Settings changed it.
func set_fade(root: Node, fade: float) -> void:
	_fade = clampf(fade, 0.0, 1.0)
	refresh_fade(root)


## The ids of the brushes faded now.
func faded_ids() -> Array:
	var out: Array = []
	for ref in _faded:
		var brush = ref.get_ref()
		if brush != null and is_instance_valid(brush):
			out.append(str(brush.get("brush_id")))
	return out


func _unfade() -> void:
	for ref in _faded:
		var brush = ref.get_ref()
		if brush != null and is_instance_valid(brush):
			var drawn = brush.get("mesh_instance")
			if drawn is GeometryInstance3D:
				_draw_fade(brush, (drawn as GeometryInstance3D).transparency)
	_faded.clear()


## Set the transparency `brush` draws its mesh with on the rendering server, and
## leave the mesh node's own `transparency` as it is. False with no mesh to fade.
static func _draw_fade(brush: Node, value: float) -> bool:
	var drawn = brush.get("mesh_instance")
	if not (drawn is GeometryInstance3D) or not is_instance_valid(drawn):
		return false
	RenderingServer.instance_geometry_set_transparency(
		(drawn as GeometryInstance3D).get_instance(), value
	)
	return true


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
