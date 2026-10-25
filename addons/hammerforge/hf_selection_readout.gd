@tool
class_name HFSelectionReadout
extends RefCounted
## What is selected and how big it is, kept current for the two places that show
## it: the size labels on the selection's bounds in the viewport (#1403) and the
## Selection Info section of the dock (#1404). Both read one summary, so the
## numbers in the viewport and in the dock never disagree.
##
## The plugin holds one, points it at the level it is editing, hands it a source
## for the selection and vertex mode, and tells it about what only the plugin
## hears: a change of selection, an undo step, the vertex overlay's redraws. The
## level's own signals say when a brush, the face selection or the grid changes.
## A move with Godot's gizmo or a resize handle says nothing until it is
## committed, so while anything is selected the readout also compares where the
## selected brushes stand once a frame and refreshes when one has moved.
##
## The labels are Label3D nodes on the level, internal and with no owner, as the
## Face Select mark is: never saved, never in the Scene tree, freed when there is
## nothing to label, when the switch goes off, when the plugin points at another
## level and when the plugin goes.

## The summary changed. The dock's Selection Info section listens.
signal refreshed(summary: Dictionary)

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFSizeLabels = preload("hf_size_labels.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Godot's own axis colours, so each label reads as the axis it measures.
const AXIS_COLORS: Array[Color] = [
	Color(0.96, 0.2, 0.32), Color(0.53, 0.84, 0.01), Color(0.16, 0.55, 0.96)
]
## The group label's colour, apart from the three axes'.
const GROUP_LABEL_COLOR := Color(1.0, 0.85, 0.4)
## An extent below this is a flat side, a single face seen edge on, with no
## width to label.
const FLAT := 0.0005

var _watched_root: WeakRef = null
## Returns `{"nodes": Array, "vertex_mode": bool}` for the selection now.
var _source: Callable = Callable()
var _show_size := false
var _labels := HFSizeLabels.new()
## The name of the group the selection is, above it (#1723).
var _group_label := _make_group_label()
var _summary: Dictionary = empty_summary()
var _refresh_queued := false
## The ids of the brushes the summary was measured on, for `brush_changed`.
var _measured_ids: Dictionary = {}
## Where each measured brush stood, `[instance id, global transform, size]`.
var _measured_poses: Array = []
var _polling_tree: SceneTree = null


## Read the selection from [param source] from now on.
func set_source(source: Callable) -> void:
	_source = source
	queue_refresh()


## Measure on [param root] from now on, taking any labels off the level they
## were on. Null measures nothing.
func watch(root: Node) -> void:
	if root != null and not is_instance_valid(root):
		root = null
	if root != null and root == _root():
		return
	_stop_watching()
	if root != null and root.has_signal("brush_changed"):
		root.connect("brush_changed", _on_brush_changed)
		root.connect("brush_removed", _on_brush_removed)
		root.connect("face_selection_changed", queue_refresh)
		root.connect("state_loaded", queue_refresh)
		root.connect("grid_snap_changed", _on_grid_snap_changed)
		_watched_root = weakref(root)
	refresh()


## Stop measuring and take every label down, as the plugin does on its way out.
func reset() -> void:
	_stop_watching()
	_source = Callable()


## Show or hide the size labels. The summary is kept either way, for the dock.
func set_show_size(enabled: bool) -> void:
	if _show_size == enabled:
		return
	_show_size = enabled
	_update_labels()


func is_showing_size() -> bool:
	return _show_size


## Measure again once the frame's changes are in. A nudge of a hundred brushes
## tags each of them, and one refresh covers the lot.
func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_run_queued_refresh.call_deferred()


## Measure the selection now, and redraw the labels from it.
func refresh() -> void:
	var root := _root()
	var nodes: Array = []
	var vertex_mode := false
	if _source.is_valid():
		var state = _source.call()
		if state is Dictionary:
			nodes = (state as Dictionary).get("nodes", [])
			vertex_mode = bool((state as Dictionary).get("vertex_mode", false))
	var summary := empty_summary()
	if root != null and root.is_inside_tree():
		summary = summarize(root, nodes, vertex_mode)
	_remember_measured(summary.get("brushes", []))
	summary.erase("brushes")
	var changed := summary != _summary
	_summary = summary
	_update_labels()
	_update_polling(root)
	if changed:
		refreshed.emit(_summary.duplicate(true))


## The selection as last measured. See `summarize()` for its keys.
func get_summary() -> Dictionary:
	return _summary.duplicate(true)


## The labels shown now, width, depth and height in that order where each has
## a length.
func get_labels() -> Array[Label3D]:
	return _labels.get_labels()


## The node the labels hang from, or null while none is shown.
func get_label_container() -> Node3D:
	return _labels.get_container()


# ---------------------------------------------------------------------------
# Measuring
# ---------------------------------------------------------------------------


static func empty_summary() -> Dictionary:
	return {
		"kind": "",
		"count": 0,
		"step": 0.0,
		"world": {},
		"local": {},
		"has_bounds": false,
		"bounds": AABB(),
		"vertex": {},
		"group": "",
		"open_group": "",
	}


## What [param nodes] and the level's face and vertex selections amount to.
##
## - `kind`: "" for nothing, or "brush", "brushes", "face", "faces", "vertex",
##   "vertices", "edge", "edges". A vertex or edge selection in vertex mode comes
##   first, then a face selection, then the selected brushes.
## - `count`, and `step`, the grid step the numbers are printed to.
## - `world` and `local`: the numbers in each space. Local is the brush's own
##   space for a vertex, edge or face and the parent's space for a brush, as the
##   Inspector shows it; empty when several things do not share one. One brush
##   has `centre` and `size`, one face `centre`, `normal` and `area`, one vertex
##   `position`, one edge `length` and `midpoint`, and several of anything the
##   `centre` and `size` of their bounds.
## - `bounds` (world, with `has_bounds`): what the size labels go on, the
##   picked faces for a face selection and the selected brushes otherwise.
## - `vertex`: `brush_id` and `index` of the one vertex, for typing its place.
## - `group`: the group the selection is, when it is one group and nothing else,
##   and `open_group`, the group open now (#1723).
## - `brushes`: the brushes measured.
static func summarize(root: Node, nodes: Array, vertex_mode: bool) -> Dictionary:
	var summary := empty_summary()
	summary["brushes"] = []
	if root == null or not is_instance_valid(root):
		return summary
	var step = root.get("grid_snap")
	summary["step"] = float(step) if step != null else 0.0
	var brushes: Array = []
	for node in nodes:
		if node is DraftBrush and is_instance_valid(node) and (node as Node).is_inside_tree():
			brushes.append(node)
	var vs = root.get("vertex_system")
	if vertex_mode and vs != null:
		if vs.sub_mode == vs.VertexSubMode.EDGE:
			_summarize_edges(root, vs, summary)
		else:
			_summarize_vertices(root, vs, summary)
	if summary["kind"] == "":
		_summarize_faces(_picked_faces(root), summary)
	if summary["kind"] == "" and not brushes.is_empty():
		_summarize_brushes(brushes, summary)
	if not summary["has_bounds"] and not brushes.is_empty():
		summary["bounds"] = _aabb_of(_world_points_of(brushes))
		summary["has_bounds"] = true
	var measured: Array = summary["brushes"]
	for brush in brushes:
		if not measured.has(brush):
			measured.append(brush)
	var groups = root.get("visgroup_system")
	if groups != null:
		summary["open_group"] = str(groups.open_group)
		var units: Dictionary = groups.units_of(nodes)
		if (units["groups"] as Array).size() == 1 and (units["nodes"] as Array).is_empty():
			summary["group"] = str(units["groups"][0])
	return summary


## A brush's corners in its own space: its faces' vertices, or the box its size
## describes when it has no faces yet.
static func brush_points(brush: DraftBrush) -> PackedVector3Array:
	var points := PackedVector3Array()
	for face in brush.faces:
		if face != null:
			points.append_array(face.local_verts)
	if points.is_empty():
		var half := brush.size * 0.5
		for corner in 8:
			points.append(
				Vector3(
					half.x if corner & 1 else -half.x,
					half.y if corner & 2 else -half.y,
					half.z if corner & 4 else -half.z
				)
			)
	return points


## The size labels for [param bounds]: width along the bottom edge on the +Z
## side, depth along the bottom edge on the +X side and height up the corner they
## meet at, each where it has a length, printed to the grid of [param step]. The
## two along the bottom sit under their edge and the height beside its own, off
## the resize handle in the middle of each face, which a thin brush puts right
## on the edge.
static func label_entries(bounds: AABB, step: float) -> Array:
	var low := bounds.position
	var high := bounds.end
	var mid := bounds.get_center()
	var under := Vector2(0, -HFSizeLabels.FONT_SIZE)
	var beside := Vector2(HFSizeLabels.FONT_SIZE * 1.5, 0)
	var places := [
		[0, Vector3(mid.x, low.y, high.z), under],
		[2, Vector3(high.x, low.y, mid.z), under],
		[1, Vector3(high.x, mid.y, high.z), beside],
	]
	var entries: Array = []
	for place in places:
		var axis: int = place[0]
		var length: float = bounds.size[axis]
		if length < FLAT:
			continue
		var entry := {
			"axis": axis,
			"position": place[1],
			"offset": place[2],
			"text": HFNumberFormat.number(length, step),
			"color": AXIS_COLORS[axis],
		}
		entries.append(entry)
	return entries


## The area of a flat polygon, from Newell's sum.
static func polygon_area(points: PackedVector3Array) -> float:
	var sum := Vector3.ZERO
	for i in points.size():
		sum += points[i].cross(points[(i + 1) % points.size()])
	return sum.length() * 0.5


static func _summarize_brushes(brushes: Array, summary: Dictionary) -> void:
	summary["count"] = brushes.size()
	summary["brushes"] = brushes
	if brushes.size() == 1:
		var brush: DraftBrush = brushes[0]
		summary["kind"] = "brush"
		# A primitive is its size about its origin, which is what the Inspector and
		# `get_brush_info_from_node()` say. A brush whose faces were edited by hand
		# no longer fills that box, so its faces say where it is and how big.
		var centre := Vector3.ZERO
		var size: Vector3 = brush.size
		if brush.shape == DraftBrush.BrushShape.CUSTOM:
			var own := _aabb_of(brush_points(brush))
			centre = own.get_center()
			size = own.size
		summary["world"] = {
			"centre": brush.global_transform * centre,
			"size": size * brush.global_transform.basis.get_scale(),
		}
		summary["local"] = {
			"centre": brush.transform * centre,
			"size": size * brush.transform.basis.get_scale(),
		}
		return
	summary["kind"] = "brushes"
	var world := _world_points_of(brushes)
	summary["world"] = _bounds_entry(world)
	var parent := (brushes[0] as Node).get_parent() as Node3D
	for brush in brushes:
		if (brush as Node).get_parent() != parent:
			parent = null
			break
	if parent != null:
		summary["local"] = _bounds_entry(parent.global_transform.affine_inverse() * world)


static func _summarize_faces(picked: Array, summary: Dictionary) -> void:
	if picked.is_empty():
		return
	summary["count"] = picked.size()
	var world := PackedVector3Array()
	var local := PackedVector3Array()
	var brushes: Array = []
	for item in picked:
		var brush: DraftBrush = item["brush"]
		var face: FaceData = item["face"]
		world.append_array(brush.global_transform * face.local_verts)
		local.append_array(face.local_verts)
		if not brushes.has(brush):
			brushes.append(brush)
	summary["brushes"] = brushes
	summary["bounds"] = _aabb_of(world)
	summary["has_bounds"] = true
	if picked.size() == 1:
		var brush: DraftBrush = picked[0]["brush"]
		var face: FaceData = picked[0]["face"]
		summary["kind"] = "face"
		summary["world"] = {
			"centre": _mean(world),
			"normal": face.normal_through(brush.global_transform.basis),
			"area": polygon_area(world),
		}
		summary["local"] = {
			"centre": _mean(local), "normal": face.normal, "area": polygon_area(local)
		}
		return
	summary["kind"] = "faces"
	summary["world"] = _bounds_entry(world)
	if brushes.size() == 1:
		summary["local"] = _bounds_entry(local)


static func _summarize_vertices(root: Node, vs: Object, summary: Dictionary) -> void:
	var world := PackedVector3Array()
	var local := PackedVector3Array()
	var brushes: Array = []
	var first := {}
	for brush_id in vs.selected_vertices:
		var brush := root.call("find_brush_by_id", str(brush_id)) as DraftBrush
		if brush == null or not brush.is_inside_tree():
			continue
		var verts: PackedVector3Array = vs.get_brush_vertices(brush)
		for index in vs.selected_vertices[brush_id]:
			if index < 0 or index >= verts.size():
				continue
			local.append(verts[index])
			world.append(brush.global_transform * verts[index])
			if first.is_empty():
				first = {"brush_id": str(brush_id), "index": int(index)}
			if not brushes.has(brush):
				brushes.append(brush)
	if world.is_empty():
		return
	summary["count"] = world.size()
	summary["brushes"] = brushes
	if world.size() == 1:
		summary["kind"] = "vertex"
		summary["vertex"] = first
		summary["world"] = {"position": world[0]}
		summary["local"] = {"position": local[0]}
		return
	summary["kind"] = "vertices"
	summary["world"] = _bounds_entry(world)
	if brushes.size() == 1:
		summary["local"] = _bounds_entry(local)


static func _summarize_edges(root: Node, vs: Object, summary: Dictionary) -> void:
	var world := PackedVector3Array()
	var local := PackedVector3Array()
	var brushes: Array = []
	var count := 0
	for brush_id in vs.selected_edges:
		var brush := root.call("find_brush_by_id", str(brush_id)) as DraftBrush
		if brush == null or not brush.is_inside_tree():
			continue
		var verts: PackedVector3Array = vs.get_brush_vertices(brush)
		for edge in vs.selected_edges[brush_id]:
			var a := int(edge[0])
			var b := int(edge[1])
			if a < 0 or b < 0 or a >= verts.size() or b >= verts.size():
				continue
			count += 1
			for index in [a, b]:
				local.append(verts[index])
				world.append(brush.global_transform * verts[index])
			if not brushes.has(brush):
				brushes.append(brush)
	if count == 0:
		return
	summary["count"] = count
	summary["brushes"] = brushes
	if count == 1:
		summary["kind"] = "edge"
		summary["world"] = {
			"length": world[0].distance_to(world[1]), "midpoint": (world[0] + world[1]) * 0.5
		}
		summary["local"] = {
			"length": local[0].distance_to(local[1]), "midpoint": (local[0] + local[1]) * 0.5
		}
		return
	summary["kind"] = "edges"
	summary["world"] = _bounds_entry(world)
	if brushes.size() == 1:
		summary["local"] = _bounds_entry(local)


## Each picked face that is still there, `{"brush", "face_idx", "face"}`. A key
## can name a brush Godot deleted this frame, until the reconcile unpicks it.
static func _picked_faces(root: Node) -> Array:
	var picked: Array = []
	var selection = root.get("face_selection")
	if not (selection is Dictionary):
		return picked
	for key in (selection as Dictionary).keys():
		var brush := root.call("_find_brush_by_key", str(key)) as DraftBrush
		if brush == null or not brush.is_inside_tree():
			continue
		for index in (selection as Dictionary).get(key, []):
			var face_idx := int(index)
			if face_idx < 0 or face_idx >= brush.faces.size():
				continue
			var face: FaceData = brush.faces[face_idx]
			if face == null or face.local_verts.size() < 3:
				continue
			picked.append({"brush": brush, "face_idx": face_idx, "face": face})
	return picked


static func _world_points_of(brushes: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for brush in brushes:
		points.append_array((brush as DraftBrush).global_transform * brush_points(brush))
	return points


static func _bounds_entry(points: PackedVector3Array) -> Dictionary:
	var bounds := _aabb_of(points)
	return {"centre": bounds.get_center(), "size": bounds.size}


static func _aabb_of(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


static func _mean(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(maxi(points.size(), 1))


# ---------------------------------------------------------------------------
# Labels and upkeep
# ---------------------------------------------------------------------------


func _update_labels() -> void:
	var root := _root()
	_update_group_label(root)
	if not _show_size or root == null or not bool(_summary.get("has_bounds", false)):
		_labels.clear()
		return
	_labels.show_labels(root, label_entries(_summary["bounds"], float(_summary.get("step", 0.0))))


## The group's name above the middle of its top, whether or not the sizes show.
func _update_group_label(root: Node) -> void:
	var group_name := str(_summary.get("group", ""))
	if root == null or group_name == "" or not bool(_summary.get("has_bounds", false)):
		_group_label.clear()
		return
	var bounds: AABB = _summary["bounds"]
	var top := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	(
		_group_label
		. show_labels(
			root,
			[
				{
					"position": top,
					"offset": Vector2(0, HFSizeLabels.FONT_SIZE),
					"text": group_name,
					"color": GROUP_LABEL_COLOR,
				}
			]
		)
	)


static func _make_group_label() -> HFSizeLabels:
	var made := HFSizeLabels.new()
	made.container_name = &"_GroupLabel"
	return made


func _remember_measured(brushes: Array) -> void:
	_measured_ids.clear()
	for brush in brushes:
		_measured_ids[str((brush as DraftBrush).brush_id)] = true
	_measured_poses = _poses_of(brushes)


static func _poses_of(brushes: Array) -> Array:
	var poses: Array = []
	for brush in brushes:
		if is_instance_valid(brush) and (brush as Node).is_inside_tree():
			poses.append(
				[brush.get_instance_id(), (brush as Node3D).global_transform, brush.get("size")]
			)
		else:
			poses.append([0])
	return poses


## Look each frame only while there is something measured to move.
func _update_polling(root: Node) -> void:
	var tree: SceneTree = root.get_tree() if root != null and root.is_inside_tree() else null
	if _summary.get("kind", "") == "" or _measured_poses.is_empty():
		tree = null
	if tree == _polling_tree:
		return
	_stop_polling()
	if tree != null:
		tree.process_frame.connect(_on_process_frame)
		_polling_tree = tree


func _stop_polling() -> void:
	if _polling_tree != null and is_instance_valid(_polling_tree):
		if _polling_tree.process_frame.is_connected(_on_process_frame):
			_polling_tree.process_frame.disconnect(_on_process_frame)
	_polling_tree = null


func _on_process_frame() -> void:
	var brushes: Array = []
	for pose in _measured_poses:
		var brush := instance_from_id(int(pose[0])) if int(pose[0]) != 0 else null
		brushes.append(brush)
	if _poses_of(brushes) != _measured_poses:
		refresh()


func _stop_watching() -> void:
	var root := _root()
	if root != null:
		if root.is_connected("brush_changed", _on_brush_changed):
			root.disconnect("brush_changed", _on_brush_changed)
		if root.is_connected("brush_removed", _on_brush_removed):
			root.disconnect("brush_removed", _on_brush_removed)
		if root.is_connected("face_selection_changed", queue_refresh):
			root.disconnect("face_selection_changed", queue_refresh)
		if root.is_connected("state_loaded", queue_refresh):
			root.disconnect("state_loaded", queue_refresh)
		if root.is_connected("grid_snap_changed", _on_grid_snap_changed):
			root.disconnect("grid_snap_changed", _on_grid_snap_changed)
	_watched_root = null
	_stop_polling()
	_labels.clear()
	_group_label.clear()
	_measured_ids.clear()
	_measured_poses.clear()
	var had_summary: bool = _summary.get("kind", "") != ""
	_summary = empty_summary()
	if had_summary:
		refreshed.emit(_summary.duplicate(true))


func _root() -> Node:
	if _watched_root == null:
		return null
	return _watched_root.get_ref() as Node


func _run_queued_refresh() -> void:
	_refresh_queued = false
	refresh()


## A move, a resize or a vertex edit tags the brush it changed. Only a measured
## brush changes the numbers.
func _on_brush_changed(brush_id: String) -> void:
	if _measured_ids.has(brush_id):
		queue_refresh()


func _on_brush_removed(_brush_id: String) -> void:
	queue_refresh()


func _on_grid_snap_changed(_value: float) -> void:
	queue_refresh()
