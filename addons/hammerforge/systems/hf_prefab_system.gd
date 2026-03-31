@tool
extends RefCounted
class_name HFPrefabSystem
## Subsystem for managing prefab instances, variants, live-linking,
## and propagation.  Tracks which placed brushes/entities came from
## which .hfprefab file so we can re-sync them later.
##
## Entity membership is tracked by a stable ID stored in node meta
## ("hf_prefab_entity_id") — NOT by scene name, which can collide.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")

var root: Node3D  # LevelRoot — untyped to avoid circular preload

# --- Instance registry ---
# key = instance_id (String), value = PrefabInstanceRecord
var _instances: Dictionary = {}
var _next_instance_id: int = 1
var _next_entity_uid: int = 1


class PrefabInstanceRecord:
	var instance_id: String = ""
	var source_path: String = ""  # res://prefabs/foo.hfprefab
	var variant_name: String = "base"  # active variant
	var brush_ids: Array = []  # String brush IDs belonging to this instance
	var entity_uids: Array = []  # stable IDs ("pent_N") belonging to this instance
	var overrides: Dictionary = {}  # field_path → value  (per-instance tweaks)
	var linked: bool = false  # if true, propagation applies


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Entity UID helpers — stable, unique, independent of scene name
# ---------------------------------------------------------------------------


func _assign_entity_uid() -> String:
	var uid := "pent_%d" % _next_entity_uid
	_next_entity_uid += 1
	return uid


func _find_entity_by_uid(uid: String) -> Node3D:
	if uid == "":
		return null
	if root.entities_node:
		for child in root.entities_node.get_children():
			if str(child.get_meta("hf_prefab_entity_id", "")) == uid:
				return child
	# Also check brush entities
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if str(child.get_meta("hf_prefab_entity_id", "")) == uid:
				return child
	return null


# ---------------------------------------------------------------------------
# Instance tracking
# ---------------------------------------------------------------------------


## Register a newly placed prefab instance.  Returns the instance_id.
## entity_nodes: Array of actual entity Node3D references (not names).
func register_instance(
	source_path: String,
	brush_ids: Array,
	entity_nodes: Array,
	linked: bool = false,
	variant_name: String = "base"
) -> String:
	var iid := "pfx_%d" % _next_instance_id
	_next_instance_id += 1
	var rec := PrefabInstanceRecord.new()
	rec.instance_id = iid
	rec.source_path = source_path
	rec.variant_name = variant_name
	rec.brush_ids = brush_ids.duplicate()
	rec.linked = linked

	# Assign stable UIDs to each entity node
	var uids: Array = []
	for node in entity_nodes:
		if node is Node3D:
			var uid := _assign_entity_uid()
			node.set_meta("hf_prefab_entity_id", uid)
			uids.append(uid)
	rec.entity_uids = uids

	_instances[iid] = rec
	# Tag every brush/entity node with the instance_id so we can find them
	_tag_nodes(rec)
	return iid


## Remove a registered instance (e.g. on delete/undo).
func unregister_instance(instance_id: String) -> void:
	if _instances.has(instance_id):
		var rec: PrefabInstanceRecord = _instances[instance_id]
		_untag_nodes(rec)
		_instances.erase(instance_id)


## Get instance record by id.
func get_instance(instance_id: String) -> PrefabInstanceRecord:
	return _instances.get(instance_id, null)


## Find the instance record for a given node (brush or entity).
func get_instance_for_node(node: Node3D) -> PrefabInstanceRecord:
	var iid: String = str(node.get_meta("hf_prefab_instance", ""))
	if iid == "" or not _instances.has(iid):
		return null
	return _instances[iid]


## Return all instance records whose source_path matches.
func get_instances_for_source(source_path: String) -> Array:
	var result: Array = []
	for iid in _instances:
		var rec: PrefabInstanceRecord = _instances[iid]
		if rec.source_path == source_path:
			result.append(rec)
	return result


## Get all registered instances.
func get_all_instances() -> Dictionary:
	return _instances


func _tag_nodes(rec: PrefabInstanceRecord) -> void:
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			brush.set_meta("hf_prefab_instance", rec.instance_id)
			brush.set_meta("hf_prefab_source", rec.source_path)
			brush.set_meta("hf_prefab_variant", rec.variant_name)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			ent.set_meta("hf_prefab_instance", rec.instance_id)
			ent.set_meta("hf_prefab_source", rec.source_path)
			ent.set_meta("hf_prefab_variant", rec.variant_name)


func _untag_nodes(rec: PrefabInstanceRecord) -> void:
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			brush.remove_meta("hf_prefab_instance")
			brush.remove_meta("hf_prefab_source")
			brush.remove_meta("hf_prefab_variant")
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			ent.remove_meta("hf_prefab_instance")
			ent.remove_meta("hf_prefab_source")
			ent.remove_meta("hf_prefab_variant")
			ent.remove_meta("hf_prefab_entity_id")


func _find_brush_by_id(brush_id: String) -> Node3D:
	if not root.draft_brushes_node:
		return null
	for child in root.draft_brushes_node.get_children():
		if str(child.get_meta("brush_id", "")) == brush_id:
			return child
	return null


# ---------------------------------------------------------------------------
# Variant cycling
# ---------------------------------------------------------------------------


## Cycle to the next variant on a prefab instance.
## Returns the new variant name, or "" if not applicable.
func cycle_variant(instance_id: String) -> String:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return ""
	var prefab = HFPrefabType.load_from_file(rec.source_path)
	if not prefab:
		return ""
	var variant_names: Array = prefab.get_variant_names()
	if variant_names.size() <= 1:
		return rec.variant_name
	var idx := variant_names.find(rec.variant_name)
	idx = (idx + 1) % variant_names.size()
	var new_variant: String = variant_names[idx]
	_apply_variant(rec, prefab, new_variant)
	return new_variant


## Apply a specific variant to an instance.
func set_variant(instance_id: String, variant_name: String) -> bool:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return false
	var prefab = HFPrefabType.load_from_file(rec.source_path)
	if not prefab:
		return false
	if not prefab.has_variant(variant_name):
		return false
	_apply_variant(rec, prefab, variant_name)
	return true


func _apply_variant(rec: PrefabInstanceRecord, prefab: HFPrefabType, variant_name: String) -> void:
	# Compute centroid of current instance to keep placement stable
	var centroid := _compute_instance_centroid(rec)

	# Remove existing brushes/entities for this instance
	_remove_instance_nodes(rec)

	# Instantiate the new variant at the same centroid
	var data: Dictionary = prefab.get_variant_data(variant_name)
	var brush_infos: Array = data.get("brush_infos", [])
	var entity_infos: Array = data.get("entity_infos", [])

	if root.has_method("begin_signal_batch"):
		root.begin_signal_batch()

	var new_brush_ids: Array = []
	var name_map: Dictionary = {}

	for info in brush_infos:
		var placed: Dictionary = info.duplicate(true)
		if placed.has("transform"):
			var t: Transform3D = placed["transform"]
			t.origin += centroid
			placed["transform"] = t
		if root.brush_system.has_method("next_brush_id"):
			placed["brush_id"] = root.brush_system.next_brush_id()
		var brush = root.brush_system.create_brush_from_info(placed)
		if brush:
			new_brush_ids.append(str(placed.get("brush_id", "")))

	var new_entity_uids: Array = []
	for info in entity_infos:
		var placed: Dictionary = info.duplicate(true)
		if placed.has("transform"):
			var t: Transform3D = placed["transform"]
			t.origin += centroid
			placed["transform"] = t
		var old_name: String = str(placed.get("name", ""))
		var entity = root.entity_system.restore_entity_from_info(placed)
		if entity:
			var uid := _assign_entity_uid()
			entity.set_meta("hf_prefab_entity_id", uid)
			new_entity_uids.append(uid)
			if old_name != "":
				name_map[old_name] = entity.name

	# Remap I/O (still uses scene names for entity I/O target resolution)
	if not name_map.is_empty():
		for uid in new_entity_uids:
			var ent = _find_entity_by_uid(uid)
			if ent:
				root.entity_system.remap_io_connections(ent, name_map)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	# Update record
	rec.brush_ids = new_brush_ids
	rec.entity_uids = new_entity_uids
	rec.variant_name = variant_name
	_tag_nodes(rec)


func _compute_instance_centroid(rec: PrefabInstanceRecord) -> Vector3:
	var positions: Array = []
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			positions.append(brush.global_position)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			positions.append(ent.global_position)
	if positions.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for p in positions:
		c += p
	return c / float(positions.size())


func _remove_instance_nodes(rec: PrefabInstanceRecord) -> void:
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			brush.get_parent().remove_child(brush)
			brush.queue_free()
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			ent.get_parent().remove_child(ent)
			ent.queue_free()


# ---------------------------------------------------------------------------
# Override tracking
# ---------------------------------------------------------------------------


## Record an override on a prefab instance.
func set_override(instance_id: String, field_path: String, value: Variant) -> void:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return
	rec.overrides[field_path] = value


## Remove an override.
func clear_override(instance_id: String, field_path: String) -> void:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return
	rec.overrides.erase(field_path)


## Get all overrides for display.
func get_overrides(instance_id: String) -> Dictionary:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return {}
	return rec.overrides.duplicate()


# ---------------------------------------------------------------------------
# Live-linked propagation
# ---------------------------------------------------------------------------


## Propagate changes from the source .hfprefab to all linked instances.
## Returns the number of instances updated.
func propagate_from_source(source_path: String) -> int:
	var prefab = HFPrefabType.load_from_file(source_path)
	if not prefab:
		return 0
	var instances = get_instances_for_source(source_path)
	var count := 0
	for rec in instances:
		if not rec.linked:
			continue
		_apply_variant(rec, prefab, rec.variant_name)
		# Re-apply overrides on top
		_reapply_overrides(rec)
		count += 1
	return count


## Re-capture the current state of an instance back to the source prefab.
## This is the "edit one instance → push to source" workflow.
func push_instance_to_source(instance_id: String) -> bool:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec or rec.source_path == "":
		return false
	var prefab = HFPrefabType.load_from_file(rec.source_path)
	if not prefab:
		prefab = HFPrefabType.new()
		prefab.prefab_name = rec.source_path.get_file().get_basename()

	# Gather current nodes
	var brush_nodes: Array = []
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			brush_nodes.append(brush)
	var entity_nodes: Array = []
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			entity_nodes.append(ent)

	# Re-capture as the current variant
	var captured = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, brush_nodes, entity_nodes
	)
	prefab.set_variant_data(rec.variant_name, captured.brush_infos, captured.entity_infos)

	var err := prefab.save_to_file(rec.source_path)
	return err == OK


## Compute a diff between a prefab instance and its source.
## Returns an Array of {field, source_value, instance_value} dictionaries.
func compute_instance_diff(instance_id: String) -> Array:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if not rec:
		return []
	var prefab = HFPrefabType.load_from_file(rec.source_path)
	if not prefab:
		return []
	var diff: Array = []
	var data: Dictionary = prefab.get_variant_data(rec.variant_name)
	var source_brushes: Array = data.get("brush_infos", [])
	var source_entities: Array = data.get("entity_infos", [])

	# Compare brush counts
	if source_brushes.size() != rec.brush_ids.size():
		(
			diff
			. append(
				{
					"field": "brush_count",
					"source_value": source_brushes.size(),
					"instance_value": rec.brush_ids.size(),
				}
			)
		)

	# Compare entity counts
	if source_entities.size() != rec.entity_uids.size():
		(
			diff
			. append(
				{
					"field": "entity_count",
					"source_value": source_entities.size(),
					"instance_value": rec.entity_uids.size(),
				}
			)
		)

	# Per-field overrides
	for field_path in rec.overrides:
		(
			diff
			. append(
				{
					"field": field_path,
					"source_value": "(original)",
					"instance_value": rec.overrides[field_path],
				}
			)
		)

	return diff


func _reapply_overrides(rec: PrefabInstanceRecord) -> void:
	# Overrides are stored as field_path → value.
	# field_path format: "brush/<index>/size", "entity/<index>/transform", etc.
	for field_path in rec.overrides:
		var parts: PackedStringArray = field_path.split("/")
		if parts.size() < 3:
			continue
		var target_type: String = parts[0]
		var idx_str: String = parts[1]
		if not idx_str.is_valid_int():
			continue
		var idx: int = idx_str.to_int()
		var prop: String = parts[2]

		if target_type == "brush" and idx < rec.brush_ids.size():
			var brush = _find_brush_by_id(rec.brush_ids[idx])
			if brush and prop == "size":
				var size_val = rec.overrides[field_path]
				if size_val is Vector3:
					brush.set_meta("brush_size", size_val)
		elif target_type == "entity" and idx < rec.entity_uids.size():
			var ent = _find_entity_by_uid(rec.entity_uids[idx])
			if ent and prop == "transform" and rec.overrides[field_path] is Transform3D:
				ent.global_transform = rec.overrides[field_path]


# ---------------------------------------------------------------------------
# Quick group-to-prefab
# ---------------------------------------------------------------------------


## Suggest a name for a new prefab based on the contents.
func suggest_prefab_name(brush_nodes: Array, entity_nodes: Array) -> String:
	if not brush_nodes.is_empty() and not entity_nodes.is_empty():
		return "group_%d_brushes_%d_entities" % [brush_nodes.size(), entity_nodes.size()]
	if not brush_nodes.is_empty():
		if brush_nodes.size() == 1:
			var shape: int = brush_nodes[0].get_meta("brush_shape", 0)
			return _shape_name(shape)
		return "%d_brush_group" % brush_nodes.size()
	if not entity_nodes.is_empty():
		if entity_nodes.size() == 1:
			var etype: String = str(entity_nodes[0].get("entity_type", "entity"))
			return etype.to_snake_case() if etype != "" else "entity"
		return "%d_entity_group" % entity_nodes.size()
	return "untitled_prefab"


func _shape_name(shape: int) -> String:
	# Maps to LevelRoot.BrushShape enum
	match shape:
		0:
			return "box"
		1:
			return "cylinder"
		2:
			return "sphere"
		3:
			return "cone"
		4:
			return "wedge"
		5:
			return "pyramid"
		_:
			return "brush"


## Quick-save selection as prefab. Returns the saved path or "".
func quick_save_prefab(
	brush_nodes: Array, entity_nodes: Array, prefab_name: String = "", linked: bool = false
) -> String:
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return ""
	if prefab_name == "":
		prefab_name = suggest_prefab_name(brush_nodes, entity_nodes)

	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, brush_nodes, entity_nodes
	)
	prefab.prefab_name = prefab_name

	var dir_path := "res://prefabs"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file_name := prefab_name.to_snake_case() + ".hfprefab"
	var path := dir_path.path_join(file_name)
	var err := prefab.save_to_file(path)
	if err != OK:
		return ""

	# Register as a linked instance if requested
	if linked:
		var brush_ids: Array = []
		for b in brush_nodes:
			brush_ids.append(str(b.get_meta("brush_id", "")))
		register_instance(path, brush_ids, entity_nodes, true)

	return path


# ---------------------------------------------------------------------------
# Serialization (for save/load)
# ---------------------------------------------------------------------------


func capture_state() -> Dictionary:
	var data: Dictionary = {}
	data["next_instance_id"] = _next_instance_id
	data["next_entity_uid"] = _next_entity_uid
	var instances_data: Array = []
	for iid in _instances:
		var rec: PrefabInstanceRecord = _instances[iid]
		(
			instances_data
			. append(
				{
					"instance_id": rec.instance_id,
					"source_path": rec.source_path,
					"variant_name": rec.variant_name,
					"brush_ids": rec.brush_ids.duplicate(),
					"entity_uids": rec.entity_uids.duplicate(),
					"overrides": rec.overrides.duplicate(true),
					"linked": rec.linked,
				}
			)
		)
	data["instances"] = instances_data
	return data


func restore_state(data: Dictionary) -> void:
	_instances.clear()
	_next_instance_id = data.get("next_instance_id", 1)
	_next_entity_uid = data.get("next_entity_uid", 1)
	var instances_data: Array = data.get("instances", [])
	for entry in instances_data:
		if not entry is Dictionary:
			continue
		var rec := PrefabInstanceRecord.new()
		rec.instance_id = str(entry.get("instance_id", ""))
		rec.source_path = str(entry.get("source_path", ""))
		rec.variant_name = str(entry.get("variant_name", "base"))
		rec.brush_ids = entry.get("brush_ids", [])
		rec.entity_uids = entry.get("entity_uids", [])
		rec.overrides = entry.get("overrides", {})
		rec.linked = bool(entry.get("linked", false))
		if rec.instance_id != "":
			_instances[rec.instance_id] = rec
			_tag_nodes(rec)
