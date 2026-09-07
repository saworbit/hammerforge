@tool
class_name HFDuplicator
extends RefCounted

## Manages a set of duplicate brush copies from source brushes with progressive offsets.

var duplicator_id := ""
var source_brush_ids: PackedStringArray = PackedStringArray()
var instance_groups: Array = []  # Array of PackedStringArray, one per copy
var count := 0
var offset := Vector3.ZERO


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
	var groups = data.get("instance_groups", [])
	dup.instance_groups = []
	for g in groups:
		var psa := PackedStringArray()
		for item in g:
			psa.append(str(item))
		dup.instance_groups.append(psa)
	return dup
