@tool
extends RefCounted
class_name HFSnapSystem
## Centralized snap system with grid, vertex, center, edge, and perpendicular modes.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFOverlayMesh = preload("hf_overlay_mesh.gd")
@warning_ignore_restore("shadowed_global_identifier")

enum SnapMode { GRID = 1, VERTEX = 2, CENTER = 4, EDGE = 8, PERPENDICULAR = 16 }

## What a snapped point is on (#1691). The viewport marks each kind with its own
## shape and names it, and Tab steps from one kind to the next, so the mapper can
## see why a point lands where it does and ask for another.
const KIND_GRID := "grid"
const KIND_VERTEX := "vertex"
const KIND_MIDPOINT := "midpoint"
const KIND_CENTRE := "centre"
const KIND_PERPENDICULAR := "perpendicular"
## The snap line the Measure tool sets with Align to this.
const KIND_LINE := "line"
## What the viewport calls each kind beside its marker.
const KIND_LABELS := {
	KIND_GRID: "Grid",
	KIND_VERTEX: "Vertex",
	KIND_MIDPOINT: "Midpoint",
	KIND_CENTRE: "Centre",
	KIND_PERPENDICULAR: "Perpendicular",
	KIND_LINE: "Line",
}
## The kinds a one-pick limit can ask for, with the snap mode each one is.
const LIMIT_MODES := {
	KIND_GRID: SnapMode.GRID,
	KIND_VERTEX: SnapMode.VERTEX,
	KIND_MIDPOINT: SnapMode.EDGE,
	KIND_CENTRE: SnapMode.CENTER,
	KIND_PERPENDICULAR: SnapMode.PERPENDICULAR,
}

## How near the cursor, in pixels, another brush's vertex has to be for a vertex
## or handle drag to land on it (#1399). A drag happens at every zoom, so the
## reach is measured on screen rather than in metres as a placement's is.
const DRAG_VERTEX_SNAP_PX := 10.0

## Half the width of the marker on the vertex a drag has landed on, in metres:
## the size of the vertex edit crosses, so the two read as one family.
const DRAG_MARKER_HALF := 0.4

## The quick grid sizes, in metres, offered by the dock buttons and the
## viewport context menu. One world unit is one metre (#625), so the rungs are
## a trim size up to a room size rather than the power-of-two Quake ladder
## that used to be here. Both surfaces read this one, because two ladders that
## drift apart show the same button doing two different things.
const GRID_PRESETS: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

## Past this many faces a brush's `faces` array is engine tessellation rather
## than geometry anyone could aim at: a cylinder brush is one FaceData per
## triangle, a sphere is thousands. Those brushes keep the bounding box they
## always had, now oriented by the brush transform. Hand built geometry
## (polygon, path, merged, bevelled, vertex edited) sits well under this.
const MAX_SNAP_FACES := 64

## Corner order for _box_corners(), and the 12 box edges as index pairs into it.
const BOX_EDGE_INDICES: Array = [
	[0, 1],
	[0, 2],
	[0, 4],
	[1, 3],
	[1, 5],
	[2, 3],
	[2, 6],
	[3, 7],
	[4, 5],
	[4, 6],
	[5, 7],
	[6, 7],
]

## Millimetre precision for _vertex_key. Two vertices closer than 1/1000 of a
## unit are the same snap target.
const VERTEX_KEY_SCALE := 1000.0

var root: Node3D
var enabled_modes: int = SnapMode.GRID
## How far a candidate may be from the point and still be snapped to.
##
## A value of zero or less turns every geometry candidate off, so it is refused
## rather than quietly disabling snapping. The backing variable is separate
## because a setter that assigns to its own property re-enters itself.
## 2.0 was this number when a grid step was 16 units, where it was an eighth of
## a step. At one unit to the metre it would be four grid steps, so every
## vertex in the room would beat the grid and grid snap would stop meaning
## anything. 0.1 m is the same "you are plainly aiming at that corner" distance.
var _snap_threshold: float = 0.1

var snap_threshold: float:
	get:
		return _snap_threshold
	set(value):
		if not is_finite(value) or value <= 0.0:
			HFLog.warn(
				(
					"HFSnapSystem: a snap threshold of %s would turn every candidate off. Kept %s."
					% [str(value), str(_snap_threshold)]
				)
			)
			return
		_snap_threshold = value
var _custom_snap_origin: Vector3 = Vector3.ZERO
var _custom_snap_dir: Vector3 = Vector3.ZERO
var _has_custom_snap := false

## Diagnostic: how many brushes had their geometry transformed by the last
## candidate query. Brushes culled by distance are not counted. Read by the scale
## test and useful when profiling a large level.
var brushes_measured: int = 0

## Face snap geometry per brush id. Brush space does not move with the brush,
## so an entry survives every drag, rotate and resize of everything around it
## and only goes stale when a brush's own faces change.
var _face_geometry_cache: Dictionary = {}

## The keys held over the viewport, as its last event had them: the invert key
## turns the grid the other way for a drag (#1431), the vertex key turns vertex
## snap on for a vertex or handle drag (#1399). The viewport sets both on every
## event, so a key pressed or let go mid-drag counts from the next motion. Only
## the drag queries below read them: a placement goes through `snap_point()`,
## which never does, so a key let go where the viewport cannot see it never
## reaches a drop or a palette command.
var invert_held := false
var vertex_held := false

## The marker on the vertex a drag has landed on, or null.
var _drag_marker: MeshInstance3D = null

## The nearest candidate of each kind the last query found, nearest first, each
## `{point, kind, distance}`. What Tab steps through.
var last_choices: Array = []
## The pick the viewport marks, `{point, kind}`, from the last query made while
## the pointer moved over it, or `{}`. A drop or a palette command snaps too and
## never shows here.
var shown_pick: Dictionary = {}
## Moves on every Tab and every one-pick limit, so a preview cached by pointer
## position knows to ask again.
var revision := 0
var _pointer_event := false
var _picked_in_event := false
## The kind Tab stepped to, and where the pointer was then. Moving further than
## the snap reach from there lets it go.
var _stepped_kind := ""
var _step_anchor := Vector3.ZERO
## The one kind the next pick may take, or "" for the running modes.
var _only_kind := ""


func _init(level_root: Node3D) -> void:
	root = level_root
	if root == null:
		return
	for sig in ["brush_changed", "brush_removed"]:
		if root.has_signal(sig):
			root.connect(sig, Callable(self, "_on_brush_geometry_invalidated"))


## Drop one brush's cached geometry. Both signals carry the id that changed.
func _on_brush_geometry_invalidated(brush_id: String) -> void:
	_face_geometry_cache.erase(brush_id)


func set_mode(mode: int, on: bool) -> void:
	if on:
		enabled_modes = enabled_modes | mode
	else:
		enabled_modes = enabled_modes & ~mode


func is_mode_on(mode: int) -> bool:
	return (enabled_modes & mode) != 0


func snap_point(point: Vector3, grid_snap: float, exclude_ids: Array = []) -> Vector3:
	return _snap(point, grid_snap if is_mode_on(SnapMode.GRID) else 0.0, exclude_ids)


## Where a point a drag holds lands, the draw's corners: as `snap_point()`, with
## the grid the drag asks for in place of G alone (#1431).
func snap_drag_point(point: Vector3, grid_snap: float, exclude_ids: Array = []) -> Vector3:
	return _snap(point, drag_grid_step(grid_snap), exclude_ids)


## Record the keys the viewport's latest event held. True when either changed.
func hold_drag_keys(invert: bool, vertex: bool) -> bool:
	var changed := invert != invert_held or vertex != vertex_held
	invert_held = invert
	vertex_held = vertex
	return changed


## Whether a drag lands on the grid: G, turned the other way while the invert
## key is held. The draw, the resize handles and the vertex drags all ask here,
## so G and the key mean the same everywhere (#1431).
func drag_grid_on() -> bool:
	return is_mode_on(SnapMode.GRID) != invert_held


## The grid step a drag lands on, or 0 when it lands where the cursor puts it.
func drag_grid_step(grid_snap: float) -> float:
	return grid_snap if grid_snap > 0.0 and drag_grid_on() else 0.0


## Whether a vertex or handle drag lands on other brushes' vertices: V, or its
## key held for the drag while V is off (#1399).
func drag_vertex_snap_on() -> bool:
	return is_mode_on(SnapMode.VERTEX) or vertex_held


func _snap(point: Vector3, step: float, exclude_ids: Array) -> Vector3:
	var choices := _choices(point, step, exclude_ids)
	last_choices = choices
	var pick := _pick_from(choices, point)
	if _pointer_event:
		_picked_in_event = true
		shown_pick = pick
	if pick.is_empty():
		return point
	return pick["point"]


## The nearest candidate of each kind within reach of `point`, nearest first. The
## grid is always in reach when it is on, and beats geometry further than the
## threshold, as it always has. With a one-pick limit only that kind is asked
## for, whether its mode is on or not.
func _choices(point: Vector3, step: float, exclude_ids: Array) -> Array:
	var nearest := {}
	if _only_kind == KIND_GRID and step <= 0.0:
		step = float(root.get("grid_snap")) if root else 0.0
	if step > 0.0 and (_only_kind == "" or _only_kind == KIND_GRID):
		var grid_snapped := point.snapped(Vector3(step, step, step))
		nearest[KIND_GRID] = [grid_snapped, point.distance_to(grid_snapped)]
	var running := enabled_modes
	if _only_kind != "" and _only_kind != KIND_GRID:
		enabled_modes = int(LIMIT_MODES.get(_only_kind, 0))
	if (
		is_mode_on(SnapMode.VERTEX)
		or is_mode_on(SnapMode.CENTER)
		or is_mode_on(SnapMode.EDGE)
		or is_mode_on(SnapMode.PERPENDICULAR)
	):
		for candidate in _collect_kinded(exclude_ids, point, snap_threshold):
			var d := point.distance_to(candidate[0])
			var kind: String = candidate[1]
			if d < snap_threshold and (not nearest.has(kind) or d < nearest[kind][1]):
				nearest[kind] = [candidate[0], d]
	enabled_modes = running

	# Custom snap line (from measure tool "Align to this")
	if _has_custom_snap and _only_kind == "":
		var projected := _project_onto_line(point, _custom_snap_origin, _custom_snap_dir)
		var d := point.distance_to(projected)
		if d < snap_threshold:
			nearest[KIND_LINE] = [projected, d]

	var out: Array = []
	for kind in nearest:
		out.append({"point": nearest[kind][0], "kind": kind, "distance": nearest[kind][1]})
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out


## The choice a pick takes: the kind Tab stepped to while the pointer stays near
## where Tab was pressed, otherwise the nearest.
func _pick_from(choices: Array, point: Vector3) -> Dictionary:
	if choices.is_empty():
		return {}
	if _stepped_kind != "":
		if point.distance_to(_step_anchor) <= snap_threshold:
			for choice in choices:
				if choice["kind"] == _stepped_kind:
					return choice
		_stepped_kind = ""
	return choices[0]


## Step the shown pick to the next kind in reach, and back round (#1691). False,
## with nothing changed, when fewer than two kinds are in reach of the pick the
## viewport shows, so Tab keeps its other uses then.
func step_choice() -> bool:
	if not can_step():
		return false
	var at := 0
	for i in last_choices.size():
		if last_choices[i]["kind"] == shown_pick.get("kind", ""):
			at = i
	var next: Dictionary = last_choices[(at + 1) % last_choices.size()]
	_stepped_kind = next["kind"]
	_step_anchor = shown_pick.get("point", next["point"])
	revision += 1
	return true


## Whether Tab has somewhere to step: the viewport shows a pick and more than one
## kind is in reach of it.
func can_step() -> bool:
	return not shown_pick.is_empty() and last_choices.size() > 1


## Limit the next pick to one kind, whatever the running modes are, then go back
## to them (#1691). False for a kind there is no limit for.
func limit_next_pick(kind: String) -> bool:
	if not LIMIT_MODES.has(kind):
		return false
	_only_kind = kind
	_stepped_kind = ""
	revision += 1
	return true


## The kind the next pick is limited to, or "".
func next_pick_limit() -> String:
	return _only_kind


## A pick was taken, by a click or the end of a drag: a one-pick limit and a Tab
## step are spent.
func pick_taken() -> void:
	if _only_kind == "" and _stepped_kind == "":
		return
	_only_kind = ""
	_stepped_kind = ""
	revision += 1


## The pointer moved over the viewport, or was pressed there. What snaps until
## `end_pointer_event()` is what the viewport marks.
func begin_pointer_event() -> void:
	_pointer_event = true
	_picked_in_event = false


## A motion that snapped nothing takes the mark down. True when the mark may have
## changed, so the viewport redraws.
func end_pointer_event(motion: bool) -> bool:
	_pointer_event = false
	if motion and not _picked_in_event and not shown_pick.is_empty():
		shown_pick = {}
		return true
	return _picked_in_event


## Mark a pick a drag made without `_snap()`, such as a vertex landing on another
## brush's vertex. Anything but a point and a kind takes the mark down.
func show_drag_pick(point: Variant, kind: String) -> void:
	if not _pointer_event:
		return
	_picked_in_event = true
	if point is Vector3 and kind != "":
		shown_pick = {"point": point, "kind": kind}
		last_choices = [shown_pick]
	else:
		shown_pick = {}
		last_choices = []


## Point every snap within `snap_threshold` of the line at the nearest point on
## it. Returns false and changes nothing when the direction is not a direction.
##
## `Vector3.ZERO.normalized()` is `Vector3.ZERO`, so a zero direction made
## `_project_onto_line()` return `line_origin + Vector3.ZERO * t` - the origin -
## for every input, and everything inside the threshold landed on one point. A
## ruler with both ends in the same place is a real thing a user can draw, and
## the only caller today checks the length before calling. The rule belongs here,
## with the code that depends on it.
func set_custom_snap_line(origin: Vector3, direction: Vector3) -> bool:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		HFLog.warn("HFSnapSystem: a snap line needs a direction. %s is not one." % str(direction))
		return false
	_custom_snap_origin = origin
	_custom_snap_dir = direction.normalized()
	_has_custom_snap = true
	return true


func clear_custom_snap_line() -> void:
	_has_custom_snap = false
	_custom_snap_origin = Vector3.ZERO
	_custom_snap_dir = Vector3.ZERO


## The vertex of a brush outside `exclude_ids` nearest the cursor on screen and
## within `max_px` of it, or null (#1399). A drag excludes the brushes it moves.
## A hidden brush is left out, since its corner is not there to aim at.
##
## A brush whose whole extent stays further from the cursor's ray than `max_px`
## reaches at its depth is passed over before its vertices are transformed, so
## the cost follows what is under the cursor, as `_collect_candidates()` does.
func vertex_near_screen(
	camera: Camera3D, screen_pos: Vector2, exclude_ids: Array, max_px := DRAG_VERTEX_SNAP_PX
) -> Variant:
	brushes_measured = 0
	if camera == null or root == null or not root.has_method("_iter_pick_nodes"):
		return null
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var forward := -camera.global_transform.basis.z
	# What `max_px` spans across the view one metre in front of the camera. A
	# perspective view widens it with depth, an orthographic one does not.
	var reach_at_one := camera.project_position(screen_pos, 1.0).distance_to(
		camera.project_position(screen_pos + Vector2(max_px, 0.0), 1.0)
	)
	var perspective := camera.projection != Camera3D.PROJECTION_ORTHOGONAL
	var best: Variant = null
	var best_px := max_px
	var preview = root.get("preview_brush")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush) or node == preview:
			continue
		var brush := node as DraftBrush
		if exclude_ids.has(str(brush.brush_id)) or not brush.is_visible_in_tree():
			continue
		var xform := brush.global_transform
		var extent := _world_reach(xform.basis, _snap_half_extent(brush))
		var to_origin := xform.origin - ray_origin
		var off_ray := (to_origin - ray_dir * to_origin.dot(ray_dir)).length()
		var depth := maxf(0.0, to_origin.dot(forward) + extent)
		var reach := reach_at_one * depth if perspective else reach_at_one
		if off_ray > reach + extent:
			continue
		brushes_measured += 1
		var local_verts: PackedVector3Array = _snap_geometry_local(brush)["verts"]
		for local_vert in local_verts:
			var world := xform * local_vert
			if camera.is_position_behind(world):
				continue
			var px := camera.unproject_position(world).distance_to(screen_pos)
			if px < best_px:
				best_px = px
				best = world
	return best


## Show the marker on `target`, the vertex a drag has landed on, or take it down
## when `target` is null (#1399). It hangs off the level unowned, so it is never
## saved, and it is drawn over everything, as the vertex edit crosses are.
func set_drag_marker(target: Variant) -> void:
	if not (target is Vector3) or root == null or not root.is_inside_tree():
		if _drag_marker != null and is_instance_valid(_drag_marker):
			HFOverlayMesh.release(_drag_marker)
		_drag_marker = null
		return
	if _drag_marker == null or not is_instance_valid(_drag_marker):
		_drag_marker = HFOverlayMesh.make(root, "_SnapTargetMarker")
		_draw_drag_marker(_drag_marker.mesh as ImmediateMesh)
	_drag_marker.global_transform = Transform3D(Basis.IDENTITY, target)


## Where the marker is, or null when no drag is snapped to a vertex.
func drag_marker_position() -> Variant:
	if _drag_marker == null or not is_instance_valid(_drag_marker):
		return null
	return _drag_marker.global_position


## A diamond round the origin with a cross through it, in the snap's cyan.
static func _draw_drag_marker(mesh: ImmediateMesh) -> void:
	var tips: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		tips.append(axis * DRAG_MARKER_HALF)
		tips.append(-axis * DRAG_MARKER_HALF)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(0.3, 0.9, 1.0))
	for i in range(0, 6, 2):
		mesh.surface_add_vertex(tips[i])
		mesh.surface_add_vertex(tips[i + 1])
		for j in range(i + 2, 6):
			mesh.surface_add_vertex(tips[i])
			mesh.surface_add_vertex(tips[j])
			mesh.surface_add_vertex(tips[i + 1])
			mesh.surface_add_vertex(tips[j])
	mesh.surface_end()


func _project_onto_line(point: Vector3, line_origin: Vector3, line_dir: Vector3) -> Vector3:
	var to_point: Vector3 = point - line_origin
	var t: float = to_point.dot(line_dir)
	return line_origin + line_dir * t


## Snap targets near `point`, in world space.
##
## `max_distance` is how far a candidate may be from the point and still matter.
## A brush whose own extent cannot reach that far is skipped before any of its
## vertices are transformed, which is the work that made this scale with the size
## of the level rather than with how much of it is under the pointer. Left at
## `INF` every brush is collected, which is what the geometry tests want.
func _collect_candidates(
	exclude_ids: Array, point: Vector3 = Vector3.ZERO, max_distance: float = INF
) -> PackedVector3Array:
	var out := PackedVector3Array()
	for candidate in _collect_kinded(exclude_ids, point, max_distance):
		out.append(candidate[0])
	return out


## `_collect_candidates()` with what each one is: `[point, kind]` pairs.
func _collect_kinded(
	exclude_ids: Array, point: Vector3 = Vector3.ZERO, max_distance: float = INF
) -> Array:
	var out: Array = []
	brushes_measured = 0
	if not root or not root.has_method("_iter_pick_nodes"):
		return out
	var do_vertex := is_mode_on(SnapMode.VERTEX)
	var do_center := is_mode_on(SnapMode.CENTER)
	var do_edge := is_mode_on(SnapMode.EDGE)
	var do_perp := is_mode_on(SnapMode.PERPENDICULAR)
	var preview = root.get("preview_brush")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		if node == preview:
			continue
		var brush := node as DraftBrush
		if exclude_ids.has(str(brush.brush_id)):
			continue
		var origin := brush.global_position
		var origin_distance := point.distance_to(origin)
		if do_center and origin_distance <= max_distance:
			out.append([origin, KIND_CENTRE])
		if not (do_vertex or do_edge or do_perp):
			continue
		# Snap points live in brush space. Going through the transform is what
		# carries the rotation and scale that world axis offsets threw away.
		var xform := brush.global_transform
		# Measured from the brush origin, so a long wall whose origin is far away
		# is still kept while any part of it is in range. Edges lie between two
		# vertices inside that reach, so perpendicular snap is covered too.
		#
		# The extent is read before the snap points are, because building them is
		# the work this is here to skip.
		if (
			max_distance < INF
			and origin_distance > max_distance + _world_reach(xform.basis, _snap_half_extent(brush))
		):
			continue
		var geometry := _snap_geometry_local(brush)
		brushes_measured += 1
		var local_verts: PackedVector3Array = geometry["verts"]
		var verts := PackedVector3Array()
		for local_vert in local_verts:
			verts.append(xform * local_vert)
		if do_vertex:
			for vert in verts:
				out.append([vert, KIND_VERTEX])
		if do_edge or do_perp:
			for edge in geometry["edges"]:
				var a: Vector3 = verts[edge[0]]
				var b: Vector3 = verts[edge[1]]
				if do_edge:
					out.append([(a + b) * 0.5, KIND_MIDPOINT])
				if do_perp:
					out.append([_closest_point_on_segment(point, a, b), KIND_PERPENDICULAR])
	return out


## How far one brush's snap points reach from its own origin, in brush space.
##
## The same answer as the `half` on the geometry `_snap_geometry_local()` returns,
## read without building the snap points, because on a large level most brushes
## are only asked this and then dropped. The two follow the same branch and
## `test_snap_candidate_culling.gd` holds them to the same answer.
func _snap_half_extent(brush: DraftBrush) -> Vector3:
	if brush.shape != DraftBrush.BrushShape.BOX:
		var faces: Array = brush.faces
		if not faces.is_empty() and faces.size() <= MAX_SNAP_FACES:
			var face_geometry := _cached_face_geometry(brush, faces)
			var face_verts: PackedVector3Array = face_geometry["verts"]
			if face_verts.size() >= 2:
				return face_geometry["half"]
	return (brush.size * 0.5).abs()


## Snap targets for one brush in brush-local space: unique vertices, plus the
## unique edges between them as index pairs into that vertex list.
##
## A brush that carries its own faces is described by them, so a wedge, prism,
## polygon, path or merged brush snaps to real corners instead of the corners of
## a box it does not fill. Everything else falls back to its bounding box.
func _snap_geometry_local(brush: DraftBrush) -> Dictionary:
	# A BOX brush is defined by its size: _rebuild_faces regenerates its faces
	# from size alone, so its corners are the size corners. Boxes are most of a
	# level, so take them straight rather than deduping six faces every query.
	if brush.shape == DraftBrush.BrushShape.BOX:
		return _box_geometry(brush.size)
	var faces: Array = brush.faces
	if not faces.is_empty() and faces.size() <= MAX_SNAP_FACES:
		var face_geometry := _cached_face_geometry(brush, faces)
		var face_verts: PackedVector3Array = face_geometry["verts"]
		if face_verts.size() >= 2:
			return face_geometry
	return _box_geometry(brush.size)


static func _box_geometry(size: Vector3) -> Dictionary:
	var half: Vector3 = size * 0.5
	return {"verts": _box_corners(half), "edges": BOX_EDGE_INDICES, "half": half.abs()}


## How far the transformed local box reaches from the brush origin.
##
## The furthest corner of a box under a basis is the one that takes every axis
## the same way, so summing the absolute contributions per axis bounds all eight
## of them. True for any basis, including a sheared or mirrored one.
static func _world_reach(basis: Basis, half: Vector3) -> float:
	var x: Vector3 = basis.x * half.x
	var y: Vector3 = basis.y * half.y
	var z: Vector3 = basis.z * half.z
	return (
		Vector3(
			absf(x.x) + absf(y.x) + absf(z.x),
			absf(x.y) + absf(y.y) + absf(z.y),
			absf(x.z) + absf(y.z) + absf(z.z)
		)
		. length()
	)


## Deduping a brush's faces is the expensive half of a snap query and it runs
## per brush per mouse motion event. The result is in brush space, so it only
## depends on the faces themselves.
##
## `brush_changed` is what says those faces moved. The stamp covers the paths
## that change geometry without announcing it first: a node swapped in under the
## same id by an undo, a face array replaced outright, and a resize, which
## rebuilds a wedge or prism's faces to the same count on the same node. A brush
## with no id is never cached, because nothing would name it to invalidate it.
func _cached_face_geometry(brush: DraftBrush, faces: Array) -> Dictionary:
	var brush_id := str(brush.brush_id)
	if brush_id == "":
		return _face_snap_geometry(faces)
	var instance_id := brush.get_instance_id()
	var face_count := faces.size()
	var size: Vector3 = brush.size
	var entry = _face_geometry_cache.get(brush_id)
	if (
		entry != null
		and entry["instance_id"] == instance_id
		and entry["face_count"] == face_count
		and entry["size"] == size
	):
		return entry["geometry"]
	var geometry := _face_snap_geometry(faces)
	_face_geometry_cache[brush_id] = {
		"instance_id": instance_id,
		"face_count": face_count,
		"size": size,
		"geometry": geometry,
	}
	return geometry


## Unique vertices and unique edges read off a brush's faces. A hull corner
## belongs to three or more faces and an edge to two, so both are deduped by
## rounded position.
static func _face_snap_geometry(faces: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var index_by_key: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		for v in face.local_verts:
			var key := _vertex_key(v)
			if not index_by_key.has(key):
				index_by_key[key] = verts.size()
				verts.append(v)
	var edges: Array = []
	var seen_edges: Dictionary = {}
	for face in faces:
		if face == null:
			continue
		var ring: PackedVector3Array = face.local_verts
		var count := ring.size()
		if count < 2:
			continue
		for i in range(count):
			var ia: int = index_by_key.get(_vertex_key(ring[i]), -1)
			var ib: int = index_by_key.get(_vertex_key(ring[(i + 1) % count]), -1)
			if ia < 0 or ib < 0 or ia == ib:
				continue
			var lo := mini(ia, ib)
			var hi := maxi(ia, ib)
			var edge_key := Vector2i(lo, hi)
			if seen_edges.has(edge_key):
				continue
			seen_edges[edge_key] = true
			edges.append([lo, hi])
	# The box that holds these vertices, so a query can tell how far this brush
	# reaches without transforming any of them.
	var half := Vector3.ZERO
	for v in verts:
		half = Vector3(maxf(half.x, absf(v.x)), maxf(half.y, absf(v.y)), maxf(half.z, absf(v.z)))
	return {"verts": verts, "edges": edges, "half": half}


## Vertices dedupe at millimetre precision. Keying by Vector3i holds that
## tolerance without formatting a string per vertex, which matters because this
## runs for every vertex of every non box brush on every mouse motion event.
static func _vertex_key(v: Vector3) -> Vector3i:
	return Vector3i(
		roundi(v.x * VERTEX_KEY_SCALE),
		roundi(v.y * VERTEX_KEY_SCALE),
		roundi(v.z * VERTEX_KEY_SCALE)
	)


## The 8 corners of a box, in the order BOX_EDGE_INDICES expects.
static func _box_corners(half: Vector3) -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
		]
	)


func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return a
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t
