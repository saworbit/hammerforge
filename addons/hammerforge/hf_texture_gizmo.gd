@tool
class_name HFTextureGizmo
extends RefCounted
## The Texture Gizmo: slide, stretch and turn the texture on the faces picked in
## Face Select by dragging in the viewport (#1420).
##
## It sits at the centre of the picked faces with its axes along the texture's U
## and V on the first of them. The square in the middle slides the texture, an
## axis end stretches it along that axis (Shift stretches both), and the ring
## turns it. Every picked face takes the same change on its own U and V, measured
## on that face, and a face laid out by hand has its layout moved with it, as
## Justify moves one (#654), through `LevelRoot.set_face_uv_params()`.
##
## A drag writes the faces as the cursor goes, so the texture is seen moving, and
## records one undo step when it is let go. Right click or Escape puts every face
## back as the press found it and records nothing.
##
## Drawn like the Face Select mark: an ImmediateMesh on an internal child of the
## level with no owner, so it is never saved, listed or copied. The handles keep
## one size on screen, so the plugin hands it the camera as the pointer moves.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")

enum Handle { NONE, SLIDE, STRETCH_U, STRETCH_V, TURN }

## Sizes on screen, in pixels.
const AXIS_PX := 80.0
const RING_PX := 52.0
const CENTRE_PX := 7.0
const END_PX := 5.0
## How near the pointer has to be to take a handle.
const PICK_PX := 9.0
const RING_PICK_PX := 6.0
const RING_SEGMENTS := 48
## A stretch snaps to eighths of the size it started at, and never goes below a
## sixteenth: the gizmo stretches, and Flip is the way to mirror a texture.
const STRETCH_STEP := 0.125
const MIN_STRETCH := 0.0625

const U_COLOR := Color(0.95, 0.3, 0.3)
const V_COLOR := Color(0.35, 0.85, 0.35)
const SLIDE_COLOR := Color(0.95, 0.95, 0.95)
const RING_COLOR := Color(0.35, 0.6, 1.0)
const ACTIVE_COLOR := Color(1.0, 0.85, 0.1)
const NODE_NAME := &"_TextureGizmo"

const ACTION_NAMES := {
	Handle.SLIDE: "Slide Texture",
	Handle.STRETCH_U: "Stretch Texture",
	Handle.STRETCH_V: "Stretch Texture",
	Handle.TURN: "Turn Texture",
}

var _watched_root: WeakRef = null
## The toggle is on and Face Select is open.
var _shown := false
## Where the gizmo stands, from `_build_frame()`: `{"centre", "u", "v", "normal",
## "faces"}`, the axes being unit vectors in the level. Empty while it is hidden.
var _frame: Dictionary = {}
## World units per screen pixel at the centre, for the last camera seen.
var _units_per_px := 0.0
var _hovered: int = Handle.NONE
## The camera the pointer was last seen through, which sizes the handles.
var _camera_ref: WeakRef = null
## The drag under way, empty when there is none. See `begin_drag()`.
var _drag: Dictionary = {}
var _mesh_instance: MeshInstance3D = null
var _mesh: ImmediateMesh = null
var _refresh_queued := false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


## Stand on the faces of [param root] from now on. A drag on the level it was on
## is called off first.
func watch(root: Node) -> void:
	if root != null and not is_instance_valid(root):
		root = null
	if root != null and root == _root():
		return
	_stop_watching()
	if root != null and root.has_signal("face_selection_changed"):
		root.connect("face_selection_changed", _on_face_selection_changed)
		root.connect("state_loaded", _on_face_selection_changed)
		root.connect("brush_changed", _on_brush_changed)
		_watched_root = weakref(root)
	refresh()


## Call off any drag and take the gizmo down, as the plugin does on its way out.
func reset() -> void:
	_stop_watching()


## Show the gizmo or not: the toggle is on and Face Select is open.
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	if not shown:
		cancel()
	refresh()


## Whether there is a gizmo on screen to take a press.
func is_visible() -> bool:
	return _shown and not _frame.is_empty()


func is_dragging() -> bool:
	return not _drag.is_empty()


func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_run_queued_refresh.call_deferred()


## Stand the gizmo on the watched level's face selection and draw it. A drag keeps
## the frame it started on, so the axes do not turn under a turn.
func refresh() -> void:
	var root := _root()
	if not _shown or root == null or not root.is_inside_tree():
		# A level that leaves the tree under a drag gets its faces back first.
		if is_dragging():
			cancel()
			return
		_frame = {}
		_free_mesh_instance()
		return
	if _drag.is_empty():
		_frame = _build_frame(root)
	if _frame.is_empty():
		_free_mesh_instance()
		return
	_measure(_camera())
	_draw(root)


## Size the gizmo for [param camera], as the plugin does when it is shown.
func set_camera(camera: Camera3D) -> void:
	_camera_ref = weakref(camera) if camera != null else null


# ---------------------------------------------------------------------------
# Pointer
# ---------------------------------------------------------------------------


## Size the handles for [param camera] and light the one under [param position].
## Returns that handle.
func hover(camera: Camera3D, position: Vector2) -> int:
	if not is_visible() or is_dragging():
		return Handle.NONE
	var old_size := _units_per_px
	var handle := handle_at(camera, position)
	if handle != _hovered or not is_equal_approx(old_size, _units_per_px):
		_hovered = handle
		refresh()
	return handle


## The handle under [param position] seen through [param camera], or NONE.
## The axis ends come first, then the middle, then the ring.
func handle_at(camera: Camera3D, position: Vector2) -> int:
	if not is_visible() or camera == null:
		return Handle.NONE
	set_camera(camera)
	var centre: Vector3 = _frame["centre"]
	if camera.is_position_behind(centre):
		return Handle.NONE
	_measure(camera)
	for handle in [Handle.STRETCH_U, Handle.STRETCH_V, Handle.SLIDE]:
		if position.distance_to(screen_point(camera, handle)) <= PICK_PX:
			return handle
	var ring := _ring_points(centre, RING_PX * _units_per_px)
	for i in ring.size():
		var a := camera.unproject_position(ring[i])
		var b := camera.unproject_position(ring[(i + 1) % ring.size()])
		var on_segment := Geometry2D.get_closest_point_to_segment(position, a, b)
		if position.distance_to(on_segment) <= RING_PICK_PX:
			return Handle.TURN
	return Handle.NONE


## Where [param handle] is on screen through [param camera]: the middle square,
## or the end of an axis.
func screen_point(camera: Camera3D, handle: int) -> Vector2:
	if _frame.is_empty() or camera == null:
		return Vector2(-1, -1)
	return camera.unproject_position(world_point(camera, handle))


## Where [param handle] is in the level, sized for [param camera]: the middle,
## the end of an axis, or the point of the ring on the U axis.
func world_point(camera: Camera3D, handle: int) -> Vector3:
	if _frame.is_empty():
		return Vector3.ZERO
	_measure(camera)
	var centre: Vector3 = _frame["centre"]
	match handle:
		Handle.STRETCH_U:
			return centre + _frame["u"] * AXIS_PX * _units_per_px
		Handle.STRETCH_V:
			return centre + _frame["v"] * AXIS_PX * _units_per_px
		Handle.TURN:
			return centre + _frame["u"] * RING_PX * _units_per_px
	return centre


## A copy of where the gizmo stands: `{"centre", "u", "v", "normal"}` and the
## faces it moves, or empty while it is hidden.
func get_frame() -> Dictionary:
	return _frame.duplicate(true)


## The node the gizmo is drawn on, or null while it is hidden.
func get_mesh_instance() -> MeshInstance3D:
	return _mesh_instance if is_instance_valid(_mesh_instance) else null


# ---------------------------------------------------------------------------
# Dragging
# ---------------------------------------------------------------------------


## Take hold of [param handle] at [param position]. The faces are recorded as the
## press finds them, for the undo step and for a cancel. False when there is
## nothing to take: no gizmo, no handle, or the pointer off the gizmo's plane.
func begin_drag(camera: Camera3D, position: Vector2, handle: int) -> bool:
	var root := _root()
	if root == null or not is_visible() or handle == Handle.NONE or is_dragging():
		return false
	var start = _on_plane(camera, position)
	if start == null:
		return false
	set_camera(camera)
	_measure(camera)
	var centre: Vector3 = _frame["centre"]
	var reach := AXIS_PX * _units_per_px
	var along := _along(start - centre)
	var brush_ids: Array = []
	var originals: Array = []
	for record in _frame["faces"]:
		var face := _face_of(root, record)
		if face == null:
			continue
		# The id the undo step and set_face_uv_params() find the brush by, given
		# to it here when it has none yet, as a drop or the dock gives one.
		var brush_id := str(
			root.get_brush_info_from_node(_brush_of(root, record)).get("brush_id", "")
		)
		if brush_id == "":
			continue
		record["brush_id"] = brush_id
		if not brush_ids.has(brush_id):
			brush_ids.append(brush_id)
		var original := {
			"record": record,
			"scale": face.uv_scale,
			"offset": face.uv_offset,
			"rotation": face.uv_rotation,
			"custom_uvs": face.custom_uvs.duplicate(),
		}
		originals.append(original)
	if originals.is_empty():
		return false
	_drag = {
		"handle": handle,
		"start": start,
		"originals": originals,
		"before": HFUndoHelper.capture_scope_or_state(root, brush_ids),
		# How far along its axis the press took an end. Measured rather than
		# assumed, so a press a few pixels short of the end does not jump.
		"reach_u": along.x if along.x > reach * 0.25 else reach,
		"reach_v": along.y if along.y > reach * 0.25 else reach,
		"angle": _angle_of(start - centre),
		"slide": Vector2.ZERO,
		"stretch": Vector2.ONE,
		"turn": 0.0,
	}
	_hovered = handle
	refresh()
	return true


## Follow the pointer to [param position]. [param grid_step] snaps a slide and
## [param stretch_step] a stretch, 0 leaving either free; [param angle_step] snaps
## a turn, in radians. [param both] stretches U and V together.
func drag_to(
	camera: Camera3D,
	position: Vector2,
	both: bool,
	grid_step: float,
	stretch_step: float,
	angle_step: float
) -> void:
	var root := _root()
	if root == null or not is_dragging() or _frame.is_empty():
		return
	var point = _on_plane(camera, position)
	if point == null:
		return
	var centre: Vector3 = _frame["centre"]
	var handle: int = _drag["handle"]
	match handle:
		Handle.SLIDE:
			var slide := _along(point - (_drag["start"] as Vector3))
			if grid_step > 0.0:
				slide = slide.snapped(Vector2(grid_step, grid_step))
			_drag["slide"] = slide
		Handle.STRETCH_U, Handle.STRETCH_V:
			var along := _along(point - centre)
			var stretch := (
				along.x / float(_drag["reach_u"])
				if handle == Handle.STRETCH_U
				else along.y / float(_drag["reach_v"])
			)
			if stretch_step > 0.0:
				stretch = snappedf(stretch, stretch_step)
			stretch = maxf(stretch, MIN_STRETCH)
			if both:
				_drag["stretch"] = Vector2(stretch, stretch)
			elif handle == Handle.STRETCH_U:
				_drag["stretch"] = Vector2(stretch, 1.0)
			else:
				_drag["stretch"] = Vector2(1.0, stretch)
		Handle.TURN:
			var turn := wrapf(_angle_of(point - centre) - float(_drag["angle"]), -PI, PI)
			if angle_step > 0.0:
				turn = snappedf(turn, angle_step)
			_drag["turn"] = turn
	_apply(root)
	refresh()


## Let go: one undo step when a face changed, none when nothing did. True when a
## step was recorded.
func finish(undo_redo, history_cb: Callable = Callable()) -> bool:
	var root := _root()
	var drag := _drag
	_drag = {}
	if drag.is_empty() or root == null:
		return false
	var before: Dictionary = drag["before"]
	var recorded := HFUndoHelper.commit_completed_if_changed(
		undo_redo,
		root,
		ACTION_NAMES.get(int(drag["handle"]), "Move Texture"),
		before["state"],
		history_cb,
		before["scope_ids"]
	)
	refresh()
	return recorded


## Put every face back as the press found it and record nothing. True when there
## was a drag to call off.
func cancel() -> bool:
	var drag := _drag
	_drag = {}
	if drag.is_empty():
		return false
	var root := _root()
	if root != null:
		for original in drag["originals"]:
			var brush := _brush_of(root, original["record"])
			if brush == null:
				continue
			var face := _restore(brush, original)
			if face != null:
				brush.rebuild_preview()
	refresh()
	return true


# ---------------------------------------------------------------------------
# The texture on a face
# ---------------------------------------------------------------------------


## Where the gizmo stands for the faces picked in [param root], or empty when no
## picked face has a texture lying on it.
func _build_frame(root: Node) -> Dictionary:
	var selection = root.get("face_selection")
	if not (selection is Dictionary) or (selection as Dictionary).is_empty():
		return {}
	var records: Array = []
	var centre_sum := Vector3.ZERO
	var primary: Dictionary = root.get_primary_selected_face()
	var primary_record: Dictionary = {}
	for key in (selection as Dictionary).keys():
		var brush := root.call("_find_brush_by_key", str(key)) as DraftBrush
		if brush == null or not brush.is_inside_tree():
			continue
		for index in (selection as Dictionary).get(key, []):
			var record := face_record(brush, int(index))
			if record.is_empty():
				continue
			record["key"] = str(key)
			records.append(record)
			centre_sum += record["centroid"]
			if brush == primary.get("brush") and int(index) == int(primary.get("face_idx", -1)):
				primary_record = record
	if records.is_empty():
		return {}
	if primary_record.is_empty():
		primary_record = records[0]
	var axes := texture_axes(primary_record, primary_record["uv_map"])
	return {
		"centre": centre_sum / float(records.size()),
		"u": axes[0].normalized(),
		"v": axes[1].normalized(),
		"normal": primary_record["normal"],
		"faces": records,
	}


## How the texture lies on face [param face_idx] of [param brush], as the face's
## projection lays it before any layout by hand. Empty for a face with no area or
## one its projection sees edge on, which no slide or turn could reach.
##
## The projection is read off the face's corners rather than worked out per kind,
## so Box UV, the planar axes, legacy walls and Cylindrical are read alike: `q` is
## what the projection gives a point before the face's scale, turn and offset, and
## `q_map` takes a point on the face, in the face's own plane coordinates, to it.
## Exact for a planar projection, and the nearest flat reading of a Cylindrical
## one.
static func face_record(brush: DraftBrush, face_idx: int) -> Dictionary:
	if brush == null or face_idx < 0 or face_idx >= brush.faces.size():
		return {}
	var face: FaceData = brush.faces[face_idx]
	if face == null or face.local_verts.size() < 3:
		return {}
	var uv_map := face.uv_transform()
	if is_zero_approx(uv_map.determinant()):
		return {}
	var xform := brush.global_transform
	var corners: PackedVector3Array = xform * face.local_verts
	var normal := face.normal_through(xform.basis)
	var origin := corners[0]
	var t1 := (corners[1] - origin).normalized()
	for i in range(1, corners.size()):
		if (corners[i] - origin).length() > 0.0001:
			t1 = (corners[i] - origin).normalized()
			break
	t1 = (t1 - normal * t1.dot(normal)).normalized()
	var t2 := normal.cross(t1)
	var q := uv_map.affine_inverse() * face.projected_uvs()
	# The two corners furthest from making a line with the first.
	var best := 0.0
	var pair := Vector2i(-1, -1)
	var planar := PackedVector2Array()
	for corner in corners:
		planar.append(Vector2((corner - origin).dot(t1), (corner - origin).dot(t2)))
	for i in range(1, planar.size()):
		for j in range(i + 1, planar.size()):
			var area := absf(planar[i].cross(planar[j]))
			if area > best:
				best = area
				pair = Vector2i(i, j)
	if pair.x < 0 or best < 0.000001:
		return {}
	var on_face := Transform2D(planar[pair.x], planar[pair.y], Vector2.ZERO)
	var in_q := Transform2D(q[pair.x] - q[0], q[pair.y] - q[0], Vector2.ZERO)
	var q_map := in_q * on_face.affine_inverse()
	if absf(q_map.determinant()) < 0.000001:
		return {}
	q_map.origin = q[0]
	var centroid := Vector3.ZERO
	for corner in corners:
		centroid += corner
	return {
		"face_idx": face_idx,
		"origin": origin,
		"t1": t1,
		"t2": t2,
		"normal": normal,
		"q_map": q_map,
		"uv_map": uv_map,
		"centroid": centroid / float(corners.size()),
	}


## The directions in the level along which the texture's U and V run on the face
## of [param record] under [param uv_map], a `FaceData.uv_transform()`, each as
## long as one repeat of the texture.
static func texture_axes(record: Dictionary, uv_map: Transform2D) -> Array:
	var on_face := _uv_on_face(record, uv_map).affine_inverse()
	var u := on_face.basis_xform(Vector2(1.0, 0.0))
	var v := on_face.basis_xform(Vector2(0.0, 1.0))
	var t1: Vector3 = record["t1"]
	var t2: Vector3 = record["t2"]
	return [t1 * u.x + t2 * u.y, t1 * v.x + t2 * v.y]


## The linear part of the map from the face's plane coordinates to its UVs under
## [param uv_map].
static func _uv_on_face(record: Dictionary, uv_map: Transform2D) -> Transform2D:
	var q_map: Transform2D = record["q_map"]
	var linear := Transform2D(uv_map.x, uv_map.y, Vector2.ZERO)
	return linear * Transform2D(q_map.x, q_map.y, Vector2.ZERO)


## `FaceData.uv_transform()` for these values.
static func uv_transform_for(uv_scale: Vector2, uv_rotation: float, offset: Vector2) -> Transform2D:
	return Transform2D(
		Vector2(1.0, 0.0).rotated(uv_rotation) * uv_scale,
		Vector2(0.0, 1.0).rotated(uv_rotation) * uv_scale,
		offset
	)


## The scale, rotation and offset that move the texture on one face by the drag:
## [param slide] along the face's own U and V, in level units; [param stretch] on
## its U and V, about [param pivot]; and [param turn] radians about [param pivot],
## anticlockwise seen from in front of the face. Returns `[scale, offset,
## rotation]`.
##
## The turn is made before the scale is applied, as `uv_rotation` is, so a texture
## stretched along one axis turns as a stretched picture rather than shearing. On
## a face its projection sees at a slant the turn is the projection's, which is
## the turn Rotate gives it.
static func moved_uvs(
	record: Dictionary,
	uv_scale: Vector2,
	offset: Vector2,
	uv_rotation: float,
	slide: Vector2,
	stretch: Vector2,
	turn: float,
	pivot: Vector3
) -> Array:
	var was := uv_transform_for(uv_scale, uv_rotation, offset)
	var q_map: Transform2D = record["q_map"]
	var normal: Vector3 = record["normal"]
	var origin: Vector3 = record["origin"]
	var on_plane := pivot - normal * (pivot - origin).dot(normal)
	var t1: Vector3 = record["t1"]
	var t2: Vector3 = record["t2"]
	var pivot_q := q_map * Vector2((on_plane - origin).dot(t1), (on_plane - origin).dot(t2))
	var pivot_uv := was * pivot_q
	# An axis the drag does not stretch keeps its scale as it is, even one past
	# what the Scale boxes show.
	var new_scale := uv_scale
	if not is_equal_approx(stretch.x, 1.0):
		new_scale.x = _held_uv_scale(uv_scale.x / stretch.x)
	if not is_equal_approx(stretch.y, 1.0):
		new_scale.y = _held_uv_scale(uv_scale.y / stretch.y)
	# A map that keeps the face's handedness turns the projection with the face,
	# and one that mirrors it turns it the other way.
	var handed := 1.0 if q_map.determinant() > 0.0 else -1.0
	var new_rotation := uv_rotation - handed * turn
	var now := uv_transform_for(new_scale, new_rotation, Vector2.ZERO)
	var new_offset := pivot_uv - now * pivot_q
	# One level unit along the face's U and V, in UVs, for the slide.
	var axes := texture_axes(record, now)
	var u_length: float = (axes[0] as Vector3).length()
	var v_length: float = (axes[1] as Vector3).length()
	if u_length > 0.0 and v_length > 0.0:
		new_offset -= Vector2(slide.x / u_length, slide.y / v_length)
	return [new_scale, new_offset, new_rotation]


## [param value] held to the size the Scale boxes can show, keeping its sign, as
## x2 and /2 hold it.
static func _held_uv_scale(value: float) -> float:
	var size := clampf(
		absf(value), HFBrushSystemType.UV_SCALE_STEP, HFBrushSystemType.UV_SCALE_LIMIT
	)
	return size if value >= 0.0 else -size


## Write the drag so far onto every face, each from where the press found it, so
## the result does not drift with the number of pointer moves.
func _apply(root: Node) -> void:
	var centre: Vector3 = _frame["centre"]
	var slide: Vector2 = _drag["slide"]
	var stretch: Vector2 = _drag["stretch"]
	var turn: float = _drag["turn"]
	for original in _drag["originals"]:
		var record: Dictionary = original["record"]
		var brush := _brush_of(root, record)
		if brush == null:
			continue
		if _restore(brush, original) == null:
			continue
		var moved := moved_uvs(
			record,
			original["scale"],
			original["offset"],
			original["rotation"],
			slide,
			stretch,
			turn,
			centre
		)
		root.set_face_uv_params(
			record["brush_id"], record["face_idx"], moved[0], moved[1], moved[2]
		)


static func _restore(brush: DraftBrush, original: Dictionary) -> FaceData:
	var face_idx: int = original["record"]["face_idx"]
	if face_idx < 0 or face_idx >= brush.faces.size():
		return null
	var face: FaceData = brush.faces[face_idx]
	if face == null:
		return null
	face.uv_scale = original["scale"]
	face.uv_offset = original["offset"]
	face.uv_rotation = original["rotation"]
	face.custom_uvs = (original["custom_uvs"] as PackedVector2Array).duplicate()
	return face


## The brush a face of the gizmo is on: by its id once a drag has given it one,
## by the key the face selection files it under before that.
func _brush_of(root: Node, record: Dictionary) -> DraftBrush:
	var key := str(record.get("brush_id", record.get("key", "")))
	var brush := root.call("_find_brush_by_key", key) as DraftBrush
	if brush == null or not is_instance_valid(brush):
		return null
	return brush


func _face_of(root: Node, record: Dictionary) -> FaceData:
	var brush := _brush_of(root, record)
	var face_idx: int = record["face_idx"]
	if brush == null or face_idx < 0 or face_idx >= brush.faces.size():
		return null
	return brush.faces[face_idx]


# ---------------------------------------------------------------------------
# The gizmo's plane
# ---------------------------------------------------------------------------


## Where the ray through [param position] meets the plane the gizmo stands in, or
## null when it runs along it or away from it.
func _on_plane(camera: Camera3D, position: Vector2) -> Variant:
	if camera == null or _frame.is_empty():
		return null
	var plane := Plane(_frame["normal"], _frame["centre"])
	return plane.intersects_ray(
		camera.project_ray_origin(position), camera.project_ray_normal(position)
	)


## [param offset] as so much U and so much V of the gizmo's axes, which need not
## be square to each other.
func _along(offset: Vector3) -> Vector2:
	var u: Vector3 = _frame["u"]
	var v: Vector3 = _frame["v"]
	var uu := u.dot(u)
	var uv := u.dot(v)
	var vv := v.dot(v)
	var det := uu * vv - uv * uv
	if absf(det) < 0.000001:
		return Vector2.ZERO
	var ou := offset.dot(u)
	var ov := offset.dot(v)
	return Vector2((ou * vv - ov * uv) / det, (ov * uu - ou * uv) / det)


## The angle of [param offset] about the gizmo's normal, from its U axis,
## anticlockwise seen from in front.
func _angle_of(offset: Vector3) -> float:
	var normal: Vector3 = _frame["normal"]
	var across := normal.cross(_frame["u"])
	return atan2(offset.dot(across), offset.dot(_frame["u"]))


func _ring_points(centre: Vector3, radius: float) -> PackedVector3Array:
	var normal: Vector3 = _frame["normal"]
	var e1: Vector3 = _frame["u"]
	var e2 := normal.cross(e1)
	var points := PackedVector3Array()
	for i in RING_SEGMENTS:
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		points.append(centre + (e1 * cos(angle) + e2 * sin(angle)) * radius)
	return points


## World units per screen pixel at the gizmo's centre.
func _measure(camera: Camera3D) -> void:
	if camera == null or _frame.is_empty():
		return
	var viewport := camera.get_viewport()
	var height := viewport.get_visible_rect().size.y if viewport else 600.0
	if height <= 0.0:
		return
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_units_per_px = camera.size / height
		return
	var centre: Vector3 = _frame["centre"]
	var depth := maxf((centre - camera.global_position).dot(-camera.global_basis.z), camera.near)
	_units_per_px = 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / height


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------


func _draw(root: Node) -> void:
	if _units_per_px <= 0.0:
		return
	_ensure_mesh_instance(root)
	_mesh.clear_surfaces()
	var u: Vector3 = _frame["u"]
	var v: Vector3 = _frame["v"]
	var centre: Vector3 = _frame["centre"]
	var handle: int = _drag.get("handle", _hovered)
	var stretch: Vector2 = _drag.get("stretch", Vector2.ONE)
	var slide: Vector2 = _drag.get("slide", Vector2.ZERO)
	# The gizmo goes with a slide, so it stays on the part of the texture it took.
	var at := centre + u * slide.x + v * slide.y
	var reach := AXIS_PX * _units_per_px
	var u_end := at + u * reach * stretch.x
	var v_end := at + v * reach * stretch.y
	var ring := _ring_points(at, RING_PX * _units_per_px)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line(at, u_end, ACTIVE_COLOR if handle == Handle.STRETCH_U else U_COLOR)
	_line(at, v_end, ACTIVE_COLOR if handle == Handle.STRETCH_V else V_COLOR)
	var ring_color := ACTIVE_COLOR if handle == Handle.TURN else RING_COLOR
	for i in ring.size():
		_line(ring[i], ring[(i + 1) % ring.size()], ring_color)
	if is_dragging() and handle == Handle.TURN:
		# Where the turn started and where it has got to.
		var radius := RING_PX * _units_per_px
		var normal: Vector3 = _frame["normal"]
		var start_angle: float = _drag["angle"]
		var now_angle := start_angle + float(_drag["turn"])
		var across := normal.cross(u)
		_line(at, at + (u * cos(start_angle) + across * sin(start_angle)) * radius, RING_COLOR)
		_line(at, at + (u * cos(now_angle) + across * sin(now_angle)) * radius, ACTIVE_COLOR)
	_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_square(at, CENTRE_PX, ACTIVE_COLOR if handle == Handle.SLIDE else SLIDE_COLOR)
	_square(u_end, END_PX, ACTIVE_COLOR if handle == Handle.STRETCH_U else U_COLOR)
	_square(v_end, END_PX, ACTIVE_COLOR if handle == Handle.STRETCH_V else V_COLOR)
	_mesh.surface_end()


func _line(from: Vector3, to: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(to)


## A square [param half_px] pixels from its middle to its sides, facing the camera
## the viewport draws through.
func _square(at: Vector3, half_px: float, color: Color) -> void:
	var camera := _camera()
	var right := Vector3.RIGHT
	var up := Vector3.UP
	if camera != null:
		right = camera.global_basis.x
		up = camera.global_basis.y
	var half := half_px * _units_per_px
	var corners := [
		at + (-right - up) * half,
		at + (right - up) * half,
		at + (right + up) * half,
		at + (-right + up) * half,
	]
	for index in [0, 1, 2, 0, 2, 3]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(corners[index])


func _ensure_mesh_instance(root: Node) -> void:
	if is_instance_valid(_mesh_instance) and _mesh_instance.get_parent() == root:
		return
	_free_mesh_instance()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = NODE_NAME
	# The points are world space, so the level's own transform must not move them.
	_mesh_instance.top_level = true
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Over everything, the Face Select mark included, as a gizmo is.
	material.no_depth_test = true
	material.render_priority = Material.RENDER_PRIORITY_MAX
	_mesh_instance.material_override = material
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	root.add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)


func _free_mesh_instance() -> void:
	if is_instance_valid(_mesh_instance):
		var parent := _mesh_instance.get_parent()
		if parent:
			parent.remove_child(_mesh_instance)
		_mesh_instance.free()
	_mesh_instance = null
	_mesh = null


# ---------------------------------------------------------------------------
# The watched level
# ---------------------------------------------------------------------------


func _stop_watching() -> void:
	cancel()
	var root := _root()
	if root != null:
		if root.is_connected("face_selection_changed", _on_face_selection_changed):
			root.disconnect("face_selection_changed", _on_face_selection_changed)
		if root.is_connected("state_loaded", _on_face_selection_changed):
			root.disconnect("state_loaded", _on_face_selection_changed)
		if root.is_connected("brush_changed", _on_brush_changed):
			root.disconnect("brush_changed", _on_brush_changed)
	_watched_root = null
	_frame = {}
	_hovered = Handle.NONE
	_free_mesh_instance()


func _root() -> Node:
	if _watched_root == null:
		return null
	return _watched_root.get_ref() as Node


func _camera() -> Camera3D:
	if _camera_ref == null:
		return null
	return _camera_ref.get_ref() as Camera3D


func _run_queued_refresh() -> void:
	_refresh_queued = false
	refresh()


## The faces under a drag are no longer the picked ones, so the drag is called off.
func _on_face_selection_changed() -> void:
	cancel()
	queue_refresh()


## A brush with a picked face moved or was retextured, so the gizmo follows. A
## drag's own writes tag the brushes it moves, and are left alone.
func _on_brush_changed(brush_id: String) -> void:
	if is_dragging():
		return
	var root := _root()
	if root == null:
		return
	var selection = root.get("face_selection")
	if selection is Dictionary and (selection as Dictionary).has(brush_id):
		queue_refresh()
