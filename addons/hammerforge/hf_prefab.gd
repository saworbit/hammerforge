@tool
class_name HFPrefab
extends RefCounted
## Reusable brush + entity group that can be saved to .hfprefab files
## and instanced into any level.
##
## Captures brush infos and entity infos with transforms relative to
## a centroid, so they can be placed at any world position.
##
## Supports variants (e.g. different door styles) stored alongside
## the base data, tags for browser filtering, and linked-instance
## metadata for propagation workflows.

const HFLog = preload("res://addons/hammerforge/hf_log.gd")

var prefab_name: String = ""
var brush_infos: Array = []  # Array[Dictionary]  — from get_brush_info_from_node()
var entity_infos: Array = []  # Array[Dictionary] — from capture_entity_info()

# Variants — keyed by variant name.  Each value is {brush_infos, entity_infos}.
# "base" always mirrors the top-level brush_infos/entity_infos.
var variants: Dictionary = {}

# Tags for browser search/filtering (e.g. ["door", "architecture", "interior"])
var tags: PackedStringArray = []


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
## variant_name selects which variant to use ("base" or "" = default).
## Returns a dictionary: {"brush_ids": Array, "entity_count": int, "entity_names": Array, "entity_nodes": Array}.
func instantiate(
	brush_system, entity_system, root, placement_pos: Vector3, variant_name: String = ""
) -> Dictionary:
	var result := {
		"brush_ids": [] as Array,
		"entity_count": 0,
		"entity_names": [] as Array,
		"entity_nodes": [] as Array
	}

	# Resolve variant data
	var b_infos: Array = brush_infos
	var e_infos: Array = entity_infos
	if variant_name != "" and variant_name != "base" and variants.has(variant_name):
		var vdata: Dictionary = variants[variant_name]
		b_infos = vdata.get("brush_infos", [])
		e_infos = vdata.get("entity_infos", [])

	if b_infos.is_empty() and e_infos.is_empty():
		return result

	# Batch signals to avoid flooding
	if root.has_method("begin_signal_batch"):
		root.begin_signal_batch()

	# Name remapping for entity I/O connections
	var name_map: Dictionary = {}
	var new_brush_ids: Array = []

	# Instantiate brushes
	for info in b_infos:
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
	var new_entity_names: Array = []
	var new_entity_nodes: Array = []
	for info in e_infos:
		var placed_info: Dictionary = info.duplicate(true)
		if placed_info.has("transform"):
			var t: Transform3D = placed_info["transform"]
			t.origin += placement_pos
			placed_info["transform"] = t
		var old_name: String = str(placed_info.get("name", ""))
		var entity = entity_system.restore_entity_from_info(placed_info)
		if entity:
			result["entity_count"] += 1
			new_entity_names.append(entity.name)
			new_entity_nodes.append(entity)
			if old_name != "":
				name_map[old_name] = entity.name

	# Remap I/O connections
	if not name_map.is_empty() and entity_system.has_method("remap_io_connections"):
		for entity_info in e_infos:
			var ent_name: String = name_map.get(str(entity_info.get("name", "")), "")
			if ent_name == "":
				continue
			var entities = entity_system.find_entities_by_name(ent_name)
			if not entities.is_empty():
				entity_system.remap_io_connections(entities[0], name_map)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	result["brush_ids"] = new_brush_ids
	result["entity_names"] = new_entity_names
	result["entity_nodes"] = new_entity_nodes
	return result


# ---------------------------------------------------------------------------
# Variant API
# ---------------------------------------------------------------------------


## Get all variant names (always includes "base").
func get_variant_names() -> Array:
	var names: Array = ["base"]
	for key in variants:
		if key != "base":
			names.append(key)
	return names


## Check if a specific variant exists.
func has_variant(variant_name: String) -> bool:
	if variant_name == "base" or variant_name == "":
		return true
	return variants.has(variant_name)


## Get brush_infos and entity_infos for a variant.
func get_variant_data(variant_name: String) -> Dictionary:
	if variant_name == "base" or variant_name == "":
		return {"brush_infos": brush_infos, "entity_infos": entity_infos}
	if variants.has(variant_name):
		return variants[variant_name]
	return {"brush_infos": brush_infos, "entity_infos": entity_infos}


## Set/create a variant's data.
func set_variant_data(variant_name: String, p_brush_infos: Array, p_entity_infos: Array) -> void:
	if variant_name == "base" or variant_name == "":
		brush_infos = p_brush_infos
		entity_infos = p_entity_infos
		return
	variants[variant_name] = {
		"brush_infos": p_brush_infos,
		"entity_infos": p_entity_infos,
	}


## Remove a variant (cannot remove "base").
func remove_variant(variant_name: String) -> bool:
	if variant_name == "base" or variant_name == "":
		return false
	return variants.erase(variant_name)


## Add a variant by capturing from a selection (convenience wrapper).
func add_variant_from_selection(
	variant_name: String, brush_system, entity_system, brush_nodes: Array, entity_nodes: Array
) -> void:
	var captured = HFPrefab.capture_from_selection(
		brush_system, entity_system, brush_nodes, entity_nodes
	)
	set_variant_data(variant_name, captured.brush_infos, captured.entity_infos)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------


## Serialize to a dictionary suitable for JSON storage.
func to_dict() -> Dictionary:
	var data := {
		"prefab_name": prefab_name,
		"brush_infos": HFLevelIO.encode_variant(brush_infos),
		"entity_infos": HFLevelIO.encode_variant(entity_infos),
	}

	# Tags
	if not tags.is_empty():
		data["tags"] = Array(tags)

	# Variants (skip "base" — it's the top-level data)
	if not variants.is_empty():
		var v_data: Dictionary = {}
		for vname in variants:
			var vd: Dictionary = variants[vname]
			v_data[vname] = {
				"brush_infos": HFLevelIO.encode_variant(vd.get("brush_infos", [])),
				"entity_infos": HFLevelIO.encode_variant(vd.get("entity_infos", [])),
			}
		data["variants"] = v_data

	return data


## Deserialize from a dictionary.
static func from_dict(data: Dictionary) -> HFPrefab:
	var prefab = HFPrefab.new()
	prefab.prefab_name = str(data.get("prefab_name", ""))
	var raw_brushes = HFLevelIO.decode_variant(data.get("brush_infos", []))
	var raw_entities = HFLevelIO.decode_variant(data.get("entity_infos", []))
	prefab.brush_infos = raw_brushes if raw_brushes is Array else []
	prefab.entity_infos = raw_entities if raw_entities is Array else []

	# Tags
	var raw_tags = data.get("tags", [])
	if raw_tags is Array:
		for t in raw_tags:
			prefab.tags.append(str(t))

	# Variants
	var raw_variants = data.get("variants", {})
	if raw_variants is Dictionary:
		for vname in raw_variants:
			var vd = raw_variants[vname]
			if vd is Dictionary:
				var vb = HFLevelIO.decode_variant(vd.get("brush_infos", []))
				var ve = HFLevelIO.decode_variant(vd.get("entity_infos", []))
				prefab.variants[str(vname)] = {
					"brush_infos": vb if vb is Array else [],
					"entity_infos": ve if ve is Array else [],
				}

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
		HFLog.warn("HFPrefab: file not found: %s" % path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		HFLog.warn("HFPrefab: cannot open: %s" % path)
		return null
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		HFLog.warn("HFPrefab: invalid JSON in %s" % path)
		return null
	return from_dict(parsed)
