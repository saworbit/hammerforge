@tool
class_name HFDuplicator
extends RefCounted

## Manages a set of duplicate brush copies laid out from source brushes.
##
## Three layouts share one instance bookkeeping: a linear run of progressive
## offsets, a radial ring about an axis, and a 3D lattice. Radial copies compose
## their transform through `HFTransformSystem`, so there is one rotation
## implementation in the plugin rather than two.

enum ArrayMode { LINEAR, RADIAL, GRID }

var duplicator_id := ""
var source_brush_ids: PackedStringArray = PackedStringArray()
var instance_groups: Array = []  # Array of PackedStringArray, one per copy
var count := 0
var offset := Vector3.ZERO
var mode: int = ArrayMode.LINEAR
## Radial layout: rotation axis (0 = X, 1 = Y, 2 = Z), degrees between copies,
## and the world point the ring turns about.
var axis_index: int = 1
var step_degrees: float = 90.0
var pivot: Vector3 = Vector3.ZERO
## Grid layout: copies per axis including the source cell, and the gap between
## cells on each axis.
var grid_counts: Vector3i = Vector3i(2, 1, 2)
var grid_spacing: Vector3 = Vector3(64.0, 64.0, 64.0)


func _init() -> void:
	duplicator_id = "dup_%d" % Time.get_ticks_msec()


## Create N copies of the source brushes with progressive offset.
## brush_system is untyped to avoid circular preload.
func generate(brush_system, p_count: int, p_offset: Vector3) -> bool:
	if source_brush_ids.is_empty() or p_count < 1:
		return false
	count = p_count
	offset = p_offset
	instance_groups.clear()

	for copy_index in range(1, p_count + 1):
		var copy_ids := PackedStringArray()
		for source_id in source_brush_ids:
			var brush_node = brush_system.find_brush_by_id(source_id)
			if not is_instance_valid(brush_node):
				push_warning("HFDuplicator: source brush '%s' not found, skipping" % source_id)
				continue
			var info: Dictionary = brush_system.build_duplicate_info(
				brush_node, p_offset * copy_index
			)
			if info.is_empty():
				continue
			var new_brush = brush_system.create_brush_from_info(info)
			if not is_instance_valid(new_brush):
				continue
			new_brush.set_meta("duplicator_instance_of", duplicator_id)
			var new_id: String = str(info.get("brush_id", ""))
			if new_id != "":
				copy_ids.append(new_id)
		instance_groups.append(copy_ids)

	# Tag source brushes
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush):
			source_brush.set_meta("duplicator_id", duplicator_id)

	return true


## Create N copies rotated `step_degrees` apart about `p_pivot`.
##
## The step is given directly rather than as a total sweep so there is no
## ambiguity about whether the last copy lands on the end angle. To close a full
## ring, pass `360.0 / (p_count + 1)`.
func generate_radial(
	brush_system, p_count: int, p_axis_index: int, p_step_degrees: float, p_pivot: Vector3
) -> bool:
	if source_brush_ids.is_empty() or p_count < 1:
		return false
	mode = ArrayMode.RADIAL
	count = p_count
	axis_index = p_axis_index
	step_degrees = p_step_degrees
	pivot = p_pivot
	instance_groups.clear()

	for copy_index in range(1, p_count + 1):
		var angle := deg_to_rad(p_step_degrees * copy_index)
		var rot := HFTransformSystem.rotation_basis(p_axis_index, angle)
		var copy_ids := PackedStringArray()
		for source_id in source_brush_ids:
			var info := _copy_info(brush_system, source_id)
			if info.is_empty():
				continue
			var source_xform: Transform3D = info.get("transform", Transform3D.IDENTITY)
			info["transform"] = HFTransformSystem.rotated_transform(source_xform, rot, p_pivot)
			info.erase("center")
			var new_id := _spawn_copy(brush_system, info)
			if new_id != "":
				copy_ids.append(new_id)
		instance_groups.append(copy_ids)

	_tag_sources(brush_system)
	return true


## Create a lattice of copies. `p_counts` includes the source cell on each axis,
## so 2x1x2 produces three copies around one original.
func generate_grid(brush_system, p_counts: Vector3i, p_spacing: Vector3) -> bool:
	if source_brush_ids.is_empty():
		return false
	var counts := Vector3i(maxi(1, p_counts.x), maxi(1, p_counts.y), maxi(1, p_counts.z))
	if counts.x * counts.y * counts.z <= 1:
		return false
	mode = ArrayMode.GRID
	grid_counts = counts
	grid_spacing = p_spacing
	count = counts.x * counts.y * counts.z - 1
	instance_groups.clear()

	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				if ix == 0 and iy == 0 and iz == 0:
					continue
				var cell_offset := Vector3(p_spacing.x * ix, p_spacing.y * iy, p_spacing.z * iz)
				var copy_ids := PackedStringArray()
				for source_id in source_brush_ids:
					var brush_node = brush_system.find_brush_by_id(source_id)
					if not is_instance_valid(brush_node):
						push_warning(
							"HFDuplicator: source brush '%s' not found, skipping" % source_id
						)
						continue
					var info: Dictionary = brush_system.build_duplicate_info(
						brush_node, cell_offset
					)
					if info.is_empty():
						continue
					var new_id := _spawn_copy(brush_system, info)
					if new_id != "":
						copy_ids.append(new_id)
				instance_groups.append(copy_ids)

	_tag_sources(brush_system)
	return true


func _copy_info(brush_system, source_id: String) -> Dictionary:
	var brush_node = brush_system.find_brush_by_id(source_id)
	if not is_instance_valid(brush_node):
		push_warning("HFDuplicator: source brush '%s' not found, skipping" % source_id)
		return {}
	return brush_system.build_duplicate_info(brush_node, Vector3.ZERO)


func _spawn_copy(brush_system, info: Dictionary) -> String:
	var new_brush = brush_system.create_brush_from_info(info)
	if not is_instance_valid(new_brush):
		return ""
	new_brush.set_meta("duplicator_instance_of", duplicator_id)
	return str(info.get("brush_id", ""))


func _tag_sources(brush_system) -> void:
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush):
			source_brush.set_meta("duplicator_id", duplicator_id)


## Remove all instance brushes created by this duplicator.
func clear_instances(brush_system) -> void:
	for group in instance_groups:
		for brush_id in group:
			brush_system.delete_brush_by_id(brush_id)
	instance_groups.clear()

	# Remove meta from source brushes (if they still exist)
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush) and source_brush.has_meta("duplicator_id"):
			source_brush.remove_meta("duplicator_id")
	count = 0


## Return all instance brush IDs flattened into one array.
func get_all_instance_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for group in instance_groups:
		for brush_id in group:
			out.append(brush_id)
	return out


## Serialize to dictionary for state capture.
func to_dict() -> Dictionary:
	var groups_arr: Array = []
	for g in instance_groups:
		groups_arr.append(Array(g))
	return {
		"duplicator_id": duplicator_id,
		"source_brush_ids": Array(source_brush_ids),
		"count": count,
		"offset": [offset.x, offset.y, offset.z],
		"instance_groups": groups_arr,
		"mode": mode,
		"axis_index": axis_index,
		"step_degrees": step_degrees,
		"pivot": [pivot.x, pivot.y, pivot.z],
		"grid_counts": [grid_counts.x, grid_counts.y, grid_counts.z],
		"grid_spacing": [grid_spacing.x, grid_spacing.y, grid_spacing.z],
	}


## Reconstruct a duplicator from a serialized dictionary.
static func from_dict(data: Dictionary) -> HFDuplicator:
	var dup := HFDuplicator.new()
	dup.duplicator_id = str(data.get("duplicator_id", dup.duplicator_id))
	var src_arr = data.get("source_brush_ids", [])
	var src := PackedStringArray()
	for s in src_arr:
		src.append(str(s))
	dup.source_brush_ids = src
	dup.count = int(data.get("count", 0))
	var off_arr = data.get("offset", [0.0, 0.0, 0.0])
	if off_arr is Array and off_arr.size() >= 3:
		dup.offset = Vector3(float(off_arr[0]), float(off_arr[1]), float(off_arr[2]))
	# A dictionary written before array modes existed has no "mode" key and loads
	# as the linear layout it was.
	dup.mode = int(data.get("mode", ArrayMode.LINEAR))
	dup.axis_index = int(data.get("axis_index", 1))
	dup.step_degrees = float(data.get("step_degrees", 90.0))
	var pivot_arr = data.get("pivot", [0.0, 0.0, 0.0])
	if pivot_arr is Array and pivot_arr.size() >= 3:
		dup.pivot = Vector3(float(pivot_arr[0]), float(pivot_arr[1]), float(pivot_arr[2]))
	var counts_arr = data.get("grid_counts", [2, 1, 2])
	if counts_arr is Array and counts_arr.size() >= 3:
		dup.grid_counts = Vector3i(int(counts_arr[0]), int(counts_arr[1]), int(counts_arr[2]))
	var spacing_arr = data.get("grid_spacing", [64.0, 64.0, 64.0])
	if spacing_arr is Array and spacing_arr.size() >= 3:
		dup.grid_spacing = Vector3(
			float(spacing_arr[0]), float(spacing_arr[1]), float(spacing_arr[2])
		)
	var groups = data.get("instance_groups", [])
	dup.instance_groups = []
	for g in groups:
		var psa := PackedStringArray()
		for item in g:
			psa.append(str(item))
		dup.instance_groups.append(psa)
	return dup
