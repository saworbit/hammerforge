@tool
extends RefCounted
class_name HFGridSystem

## A turn smaller than this, in degrees, is the world's grid.
const TURN_EPSILON := 0.001

var root: Node3D
## View state only. A manual plane stays put until Reset Grid.
var _position_held := false
## The floor grid's turn about up, in degrees, and a point its lines run through
## (#1893), for a part of a level set at an angle. A wall grid stays the world's.
## View state, as the held plane is: never saved in the level. Kept between -45
## and 45, since a square grid looks the same every quarter turn, and 0 is the
## world's grid.
var turn_degrees := 0.0
var turn_origin := Vector3.ZERO


func _init(level_root: Node3D) -> void:
	root = level_root


func setup_editor_grid() -> void:
	if not Engine.is_editor_hint():
		var existing = root.get_node_or_null("EditorGrid") as MeshInstance3D
		if existing:
			existing.queue_free()
		return
	root.grid_mesh = root.get_node_or_null("EditorGrid") as MeshInstance3D
	if not root.grid_mesh:
		root.grid_mesh = MeshInstance3D.new()
		root.grid_mesh.name = "EditorGrid"
		root.add_child(root.grid_mesh)
	root.grid_mesh.owner = null
	var plane := PlaneMesh.new()
	plane.size = Vector2(root.grid_plane_size, root.grid_plane_size)
	root.grid_mesh.mesh = plane
	root.grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not root.grid_material:
		root.grid_material = ShaderMaterial.new()
		root.grid_material.shader = preload("../editor_grid.gdshader")
	root.grid_mesh.material_override = root.grid_material
	root.grid_mesh.visible = root._grid_visible
	root.grid_plane_origin = root.global_position
	root.grid_axis_preference = root.AxisLock.Y
	update_grid_material()
	update_grid_transform(root.grid_axis_preference, root.grid_plane_origin)


func set_grid_visible(value: bool) -> void:
	if root._grid_visible == value:
		return
	root._grid_visible = value
	if root.grid_mesh and root.grid_mesh.is_inside_tree():
		root.grid_mesh.visible = root._grid_visible


func update_grid_material() -> void:
	if not root.grid_material:
		return
	var size = max(root._grid_snap, 0.001)
	root.grid_material.set_shader_parameter("snap_size", size)
	root.grid_material.set_shader_parameter("grid_color", root.grid_color)
	root.grid_material.set_shader_parameter(
		"major_line_frequency", float(root.grid_major_line_frequency)
	)


## Brighten the two grid lines through `point`, where a draw would start
## (#1400). The point is in the world, and the shader finds it on the grid
## wherever the grid has moved to since, so a grid that follows the cursor
## keeps the lines on it.
func set_cursor(point: Vector3, shown: bool) -> void:
	if not root.grid_material:
		return
	root.grid_material.set_shader_parameter("cursor_point", point)
	root.grid_material.set_shader_parameter("cursor_visible", shown)


func update_grid_transform(axis: int, origin: Vector3) -> void:
	root.grid_plane_origin = origin
	if not root.grid_mesh or not root.grid_mesh.is_inside_tree():
		return
	var rot = Vector3.ZERO
	match axis:
		root.AxisLock.X:
			rot = Vector3(0.0, 0.0, -90.0)
		root.AxisLock.Z:
			rot = Vector3(90.0, 0.0, 0.0)
		_:
			rot = Vector3.ZERO
	root.grid_mesh.rotation_degrees = rot
	if is_turned() and axis == root.AxisLock.Y:
		# The lines are drawn from the mesh's own origin, so it stands on a point of
		# the turned grid, at the plane's height.
		var on_grid := grid_point(origin, maxf(root.grid_snap, 0.001))
		on_grid.y = origin.y
		root.grid_mesh.rotation_degrees = Vector3(0.0, turn_degrees, 0.0)
		root.grid_mesh.global_position = on_grid
		return
	root.grid_mesh.global_position = origin


## The world axis the grid's plane faces along.
func grid_normal() -> Vector3:
	var normal := Vector3.ZERO
	normal[effective_grid_axis() - 1] = 1.0
	return normal


## Whether the grid is turned: the floor grid is, while a turn is set.
func is_turned() -> bool:
	return turn_degrees != 0.0 and effective_grid_axis() == root.AxisLock.Y


## Turn the floor grid `degrees` about up, its lines through `origin` (#1893).
## Heights stay whole steps from the world origin: only where the lines run
## across the floor moves. A quarter turn, or none, is the world's grid.
func set_turn(degrees: float, origin: Vector3 = turn_origin) -> void:
	var turn := fposmod(degrees + 45.0, 90.0) - 45.0
	if absf(turn) < TURN_EPSILON:
		turn = 0.0
	turn_degrees = snappedf(turn, 0.0001)
	turn_origin = Vector3(origin.x, 0.0, origin.z) if turn_degrees != 0.0 else Vector3.ZERO
	refresh_grid_plane()
	if root.has_signal("grid_turn_changed"):
		root.emit_signal("grid_turn_changed", turn_degrees)


## The turn about up that lays the grid's X along `direction` in the floor's
## plane, in degrees, or null for a direction straight up or down.
static func turn_along(direction: Vector3) -> Variant:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.0001:
		return null
	return rad_to_deg(atan2(-flat.y, flat.x))


## The grid's own frame: its turn about up, through where its lines run. The
## world's frame when it is not turned.
func grid_frame() -> Transform3D:
	if not is_turned():
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3.UP, deg_to_rad(turn_degrees)), turn_origin)


## The grid point nearest `point`: a whole number of `step`s along each of the
## grid's own axes from where its lines run, the world's points when it is not
## turned. Every snap that reads the grid asks here (#1893).
func grid_point(point: Vector3, step: float) -> Vector3:
	if not is_turned():
		return nearest_grid_point(point, step)
	if not (step > 0.0):
		return point
	var frame := grid_frame()
	return frame * (frame.affine_inverse() * point).snapped(Vector3.ONE * step)


## `offset` in whole `step`s along the grid's own axes, for a drag that moves by
## steps rather than to points.
func grid_offset(offset: Vector3, step: float) -> Vector3:
	if not (step > 0.0):
		return offset
	if not is_turned():
		return offset.snapped(Vector3.ONE * step)
	var basis := grid_frame().basis
	return basis * (basis.inverse() * offset).snapped(Vector3.ONE * step)


func effective_grid_axis() -> int:
	if root.manual_axis_lock and root.axis_lock != root.AxisLock.NONE:
		return root.axis_lock
	return root.grid_axis_preference


func set_grid_plane_origin(origin: Vector3, axis: int) -> void:
	update_grid_transform(axis, origin)


func refresh_grid_plane() -> void:
	if not Engine.is_editor_hint():
		return
	var axis = effective_grid_axis()
	var origin = root.grid_plane_origin
	if not _position_held and origin == Vector3.ZERO and root.last_brush_center != Vector3.ZERO:
		origin = root.last_brush_center
	update_grid_transform(axis, origin)


## Record a completed draw's world-space base, despite the legacy center name.
## Restore/import callers must not move the construction plane.
func record_last_brush(center: Vector3) -> void:
	root.last_brush_center = center
	if _position_held:
		return
	root.grid_axis_preference = effective_grid_axis()
	set_grid_plane_origin(center, root.grid_axis_preference)


## The same commands for keys, the palette and dock buttons. No level mutation
## or undo step: these only choose where a later draw starts.
## `grid_up`/`grid_down` move one step; `grid_reset` returns to the root origin
## on Y. `grid_align` uses selected vertices, then a selected face's dominant
## world axis through its center, then selected brush bounds' top; none resets.
## The held plane is editor view state and is not serialized into the level.
func run_command(action: String, nodes: Array = []) -> void:
	match action:
		"grid_up", "grid_down":
			var axis := effective_grid_axis()
			var point: Vector3 = root.grid_plane_origin
			point[axis - 1] += maxf(root.grid_snap, 0.001) * (1.0 if action == "grid_up" else -1.0)
			_hold_plane(point, axis)
		"grid_reset":
			_position_held = false
			turn_degrees = 0.0
			turn_origin = Vector3.ZERO
			if root.has_signal("grid_turn_changed"):
				root.emit_signal("grid_turn_changed", 0.0)
			root.grid_axis_preference = root.AxisLock.Y
			root.manual_axis_lock = false
			root.axis_lock = root.AxisLock.NONE
			root.last_brush_center = root.global_position
			set_grid_plane_origin(root.global_position, root.AxisLock.Y)
		"grid_align":
			_align_to_selection(nodes)


## The grid point nearest `point`: a whole number of `step`s from the world
## origin on each axis, the points a draw snaps to (`LevelRoot._snap_point()`).
## A held drawing plane changes where a draw starts, not where the points are:
## `_hold_plane()` and `follow_cursor()` keep its origin on them across the
## plane, and only its height may sit between two.
static func nearest_grid_point(point: Vector3, step: float) -> Vector3:
	if not (step > 0.0):
		return point
	return point.snapped(Vector3.ONE * step)


## Whether Snap to Grid has a grid to snap to. A grid snap of 0 turns snapping
## off, and then there are no grid points to move anything onto.
func can_snap_to_grid() -> HFOpResult:
	if root.grid_snap > 0.0:
		return HFOpResult.success()
	return HFOpResult.fail("Snap to Grid: grid snap is off", "Set a grid size first")


func _hold_plane(point: Vector3, axis: int) -> void:
	_position_held = true
	root.grid_axis_preference = axis
	if root.manual_axis_lock:
		root.axis_lock = axis
	var snap: float = maxf(root.grid_snap, 0.001)
	var origin := grid_point(point, snap)
	origin[axis - 1] = point[axis - 1]
	set_grid_plane_origin(origin, axis)


func _align_to_selection(nodes: Array) -> void:
	var points: PackedVector3Array = root.vertex_system.get_selected_world_positions()
	var axis := effective_grid_axis()
	# One edge picked in Vertex mode turns the floor grid to run along it, through
	# its first end (#1893).
	var edge := _picked_edge()
	if edge.size() == 2:
		var along: Variant = turn_along(edge[1] - edge[0])
		if along != null:
			set_turn(float(along), edge[0])
	if points.is_empty():
		var picked: Dictionary = root.get_primary_selected_face()
		if not picked.is_empty():
			var brush: Node3D = picked["brush"]
			var faces: Array = brush.get_faces()
			var index := int(picked["face_idx"])
			if index >= 0 and index < faces.size():
				var face: FaceData = faces[index]
				face.ensure_geometry()
				var normal := face.normal_through(brush.global_basis)
				axis = normal.abs().max_axis_index() + 1
				for vertex in face.local_verts:
					points.append(brush.global_transform * vertex)
				# A floor or a ceiling takes its brush's turn.
				if axis == root.AxisLock.Y:
					_turn_with(brush)
	if not points.is_empty():
		var middle := Vector3.ZERO
		for point in points:
			middle += point
		_hold_plane(middle / float(points.size()), axis)
		return
	var bounds := AABB()
	var found := false
	for node in nodes:
		if not is_instance_valid(node) or not root.is_brush_node(node):
			continue
		var box: AABB = root.brush_system.world_bounds_of(node)
		if not found:
			# The grid takes the first brush's turn, square or not.
			_turn_with(node)
		bounds = bounds.merge(box) if found else box
		found = true
	if found:
		var point := bounds.get_center()
		point.y = bounds.end.y
		_hold_plane(point, root.AxisLock.Y)
	else:
		run_command("grid_reset")


## The two ends of the one edge picked in Vertex mode, in the world, or nothing
## when no edge or more than one is picked.
func _picked_edge() -> PackedVector3Array:
	var vertex_system = root.get("vertex_system")
	if vertex_system == null:
		return PackedVector3Array()
	var picked: Array = []
	for brush_id in vertex_system.selected_edges:
		for pair in vertex_system.selected_edges[brush_id]:
			picked.append([str(brush_id), pair])
	if picked.size() != 1:
		return PackedVector3Array()
	var brush = root.find_brush_by_id(picked[0][0])
	if brush == null:
		return PackedVector3Array()
	var corners: PackedVector3Array = vertex_system.get_brush_vertices(brush)
	var pair: Array = picked[0][1]
	if int(pair[0]) >= corners.size() or int(pair[1]) >= corners.size():
		return PackedVector3Array()
	var xform: Transform3D = brush.global_transform
	return PackedVector3Array([xform * corners[int(pair[0])], xform * corners[int(pair[1])]])


## Turn the floor grid as `brush` is turned about up, its lines along the brush's
## sides through its lowest corner, so a box drawn beside it lines up with it.
func _turn_with(brush: Node3D) -> void:
	var along: Variant = turn_along(brush.global_basis.x)
	if along == null:
		return
	var corner := Vector3.INF
	for face in brush.get_faces():
		if face == null:
			continue
		for vertex in (face as FaceData).local_verts:
			corner = corner.min(vertex)
	set_turn(float(along), brush.global_transform * corner if corner.is_finite() else Vector3.ZERO)


## Snap the other axes without rounding an explicitly aligned plane away. Only a
## hit on the plane itself keeps the plane's height: a draw that starts on a
## draft face or a physics surface starts on that surface. A `drag` snaps with
## the grid the drag's held keys ask for (#1431).
func snap_draw_hit(hit: Dictionary, drag := false) -> Vector3:
	var point: Vector3 = (
		root._snap_drag_point(hit["position"]) if drag else root._snap_point(hit["position"])
	)
	if _position_held and hit.get(root.CONSTRUCTION_PLANE_HIT, false):
		var index := effective_grid_axis() - 1
		point[index] = root.grid_plane_origin[index]
	return point


## Follow only along the plane, including when its exact height is off-grid.
func follow_cursor(camera: Camera3D, mouse_pos: Vector2) -> void:
	var axis := effective_grid_axis()
	var hit = intersect_axis_plane(camera, mouse_pos, axis, root.grid_plane_origin)
	if hit is Vector3:
		var point: Vector3 = grid_point(hit, maxf(root.grid_snap, 0.001))
		point[axis - 1] = root.grid_plane_origin[axis - 1]
		set_grid_plane_origin(point, axis)


func intersect_axis_plane(
	camera: Camera3D, mouse_pos: Vector2, axis: int, origin: Vector3
) -> Variant:
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var normal = Vector3.UP
	var distance = origin.y
	match axis:
		root.AxisLock.X:
			normal = Vector3.RIGHT
			distance = origin.x
		root.AxisLock.Z:
			normal = Vector3.BACK
			distance = origin.z
		_:
			normal = Vector3.UP
			distance = origin.y
	var denom = normal.dot(dir)
	if abs(denom) < 0.0001:
		return null
	var t = (distance - normal.dot(from)) / denom
	if t < 0.0:
		return null
	return from + dir * t


func update_editor_grid(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not Engine.is_editor_hint():
		return
	if not root._grid_visible:
		return
	if not root.grid_mesh or not root.grid_mesh.is_inside_tree() or not camera:
		return
	var axis = effective_grid_axis()
	if root.grid_follow_brush:
		follow_cursor(camera, mouse_pos)
		return
	update_grid_transform(axis, root.grid_plane_origin)
