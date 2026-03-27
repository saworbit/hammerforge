@tool
class_name HFPrefab
extends RefCounted
## Reusable brush + entity group that can be saved to .hfprefab files
## and instanced into any level.
##
## Captures brush infos and entity infos with transforms relative to
## a centroid, so they can be placed at any world position.

var prefab_name: String = ""
var brush_infos: Array = []  # Array[Dictionary]  — from get_brush_info_from_node()
var entity_infos: Array = []  # Array[Dictionary] — from capture_entity_info()


## Capture a prefab from the current selection.
## brush_nodes: Array of DraftBrush nodes
## entity_nodes: Array of DraftEntity nodes
## brush_system / entity_system: subsystem references (untyped to avoid circular preload)
static func capture_from_selection(
	brush_system, entity_system, brush_nodes: Array, entity_nodes: Array
) -> HFPrefab:
	var prefab = HFPrefab.new()
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return prefab

	# Compute centroid of all nodes
	var positions: Array = []
	for b in brush_nodes:
		if b is Node3D:
			positions.append(b.global_position)
	for e in entity_nodes:
		if e is Node3D:
			positions.append(e.global_position)
	var centroid := Vector3.ZERO
	if not positions.is_empty():
		for pos in positions:
			centroid += pos
		centroid /= float(positions.size())

	# Capture brushes
	for brush in brush_nodes:
		var info: Dictionary = brush_system.get_brush_info_from_node(brush)
		if info.is_empty():
			continue
		# Make transform relative to centroid
		if info.has("transform"):
			var t: Transform3D = info["transform"]
			t.origin -= centroid
			info["transform"] = t
		# Clear brush_id so new ones are assigned on instantiation
		info.erase("brush_id")
		# Clear group memberships (prefab instances get their own)
		info.erase("group_id")
		prefab.brush_infos.append(info)

	# Capture entities
	for entity in entity_nodes:
		var info: Dictionary = entity_system.capture_entity_info(entity)
		if info.is_empty():
			continue
		if info.has("transform"):
			var t: Transform3D = info["transform"]
			t.origin -= centroid
			info["transform"] = t
		prefab.entity_infos.append(info)

	return prefab


## Instantiate this prefab at a world position.
## Returns a dictionary: {"brush_ids": Array, "entity_count": int}.
func instantiate(brush_system, entity_system, root, placement_pos: Vector3) -> Dictionary:
	var result := {"brush_ids": [] as Array, "entity_count": 0}
	if brush_infos.is_empty() and entity_infos.is_empty():
		return result

	# Batch signals to avoid flooding
	if root.has_method("begin_signal_batch"):
		root.begin_signal_batch()

	# Name remapping for entity I/O connections
	var name_map: Dictionary = {}
	var new_brush_ids: Array = []

	# Instantiate brushes
	for info in brush_infos:
		var placed_info: Dictionary = info.duplicate(true)
		# Offset transform by placement position
		if placed_info.has("transform"):
			var t: Transform3D = placed_info["transform"]
			t.origin += placement_pos
			placed_info["transform"] = t
		# Assign new brush_id
		if brush_system.has_method("next_brush_id"):
			placed_info["brush_id"] = brush_system.next_brush_id()
		var brush = brush_system.create_brush_from_info(placed_info)
		if brush:
			new_brush_ids.append(str(placed_info.get("brush_id", "")))

	# Instantiate entities
	for info in entity_infos:
		var placed_info: Dictionary = info.duplicate(true)
		if placed_info.has("transform"):
			var t: Transform3D = placed_info["transform"]
			t.origin += placement_pos
			placed_info["transform"] = t
		var old_name: String = str(placed_info.get("name", ""))
		var entity = entity_system.restore_entity_from_info(placed_info)
		if entity:
			result["entity_count"] += 1
			if old_name != "":
				name_map[old_name] = entity.name

	# Remap I/O connections
	if not name_map.is_empty() and entity_system.has_method("remap_io_connections"):
		for entity_info in entity_infos:
			var ent_name: String = name_map.get(str(entity_info.get("name", "")), "")
			if ent_name == "":
				continue
			var entities = entity_system.find_entities_by_name(ent_name)
			if not entities.is_empty():
				entity_system.remap_io_connections(entities[0], name_map)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	result["brush_ids"] = new_brush_ids
	return result


## Serialize to a dictionary suitable for JSON storage.
func to_dict() -> Dictionary:
	return {
		"prefab_name": prefab_name,
		"brush_infos": HFLevelIO.encode_variant(brush_infos),
		"entity_infos": HFLevelIO.encode_variant(entity_infos),
	}


## Deserialize from a dictionary.
static func from_dict(data: Dictionary) -> HFPrefab:
	var prefab = HFPrefab.new()
	prefab.prefab_name = str(data.get("prefab_name", ""))
	var raw_brushes = HFLevelIO.decode_variant(data.get("brush_infos", []))
	var raw_entities = HFLevelIO.decode_variant(data.get("entity_infos", []))
	prefab.brush_infos = raw_brushes if raw_brushes is Array else []
	prefab.entity_infos = raw_entities if raw_entities is Array else []
	return prefab


## Save prefab to a .hfprefab JSON file.
func save_to_file(path: String) -> int:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	var json_text := JSON.stringify(to_dict(), "\t")
	file.store_string(json_text)
	var err := file.get_error()
	return err


## Load prefab from a .hfprefab JSON file.
static func load_from_file(path: String) -> HFPrefab:
	if not FileAccess.file_exists(path):
		push_warning("HFPrefab: file not found: %s" % path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("HFPrefab: cannot open: %s" % path)
		return null
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("HFPrefab: invalid JSON in %s" % path)
		return null
	return from_dict(parsed)
