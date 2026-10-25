@tool
extends RefCounted
class_name HFDragSystem

const HFInputStateType = preload("../input_state.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What a draw starts on, which the hover preview shows before the click (#1400):
## the grid over empty space, a face level with the grid, a flat face at another
## height, a face that is not flat (the draw still starts flat, at the height it
## was clicked), or with Draw on Face the plane of a face that is not a floor (#1401).
enum StartKind { GRID, LEVEL, RAISED, SLOPED, FACE }

## How near a face's normal has to be to straight up or down for the face to be
## flat. A face of an unturned box is exactly level; this only absorbs rounding.
const FLAT_DOT := 0.9999
## How near a normal has to be to one world axis for the face to snap to the
## world grid. Past this a face is slanted, and snaps along its own axes.
const AXIS_DOT := 0.9999
## How far a start may sit from the grid plane and still be level with it.
const LEVEL_EPSILON := 0.001

## The shapes whose ground footprint is a circle, so a dragged rectangle has to
## be reduced to one diameter before it can become a brush.
const RADIAL_SHAPES := [
	DraftBrush.BrushShape.CYLINDER,
	DraftBrush.BrushShape.CONE,
	DraftBrush.BrushShape.SPHERE,
	DraftBrush.BrushShape.CAPSULE,
]

var root: Node3D
var input_state: HFInputStateType = HFInputStateType.new()
## The brush the last Draw made, for Repeat (#1407): its `shape`, `size` and
## `operation`, and its `sides` and `material` when it had them. Empty until a
## Draw places one.
var last_drawn: Dictionary = {}
## Whether the draw under way builds in a turned grid's frame rather than a
## face's (#1893), so a Cutout grows from the floor as a plain draw's does.
var _frame_from_grid := false


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Drag lifecycle
# ---------------------------------------------------------------------------


## With `on_face`, a draw that starts on a face builds on that face's plane
## (#1401): see `face_frame()`. Over empty space it is an ordinary draw.
func begin_drag(
	camera: Camera3D,
	mouse_pos: Vector2,
	operation: int,
	size: Vector3,
	shape: int,
	sides: int = 4,
	on_face: bool = false
) -> bool:
	if not input_state.is_idle():
		return false
	var start := draw_start(camera, mouse_pos, on_face)
	if start.is_empty():
		return false
	var snapped_origin: Vector3 = start["point"]
	var frame: Variant = start.get("frame", null)
	_frame_from_grid = bool(start.get("grid_frame", false))
	if frame is Transform3D:
		# The base is laid out in the face's frame, which starts at this point.
		snapped_origin = Vector3.ZERO
	var height = root.grid_snap if root.grid_snap > 0.0 else size.y
	input_state.begin_drag(snapped_origin, operation, shape, sides, height, size, mouse_pos, frame)
	_ensure_preview(shape, operation, size, sides)
	_update_preview(
		snapped_origin,
		snapped_origin,
		height,
		shape,
		size,
		_current_axis_lock(),
		input_state.shift_pressed and not input_state.alt_pressed,
		input_state.shift_pressed and input_state.alt_pressed
	)
	return true


func update_drag(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not input_state.is_dragging():
		return
	if input_state.is_drag_base() and input_state.drag_on_face:
		_update_face_base(camera, mouse_pos)
		return
	if input_state.is_drag_base():
		var hit = root._raycast(camera, mouse_pos)
		if not hit:
			return
		# A dimension typed into the HUD owns the field it was typed for until the
		# buffer empties. Recomputing it here is what made the number look like it
		# did nothing: it went on screen and the mouse took it straight back.
		var typed_base := input_state.has_numeric_override()
		# `6,` holds the width and lets the mouse set the depth (#1693).
		var partial := typed_base and not (input_state.typed_lock_x and input_state.typed_lock_z)
		if (
			(not input_state.alt_pressed or input_state.shift_pressed)
			and (not typed_base or partial)
		):
			var held: Vector3 = input_state.drag_end
			input_state.drag_end = root.grid_system.snap_draw_hit(hit, true)
			input_state.drag_end = _apply_axis_lock(input_state.drag_origin, input_state.drag_end)
			if partial:
				input_state.drag_end = _keep_typed_sides(input_state.drag_end, held)
			_update_lock_state(input_state.drag_origin, input_state.drag_end)
		if input_state.alt_pressed:
			input_state.drag_height = _height_from_mouse(
				mouse_pos,
				input_state.height_stage_start_mouse,
				input_state.height_stage_start_height
			)
		_update_preview(
			input_state.drag_origin,
			input_state.drag_end,
			input_state.drag_height,
			input_state.drag_shape,
			input_state.drag_size_default,
			_current_axis_lock(),
			input_state.shift_pressed and not input_state.alt_pressed,
			input_state.shift_pressed and input_state.alt_pressed
		)
	elif input_state.is_drag_height():
		if not input_state.has_numeric_override():
			input_state.drag_height = _height_from_mouse(
				mouse_pos,
				input_state.height_stage_start_mouse,
				input_state.height_stage_start_height
			)
		_update_preview(
			input_state.drag_origin,
			input_state.drag_end,
			input_state.drag_height,
			input_state.drag_shape,
			input_state.drag_size_default,
			_current_axis_lock(),
			input_state.shift_pressed and not input_state.alt_pressed,
			input_state.shift_pressed and input_state.alt_pressed
		)


func end_drag_info(_camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> Dictionary:
	if not input_state.is_dragging():
		return {"handled": false}
	if input_state.is_drag_base():
		input_state.advance_to_height(mouse_pos)
		return {"handled": true, "placed": false}
	var info = _build_brush_info(
		input_state.drag_origin,
		input_state.drag_end,
		input_state.drag_height,
		input_state.drag_shape,
		size_default,
		input_state.drag_operation,
		input_state.shift_pressed and not input_state.alt_pressed,
		input_state.shift_pressed and input_state.alt_pressed
	)
	# A draw on a wall or a slope leaves the drawing plane where it was: a window
	# cut in a wall is no reason for the floor grid to rise to its sill.
	if not input_state.drag_on_face:
		info["draw_origin"] = input_state.drag_origin
	elif input_state.drag_frame.basis.y.dot(Vector3.UP) >= FLAT_DOT:
		info["draw_origin"] = input_state.drag_frame.origin
	last_drawn = _repeatable(info)
	input_state.end_drag()
	_clear_preview()
	return {"handled": true, "placed": true, "info": info}


## What Repeat keeps of a Draw's info: the brush, not where it went.
static func _repeatable(info: Dictionary) -> Dictionary:
	var kept := {"shape": info["shape"], "size": info["size"], "operation": info["operation"]}
	for key in ["sides", "material"]:
		if info.has(key):
			kept[key] = info[key]
	return kept


## A copy of `brush`, a brush `last_drawn` describes, standing on `base`: centred
## over the point with its bottom on it, as the info `create_brush_from_info()`
## takes, with an id of its own. The grid moves to it, as it does after a Draw.
func repeat_info(brush: Dictionary, base: Vector3) -> Dictionary:
	var size: Vector3 = brush["size"]
	var operation := int(brush["operation"])
	var info := {
		"shape": brush["shape"],
		"size": size,
		"center": base + Vector3(0.0, size.y * 0.5, 0.0),
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id(),
		"draw_origin": base,
	}
	for key in ["sides", "material"]:
		if brush.has(key):
			info[key] = brush[key]
	return info


func end_drag(camera: Camera3D, mouse_pos: Vector2, size_default: Vector3) -> bool:
	var result = end_drag_info(camera, mouse_pos, size_default)
	if not result.get("handled", false):
		return false
	if result.get("placed", false):
		root.create_brush_from_info(result.get("info", {}))
	return true


func cancel_drag() -> void:
	input_state.cancel()
	_clear_preview()


# ---------------------------------------------------------------------------
# Where a draw starts
# ---------------------------------------------------------------------------


## Where a Draw that starts at `mouse_pos` starts, snapped with the grid the held
## keys ask for (#1431). `begin_drag()` starts there and the hover preview shows
## it (#1400), so what the preview promises is what the click does. Repeat stands
## its copies on its `point` too (#1407). Empty where the ray meets nothing.
## `describe_start()` says what it holds.
func draw_start(camera: Camera3D, mouse_pos: Vector2, on_face: bool = false) -> Dictionary:
	var hit = root._raycast(camera, mouse_pos)
	if not hit:
		return {}
	return describe_start(hit, root.grid_system.snap_draw_hit(hit, true), on_face)


## What a draw from `hit` starts on, with `point` where the tool snaps the hit.
## Polygon and Path snap their first point their own way and pass it in, so
## their preview shows where they start too.
##
## - `point`: where the draw starts.
## - `kind`: a `StartKind`.
## - `normal`: the world normal of the face under the cursor, or of the grid
##   plane over empty space.
## - `brush`, `face_idx`: the draft face under the cursor, or null and -1. A
##   physics hit has a normal and no face.
## - `frame`: with `on_face`, the face's frame from `face_frame()`, through the
##   start point. On a turned grid, a flat start's frame turned as the grid is,
##   with `grid_frame` true when no face asked for it (#1893). Absent for a draw
##   that builds flat on the world's grid.
func describe_start(hit: Dictionary, point: Vector3, on_face: bool = false) -> Dictionary:
	var start := {
		"point": point,
		"kind": StartKind.GRID,
		"normal": _grid_normal(),
		"brush": null,
		"face_idx": -1,
	}
	if hit.get(root.CONSTRUCTION_PLANE_HIT, false):
		_turn_with_grid(start)
		return start
	var normal := surface_normal(hit)
	if normal == Vector3.ZERO:
		_turn_with_grid(start)
		return start
	start["normal"] = normal
	if hit.get("brush", null) is DraftBrush:
		start["brush"] = hit["brush"]
		start["face_idx"] = int(hit.get("face_idx", -1))
	if on_face:
		var face_point := face_start_point(hit["position"], normal)
		start["point"] = face_point
		start["frame"] = face_frame(normal, face_point)
		if normal.dot(Vector3.UP) < FLAT_DOT:
			start["kind"] = StartKind.FACE
			return start
	if absf(normal.dot(Vector3.UP)) < FLAT_DOT:
		start["kind"] = StartKind.SLOPED
	elif _on_grid_plane(start["point"]):
		start["kind"] = StartKind.LEVEL
	else:
		start["kind"] = StartKind.RAISED
	if start["kind"] != StartKind.SLOPED:
		_turn_with_grid(start)
	return start


## On a turned floor grid (#1893) a draw that starts flat builds square to it, in
## a frame turned as the grid is through the start point, the way a Draw on Face
## builds in the face's frame. A Draw on Face on a floor turns its frame the
## same way. The world's grid leaves `start` as it was.
func _turn_with_grid(start: Dictionary) -> void:
	var grid = root.get("grid_system")
	if grid == null or not grid.is_turned():
		return
	var turn := Basis(Vector3.UP, deg_to_rad(float(grid.turn_degrees)))
	var frame: Variant = start.get("frame", null)
	if frame is Transform3D:
		start["frame"] = Transform3D(turn * (frame as Transform3D).basis, frame.origin)
		return
	start["frame"] = Transform3D(turn, start["point"])
	start["grid_frame"] = true


## The world normal of the surface `hit` is on: a physics hit's own, or a draft
## face's through its brush's transform. A normal within `AXIS_DOT` of a world
## axis is put exactly on it, so a box drawn on a wall is turned by a whole
## quarter turn and not by a rounding error. Zero for the grid plane.
func surface_normal(hit: Dictionary) -> Vector3:
	var normal := Vector3.ZERO
	var brush = hit.get("brush", null)
	var face_idx := int(hit.get("face_idx", -1))
	if brush is DraftBrush and is_instance_valid(brush):
		if face_idx >= 0 and face_idx < brush.faces.size() and brush.faces[face_idx] != null:
			var face = brush.faces[face_idx]
			face.ensure_geometry()
			normal = face.normal_through(brush.global_basis)
	elif hit.get("normal") is Vector3:
		normal = (hit["normal"] as Vector3).normalized()
	if not normal.is_finite() or normal.is_zero_approx():
		return Vector3.ZERO
	var axis := _world_axis_of(normal)
	if axis >= 0:
		var exact := Vector3.ZERO
		exact[axis] = signf(normal[axis])
		return exact
	return normal


## Where a Draw on Face starts on the face through `position` facing `normal`
## (#1401). On a face along a world axis, the nearest snap point that stays on
## the face's plane: the snap moves the point across the face, never off it. On
## a slanted face the hit itself, which the face's own grid steps count from.
func face_start_point(position: Vector3, normal: Vector3) -> Vector3:
	var axis := _world_axis_of(normal)
	if axis < 0:
		return position
	var point: Vector3 = root._snap_point(position)
	point[axis] = position[axis]
	return point


## The frame a Draw on Face builds in (#1401): local Y is the face's outward
## normal, local X runs level along the face (world X on a floor or a ceiling),
## and local Z is X cross Y. That last makes the basis right handed. A left
## handed one turns every face of the new brush inside out, with nothing to show
## for it until the bake.
static func face_frame(normal: Vector3, origin: Vector3) -> Transform3D:
	var up := normal.normalized()
	var across := Vector3.RIGHT
	if absf(up.dot(Vector3.UP)) < FLAT_DOT:
		across = up.cross(Vector3.UP)
	across = (across - up * up.dot(across)).normalized()
	return Transform3D(Basis(across, up, across.cross(up)), origin)


## The index of the world axis `normal` lies along, or -1 for a slanted one.
static func _world_axis_of(normal: Vector3) -> int:
	for axis in 3:
		if absf(normal[axis]) >= AXIS_DOT:
			return axis
	return -1


func _grid_normal() -> Vector3:
	var normal := Vector3.ZERO
	normal[root.grid_system.effective_grid_axis() - 1] = 1.0
	return normal


## Whether a flat start sits on the grid plane, so the draw starts where it
## would over empty space.
func _on_grid_plane(point: Vector3) -> bool:
	if root.grid_system.effective_grid_axis() != root.AxisLock.Y:
		return false
	return absf(point.y - root.grid_plane_origin.y) < LEVEL_EPSILON


# ---------------------------------------------------------------------------
# Draw on Face (#1401)
# ---------------------------------------------------------------------------


## The base stage of a Draw on Face. The far corner follows the cursor across
## the face's whole plane, past the face's own edges, as a draw on the grid
## follows it past the brush it started on.
func _update_face_base(camera: Camera3D, mouse_pos: Vector2) -> void:
	var typed_base := input_state.has_numeric_override()
	var partial := typed_base and not (input_state.typed_lock_x and input_state.typed_lock_z)
	if (not input_state.alt_pressed or input_state.shift_pressed) and (not typed_base or partial):
		var corner: Variant = _face_point_under(camera, mouse_pos)
		if corner is Vector3:
			input_state.drag_end = (
				_keep_typed_sides(corner, input_state.drag_end) if partial else corner
			)
	if input_state.alt_pressed:
		input_state.drag_height = _height_from_mouse(
			mouse_pos, input_state.height_stage_start_mouse, input_state.height_stage_start_height
		)
	_update_preview(
		input_state.drag_origin,
		input_state.drag_end,
		input_state.drag_height,
		input_state.drag_shape,
		input_state.drag_size_default,
		_current_axis_lock(),
		input_state.shift_pressed and not input_state.alt_pressed,
		input_state.shift_pressed and input_state.alt_pressed
	)


## `end` with the sides a typed base holds put back from `held` (#1693).
func _keep_typed_sides(end: Vector3, held: Vector3) -> Vector3:
	if input_state.typed_lock_x:
		end.x = held.x
	if input_state.typed_lock_z:
		end.z = held.z
	return end


## Where the screen ray meets the face's plane, snapped and in the face's frame,
## or null when the ray runs along the plane or away from it.
func _face_point_under(camera: Camera3D, mouse_pos: Vector2) -> Variant:
	if camera == null:
		return null
	var frame := input_state.drag_frame
	var plane := Plane(frame.basis.y, frame.origin)
	var on_plane: Variant = plane.intersects_ray(
		camera.project_ray_origin(mouse_pos), camera.project_ray_normal(mouse_pos)
	)
	if not (on_plane is Vector3):
		return null
	return _snap_on_face(on_plane)


## A point on the face's plane, snapped, in the face's frame. A face along a
## world axis snaps to the world grid as any draw does; a slanted one in grid
## steps along its own axes from where the draw started.
func _snap_on_face(world: Vector3) -> Vector3:
	var frame := input_state.drag_frame
	var axis := _world_axis_of(frame.basis.y)
	var local: Vector3
	if axis >= 0:
		var on_grid: Vector3 = root._snap_drag_point(world)
		on_grid[axis] = frame.origin[axis]
		local = frame.affine_inverse() * on_grid
	else:
		local = frame.affine_inverse() * world
		var step: float = root.drag_grid_step()
		if step > 0.0:
			local.x = snappedf(local.x, step)
			local.z = snappedf(local.z, step)
	local.y = 0.0
	return local


## Where a box worked out in the face's frame goes in the world. A Solid grows
## out of the face and a Cutout into it, so a window is a Cutout drawn on the
## wall and pulled to the wall's depth.
func _face_transform(computed: Dictionary) -> Transform3D:
	var center: Vector3 = computed.center
	if input_state.drag_operation == CSGShape3D.OPERATION_SUBTRACTION and not _frame_from_grid:
		center.y -= (computed.size as Vector3).y
	var frame := input_state.drag_frame
	return Transform3D(frame.basis, frame * center)


# ---------------------------------------------------------------------------
# Preview management
# ---------------------------------------------------------------------------


func _ensure_preview(shape: int, operation: int, size_default: Vector3, sides: int) -> void:
	if root.preview_brush:
		var needs_replace = root.preview_brush.shape != shape
		if not needs_replace:
			root.preview_brush.sides = sides
			if operation == CSGShape3D.OPERATION_SUBTRACTION:
				root.preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
				root._apply_brush_material(root.preview_brush, root._make_pending_cut_material())
			else:
				root.preview_brush.operation = operation
				root._apply_brush_material(root.preview_brush, root._make_brush_material(operation))
			return
		_clear_preview()
	root.preview_brush = root._create_brush(shape, size_default, operation, sides)
	if not root.preview_brush:
		return
	root.preview_brush.name = "PreviewBrush"
	if operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node:
		root.preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
		root._apply_brush_material(root.preview_brush, root._make_pending_cut_material())
		root.pending_node.add_child(root.preview_brush)
	else:
		if root.draft_brushes_node:
			root.draft_brushes_node.add_child(root.preview_brush)


func _update_preview(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	lock_axis: int,
	equal_base: bool,
	equal_all: bool
) -> void:
	if not root.preview_brush:
		return
	var info = _compute_brush_info(
		origin, current, height, shape, size_default, lock_axis, equal_base, equal_all
	)
	if input_state.drag_on_face:
		root.preview_brush.global_transform = _face_transform(info)
	else:
		root.preview_brush.global_position = info.center
	root.preview_brush.size = info.size


func _clear_preview() -> void:
	var preview = root.preview_brush
	root.preview_brush = null
	if preview and is_instance_valid(preview) and preview.is_inside_tree():
		# Out of DraftBrushes now, not at the end of the frame: Place Brush
		# records the level in this frame, and a preview still there went into
		# the step's before state, so an undo rebuilt it as a real brush.
		preview.get_parent().remove_child(preview)
		preview.queue_free()


# ---------------------------------------------------------------------------
# Brush info computation
# ---------------------------------------------------------------------------


func _build_brush_info(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	operation: int,
	equal_base: bool,
	equal_all: bool
) -> Dictionary:
	var computed = _compute_brush_info(
		origin, current, height, shape, size_default, _current_axis_lock(), equal_base, equal_all
	)
	var info = {
		"shape": shape,
		"size": computed.size,
		"center": computed.center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id()
	}
	if input_state.drag_on_face:
		# The turn goes into the undo step with the rest, so a redo puts the brush
		# back on the face it was drawn on.
		var placed := _face_transform(computed)
		info["center"] = placed.origin
		info["transform"] = placed
	if root._shape_uses_sides(shape):
		info["sides"] = input_state.drag_sides
	root.brush_system.give_active_material(info)
	return info


func _compute_brush_info(
	origin: Vector3,
	current: Vector3,
	height: float,
	shape: int,
	size_default: Vector3,
	lock_axis: int,
	equal_base: bool,
	equal_all: bool
) -> Dictionary:
	var min_x = min(origin.x, current.x)
	var max_x = max(origin.x, current.x)
	var min_z = min(origin.z, current.z)
	var max_z = max(origin.z, current.z)
	if lock_axis == root.AxisLock.X:
		var thickness_z = (
			input_state.locked_thickness.z
			if input_state.locked_thickness.z > 0.0
			else max(root.grid_snap, size_default.z * 0.25)
		)
		var half_z = max(0.1, thickness_z * 0.5)
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	elif lock_axis == root.AxisLock.Z:
		var thickness_x = (
			input_state.locked_thickness.x
			if input_state.locked_thickness.x > 0.0
			else max(root.grid_snap, size_default.x * 0.25)
		)
		var half_x = max(0.1, thickness_x * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
	elif lock_axis == root.AxisLock.Y:
		var thickness_x = (
			input_state.locked_thickness.x
			if input_state.locked_thickness.x > 0.0
			else max(root.grid_snap, size_default.x * 0.25)
		)
		var thickness_z = (
			input_state.locked_thickness.z
			if input_state.locked_thickness.z > 0.0
			else max(root.grid_snap, size_default.z * 0.25)
		)
		var half_x = max(0.1, thickness_x * 0.5)
		var half_z = max(0.1, thickness_z * 0.5)
		min_x = origin.x - half_x
		max_x = origin.x + half_x
		min_z = origin.z - half_z
		max_z = origin.z + half_z
	var size_x = max_x - min_x
	var size_z = max_z - min_z
	if equal_base:
		var side = max(size_x, size_z)
		size_x = side
		size_z = side
		min_x = origin.x - side * 0.5
		max_x = origin.x + side * 0.5
		min_z = origin.z - side * 0.5
		max_z = origin.z + side * 0.5
	if equal_all:
		var side_all = max(size_x, size_z)
		size_x = side_all
		size_z = side_all
		height = side_all
		min_x = origin.x - side_all * 0.5
		max_x = origin.x + side_all * 0.5
		min_z = origin.z - side_all * 0.5
		max_z = origin.z + side_all * 0.5
	var extent = max(size_x, size_z)
	var min_extent = max(0.1, root.grid_snap * 0.5)
	var final_size = Vector3(size_x, height, size_z)
	if extent < min_extent:
		final_size = Vector3(size_default.x, height, size_default.z)
		min_x = origin.x - final_size.x * 0.5
		max_x = origin.x + final_size.x * 0.5
		min_z = origin.z - final_size.z * 0.5
		max_z = origin.z + final_size.z * 0.5
	# The rectangle a mapper drags is ground they can see: up to a wall, between two
	# pillars, inside a doorway. A round brush has to end up inside it. That means
	# the *smaller* dragged side is the diameter, not the larger one, and the
	# footprint is centred on the rectangle rather than grown out of the corner the
	# drag started at. Both halves of that were the other way round (#604).
	if shape in RADIAL_SHAPES:
		var diameter := maxf(0.1, minf(final_size.x, final_size.z))
		if shape == DraftBrush.BrushShape.SPHERE:
			# A SPHERE is uniform by definition - ELLIPSOID is the shape with three
			# independent axes - so the height stage cannot set it alone. Taking the
			# height into the diameter is what makes that stage land at all, instead
			# of asking for a number and throwing it away (#605). The sphere is then
			# inscribed in the box that was dragged, which is the same rule as the
			# other three.
			diameter = maxf(0.1, minf(diameter, final_size.y))
			final_size = Vector3(diameter, diameter, diameter)
		else:
			final_size = Vector3(diameter, final_size.y, diameter)
	final_size = DraftBrush.normalized_size_for_shape(shape, final_size)
	if shape in RADIAL_SHAPES:
		# Every earlier branch - axis lock, equal_base, equal_all, the default-size
		# fallback - has already written the rectangle it wants into min/max, and for
		# all of those the midpoint is the origin. Centring on the midpoint is
		# therefore the one rule that serves them and a plain drag alike.
		var center_x: float = (min_x + max_x) * 0.5
		var center_z: float = (min_z + max_z) * 0.5
		min_x = center_x - final_size.x * 0.5
		max_x = center_x + final_size.x * 0.5
		min_z = center_z - final_size.z * 0.5
		max_z = center_z + final_size.z * 0.5
	var center = Vector3(
		(min_x + max_x) * 0.5,
		origin.y + final_size.y * 0.5,
		(min_z + max_z) * 0.5,
	)
	return {"center": center, "size": final_size}


# ---------------------------------------------------------------------------
# Axis locking
# ---------------------------------------------------------------------------


func set_axis_lock(lock: int, manual: bool = true) -> void:
	if manual:
		if input_state.manual_axis_lock and input_state.axis_lock == lock:
			input_state.axis_lock = root.AxisLock.NONE
			input_state.manual_axis_lock = false
			root._refresh_grid_plane()
			return
		input_state.axis_lock = lock
		input_state.manual_axis_lock = true
		root._refresh_grid_plane()
		return
	input_state.axis_lock = lock
	root._refresh_grid_plane()


func set_shift_pressed(pressed: bool) -> void:
	input_state.shift_pressed = pressed
	if not pressed and not input_state.manual_axis_lock:
		input_state.axis_lock = root.AxisLock.NONE
	root._refresh_grid_plane()


func set_alt_pressed(pressed: bool) -> void:
	input_state.alt_pressed = pressed


## No lock in a Draw on Face: the face already fixes the plane, and the locks
## name world axes the face's own need not follow.
func _current_axis_lock() -> int:
	if input_state.drag_on_face:
		return root.AxisLock.NONE
	if input_state.manual_axis_lock:
		return input_state.axis_lock
	return root.AxisLock.NONE


func _apply_axis_lock(_origin: Vector3, current: Vector3) -> Vector3:
	return current


func _update_lock_state(origin: Vector3, current: Vector3) -> void:
	var lock = _current_axis_lock()
	if lock == root.AxisLock.NONE:
		input_state.lock_axis_active = root.AxisLock.NONE
		input_state.locked_thickness = Vector3.ZERO
		return
	if lock != input_state.lock_axis_active:
		input_state.lock_axis_active = lock
		if lock == root.AxisLock.X:
			input_state.locked_thickness.z = abs(current.z - origin.z)
		elif lock == root.AxisLock.Z:
			input_state.locked_thickness.x = abs(current.x - origin.x)
		elif lock == root.AxisLock.Y:
			input_state.locked_thickness.x = abs(current.x - origin.x)
			input_state.locked_thickness.z = abs(current.z - origin.z)


# ---------------------------------------------------------------------------
# Height
# ---------------------------------------------------------------------------


## The height the cursor asks for, in whole grid steps while the drag's grid is
## on, which G and the invert key decide as they do for the corners (#1431).
func _height_from_mouse(current: Vector2, start: Vector2, start_height: float) -> float:
	var delta = current.y - start.y
	var raw_height = start_height + (-delta / max(1.0, root.height_pixels_per_unit))
	var step: float = root.drag_grid_step()
	if step > 0.0:
		raw_height = max(step, snappedf(raw_height, step))
	return max(0.1, raw_height)
