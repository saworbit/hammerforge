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

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFSettingsFile = preload("res://addons/hammerforge/hf_settings_file.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFDimensions = preload("res://addons/hammerforge/hf_dimensions.gd")

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
##
## A material with no file of its own - made in the session, or the placeholder a
## `.map` import mints for a texture the project does not have - has no path to
## record. Its slot holds `{"name": resource_name, "material": the material}`
## instead: the material itself while this editor has it, and the name, which is
## all a file can carry and is how a `.map` names a texture anyway (#1202).
var material_slots: Dictionary = {}

## The path-less materials of the last prefab written to each path in this editor
## session, with a hash of the text written, so that reading that same file back
## gets the materials themselves and not only their names. The clipboard is a
## file, and Copy in one level then Paste in another is what it is for. Weak, so a
## material lasts no longer than the level holding it; a file written since, by
## this editor or another one sharing `user://`, does not match the hash.
static var _session_writes: Dictionary = {}

## Where the selection was standing when it was captured.
##
## Everything else in here is relative to the centroid, so that a prefab can be
## placed anywhere. The clipboard is the one caller that wants to put it back
## exactly where it came from, which is what Ctrl+C then Ctrl+V means in every
## editor in this lineage (#703). A prefab placed from the library ignores it.
var source_centroid: Vector3 = Vector3.ZERO

## The groups the capture took whole, as `HFVisgroupSystem.whole_groups()` gives
## them: `{"name", "parent"}`, outer ones first (#1897). A placed copy makes a
## group of its own for each, nested as they were, and its members' infos name
## them by `group_id`. Only a group taken whole is named, so a prefab never puts
## a piece in a group of the level it is placed into.
var groups: Array = []

## The `level_uid` of the level the clipboard was copied from, or "". The
## clipboard alone keeps a group it took only part of on its members, and a
## paste back into that level puts them in it again, as Duplicate's copy is
## (#1897). Pasted anywhere else they are in no group but their own.
var source_level: String = ""


## Capture a prefab from the current selection.
## brush_nodes: Array of DraftBrush nodes
## entity_nodes: Array of DraftEntity nodes
## brush_system / entity_system: subsystem references (untyped to avoid circular preload)
## keep_outer_groups: the clipboard's capture, which also keeps the groups it took
## only part of, for a paste into the same level.
static func capture_from_selection(
	brush_system, entity_system, brush_nodes: Array, entity_nodes: Array, keep_outer_groups := false
) -> HFPrefab:
	var prefab = HFPrefab.new()
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return prefab

	var centroid := compute_selection_centroid(brush_nodes, entity_nodes)
	prefab.source_centroid = centroid
	var visgroup_system = _visgroups_of(brush_system)
	if visgroup_system:
		prefab.groups = visgroup_system.whole_groups(brush_nodes + entity_nodes)
	var whole: Dictionary = {}
	for record in prefab.groups:
		whole[str(record["name"])] = true
	if not keep_outer_groups:
		for record in prefab.groups:
			if not whole.has(str(record["parent"])):
				record["parent"] = ""

	# Each brush's id to what the prefab calls it, for a dimension on it (#2000).
	var pieces: Dictionary = {}
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
		pieces[str(info.get("brush_id", ""))] = HFDimensions.piece_ref(prefab.brush_infos.size())
		# Clear brush_id so new ones are assigned on instantiation
		info.erase("brush_id")
		# A group taken whole stays named, for the copy's own group to take its
		# place; one taken in part is the level's, kept by the clipboard only.
		_keep_group(info, whole, keep_outer_groups)
		# Visgroup membership is the level's. A visgroup is a list of
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
		_keep_group(info, whole, keep_outer_groups)
		info.erase("visgroups")
		# Which copy in which level this entity belonged to is the level's to know.
		# Carried in the prefab, every copy placed from it would share one uid.
		info.erase("prefab_entity_id")
		prefab.entity_infos.append(info)
	# A dimension's end on a brush it holds names that brush by its place in the
	# prefab, so a copy placed measures its own brushes (#2000).
	pieces.erase("")
	HFDimensions.follow_copies(prefab.entity_infos, pieces)

	prefab.material_slots = _record_material_slots(prefab.brush_infos, _palette_of(brush_system))
	return prefab


## Leave `info`'s group on it when the capture took that group whole, or when
## `keep_outer` keeps every group for a paste back into the same level.
static func _keep_group(info: Dictionary, whole: Dictionary, keep_outer: bool) -> void:
	if not keep_outer and not whole.has(str(info.get("group_id", ""))):
		info.erase("group_id")


## The level's groups, reached through whatever was handed in, or null.
static func _visgroups_of(brush_system) -> Object:
	if brush_system == null:
		return null
	var root = brush_system.get("root")
	if root == null:
		return null
	return root.get("visgroup_system")


## The level's material palette, reached through whatever was handed in, or null.
static func _palette_of(brush_system) -> Object:
	if brush_system == null:
		return null
	var root = brush_system.get("root")
	if root == null:
		return null
	return root.get("material_manager")


## What each slot the given faces reference points at, as `{slot: resource_path}`,
## or as a record of the material itself when it has no file of its own.
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
			if mat == null:
				continue
			if _has_own_file(mat):
				out[slot] = mat.resource_path
			else:
				out[slot] = {"name": mat.resource_name, "material": mat}
	return out


## Whether a material can be loaded again by its path. A material saved inside a
## scene has one, `level.tscn::StandardMaterial3D_x`, but it loads only while that
## scene is open, which is no better than having none.
static func _has_own_file(mat: Material) -> bool:
	return mat.resource_path != "" and not mat.resource_path.contains("::")


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
## `turn` turns it about its centre. Each piece goes to the copy's frame times its
## record, `Transform3D(turn, placement_pos) * record`, which is the frame
## `HFPrefabSystem._instance_frame()` reads back off the nodes, so a variant switch
## or a propagate rebuilds a turned copy where and as it stands.
## `group_suffix` goes on the names of the groups the copy makes: Paste's " copy",
## as Duplicate names them, and nothing for a prefab placed from the library.
## Returns a dictionary: {"brush_ids": Array, "entity_count": int, "entity_names": Array, "entity_nodes": Array}.
func instantiate(
	brush_system,
	entity_system,
	root,
	placement_pos: Vector3,
	variant_name: String = "",
	turn: Basis = Basis.IDENTITY,
	group_suffix: String = ""
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
	var g_records: Array = groups
	if variant_name != "" and variant_name != "base" and variants.has(variant_name):
		var vdata: Dictionary = variants[variant_name]
		b_infos = vdata.get("brush_infos", [])
		e_infos = vdata.get("entity_infos", [])
		g_records = vdata.get("groups", [])

	if b_infos.is_empty() and e_infos.is_empty():
		return result

	# Batch signals to avoid flooding
	if root.has_method("begin_signal_batch"):
		root.begin_signal_batch()

	var new_brush_ids: Array = []
	var new_brushes: Array = []

	# A face's material is a slot number into this level's palette, and the prefab
	# was captured against another one. Resolve what each recorded slot meant
	# against the destination, appending anything it does not already hold (#621).
	var slot_map: Dictionary = _resolve_material_slots(root)

	var placed_brushes: Array = []
	# What the prefab calls each brush to the id its copy is given (#2000).
	var copies: Dictionary = {}
	for i in b_infos.size():
		var info = b_infos[i]
		if not (info is Dictionary):
			continue
		var placed_info: Dictionary = info.duplicate(true)
		_remap_face_materials(placed_info, slot_map)
		if placed_info.has("transform"):
			placed_info["transform"] = _placed(placed_info["transform"], placement_pos, turn)
		# Assign new brush_id
		if brush_system.has_method("next_brush_id"):
			placed_info["brush_id"] = brush_system.next_brush_id()
			copies[HFDimensions.piece_ref(i)] = placed_info["brush_id"]
		placed_brushes.append(placed_info)
	var placed_entities: Array = []
	for info in e_infos:
		if not (info is Dictionary):
			continue
		var placed_info: Dictionary = info.duplicate(true)
		if placed_info.has("transform"):
			placed_info["transform"] = _placed(placed_info["transform"], placement_pos, turn)
		placed_entities.append(placed_info)
	HFDimensions.follow_copies(placed_entities, copies)
	# Each group it took whole is a group of its own, nested as it was (#1897). A
	# paste back into the level it was copied from keeps the groups it took only
	# part of, as Duplicate does.
	var visgroup_system = root.get("visgroup_system")
	var made_groups: Dictionary = {}
	if visgroup_system:
		var same_level := source_level != "" and source_level == str(root.get("level_uid"))
		made_groups = visgroup_system.place_copied_groups(
			g_records, group_suffix, same_level, placed_brushes, placed_entities
		)
		visgroup_system.add_groups(made_groups)
	else:
		for placed_info in placed_brushes + placed_entities:
			placed_info.erase("group_id")
	var addresses := HFBrushEntity.fresh_identities(placed_brushes, placed_entities, entity_system)

	# Instantiate brushes
	for placed_info in placed_brushes:
		var brush = brush_system.create_brush_from_info(placed_info)
		if brush:
			new_brush_ids.append(str(placed_info.get("brush_id", "")))
			new_brushes.append(brush)
			note_new_name(addresses, placed_info, brush)

	# Instantiate entities
	var new_entity_names: Array = []
	var new_entity_nodes: Array = []
	for placed_info in placed_entities:
		var entity = entity_system.restore_entity_from_info(placed_info)
		if entity:
			result["entity_count"] += 1
			new_entity_names.append(entity.name)
			new_entity_nodes.append(entity)
			note_new_name(addresses, placed_info, entity)

	# Remap I/O connections, through the nodes that were just created rather than by
	# looking their new names back up.
	#
	# The lookup resolves an authored `entity_name` as well as a node name, so an
	# entity of this same prefab whose authored name happens to match a later one's
	# generated node name is returned first: remapped twice, while the entity it
	# stood in for is never remapped at all and keeps its outputs aimed outside the
	# instance. Every restored node is here already, exactly once. Brushes too: a
	# button is a brush, and its wires were never remapped at all (#1159).
	if not addresses.is_empty() and entity_system.has_method("remap_io_connections"):
		for node in new_brushes + new_entity_nodes:
			entity_system.remap_io_connections(node, addresses)

	# A group none of whose pieces could be built is not left behind.
	if visgroup_system:
		visgroup_system.drop_empty_groups(made_groups)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	result["brush_ids"] = new_brush_ids
	result["entity_names"] = new_entity_names
	result["entity_nodes"] = new_entity_nodes
	return result


## Where a record lands in a copy placed at `at` and turned by `turn`. Unturned it
## is only moved, exactly as before turning was offered.
static func _placed(record: Transform3D, at: Vector3, turn: Basis) -> Transform3D:
	if turn == Basis.IDENTITY:
		var moved := record
		moved.origin += at
		return moved
	return Transform3D(turn, at) * record


## Record the node name a placed node came out with against the one its record
## held, since a wire can aim at a node by its node name. An authored name already
## mapped keeps its mapping.
static func note_new_name(addresses: Dictionary, info: Dictionary, node: Node) -> void:
	var old_name := str(info.get("name", ""))
	if old_name != "" and not addresses.has(old_name):
		addresses[old_name] = str(node.name)


## Map each recorded slot onto the slot that means the same thing in this level.
##
## A recorded path already in the destination palette maps to where it sits; one
## that is not is loaded and appended, the way `HFPrototypeTextures.load_all_into()`
## already adds keyed on `resource_path`. A path that will not load is left out,
## so the face keeps the number it had rather than being pointed somewhere wrong.
##
## A material with no file of its own maps to that same material, or to one of
## the same name, the way a `.map` import matches a texture name; failing both it
## is appended. Once this editor no longer has it, only the name can be appended,
## as the blank stand-in a `.map` import mints. With no name either, there is
## nothing to carry, and that slot is left out with a warning like a lost path.
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
	var name_only: Array = []
	var nameless := 0
	for slot in material_slots:
		var record = material_slots[slot]
		if record is Dictionary:
			var mat = record.get("material")
			var label := str(record.get("name", ""))
			var landed := _slot_holding(palette, mat, label)
			if landed < 0 and mat is Material:
				landed = palette.add_material(mat)
			elif landed < 0 and label != "":
				var stand_in := StandardMaterial3D.new()
				stand_in.resource_name = label
				landed = palette.add_material(stand_in)
				name_only.append(label)
			if landed < 0:
				nameless += 1
				continue
			out[int(slot)] = landed
			continue
		var path := str(record)
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
	if not name_only.is_empty():
		HFLog.warn(
			(
				(
					"HFPrefab: '%s' was built with %d material(s) that were never saved to a "
					+ "file and are no longer open in this editor, so each came as a blank "
					+ "stand-in carrying only its name: %s"
				)
				% [prefab_name, name_only.size(), ", ".join(name_only)]
			)
		)
	if nameless > 0:
		HFLog.warn(
			(
				(
					"HFPrefab: '%s' was built with %d material(s) that were never saved to a "
					+ "file, are no longer open in this editor and have no name to find them "
					+ "by, so those faces keep whatever the palette holds"
				)
				% [prefab_name, nameless]
			)
		)
	return out


## Where the palette already holds a material with no file of its own: that very
## material, or failing that one with its name. -1 when it holds neither.
static func _slot_holding(palette, mat, label: String) -> int:
	if mat is Material:
		var at: int = palette.materials.find(mat)
		if at >= 0:
			return at
	if label == "":
		return -1
	var names: Array = palette.get_material_names()
	for index in names.size():
		if palette.materials[index] != null and str(names[index]) == label:
			return index
	return -1


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


## Get brush_infos, entity_infos and groups for a variant.
func get_variant_data(variant_name: String) -> Dictionary:
	var base := {"brush_infos": brush_infos, "entity_infos": entity_infos, "groups": groups}
	if variant_name == "base" or variant_name == "":
		return base
	if variants.has(variant_name):
		return variants[variant_name]
	return base


## Set/create a variant's data. `p_groups` as `groups` holds them (#1897).
func set_variant_data(
	variant_name: String, p_brush_infos: Array, p_entity_infos: Array, p_groups: Array = []
) -> void:
	if variant_name == "base" or variant_name == "":
		brush_infos = p_brush_infos
		entity_infos = p_entity_infos
		groups = p_groups
		return
	variants[variant_name] = {
		"brush_infos": p_brush_infos,
		"entity_infos": p_entity_infos,
		"groups": p_groups,
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
	set_variant_data(variant_name, captured.brush_infos, captured.entity_infos, captured.groups)
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
	# a number on both sides of the file. A material with no file of its own goes
	# in by name, which an older build reads past.
	if not material_slots.is_empty():
		var slot_records: Array = []
		for slot in material_slots:
			var record = material_slots[slot]
			if record is Dictionary:
				slot_records.append({"slot": int(slot), "name": str(record.get("name", ""))})
			else:
				slot_records.append({"slot": int(slot), "path": str(record)})
		slot_records.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
		data["materials"] = slot_records

	# Tags
	if not tags.is_empty():
		data["tags"] = Array(tags)

	# The groups it took whole (#1897), and for the clipboard the level it came
	# from. Only when there are any, as above.
	if not groups.is_empty():
		data["groups"] = groups.duplicate(true)
	if source_level != "":
		data["source_level"] = source_level

	# Variants (skip "base" — it's the top-level data)
	if not variants.is_empty():
		var v_data: Dictionary = {}
		for vname in variants:
			var vd: Dictionary = variants[vname]
			v_data[vname] = {
				"brush_infos": HFLevelIO.encode_variant(vd.get("brush_infos", [])),
				"entity_infos": HFLevelIO.encode_variant(vd.get("entity_infos", [])),
			}
			if not (vd.get("groups", []) as Array).is_empty():
				v_data[vname]["groups"] = (vd["groups"] as Array).duplicate(true)
		data["variants"] = v_data

	return data


## The group records in `raw`, as `groups` holds them: a hand edit or a merge
## that left something else there is read past.
static func _group_records(raw) -> Array:
	var out: Array = []
	for record in _dictionary_entries(raw, "groups"):
		var group_name := str(record.get("name", "")).strip_edges()
		if group_name != "":
			out.append({"name": group_name, "parent": str(record.get("parent", ""))})
	return out


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
		if slot < 0:
			continue
		if path != "":
			prefab.material_slots[slot] = path
		elif record.get("name") is String:
			prefab.material_slots[slot] = {"name": record["name"], "material": null}

	# Tags
	var raw_tags = data.get("tags", [])
	if raw_tags is Array:
		for t in raw_tags:
			prefab.tags.append(str(t))

	# A file written before these keys existed has no groups, as it had none.
	prefab.groups = _group_records(data.get("groups", []))
	prefab.source_level = str(data.get("source_level", ""))

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
					"groups": _group_records(vd.get("groups", [])),
				}

	return prefab


## Save prefab to a .hfprefab JSON file, whole: a save cut short leaves the old
## file, as the settings files do, not an empty one every linked copy reads (#1758).
func save_to_file(path: String) -> int:
	var json_text := JSON.stringify(to_dict(), "\t")
	var err := HFSettingsFile.write_text(path, json_text)
	if err == OK:
		_remember_session_materials(path, json_text)
	return err


func _remember_session_materials(path: String, text: String) -> void:
	var held: Dictionary = {}
	for slot in material_slots:
		var record = material_slots[slot]
		if record is Dictionary and record.get("material") is Material:
			held[int(slot)] = weakref(record["material"])
	if held.is_empty():
		_session_writes.erase(path)
	else:
		_session_writes[path] = {"hash": text.sha256_text(), "materials": held}


## Put back the materials themselves, when this editor wrote exactly this text.
func _take_back_session_materials(path: String, text: String) -> void:
	var written = _session_writes.get(path)
	if not (written is Dictionary) or written["hash"] != text.sha256_text():
		return
	for slot in written["materials"]:
		var mat = (written["materials"][slot] as WeakRef).get_ref()
		var record = material_slots.get(slot)
		if record is Dictionary and mat is Material:
			record["material"] = mat


## Load prefab from a .hfprefab JSON file, or from the copy a save cut short left
## beside it when the file itself is gone.
static func load_from_file(path: String) -> HFPrefab:
	var source := HFSettingsFile.readable_path(path)
	if source == "":
		HFLog.warn("HFPrefab: file not found: %s" % path)
		return null
	var file = FileAccess.open(source, FileAccess.READ)
	if not file:
		HFLog.warn("HFPrefab: cannot open: %s" % path)
		return null
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		HFLog.warn("HFPrefab: invalid JSON in %s" % path)
		return null
	var prefab := from_dict(parsed)
	prefab._take_back_session_materials(path, text)
	return prefab
