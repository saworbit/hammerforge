@tool
extends EditorNode3DGizmoPlugin

const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const LevelRoot = preload("level_root.gd")
const HFUndoHelper = preload("undo_helper.gd")
const HFOutlineUtil = preload("hf_outline_util.gd")
const MIN_SIZE := 0.1
const AXIS_SCALE_EPSILON := 0.00001
const ENTITY_MARKER_SIZE := Vector3.ONE

signal handle_action_started
signal handle_action_finished(cancelled: bool)


## EditorNode3DGizmoPlugin itself can only be instantiated by the editor.
## Keeping the tiny state machine in a RefCounted makes its edge cases
## independently testable in the normal headless test runner.
class HandleActionLifecycle:
	extends RefCounted
	signal started
	signal finished(cancelled: bool)

	var active := false

	func begin() -> bool:
		if active:
			return false
		active = true
		started.emit()
		return true

	func finish(cancelled: bool) -> bool:
		var was_active := active
		active = false
		if was_active:
			finished.emit(cancelled)
		return was_active


## Correlates Godot's eventual commit callback with the exact handle action
## that produced its restore payload. A gizmo, handle and transform can all be
## reused by a newer action, so those values alone cannot identify a late
## callback after focus-loss recovery.
class HandleCommitIdentity:
	extends RefCounted

	class ActionToken:
		extends RefCounted

	const COMMIT_UNKNOWN := 0
	const COMMIT_ACTIVE := 1
	const COMMIT_RETIRED := 2
	const TOKEN_KEY := &"__hammerforge_handle_action_token"
	const MAX_RETIRED_ACTIONS := 32

	var active_token: RefCounted = null
	var active_generation := -1
	var _active_descriptor: Dictionary = {}
	var _retired_descriptors: Array[Dictionary] = []

	func begin(
		gizmo_id: int, node_id: int, handle_id: int, secondary: bool, generation: int
	) -> RefCounted:
		if active_token != null:
			return null
		active_token = ActionToken.new()
		active_generation = generation
		_active_descriptor = {
			"token": active_token,
			"gizmo_id": gizmo_id,
			"node_id": node_id,
			"handle_id": handle_id,
			"secondary": secondary,
			"generation": generation,
		}
		return active_token

	func decorate_restore(
		restore: Dictionary, gizmo_id: int, node_id: int, handle_id: int, secondary: bool
	) -> Dictionary:
		if matches_active_callback(gizmo_id, node_id, handle_id, secondary):
			restore[TOKEN_KEY] = active_token
		return restore

	func classify_commit(
		restore: Variant, gizmo_id: int, node_id: int, handle_id: int, secondary: bool
	) -> int:
		var token := token_from_restore(restore)
		if token == null:
			return COMMIT_UNKNOWN
		if (
			active_token != null
			and token == active_token
			and _descriptor_matches(_active_descriptor, gizmo_id, node_id, handle_id, secondary)
		):
			return COMMIT_ACTIVE
		for descriptor in _retired_descriptors:
			if (
				descriptor.get("token") == token
				and _descriptor_matches(descriptor, gizmo_id, node_id, handle_id, secondary)
			):
				return COMMIT_RETIRED
		return COMMIT_UNKNOWN

	func consume_retired(
		restore: Variant, gizmo_id: int, node_id: int, handle_id: int, secondary: bool
	) -> bool:
		var token := token_from_restore(restore)
		if token == null:
			return false
		for index in range(_retired_descriptors.size()):
			var descriptor := _retired_descriptors[index]
			if (
				descriptor.get("token") == token
				and _descriptor_matches(descriptor, gizmo_id, node_id, handle_id, secondary)
			):
				_retired_descriptors.remove_at(index)
				return true
		return false

	func matches_active_callback(
		gizmo_id: int, node_id: int, handle_id: int, secondary: bool
	) -> bool:
		return (
			active_token != null
			and _descriptor_matches(_active_descriptor, gizmo_id, node_id, handle_id, secondary)
		)

	func owns_active(expected_token: Variant) -> bool:
		return active_token != null and expected_token == active_token

	func finish_active(expected_token: Variant) -> bool:
		if not owns_active(expected_token):
			return false
		_clear_active()
		return true

	func retire_active(expected_token: Variant) -> bool:
		if not owns_active(expected_token):
			return false
		_retired_descriptors.append(_active_descriptor.duplicate())
		while _retired_descriptors.size() > MAX_RETIRED_ACTIONS:
			_retired_descriptors.remove_at(0)
		_clear_active()
		return true

	func token_from_restore(restore: Variant) -> Variant:
		if not (restore is Dictionary):
			return null
		return (restore as Dictionary).get(TOKEN_KEY)

	func _clear_active() -> void:
		active_token = null
		active_generation = -1
		_active_descriptor = {}

	func _descriptor_matches(
		descriptor: Dictionary, gizmo_id: int, node_id: int, handle_id: int, secondary: bool
	) -> bool:
		return (
			int(descriptor.get("gizmo_id", 0)) == gizmo_id
			and int(descriptor.get("node_id", 0)) == node_id
			and int(descriptor.get("handle_id", -1)) == handle_id
			and bool(descriptor.get("secondary", false)) == secondary
		)


var undo_redo: EditorUndoRedoManager = null
var _handle_action: HandleActionLifecycle = null
var _handle_commit_identity: HandleCommitIdentity = null
var _handle_action_frozen := false
var _active_gizmo_ref: WeakRef = null
var _active_handle_restore: Dictionary = {}
var _handle_action_generation := 0

const HANDLE_DATA = [
	{"axis": Vector3(1, 0, 0), "dir": 1},
	{"axis": Vector3(1, 0, 0), "dir": -1},
	{"axis": Vector3(0, 1, 0), "dir": 1},
	{"axis": Vector3(0, 1, 0), "dir": -1},
	{"axis": Vector3(0, 0, 1), "dir": 1},
	{"axis": Vector3(0, 0, 1), "dir": -1}
]


func _init() -> void:
	_ensure_handle_action()
	_ensure_handle_commit_identity()
	create_handle_material("handles")
	create_material("main", Color(1.0, 0.82, 0.2, 0.75))


func set_undo_redo(manager: EditorUndoRedoManager) -> void:
	undo_redo = manager


func _get_gizmo_name() -> String:
	return "HammerForgeBrush"


## Godot 4.7 calls this for both drags and clicks on a handle. Keep the
## lifecycle explicit so plugin.gd can yield pointer ownership to the gizmo
## before its own click/marquee handling runs.
func _begin_handle_action(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> void:
	if _ensure_handle_action().begin():
		_handle_action_generation += 1
		var token := (
			_ensure_handle_commit_identity()
			. begin(
				_gizmo_instance_id(gizmo),
				_gizmo_node_instance_id(gizmo),
				handle_id,
				secondary,
				_handle_action_generation,
			)
		)
		if token == null:
			_ensure_handle_action().finish(true)
			return
		_handle_action_frozen = false
		_active_gizmo_ref = weakref(gizmo) if gizmo else null
		var brush := gizmo.get_node_3d() as DraftBrush if gizmo else null
		_active_handle_restore = (
			{"size": brush.size, "position": brush.global_position} if brush else {}
		)
		handle_action_started.emit()


## Request a matching _commit_handle() callback even when the handle never
## moved. Without this, a simple click can leave pointer ownership latched.
func _can_commit_handle_on_click() -> bool:
	return true


func is_handle_action_active() -> bool:
	return _ensure_handle_action().active


## Editor plugin scripts may be hot-reloaded onto an existing native gizmo
## plugin instance without rerunning every member initializer. Keep lifecycle
## access self-healing so selecting a brush during reload cannot spam nil-state
## errors or disable its handles.
func _ensure_handle_action() -> HandleActionLifecycle:
	if _handle_action == null:
		_handle_action = HandleActionLifecycle.new()
	return _handle_action


func _ensure_handle_commit_identity() -> HandleCommitIdentity:
	if _handle_commit_identity == null:
		_handle_commit_identity = HandleCommitIdentity.new()
	return _handle_commit_identity


func _finish_handle_action(cancelled: bool, expected_token: Variant) -> void:
	if not _ensure_handle_commit_identity().finish_active(expected_token):
		return
	_complete_handle_action(cancelled)


func _complete_handle_action(cancelled: bool) -> void:
	var finished := _ensure_handle_action().finish(cancelled)
	_handle_action_frozen = false
	_active_gizmo_ref = null
	_active_handle_restore = {}
	if finished:
		handle_action_finished.emit(cancelled)


## Recover a handle drag whose release was lost during an application focus or
## viewport transition. Keep the original transform locally because Godot does
## not expose its restore payload outside _commit_handle().
func cancel_active_handle_action() -> bool:
	if not _ensure_handle_action().active or _handle_action_frozen:
		return false
	var gizmo = _active_gizmo_ref.get_ref() if _active_gizmo_ref else null
	var brush := gizmo.get_node_3d() as DraftBrush if gizmo else null
	if brush and not _active_handle_restore.is_empty():
		apply_resize_transaction(brush, _active_handle_restore, true, undo_redo)
		_request_gizmo_redraw(gizmo)
	# Keep ownership active until Godot sends its matching _commit_handle().
	# Motion can still be forwarded to Godot in the meantime, but must never
	# resurrect the preview that was just restored here.
	_handle_action_frozen = true
	call_deferred(
		"_force_finish_frozen_handle_action",
		_handle_action_generation,
		_ensure_handle_commit_identity().active_token,
	)
	return true


func _has_gizmo(node: Node) -> bool:
	return node is DraftBrush or node is DraftEntity


## Give the recovery event one editor turn to reach Godot's native gizmo. If
## no matching commit arrives, release HammerForge's exclusive input latch and
## ignore the stale native callback if it eventually appears.
func _force_finish_frozen_handle_action(generation: int, expected_token: Variant) -> void:
	if generation != _handle_action_generation:
		return
	if not _ensure_handle_action().active or not _handle_action_frozen:
		return
	if not _ensure_handle_commit_identity().retire_active(expected_token):
		return
	_complete_handle_action(true)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if node is DraftEntity:
		_redraw_entity(gizmo, node as DraftEntity)
		return
	var brush = node as DraftBrush
	if not brush:
		return
	# Normalize defensively as editor hot-reload can retain a legacy backing value
	# without re-running DraftBrush's setter on already-instanced scene nodes.
	var size = DraftBrush.normalized_size_for_shape(brush.shape, brush.size)
	var half = size * 0.5
	var lines := outline_lines_for_brush(brush)
	gizmo.add_lines(lines, get_material("main", gizmo))
	if not lines.is_empty():
		gizmo.add_collision_segments(lines)
	var collision_triangles := HFOutlineUtil.triangle_mesh_from_faces(brush.faces)
	if collision_triangles:
		gizmo.add_collision_triangles(collision_triangles)

	# Custom polygon/path brushes do not have six independently resizable box
	# faces. Showing the box handles suggests a destructive edit that the data
	# model cannot represent, so keep their accurate outline selection-only.
	if not supports_resize_handles(brush):
		return

	var handles = PackedVector3Array(
		[
			Vector3(half.x, 0, 0),
			Vector3(-half.x, 0, 0),
			Vector3(0, half.y, 0),
			Vector3(0, -half.y, 0),
			Vector3(0, 0, half.z),
			Vector3(0, 0, -half.z)
		]
	)
	var ids = PackedInt32Array([0, 1, 2, 3, 4, 5])
	gizmo.add_handles(handles, get_material("handles", gizmo), ids)


func _redraw_entity(gizmo: EditorNode3DGizmo, entity: DraftEntity) -> void:
	var triangle_vertices := collision_vertices_for_entity(entity)
	var lines := HFOutlineUtil.points_bounds_lines(triangle_vertices)
	if not lines.is_empty():
		gizmo.add_lines(lines, get_material("main", gizmo))
		gizmo.add_collision_segments(lines)
	var collision_triangles := HFOutlineUtil.triangle_mesh_from_vertices(triangle_vertices)
	if collision_triangles:
		gizmo.add_collision_triangles(collision_triangles)


static func outline_lines_for_brush(brush: DraftBrush) -> PackedVector3Array:
	if not brush:
		return PackedVector3Array()
	return brush.get_editor_outline_lines()


static func outline_lines_for_entity(entity: DraftEntity) -> PackedVector3Array:
	if not entity:
		return PackedVector3Array()
	return HFOutlineUtil.points_bounds_lines(collision_vertices_for_entity(entity))


static func collision_vertices_for_entity(entity: DraftEntity) -> PackedVector3Array:
	if not entity or not HFOutlineUtil.is_effectively_visible(entity):
		return PackedVector3Array()
	var triangles := HFOutlineUtil.visible_preview_collision_triangle_vertices(
		entity, ENTITY_MARKER_SIZE
	)
	if not triangles.is_empty():
		return triangles
	# Deliberately hidden/empty preview geometry stays hidden. Truly geometry-less
	# entities still get a small native marker so they can be selected.
	if HFOutlineUtil.has_preview_geometry_descendant(entity):
		return PackedVector3Array()
	return HFOutlineUtil.box_triangle_vertices(ENTITY_MARKER_SIZE)


static func supports_resize_handles(node: Node) -> bool:
	return node is DraftBrush and (node as DraftBrush).shape != DraftBrush.BrushShape.CUSTOM


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	match handle_id:
		0:
			return "+X"
		1:
			return "-X"
		2:
			return "+Y"
		3:
			return "-Y"
		4:
			return "+Z"
		5:
			return "-Z"
		_:
			return ""


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var brush = gizmo.get_node_3d() as DraftBrush if gizmo else null
	var restore := {"size": brush.size, "position": brush.global_position} if brush else {}
	return (
		_ensure_handle_commit_identity()
		. decorate_restore(
			restore,
			_gizmo_instance_id(gizmo),
			_gizmo_node_instance_id(gizmo),
			handle_id,
			secondary,
		)
	)


func _set_handle(
	gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2
) -> void:
	if not _ensure_handle_action().active or _handle_action_frozen:
		return
	if not (
		_ensure_handle_commit_identity()
		. matches_active_callback(
			_gizmo_instance_id(gizmo),
			_gizmo_node_instance_id(gizmo),
			handle_id,
			secondary,
		)
	):
		return
	var brush = gizmo.get_node_3d() as DraftBrush
	if not brush or not camera or handle_id < 0 or handle_id >= HANDLE_DATA.size():
		return
	var snap_step = _resolve_grid_snap(brush)
	var handle_info = HANDLE_DATA[handle_id]
	var axis: Vector3 = handle_info["axis"]
	var dir: int = handle_info["dir"]
	var effective_size := DraftBrush.normalized_size_for_shape(brush.shape, brush.size)
	var frame := _axis_resize_frame(
		brush.global_transform.basis, effective_size, brush.global_position, axis, dir
	)
	if frame.is_empty():
		return
	var axis_world: Vector3 = frame["axis_world"]
	var opposite_face: Vector3 = frame["opposite_face"]

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos).normalized()
	var line_dir = axis_world * float(dir)

	var w0 = opposite_face - ray_origin
	var b = line_dir.dot(ray_dir)
	var denom = 1.0 - b * b
	if abs(denom) < 0.00001:
		return
	var d = line_dir.dot(w0)
	var e = ray_dir.dot(w0)
	var t = (b * e - d) / denom
	var resize := calculate_brush_axis_resize(
		brush.shape,
		brush.global_transform.basis,
		brush.size,
		brush.global_position,
		axis,
		dir,
		t,
		snap_step,
	)
	if resize.is_empty():
		return
	brush.size = resize["size"]
	brush.global_position = resize["position"]
	_request_gizmo_redraw(gizmo)


## Convert a face-to-face extent measured and snapped in world space back to
## the brush's local size. The opposite face is held fixed in world space, so
## this remains correct below rotated and non-uniformly scaled parents.
static func calculate_axis_resize(
	global_basis: Basis,
	current_size: Vector3,
	world_center: Vector3,
	local_axis: Vector3,
	direction: int,
	requested_world_extent: float,
	world_snap: float,
	resized_axis_indices: PackedInt32Array = PackedInt32Array(),
	minimum_local_extent: float = MIN_SIZE,
) -> Dictionary:
	if (
		not is_finite(requested_world_extent)
		or not is_finite(world_snap)
		or not is_finite(minimum_local_extent)
	):
		return {}
	var frame := _axis_resize_frame(global_basis, current_size, world_center, local_axis, direction)
	if frame.is_empty():
		return {}

	var snapped_world_extent: float = requested_world_extent
	if world_snap > 0.0:
		snapped_world_extent = snappedf(snapped_world_extent, world_snap)
	if not is_finite(snapped_world_extent):
		return {}
	var axis_scale: float = frame["axis_scale"]
	var local_extent: float = maxf(
		maxf(MIN_SIZE, minimum_local_extent), snapped_world_extent / axis_scale
	)
	var actual_world_extent: float = local_extent * axis_scale
	if not is_finite(local_extent) or not is_finite(actual_world_extent):
		return {}
	var resized := current_size
	var axis_index: int = frame["axis_index"]
	resized[axis_index] = local_extent
	for coupled_axis in resized_axis_indices:
		if coupled_axis >= 0 and coupled_axis < 3:
			resized[coupled_axis] = local_extent
	var line_direction: Vector3 = frame["axis_world"] * float(direction)
	var resized_center: Vector3 = (
		frame["opposite_face"] + line_direction * (actual_world_extent * 0.5)
	)
	if not resized_center.is_finite():
		return {}
	return {
		"size": resized,
		"position": resized_center,
		"world_extent": actual_world_extent,
		"opposite_face": frame["opposite_face"],
	}


static func calculate_brush_axis_resize(
	shape: int,
	global_basis: Basis,
	current_size: Vector3,
	world_center: Vector3,
	local_axis: Vector3,
	direction: int,
	requested_world_extent: float,
	world_snap: float,
) -> Dictionary:
	var axis_index := _axis_index(local_axis)
	var effective_size := DraftBrush.normalized_size_for_shape(shape, current_size)
	var minimum_extent := MIN_SIZE
	if shape == DraftBrush.BrushShape.CAPSULE and axis_index == 1:
		minimum_extent = effective_size.x
	var result := calculate_axis_resize(
		global_basis,
		effective_size,
		world_center,
		local_axis,
		direction,
		requested_world_extent,
		world_snap,
		resize_axis_indices_for_shape(shape, axis_index),
		minimum_extent,
	)
	if not result.is_empty():
		result["size"] = DraftBrush.normalized_size_for_shape(shape, result["size"])
	return result


static func resize_axis_indices_for_shape(shape: int, axis_index: int) -> PackedInt32Array:
	if axis_index < 0 or axis_index > 2:
		return PackedInt32Array()
	if shape == DraftBrush.BrushShape.SPHERE:
		return PackedInt32Array([0, 1, 2])
	if (
		axis_index != 1
		and (
			shape
			in [
				DraftBrush.BrushShape.CYLINDER,
				DraftBrush.BrushShape.CONE,
				DraftBrush.BrushShape.CAPSULE,
			]
		)
	):
		return PackedInt32Array([0, 2])
	return PackedInt32Array([axis_index])


static func _axis_resize_frame(
	global_basis: Basis,
	current_size: Vector3,
	world_center: Vector3,
	local_axis: Vector3,
	direction: int,
) -> Dictionary:
	if direction != -1 and direction != 1:
		return {}
	if not current_size.is_finite() or not world_center.is_finite() or not local_axis.is_finite():
		return {}
	var axis_index := _axis_index(local_axis)
	if axis_index < 0 or current_size[axis_index] < 0.0:
		return {}
	var scaled_axis := global_basis * local_axis
	if not scaled_axis.is_finite():
		return {}
	var axis_scale := scaled_axis.length()
	if not is_finite(axis_scale) or axis_scale <= AXIS_SCALE_EPSILON:
		return {}
	var axis_world := scaled_axis / axis_scale
	var opposite_face := (
		world_center - axis_world * float(direction) * current_size[axis_index] * axis_scale * 0.5
	)
	if not opposite_face.is_finite():
		return {}
	return {
		"axis_index": axis_index,
		"axis_scale": axis_scale,
		"axis_world": axis_world,
		"opposite_face": opposite_face,
	}


func _resolve_grid_snap(brush: DraftBrush) -> float:
	var current: Node = brush
	while current:
		if current is LevelRoot:
			var root = current as LevelRoot
			return max(0.0, root.grid_snap)
		current = current.get_parent()
	return 0.0


func _commit_handle(
	gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool
) -> void:
	var identity := _ensure_handle_commit_identity()
	var gizmo_id := _gizmo_instance_id(gizmo)
	var node_id := _gizmo_node_instance_id(gizmo)
	var commit_kind := identity.classify_commit(restore, gizmo_id, node_id, handle_id, secondary)
	if commit_kind == HandleCommitIdentity.COMMIT_RETIRED:
		identity.consume_retired(restore, gizmo_id, node_id, handle_id, secondary)
		if not _ensure_handle_action().active:
			_request_gizmo_redraw(gizmo)
		return
	if commit_kind != HandleCommitIdentity.COMMIT_ACTIVE:
		return

	var expected_token := identity.token_from_restore(restore)
	# Recovery already restored the preview. A native callback that races the
	# deferred fallback must therefore finish as a cancellation even if Godot
	# reports its stale release as a normal commit.
	var effective_cancel := cancel or _handle_action_frozen
	var brush = gizmo.get_node_3d() as DraftBrush if gizmo else null
	if brush:
		apply_resize_transaction(brush, restore, effective_cancel, undo_redo)
		_request_gizmo_redraw(gizmo)
	# _can_commit_handle_on_click() guarantees normal Godot 4.7 handle clicks
	# reach this callback. Keep cleanup unconditional for invalid/no-op/cancelled
	# actions as well so the viewport never remains owned by a stale gizmo drag.
	_finish_handle_action(effective_cancel, expected_token)


static func _gizmo_instance_id(gizmo: EditorNode3DGizmo) -> int:
	return gizmo.get_instance_id() if gizmo else 0


static func _gizmo_node_instance_id(gizmo: EditorNode3DGizmo) -> int:
	var node := gizmo.get_node_3d() if gizmo else null
	return node.get_instance_id() if node else 0


## Complete a live resize as one transaction. _set_handle() deliberately
## changes only the preview transform; texture-lock UV work is deferred until
## here. Restoring the original transform before HFUndoHelper captures state
## gives Undo the true pre-drag snapshot, then the do-method applies the final
## transform and its UV adjustment exactly once.
##
## Returns true only when a real committed resize was applied.
static func apply_resize_transaction(
	brush: DraftBrush,
	restore: Variant,
	cancel: bool,
	manager: EditorUndoRedoManager = null,
	transaction_root: Node = null,
) -> bool:
	if not brush or not (restore is Dictionary):
		return false
	var data: Dictionary = restore
	if not data.has("size") or not data.has("position"):
		return false
	var previous_size: Vector3 = data["size"]
	var previous_position: Vector3 = data["position"]
	var final_size := brush.size
	var final_position := brush.global_position

	if (
		cancel
		or not _resize_transform_changed(
			previous_size, previous_position, final_size, final_position
		)
	):
		_restore_preview_transform(brush, previous_size, previous_position)
		return false

	var root: Node = transaction_root if transaction_root else _find_level_root(brush)
	if root and brush.brush_id == "" and root.has_method("get_brush_info_from_node"):
		root.get_brush_info_from_node(brush)
	var brush_id := brush.brush_id
	if root and brush_id != "" and root.has_method("set_brush_transform_by_id"):
		_restore_preview_transform(brush, previous_size, previous_position)
		if manager:
			HFUndoHelper.commit(
				manager,
				root,
				"Resize Brush",
				"set_brush_transform_by_id",
				[brush_id, final_size, final_position],
				false,
				Callable(),
				""
			)
		else:
			root.set_brush_transform_by_id(brush_id, final_size, final_position)
	else:
		# Detached/test brushes have no LevelRoot transaction endpoint. Preserve
		# the final preview transform, but do not pretend an undo entry exists.
		brush.size = final_size
		brush.global_position = final_position
	return true


static func _resize_transform_changed(
	previous_size: Vector3,
	previous_position: Vector3,
	final_size: Vector3,
	final_position: Vector3,
) -> bool:
	return not (
		previous_size.is_equal_approx(final_size)
		and previous_position.is_equal_approx(final_position)
	)


static func _restore_preview_transform(
	brush: DraftBrush, previous_size: Vector3, previous_position: Vector3
) -> void:
	brush.size = previous_size
	brush.global_position = previous_position


static func _axis_index(axis: Vector3) -> int:
	var absolute_axis := axis.abs()
	if absolute_axis.is_equal_approx(Vector3.RIGHT):
		return 0
	if absolute_axis.is_equal_approx(Vector3.UP):
		return 1
	if absolute_axis.is_equal_approx(Vector3.BACK):
		return 2
	return -1


func _request_gizmo_redraw(gizmo: EditorNode3DGizmo) -> void:
	if not gizmo:
		return
	var node := gizmo.get_node_3d()
	if node and node.has_method("_refresh_editor_gizmo_now"):
		node.call("_refresh_editor_gizmo_now")
	elif node:
		node.update_gizmos()


static func _find_level_root(node: Node) -> LevelRoot:
	var current: Node = node
	while current:
		if current is LevelRoot:
			return current as LevelRoot
		current = current.get_parent()
	return null
