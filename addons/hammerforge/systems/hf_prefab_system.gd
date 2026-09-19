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

## Where prefabs are saved and where the library lists from.
##
## One constant, because it used to be three literals - here, `dock.gd` and
## `HFPrefabLibrary` - with a `set_prefab_dir()` that could only move one of
## them. A setter that changes one of three copies is worse than no setter: the
## library would have listed a different folder from the one Save writes into.
const PREFAB_DIR := "res://prefabs"

## Where a cut or copied selection waits.
##
## A clipboard is a prefab without a name: the same capture, the same file
## format, the same placement. What differs is its lifetime, and that a mapper
## uses it forty times an evening rather than saving it once (#703).
##
## In `user://` rather than in memory, so it survives a restart and so two
## editors open on two projects can pass geometry between them. Outside
## `res://` because it is not part of any project, and a clipboard buffer
## committed to a repository would be somebody's stray corridor.
const CLIPBOARD_PATH := "user://hammerforge_clipboard.hfprefab"


class PrefabInstanceRecord:
	var instance_id: String = ""
	var source_path: String = ""  # PREFAB_DIR/foo.hfprefab
	var variant_name: String = "base"  # active variant
	var brush_ids: Array = []  # String brush IDs belonging to this instance
	var entity_uids: Array = []  # stable IDs ("pent_N") belonging to this instance
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
	if root.entity_system and root.entity_system.has_method("find_entity_by_prefab_uid"):
		return root.entity_system.find_entity_by_prefab_uid(uid)
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

	# Overwriting silently is what turns a stale counter into orphaned nodes, so
	# say so rather than replace. The counter is derived from the restored records
	# now, which should mean this never fires.
	if _instances.has(iid):
		push_warning("HFPrefabSystem: instance id '%s' is already registered" % iid)
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
	if root.brush_system and root.brush_system.has_method("find_managed_brush_by_id"):
		return root.brush_system.find_managed_brush_by_id(brush_id) as Node3D
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
	# Where the instance is, measured the way the file format measures it.
	#
	# A prefab's brush transforms are stored relative to the merged visual AABB
	# centre of the selection it was captured from, and `instantiate()` adds the
	# placement back onto that. This used to take the mean of the node origins
	# instead, which is a different point for any prefab that is not symmetric
	# about it - so every variant cycle walked the instance by the difference,
	# and recomputed it against the new nodes, so cycling back did not bring it
	# home.
	var centroid := _instance_centroid(rec)

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


## The instance's current nodes measured through the one definition the prefab
## format is written against.
func _instance_centroid(rec: PrefabInstanceRecord) -> Vector3:
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
	return HFPrefabType.compute_selection_centroid(brush_nodes, entity_nodes)


func _remove_instance_nodes(rec: PrefabInstanceRecord) -> void:
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			var parent: Node = brush.get_parent()
			if parent:
				parent.remove_child(brush)
			brush.queue_free()
		else:
			push_warning(
				(
					"Prefab instance '%s': brush '%s' was not found during removal."
					% [rec.instance_id, bid]
				)
			)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			var parent: Node = ent.get_parent()
			if parent:
				parent.remove_child(ent)
			ent.queue_free()
		else:
			push_warning(
				(
					"Prefab instance '%s': entity '%s' was not found during removal."
					% [rec.instance_id, uid]
				)
			)


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
		else:
			push_warning(
				(
					"Prefab instance '%s': brush '%s' was not found while saving the source."
					% [instance_id, bid]
				)
			)
	var entity_nodes: Array = []
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			entity_nodes.append(ent)
		else:
			push_warning(
				(
					"Prefab instance '%s': entity '%s' was not found while saving the source."
					% [instance_id, uid]
				)
			)

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

	return diff


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
## Names Windows treats as devices whatever extension follows them.
const _RESERVED_FILE_NAMES := [
	"CON",
	"PRN",
	"AUX",
	"NUL",
	"COM1",
	"COM2",
	"COM3",
	"COM4",
	"COM5",
	"COM6",
	"COM7",
	"COM8",
	"COM9",
	"LPT1",
	"LPT2",
	"LPT3",
	"LPT4",
	"LPT5",
	"LPT6",
	"LPT7",
	"LPT8",
	"LPT9",
]


## A prefab name as a file name that stays inside the prefab directory.
##
## `to_snake_case()` normalises case and word breaks and does not touch a slash,
## a dot or a leading `..`, so the Save box was free text going straight into a
## path: "../escape" resolved to `res://escape.hfprefab`, beside `project.godot`
## and invisible to the panel that made it, and "level 2/pillar" failed silently
## (#667). `validate_filename()` is the engine's own rule for what a filesystem
## accepts and replaces every separator, so a name can no longer point anywhere
## but here.
##
## Capped at 200 characters before the extension. The usual filesystem limit is
## 255 bytes for the whole name, and a name the panel's list cannot show is not a
## name anybody wanted.
static func prefab_file_name(prefab_name: String) -> String:
	# Trimmed before `to_snake_case()`, which turns a run of spaces into a run of
	# underscores: "   " came out as "___" rather than as no name at all.
	var cleaned := prefab_name.strip_edges().to_snake_case().validate_filename().strip_edges()
	# Leading dots are what a traversal is made of, and a file starting with one
	# is hidden on every platform that matters.
	while cleaned.begins_with("."):
		cleaned = cleaned.substr(1)
	if cleaned.length() > 200:
		cleaned = cleaned.substr(0, 200)
	if cleaned == "":
		cleaned = "untitled"
	# `validate_filename()` replaces characters a filesystem refuses; it does not
	# know about names it refuses. On Windows `CON`, `NUL`, `PRN`, `AUX` and the
	# COM/LPT series are devices, with or without an extension, so `CON.hfprefab`
	# cannot be opened and the save failed with nothing on screen (#667).
	if _RESERVED_FILE_NAMES.has(cleaned.to_upper()):
		cleaned = "%s_prefab" % cleaned
	return cleaned + ".hfprefab"


## Say something to the mapper, the way the other subsystems do.
func _report(message: String, severity: int) -> void:
	HFLog.warn("HammerForge: %s" % message)
	if root and root.has_signal("user_message"):
		root.user_message.emit(message, severity)


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

	var dir_path := PREFAB_DIR
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file_name := prefab_file_name(prefab_name)
	var path := dir_path.path_join(file_name)
	var err := prefab.save_to_file(path)
	if err != OK:
		# `quick_save_prefab()` reported failure as an empty string and nothing
		# above it turned that into a message: the name stayed in the box, the
		# list did not change, and the Save button looked like it had not
		# registered the click. A mapper whose disk was full got exactly the same
		# feedback as one who typed a name with a slash in it (#667).
		_report("Prefab '%s' could not be written to %s (error %d)" % [prefab_name, path, err], 2)
		return ""

	# Register as a linked instance if requested
	if linked:
		var brush_ids: Array = []
		for b in brush_nodes:
			brush_ids.append(str(b.get_meta("brush_id", "")))
		register_instance(path, brush_ids, entity_nodes, true)

	return path


# ---------------------------------------------------------------------------
# Clipboard (#703)
# ---------------------------------------------------------------------------


## Put a selection on the clipboard. False when there was nothing to put there,
## or when the buffer could not be written.
##
## The same capture a prefab gets, so it arrives with its entity wiring, its
## brush entity ties and a record of what each material slot meant. It is not
## registered as a linked instance: a pasted corridor is geometry, not a copy of
## a library asset that should follow it when the asset changes.
func copy_to_clipboard(brush_nodes: Array, entity_nodes: Array) -> bool:
	if brush_nodes.is_empty() and entity_nodes.is_empty():
		return false
	var prefab = HFPrefabType.capture_from_selection(
		root.brush_system, root.entity_system, brush_nodes, entity_nodes
	)
	if prefab.brush_infos.is_empty() and prefab.entity_infos.is_empty():
		return false
	prefab.prefab_name = "Clipboard"
	var err := prefab.save_to_file(CLIPBOARD_PATH)
	if err != OK:
		# The same rule the prefab save learned in #667: a write that failed has
		# to say so, or the next paste quietly puts back whatever was there
		# before and the mapper is looking at the wrong geometry.
		_report("Copy failed: the clipboard buffer could not be written (error %d)" % err, 2)
		return false
	return true


## What is on the clipboard, or null when it is empty or unreadable.
func clipboard_contents():
	if not FileAccess.file_exists(CLIPBOARD_PATH):
		return null
	return HFPrefabType.load_from_file(CLIPBOARD_PATH)


func clipboard_is_empty() -> bool:
	return clipboard_contents() == null


## Place what is on the clipboard.
##
## `at` is where the selection's centre lands. `Vector3.INF` means "where it was
## copied from", which is what Ctrl+C then Ctrl+V means in every editor in this
## lineage, and is the only placement that lines a pasted piece up with the one
## it came from.
##
## Brush ids are minted fresh, and group and visgroup membership is dropped by
## the capture, so pasting into a level that has never heard of "West Wing" does
## not put brushes in a group with no row in the panel. Material slots are
## resolved against the destination's palette.
func paste_from_clipboard(at: Vector3 = Vector3.INF) -> Dictionary:
	var empty := {"brush_ids": [], "entity_count": 0, "entity_names": [], "entity_nodes": []}
	var prefab = clipboard_contents()
	if prefab == null:
		return empty
	if prefab.brush_infos.is_empty() and prefab.entity_infos.is_empty():
		return empty
	var placement: Vector3 = prefab.source_centroid if not at.is_finite() else at
	return prefab.instantiate(root.brush_system, root.entity_system, root, placement)


# ---------------------------------------------------------------------------
# Serialization (for save/load)
# ---------------------------------------------------------------------------


## The number at the end of a `pfx_N` or `pent_N` id, or 0 if there is not one.
static func _id_number(id: String) -> int:
	var underscore := id.rfind("_")
	if underscore < 0:
		return 0
	var tail := id.substr(underscore + 1)
	return int(tail) if tail.is_valid_int() else 0


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
		# "overrides" in an older payload is read past: the mechanism it belonged
		# to had no way in from the editor and wrote a meta nothing read.
		rec.linked = bool(entry.get("linked", false))
		if rec.instance_id != "":
			_instances[rec.instance_id] = rec
			_tag_nodes(rec)
			# The floor comes from what was restored, not from the stored counter.
			# A state whose instances list holds `pfx_1` while its
			# `next_instance_id` is 1 restores cleanly and then issues `pfx_1`
			# again, and `_instances[iid] = rec` is a plain dictionary write, so
			# the second registration overwrites the first without a word. The
			# first placement's nodes are still tagged with that id and now
			# resolve to a record describing a different prefab, which is how
			# `set_variant()` ends up orphaning brushes instead of replacing them.
			# `data.get("next_instance_id", 1)` is exactly what a `.hflevel`
			# saved before the counter was captured produces.
			_next_instance_id = maxi(_next_instance_id, _id_number(rec.instance_id) + 1)
			for uid in rec.entity_uids:
				_next_entity_uid = maxi(_next_entity_uid, _id_number(str(uid)) + 1)
