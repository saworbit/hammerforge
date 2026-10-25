@tool
extends RefCounted
## What an agent just changed, outlined in the viewport for a moment (#1653).
##
## After each change from the bridge the brushes and entities it changed are
## outlined in the agent colour, which fades over `SECONDS`. When none of them is
## in view, an arrow at the edge of the viewport points toward them for the same
## time. The plugin never moves the camera: the panel's Last line selects what
## changed, and Focus Selection frames it.

const HFOutlineUtil = preload("hf_outline_util.gd")
const HFAccessibility = preload("hf_accessibility.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFOverlayColors = preload("hf_overlay_colors.gd")
@warning_ignore_restore("shadowed_global_identifier")

const SECONDS := 1.5
const NODE_NAME := "HFAgentChanges"
## An entity's outline, a box this many metres a side.
const ENTITY_BOX := 0.5
## The edge arrow, in pixels: how far in from the edge, and how long.
const ARROW_INSET := 28.0
const ARROW_LENGTH := 22.0

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _targets: Array = []


## Outline `nodes`, brushes and entities, under `root`, fading over `SECONDS`;
## `finished` is called once it has gone, for the plugin to take the arrow down.
func show(root: Node, nodes: Array, finished: Callable = Callable()) -> void:
	clear()
	_targets = nodes.filter(func(node): return node is Node3D and is_instance_valid(node))
	if _targets.is_empty() or root == null or not is_instance_valid(root):
		return
	var lines := PackedVector3Array()
	for node in _targets:
		lines.append_array(outline_of(node))
	if lines.is_empty():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in lines:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.albedo_color = HFOverlayColors.get_color(HFOverlayColors.AGENT_CHANGE)
	_mesh = MeshInstance3D.new()
	_mesh.name = NODE_NAME
	_mesh.mesh = mesh
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Inside the level and never saved with it.
	root.add_child(_mesh, false, Node.INTERNAL_MODE_BACK)
	_mesh.global_transform = Transform3D.IDENTITY
	var tween := _mesh.create_tween()
	if HFAccessibility.reduce_motion():
		tween.tween_interval(SECONDS)
	else:
		tween.tween_method(_fade, 1.0, 0.0, SECONDS)
	tween.tween_callback(_done.bind(finished))


func _fade(strength: float) -> void:
	if _material:
		var base := HFOverlayColors.get_color(HFOverlayColors.AGENT_CHANGE)
		_material.albedo_color = Color(base, base.a * strength)


func _done(finished: Callable) -> void:
	clear()
	if finished.is_valid():
		finished.call()


func is_showing() -> bool:
	return _mesh != null and is_instance_valid(_mesh)


func clear() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		if _mesh.get_parent():
			_mesh.get_parent().remove_child(_mesh)
		_mesh.queue_free()
	_mesh = null
	_material = null


## The lines round one brush or entity, in world space.
static func outline_of(node: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var faces = node.get("faces")
	if faces is Array and not (faces as Array).is_empty():
		var xform := node.global_transform
		for point in HFOutlineUtil.face_boundary_lines(faces):
			out.append(xform * point)
		return out
	var box := HFOutlineUtil.box_lines(Vector3.ONE * ENTITY_BOX)
	for point in box:
		out.append(node.global_position + point)
	return out


## Where the edge arrow goes when no outlined node is in `camera`'s view:
## `{at, angle}` in the viewport's pixels, pointing toward the nodes, or `{}` when
## one of them is in view or there are none.
static func edge_arrow(camera: Camera3D, viewport_size: Vector2, targets: Array) -> Dictionary:
	if camera == null or targets.is_empty():
		return {}
	var centre := Vector3.ZERO
	var count := 0
	for node in targets:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var at := (node as Node3D).global_position
		if camera.is_position_in_frustum(at):
			return {}
		centre += at
		count += 1
	if count == 0:
		return {}
	centre /= float(count)
	var middle := viewport_size * 0.5
	# Behind the camera, the projection mirrors; aim by the side it is on instead.
	var local := camera.global_transform.affine_inverse() * centre
	var toward := Vector2(local.x, -local.y)
	if toward.length_squared() < 0.000001:
		toward = Vector2.DOWN
	toward = toward.normalized()
	var reach := middle - Vector2.ONE * ARROW_INSET
	var scale := minf(
		reach.x / maxf(absf(toward.x), 0.0001), reach.y / maxf(absf(toward.y), 0.0001)
	)
	return {"at": middle + toward * scale, "angle": toward.angle()}


## Draw the edge arrow on the viewport's overlay, when there is one to draw.
func draw_edge_arrow(overlay: Control, camera: Camera3D) -> void:
	if not is_showing() or overlay == null:
		return
	var arrow := edge_arrow(camera, overlay.size, _targets)
	if arrow.is_empty():
		return
	var color := HFOverlayColors.get_color(HFOverlayColors.AGENT_CHANGE)
	var tip: Vector2 = arrow["at"]
	var back := Vector2.from_angle(float(arrow["angle"]) + PI) * ARROW_LENGTH
	var side := back.orthogonal() * 0.45
	overlay.draw_colored_polygon(
		PackedVector2Array([tip, tip + back + side, tip + back - side]), color
	)
