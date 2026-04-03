@tool
extends RefCounted
class_name HFIOVisualizer

## Draws curved Bézier connection lines between entities with I/O connections.
## Color-coded by output type and delay. Arrowheads indicate direction.
## "Highlight Connected" mode pulses linked entities when one is selected.

var root: Node3D
var _mesh_instance: MeshInstance3D = null
var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var enabled: bool = false
var highlight_connected: bool = false
var _frame_counter: int = 0
var _pulse_phase: float = 0.0
var _highlight_overlays: Array = []  # MeshInstance3D nodes for pulse effect
const REFRESH_INTERVAL := 10  # Update every N frames
const CURVE_SEGMENTS := 12  # Segments per Bézier curve
const ARROW_SIZE := 0.18
const PULSE_SPEED := 4.0

# Color palette by output type keyword
const TYPE_COLORS: Dictionary = {
	"OnTrigger": Color(0.3, 0.85, 1.0, 0.85),  # Cyan — triggers
	"OnDamage": Color(1.0, 0.3, 0.3, 0.85),  # Red — damage
	"OnUse": Color(0.5, 1.0, 0.5, 0.85),  # Green — use/interact
	"OnBreak": Color(1.0, 0.6, 0.2, 0.85),  # Orange — destruction
	"OnTimer": Color(0.9, 0.9, 0.4, 0.85),  # Yellow — timed events
	"OnSpawn": Color(0.7, 0.5, 1.0, 0.85),  # Purple — spawning
}
const DEFAULT_COLOR := Color(0.2, 1.0, 0.3, 0.7)  # Green fallback
const FIRE_ONCE_COLOR := Color(1.0, 0.5, 0.0, 0.7)  # Orange — fire-once
const SELECTED_COLOR := Color(1.0, 1.0, 0.2, 0.9)  # Bright yellow
const DELAY_DIM_FACTOR := 0.6  # Dim connections with high delay
const PULSE_COLOR := Color(1.0, 1.0, 0.4, 0.6)  # Glow for highlight pulse


func _init(level_root: Node3D) -> void:
	root = level_root


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and _mesh_instance:
		_mesh_instance.visible = false
	if not enabled:
		_clear_highlight_overlays()
	if enabled:
		refresh()


func set_highlight_connected(value: bool) -> void:
	highlight_connected = value
	if not value:
		_clear_highlight_overlays()
	if value and enabled:
		refresh()


func process() -> void:
	if not enabled:
		return
	_frame_counter += 1
	_pulse_phase += 0.016 * PULSE_SPEED  # ~60fps assumed
	if _pulse_phase > TAU:
		_pulse_phase -= TAU
	if _frame_counter >= REFRESH_INTERVAL:
		_frame_counter = 0
		refresh()
	if highlight_connected and not _highlight_overlays.is_empty():
		_update_pulse()


func refresh() -> void:
	if not root or not enabled:
		return
	_ensure_mesh_instance()
	if not _immediate_mesh:
		return
	_immediate_mesh.clear_surfaces()
	if not root.entity_system:
		return
	var connections = root.entity_system.get_all_connections()
	if connections.is_empty():
		_mesh_instance.visible = false
		_clear_highlight_overlays()
		return
	_mesh_instance.visible = true
	# Determine which entity (if any) is selected
	var selected_names: Dictionary = {}
	if root.has_method("get_selected_entities"):
		var sel = root.get_selected_entities()
		for e in sel:
			if e is Node:
				selected_names[e.name] = true

	# Group connections by source→target pair to offset overlapping routes
	var route_counts: Dictionary = {}  # "src→tgt" -> count
	var route_indices: Dictionary = {}  # "src→tgt" -> current index
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var key = "%s→%s" % [str(conn.get("source_name", "")), str(conn.get("target_name", ""))]
		route_counts[key] = route_counts.get(key, 0) + 1

	# Track connected entities for highlight mode
	var connected_names: Dictionary = {}

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var source: Node3D = conn.get("source", null)
		if not source or not is_instance_valid(source):
			continue
		var target_name = str(conn.get("target_name", ""))
		if target_name == "":
			continue
		var targets = root.entity_system.find_entities_by_name(target_name)
		if targets.is_empty():
			continue
		var fire_once = bool(conn.get("fire_once", false))
		var source_name = str(conn.get("source_name", ""))
		var output_name = str(conn.get("output_name", ""))
		var delay = float(conn.get("delay", 0.0))
		var is_selected = selected_names.has(source_name) or selected_names.has(target_name)

		# Track connections for highlight mode
		if is_selected and highlight_connected:
			connected_names[source_name] = true
			connected_names[target_name] = true

		# Pick color
		var color: Color = _get_connection_color(output_name, fire_once, delay, is_selected)

		# Route key for offset calculation
		var route_key = "%s→%s" % [source_name, target_name]
		var route_idx: int = route_indices.get(route_key, 0)
		route_indices[route_key] = route_idx + 1
		var total_routes: int = route_counts.get(route_key, 1)

		for target in targets:
			if not (target is Node3D) or not is_instance_valid(target):
				continue
			var start_pos = source.global_position + Vector3(0, 0.3, 0)
			var end_pos = target.global_position + Vector3(0, 0.3, 0)
			_draw_curved_connection(start_pos, end_pos, color, route_idx, total_routes)
	_immediate_mesh.surface_end()

	# Update highlight overlays
	if highlight_connected and not selected_names.is_empty():
		_update_highlight_overlays(connected_names, selected_names)
	else:
		_clear_highlight_overlays()


func _get_connection_color(
	output_name: String, fire_once: bool, delay: float, is_selected: bool
) -> Color:
	if is_selected:
		return SELECTED_COLOR
	if fire_once:
		var c = FIRE_ONCE_COLOR
		if delay > 0.0:
			c = c.darkened(clampf(delay * 0.05, 0.0, DELAY_DIM_FACTOR))
		return c
	# Check type-specific colors
	for key in TYPE_COLORS:
		if output_name.begins_with(key) or output_name == key:
			var c: Color = TYPE_COLORS[key]
			if delay > 0.0:
				c = c.darkened(clampf(delay * 0.05, 0.0, DELAY_DIM_FACTOR))
			return c
	var c = DEFAULT_COLOR
	if delay > 0.0:
		c = c.darkened(clampf(delay * 0.05, 0.0, DELAY_DIM_FACTOR))
	return c


func _draw_curved_connection(
	start: Vector3, end: Vector3, color: Color, route_idx: int, total_routes: int
) -> void:
	var mid = (start + end) * 0.5
	var dist = start.distance_to(end)
	var up_offset = dist * 0.25  # Curve height proportional to distance

	# Offset parallel routes sideways to reduce crossing
	var direction = (end - start).normalized()
	var side = direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = direction.cross(Vector3.RIGHT).normalized()
	var lateral_offset := 0.0
	if total_routes > 1:
		lateral_offset = (float(route_idx) - float(total_routes - 1) * 0.5) * 0.3

	# Control point for quadratic Bézier — raised up and offset sideways
	var control = mid + Vector3(0, up_offset, 0) + side * lateral_offset

	# Draw curve segments
	var prev = start
	for i in range(1, CURVE_SEGMENTS + 1):
		var t = float(i) / float(CURVE_SEGMENTS)
		var pt = _quadratic_bezier(start, control, end, t)
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(prev)
		_immediate_mesh.surface_set_color(color)
		_immediate_mesh.surface_add_vertex(pt)
		prev = pt

	# Draw arrowhead at ~80% along the curve (pointing toward target)
	var arrow_t := 0.8
	var arrow_pos = _quadratic_bezier(start, control, end, arrow_t)
	var arrow_dir = _quadratic_bezier_tangent(start, control, end, arrow_t).normalized()
	_draw_arrowhead(arrow_pos, arrow_dir, color)


func _quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0 = p0.lerp(p1, t)
	var q1 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


func _quadratic_bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)


func _draw_arrowhead(pos: Vector3, dir: Vector3, color: Color) -> void:
	# Two wing lines perpendicular to direction
	var up = Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var right = dir.cross(up).normalized() * ARROW_SIZE
	var up_wing = up.cross(dir).normalized() * ARROW_SIZE
	# Ensure we use the actual perpendicular from cross products
	right = dir.cross(up).normalized() * ARROW_SIZE
	var wing_back = -dir * ARROW_SIZE * 1.5

	# Left wing
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos + wing_back + right)

	# Right wing
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos + wing_back - right)


# ---------------------------------------------------------------------------
# Highlight Connected — pulse overlays on linked entities
# ---------------------------------------------------------------------------


func _update_highlight_overlays(connected_names: Dictionary, selected_names: Dictionary) -> void:
	_clear_highlight_overlays()
	# Gather candidate nodes from both entities and brush entities
	var candidates: Array = []
	if root.entities_node:
		candidates.append_array(root.entities_node.get_children())
	if root.get("draft_brushes_node") and root.draft_brushes_node:
		candidates.append_array(root.draft_brushes_node.get_children())
	for child in candidates:
		if not is_instance_valid(child) or not (child is Node3D):
			continue
		var cname = child.name
		# Highlight connected entities but NOT the selected one itself
		if connected_names.has(cname) and not selected_names.has(cname):
			var overlay = _create_pulse_overlay(child)
			if overlay:
				_highlight_overlays.append(overlay)


func _create_pulse_overlay(entity: Node3D) -> MeshInstance3D:
	var sphere = SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	sphere.radial_segments = 8
	sphere.rings = 4
	var mi = MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = PULSE_COLOR
	mat.no_depth_test = true
	mi.material_override = mat
	mi.set_meta("_io_pulse_overlay", true)
	root.add_child(mi)
	mi.global_position = entity.global_position + Vector3(0, 0.3, 0)
	return mi


func _update_pulse() -> void:
	var alpha = 0.2 + 0.4 * (0.5 + 0.5 * sin(_pulse_phase))
	for overlay in _highlight_overlays:
		if not is_instance_valid(overlay):
			continue
		var mat = overlay.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = alpha


func _clear_highlight_overlays() -> void:
	for overlay in _highlight_overlays:
		if is_instance_valid(overlay):
			var parent: Node = overlay.get_parent()
			if parent:
				parent.remove_child(overlay)
			overlay.queue_free()
	_highlight_overlays.clear()


## Get a summary of what the selected entity is connected to.
## Returns: {"triggers": int, "triggered_by": int, "targets": Array[String]}
func get_connection_summary(entity_name: String) -> Dictionary:
	var summary: Dictionary = {
		"triggers": 0,
		"triggered_by": 0,
		"target_names": [],
		"source_names": [],
		"details": [],
	}
	if not root or not root.entity_system:
		return summary
	var connections = root.entity_system.get_all_connections()
	for conn in connections:
		if not (conn is Dictionary):
			continue
		var src = str(conn.get("source_name", ""))
		var tgt = str(conn.get("target_name", ""))
		var out_name = str(conn.get("output_name", ""))
		var inp_name = str(conn.get("input_name", ""))
		if src == entity_name:
			summary["triggers"] += 1
			if not summary["target_names"].has(tgt):
				summary["target_names"].append(tgt)
			summary["details"].append("%s → %s.%s" % [out_name, tgt, inp_name])
		elif tgt == entity_name:
			summary["triggered_by"] += 1
			if not summary["source_names"].has(src):
				summary["source_names"].append(src)
	return summary


func _ensure_mesh_instance() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "IOVisualizerMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _material:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.no_depth_test = true
	_mesh_instance.material_override = _material
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _immediate_mesh
	root.add_child(_mesh_instance)


func cleanup() -> void:
	_clear_highlight_overlays()
	if _mesh_instance and is_instance_valid(_mesh_instance):
		var parent: Node = _mesh_instance.get_parent()
		if parent:
			parent.remove_child(_mesh_instance)
		_mesh_instance.queue_free()
		_mesh_instance = null
	_immediate_mesh = null
