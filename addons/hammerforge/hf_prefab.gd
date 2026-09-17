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

## What each palette slot the prefab's faces reference meant, as
## `{slot: resource_path}`.
##
## A face's material is a slot number into the *level's* palette, so a prefab
## carrying only the numbers re-textured itself in every other level - silently,
## because within one level the palette is the same one (#621). Recorded on
## capture and remapped on placement. Merged across the base and every variant,
## since they all index the same palette.
var material_slots: Dictionary = {}

## Where the selection was standing when it was captured.
##
## Everything else in here is relative to the centroid, so that a prefab can be
## placed anywhere. The clipboard is the one caller that wants to put it back
## exactly where it came from, which is what Ctrl+C then Ctrl+V means in every
## editor in this lineage (#703). A prefab placed from the library ignores it.
var source_centroid: Vector3 = Vector3.ZERO


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

	var centroid := compute_selection_centroid(brush_nodes, entity_nodes)
	prefab.source_centroid = centroid

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
		# And visgroup membership, for the same reason. A visgroup is a list of
		# names registered per level, so a prefab placed into a level that has
		# never had "Lighting" put brushes in a group with no row in the visgroup
		# panel: it cannot be shown, hidden, renamed or deleted, it is skipped by
		# refresh_visibility(), the partitioned bake still reads it off the node,
		# and it is saved. A prefab library shared between levels is the normal
		# way to use prefabs, so this was the common case.
		info.erase("visgroups")
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
		# The same two, for the same reasons as the brush half above.
		info.erase("group_id")
		info.erase("visgroups")
		prefab.entity_infos.append(info)

	prefab.material_slots = _record_material_slots(prefab.brush_infos, _palette_of(brush_system))
	return prefab


## The level's material palette, reached through whatever was handed in, or null.
static func _palette_of(brush_system) -> Object:
	if brush_system == null:
		return null
	var root = brush_system.get("root")
	if root == null:
		return null
	return root.get("material_manager")


## What each slot the given faces reference points at, as `{slot: resource_path}`.
##
## A material with no `resource_path` cannot be recorded this way - that is #617,
## and the same fix covers both - so its slot is left out and the face keeps
## whatever the destination palette holds there, which is today's behaviour.
static func _record_material_slots(infos: Array, palette) -> Dictionary:
	var out: Dictionary = {}
	if palette == null:
		return out
	for info in infos:
		if not (info is Dictionary):
			continue
		for face in info.get("faces", []):
			if not (face is Dictionary):
				continue
			var slot := int(face.get("material_idx", -1))
			if slot < 0 or out.has(slot):
				continue
			var mat = palette.get_material(slot)
			if mat == null or mat.resource_path == "":
				continue
			out[slot] = mat.resource_path
	return out


## Combined visual AABB center of the selection. Falls back to origin mean
## when no mesh bounds are available.
static func compute_selection_centroid(brush_nodes: Array, entity_nodes: Array) -> Vector3:
	var merged := AABB()
	var has_aabb := false
	for node in brush_nodes + entity_nodes:
		if not (node is Node3D):
			continue
		var aabb := _visual_aabb(node)
		if aabb.size == Vector3.ZERO and aabb.position == Vector3.ZERO:
			aabb = AABB((node as Node3D).global_position, Vector3.ZERO)
		if not has_aabb:
			merged = aabb
			has_aabb = true
		else:
			merged = merged.merge(aabb)
	if has_aabb:
		return merged.get_center()
	return Vector3.ZERO


static func _visual_aabb(node: Node3D) -> AABB:
	if node == null or not is_instance_valid(node):
		return AABB()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			return mi.global_transform * mi.get_aabb()
	if "mesh_instance" in node:
		var nested = node.get("mesh_instance")
		if nested is MeshInstance3D and nested.mesh:
			return nested.global_transform * nested.get_aabb()
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			return child.global_transform * (child as MeshInstance3D).get_aabb()
	return AABB()


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

	# A face's material is a slot number into this level's palette, and the prefab
	# was captured against another one. Resolve what each recorded slot meant
	# against the destination, appending anything it does not already hold (#621).
	var slot_map: Dictionary = _resolve_material_slots(root)

	# Instantiate brushes
	for info in b_infos:
		if not (info is Dictionary):
			continue
		var placed_info: Dictionary = info.duplicate(true)
		_remap_face_materials(placed_info, slot_map)
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
		if not (info is Dictionary):
			continue
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

	# Remap I/O connections, through the nodes that were just created rather than by
	# looking their new names back up.
	#
	# The lookup resolves an authored `entity_name` as well as a node name, so an
	# entity of this same prefab whose authored name happens to match a later one's
	# generated node name is returned first: remapped twice, while the entity it
	# stood in for is never remapped at all and keeps its outputs aimed outside the
	# instance. Every restored node is here already, exactly once.
	if not name_map.is_empty() and entity_system.has_method("remap_io_connections"):
		for entity in new_entity_nodes:
			entity_system.remap_io_connections(entity, name_map)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	result["brush_ids"] = new_brush_ids
	result["entity_names"] = new_entity_names
	result["entity_nodes"] = new_entity_nodes
	return result


## Map each recorded slot onto the slot that means the same thing in this level.
##
## A recorded path already in the destination palette maps to where it sits; one
## that is not is loaded and appended, the way `HFPrototypeTextures.load_all_into()`
## already adds keyed on `resource_path`. A path that will not load is left out,
## so the face keeps the number it had rather than being pointed somewhere wrong.
func _resolve_material_slots(root) -> Dictionary:
	var out: Dictionary = {}
	if material_slots.is_empty() or root == null:
		return out
	var palette = root.get("material_manager")
	if palette == null:
		return out
	var by_path: Dictionary = {}
	for index in palette.materials.size():
		var held = palette.materials[index]
		if held != null and held.resource_path != "" and not by_path.has(held.resource_path):
			by_path[held.resource_path] = index
	var missing: Array = []
	for slot in material_slots:
		var path := str(material_slots[slot])
		if path == "":
			continue
		if by_path.has(path):
			out[int(slot)] = int(by_path[path])
			continue
		if not ResourceLoader.exists(path):
			missing.append(path)
			continue
		var loaded = ResourceLoader.load(path)
		if loaded is Material:
			var added: int = palette.add_material(loaded)
			by_path[path] = added
			out[int(slot)] = added
		else:
			missing.append(path)
	if not missing.is_empty():
		HFLog.warn(
			(
				(
					"HFPrefab: '%s' was built with %d material(s) this project cannot load, "
					+ "so those faces keep whatever the palette holds: %s"
				)
				% [prefab_name, missing.size(), ", ".join(missing)]
			)
		)
	return out


## Point each face at the slot its material landed in.
static func _remap_face_materials(info: Dictionary, slot_map: Dictionary) -> void:
	if slot_map.is_empty():
		return
	for face in info.get("faces", []):
		if not (face is Dictionary):
			continue
		var slot := int(face.get("material_idx", -1))
		if slot_map.has(slot):
			face["material_idx"] = int(slot_map[slot])


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
	# Every variant indexes the same palette, so one record covers them all.
	for slot in captured.material_slots:
		if not material_slots.has(slot):
			material_slots[slot] = captured.material_slots[slot]


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

	# Only when there is one to record, so a prefab written by an older build and
	# one captured from nothing read back the same way.
	if source_centroid != Vector3.ZERO:
		data["source_centroid"] = HFLevelIO.encode_variant(source_centroid)

	# What each referenced palette slot meant. Written as records rather than a
	# dictionary keyed by number, because JSON has only String keys and a slot is
	# a number on both sides of the file.
	if not material_slots.is_empty():
		var slot_records: Array = []
		for slot in material_slots:
			slot_records.append({"slot": int(slot), "path": str(material_slots[slot])})
		slot_records.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
		data["materials"] = slot_records

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
## The Dictionary entries of a decoded list, and a warning about what was dropped.
##
## `.hfprefab` files are JSON in the project, so a merge conflict, a truncated
## write or an older build with a different shape all produce one with an entry
## that is not a Dictionary. `instantiate()` called `info.duplicate(true)` on it,
## which is a runtime error, and GDScript has no exception handling — so the
## function unwound past its own `end_signal_batch()` and left the level's signal
## batch open for the rest of the editor session, with the dock silently frozen.
static func _dictionary_entries(raw, what: String) -> Array:
	if not (raw is Array):
		if raw != null:
			HFLog.warn("HFPrefab: '%s' is not a list, ignoring it" % what)
		return []
	var out: Array = []
	var dropped := 0
	for entry in raw:
		if entry is Dictionary:
			out.append(entry)
		else:
			dropped += 1
	if dropped > 0:
		HFLog.warn("HFPrefab: dropped %d '%s' entries that were not objects" % [dropped, what])
	return out


static func from_dict(data: Dictionary) -> HFPrefab:
	var prefab = HFPrefab.new()
	prefab.prefab_name = str(data.get("prefab_name", ""))
	var raw_brushes = HFLevelIO.decode_variant(data.get("brush_infos", []))
	var raw_entities = HFLevelIO.decode_variant(data.get("entity_infos", []))
	prefab.brush_infos = _dictionary_entries(raw_brushes, "brush_infos")
	prefab.entity_infos = _dictionary_entries(raw_entities, "entity_infos")
	# A file written before this key existed, or one whose value is not a vector
	# because it was hand edited, places at the origin the way it always did.
	var centroid = HFLevelIO.decode_variant(data.get("source_centroid", null))
	if centroid is Vector3 and (centroid as Vector3).is_finite():
		prefab.source_centroid = centroid
	# A prefab written before this key existed has none, and nothing is remapped,
	# which is exactly what it did before.
	for record in _dictionary_entries(data.get("materials", []), "materials"):
		var path := str(record.get("path", "")).strip_edges()
		var slot := int(record.get("slot", -1))
		if slot >= 0 and path != "":
			prefab.material_slots[slot] = path

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
					"brush_infos": _dictionary_entries(vb, "variant brush_infos"),
					"entity_infos": _dictionary_entries(ve, "variant entity_infos"),
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
