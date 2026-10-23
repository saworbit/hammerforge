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
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFFileNames = preload("res://addons/hammerforge/hf_file_names.gd")
const HFRebuildCarry = preload("res://addons/hammerforge/hf_rebuild_carry.gd")
@warning_ignore_restore("shadowed_global_identifier")

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

## The record key that holds a node's name.
const NODE_NAME := "name"

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

## Where this process saves prefabs and keeps the clipboard: the two paths above
## unless something points them elsewhere before the plugin comes up. The editor
## never does. A test run does, before its first test
## (`tests/support/gut_pre_run.gd`), because every checkout shares one `user://`
## and two suites running at once in two worktrees rewrote one clipboard file
## under each other (#1304). The library panel and the agent bridge copy
## `prefab_dir` when they are built, so a change after that moves only a save.
static var prefab_dir: String = PREFAB_DIR
static var clipboard_path: String = CLIPBOARD_PATH

## The meta a node carries as a piece of a placed copy: the copy's id, the prefab
## file, the variant it shows, and on an entity the stable id the copy finds it
## by. One list, written once, so tagging, untagging and every reader agree on it;
## it used to be spelled out in five files (#1339). The names are in saved scenes,
## so none of them changes.
const INSTANCE_META := &"hf_prefab_instance"
const SOURCE_META := &"hf_prefab_source"
const VARIANT_META := &"hf_prefab_variant"
const ENTITY_ID_META := &"hf_prefab_entity_id"
const LINK_META := [ENTITY_ID_META, INSTANCE_META, SOURCE_META, VARIANT_META]


class PrefabInstanceRecord:
	var instance_id: String = ""
	var source_path: String = ""  # PREFAB_DIR/foo.hfprefab
	var variant_name: String = "base"  # active variant
	var brush_ids: Array = []  # String brush IDs belonging to this instance
	var entity_uids: Array = []  # stable IDs ("pent_N") belonging to this instance
	var linked: bool = false  # if true, propagation applies
	## What this copy keeps of its own through a Pull and a variant switch, and
	## Push leaves out of the prefab (#1734): a piece's key, "b" or "e" and its
	## index (`piece_key()`), to `{"properties": [names], "wiring": bool}`.
	var kept: Dictionary = {}


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
			node.set_meta(ENTITY_ID_META, uid)
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


## Place `prefab`, read from `source_path`, with its centre at `frame.origin`,
## turned by `frame.basis`, and record the copy. What a drop from the library, the
## viewport menu's Place Selected Prefab and the agent bridge's place_prefab all
## run (#1301), so a copy is the same copy however it was placed. Returns what
## `HFPrefab.instantiate()` does plus `instance_id`, or `{}` when the variant holds
## nothing to place.
func place(
	prefab: HFPrefabType,
	source_path: String,
	frame: Transform3D,
	variant_name: String = "base",
	linked: bool = false
) -> Dictionary:
	var variant := "base" if variant_name == "" else variant_name
	var result: Dictionary = prefab.instantiate(
		root.brush_system, root.entity_system, root, frame.origin, variant, frame.basis
	)
	if (
		(result.get("brush_ids", []) as Array).is_empty()
		and int(result.get("entity_count", 0)) == 0
	):
		return {}
	_turn_angles(result["brush_ids"], result["entity_nodes"], frame.basis)
	# New work joins the current visgroup (#1732).
	if root.visgroup_system:
		root.visgroup_system.join_current_all(result["brush_ids"], result["entity_nodes"])
	result["instance_id"] = register_instance(
		source_path, result["brush_ids"], result["entity_nodes"], linked, variant
	)
	return result


## Turn what a copy's pieces keep as a facing in their data by the copy's turn: a
## door's move angle and a spawn's yaw. Their transforms turn with the frame and
## these did not, so a door in a doorway placed turned slid the way the prefab's
## door slides, and a variant switch put a turned copy's doors back to the
## prefab's. The calls HF Rotate makes, so a copy placed turned and one turned
## after are the same copy. A turn off world up turns neither, as with Rotate.
func _turn_angles(brush_ids: Array, entity_nodes: Array, turn: Basis) -> void:
	if turn == Basis.IDENTITY:
		return
	var transform_system = root.get("transform_system")
	if transform_system == null:
		return
	for brush_id in brush_ids:
		var brush = _find_brush_by_id(str(brush_id))
		if brush:
			transform_system.turn_brush_entity_angle(brush, turn)
	for entity in entity_nodes:
		if is_instance_valid(entity) and entity.get("entity_data") is Dictionary:
			transform_system.turn_entity_angle(entity, turn)


## Remove a registered instance (e.g. on delete/undo).
func unregister_instance(instance_id: String) -> void:
	if _instances.has(instance_id):
		var rec: PrefabInstanceRecord = _instances[instance_id]
		_untag_nodes(rec)
		_instances.erase(instance_id)


## Make a placed copy ordinary brushes and entities (#1734): its pieces lose
## their link and the level forgets the copy, so no later Pull, Push or variant
## switch reaches them. False for an id the level does not hold.
func unlink_instance(instance_id: String) -> bool:
	if not _instances.has(instance_id):
		return false
	unregister_instance(instance_id)
	return true


## Every placed copy of the prefab `instance_id` is a copy of, itself included.
func copies_like(instance_id: String) -> Array:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	return get_instances_for_source(rec.source_path) if rec else []


## The live brushes and entities of a placed copy.
func pieces_of(rec: PrefabInstanceRecord) -> Array:
	var out: Array = []
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			out.append(brush)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			out.append(ent)
	return out


## Get instance record by id.
func get_instance(instance_id: String) -> PrefabInstanceRecord:
	return _instances.get(instance_id, null)


## The placed copy `node` is a piece of, or null. A node is a piece only while
## its tag names a record the level holds: a tag a saved scene brought in for a
## copy that is gone names nothing. With `walk_parents` the nearest tagged
## ancestor below the level root answers for the node. The toolbar badge, the
## hover overlay and the bridge's brush listing all read through here (#1340).
func instance_of(node: Node, walk_parents: bool = false) -> PrefabInstanceRecord:
	var current: Node = node
	while current != null and current != root:
		var instance_id := str(current.get_meta(INSTANCE_META, ""))
		if instance_id != "":
			return _instances.get(instance_id, null)
		if not walk_parents:
			return null
		current = current.get_parent()
	return null


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


## Tag the record's live pieces with the copy they belong to. Returns what each
## now carries, by node, as `LevelRoot.clear_stale_membership()` takes it.
func _tag_nodes(rec: PrefabInstanceRecord) -> Dictionary:
	var written: Dictionary = {}
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			written[brush] = _write_link(brush, rec)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			written[ent] = _write_link(ent, rec)
			# The uid the entity was found by is the record's as well.
			written[ent][ENTITY_ID_META] = uid
	return written


## Write the copy's link on `node`, and return it.
static func _write_link(node: Node, rec: PrefabInstanceRecord) -> Dictionary:
	var link := {
		INSTANCE_META: rec.instance_id,
		SOURCE_META: rec.source_path,
		VARIANT_META: rec.variant_name,
	}
	for key in link:
		node.set_meta(key, link[key])
	return link


func _untag_nodes(rec: PrefabInstanceRecord) -> void:
	for bid in rec.brush_ids:
		var brush = _find_brush_by_id(bid)
		if brush:
			untag(brush)
	for uid in rec.entity_uids:
		var ent = _find_entity_by_uid(uid)
		if ent:
			untag(ent)


## Take every link off `node`, whichever copy it named: what an unregister, a
## restore and the cleanup of a native duplicate all mean by "no longer a piece".
static func untag(node: Node) -> void:
	for key in LINK_META:
		if node.has_meta(key):
			node.remove_meta(key)


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
	if not rec or _instance_is_gone(rec):
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
	if not rec or _instance_is_gone(rec):
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
	var placed_from: Dictionary = prefab.get_variant_data(rec.variant_name)
	var pieces := _instance_pieces(rec, placed_from)
	var frame := _instance_frame(rec, pieces)
	# What the copy has that the prefab does not hold, read off before it goes: its
	# node names, which the editor takes as an address (#1178), and its visgroups
	# and group, which a prefab does not carry (#368, #1190). Keyed by the node name
	# each node was placed under. The look and the entities are the prefab's.
	var carry := HFRebuildCarry.capture(
		_keyed(pieces, NODE_NAME),
		[HFRebuildCarry.NODE_NAME, HFRebuildCarry.MEMBERSHIP],
		root.visgroup_system
	)
	var kept_nodes := carry.kept(HFRebuildCarry.NODE_NAME)
	# And the names its entities answer to (#1168). One is every node of its
	# entity's, so it is keyed by the authored name in the records, and
	# `fresh_identities()` gives it back as it names them.
	var names := HFRebuildCarry.capture(
		_keyed(pieces, HFBrushEntity.NAME_META), [HFRebuildCarry.ENTITY_NAME]
	)
	var kept := names.kept(HFRebuildCarry.ENTITY_NAME)
	# A name the copy was given where the prefab gives none had no authored name to
	# be kept by, and the rebuild dropped it (#1274). It is kept by the node name
	# instead, as node names are.
	var unnamed := HFRebuildCarry.capture(
		pieces.map(func(piece): return [_unnamed_key(piece[0]), piece[1]]),
		[HFRebuildCarry.ENTITY_NAME]
	)
	var own_names := unnamed.kept(HFRebuildCarry.ENTITY_NAME)
	# And what the copy keeps of its own (#1734), by piece.
	var kept_values := _read_kept(rec)

	# Remove existing brushes/entities for this instance
	_remove_instance_nodes(rec)

	# Instantiate the new variant where the copy is, turned as it is
	var data: Dictionary = prefab.get_variant_data(variant_name)
	var brush_infos: Array = data.get("brush_infos", [])
	var entity_infos: Array = data.get("entity_infos", [])

	if root.has_method("begin_signal_batch"):
		root.begin_signal_batch()

	var placed_brushes: Array = []
	for info in brush_infos:
		var placed: Dictionary = info.duplicate(true)
		if placed.has("transform"):
			placed["transform"] = frame * (placed["transform"] as Transform3D)
		if root.brush_system.has_method("next_brush_id"):
			placed["brush_id"] = root.brush_system.next_brush_id()
		placed_brushes.append(placed)
	var placed_entities: Array = []
	for info in entity_infos:
		var placed: Dictionary = info.duplicate(true)
		if placed.has("transform"):
			placed["transform"] = frame * (placed["transform"] as Transform3D)
		placed_entities.append(placed)
	# Read before `fresh_identities()` mints new ties, which it groups by.
	var own := _own_names(placed_brushes + placed_entities, own_names)
	# Entities of their own, as a placement makes them (#1158, #1159), under the
	# names they had (#1168), with no free name taken from the ones given back
	# here. A name the prefab gives wins over one the copy was given.
	var addresses := HFBrushEntity.fresh_identities(
		placed_brushes,
		placed_entities,
		root.entity_system,
		kept,
		own.map(func(pair): return pair[1])
	)
	for pair in own:
		pair[0][HFBrushEntity.NAME_META] = pair[1]

	var new_brush_ids: Array = []
	var new_nodes: Array = []
	# Each node made, with the name it was captured under.
	var made: Array = []
	for placed in placed_brushes:
		var captured := str(placed.get(NODE_NAME, ""))
		if kept_nodes.has(captured):
			placed[NODE_NAME] = kept_nodes[captured]
		var brush = root.brush_system.create_brush_from_info(placed)
		if brush:
			new_brush_ids.append(str(placed.get("brush_id", "")))
			new_nodes.append(brush)
			made.append([captured, brush])

	var new_entity_uids: Array = []
	var new_entities: Array = []
	for placed in placed_entities:
		var captured := str(placed.get(NODE_NAME, ""))
		if kept_nodes.has(captured):
			placed[NODE_NAME] = kept_nodes[captured]
		var entity = root.entity_system.restore_entity_from_info(placed)
		if entity:
			var uid := _assign_entity_uid()
			entity.set_meta(ENTITY_ID_META, uid)
			new_entity_uids.append(uid)
			new_entities.append(entity)
			new_nodes.append(entity)
			made.append([captured, entity])

	carry.restore(made)
	for entry in made:
		HFPrefabType.note_new_name(addresses, {NODE_NAME: entry[0]}, entry[1])
	_turn_angles(new_brush_ids, new_entities, frame.basis)

	# Remap I/O through the nodes just made, brushes as well as entities.
	if not addresses.is_empty():
		for node in new_nodes:
			root.entity_system.remap_io_connections(node, addresses)

	if root.has_method("end_signal_batch"):
		root.end_signal_batch()

	# Update record
	rec.brush_ids = new_brush_ids
	rec.entity_uids = new_entity_uids
	rec.variant_name = variant_name
	_tag_nodes(rec)
	_give_kept(rec, kept_values)


## A piece's key in its copy: "b" and its brush's index, or "e" and its entity's.
## The index pairs the piece with its record in the prefab, through a Pull and a
## Push alike. "" for a node that is no piece of `rec`.
func piece_key(rec: PrefabInstanceRecord, node: Node) -> String:
	if rec == null or node == null:
		return ""
	if node is DraftBrush:
		var at := rec.brush_ids.find(str(node.get("brush_id")))
		return "b%d" % at if at >= 0 else ""
	var uid_at := rec.entity_uids.find(str(node.get_meta(ENTITY_ID_META, "")))
	return "e%d" % uid_at if uid_at >= 0 else ""


## The piece of `rec` a key names, or null.
func node_of_piece(rec: PrefabInstanceRecord, key: String) -> Node:
	if key.length() < 2 or not key.substr(1).is_valid_int():
		return null
	var at := key.substr(1).to_int()
	if key.begins_with("b") and at < rec.brush_ids.size():
		return _find_brush_by_id(str(rec.brush_ids[at]))
	if key.begins_with("e") and at < rec.entity_uids.size():
		return _find_entity_by_uid(str(rec.entity_uids[at]))
	return null


## Keep `prop_name` of `node`'s value on its copy, or stop. False when `node` is
## no piece of a copy, or nothing changed.
func set_kept(node: Node, prop_name: String, keep: bool) -> bool:
	var rec := instance_of(node)
	var key := piece_key(rec, node)
	if key == "" or prop_name == "":
		return false
	var entry: Dictionary = rec.kept.get(key, {"properties": [], "wiring": false})
	var props: Array = entry["properties"]
	if props.has(prop_name) == keep:
		return false
	if keep:
		props.append(prop_name)
	else:
		props.erase(prop_name)
	_store_kept(rec, key, entry)
	return true


## Keep every wire out of `node` on its copy, or stop.
func set_wiring_kept(node: Node, keep: bool) -> bool:
	var rec := instance_of(node)
	var key := piece_key(rec, node)
	if key == "":
		return false
	var entry: Dictionary = rec.kept.get(key, {"properties": [], "wiring": false})
	if bool(entry["wiring"]) == keep:
		return false
	entry["wiring"] = keep
	_store_kept(rec, key, entry)
	return true


func _store_kept(rec: PrefabInstanceRecord, key: String, entry: Dictionary) -> void:
	if (entry["properties"] as Array).is_empty() and not bool(entry["wiring"]):
		rec.kept.erase(key)
	else:
		rec.kept[key] = entry


## What `node`'s copy keeps of it: `{"properties": [names], "wiring": bool}`.
func kept_of(node: Node) -> Dictionary:
	var rec := instance_of(node)
	var key := piece_key(rec, node)
	return (rec.kept.get(key, {"properties": [], "wiring": false}) as Dictionary).duplicate(true)


## Forget everything the copy keeps, and give it the prefab's values again by
## rebuilding it from its file. False when there was nothing kept.
func clear_kept(node: Node) -> bool:
	var rec := instance_of(node)
	if rec == null or rec.kept.is_empty():
		return false
	rec.kept.clear()
	return set_variant(rec.instance_id, rec.variant_name)


## The linked copy `nodes` are all of, every piece of it and nothing else, or "".
## What Ctrl+D duplicates as another linked copy when asked to (#1734).
func whole_linked_copy(nodes: Array) -> String:
	if nodes.is_empty():
		return ""
	var rec := instance_of(nodes[0])
	if rec == null or not rec.linked:
		return ""
	var pieces := pieces_of(rec)
	if pieces.size() != nodes.size():
		return ""
	for node in nodes:
		if not pieces.has(node):
			return ""
	return rec.instance_id


## Place another linked copy of the prefab `instance_id` is a copy of, moved by
## `offset`, keeping what that copy keeps. It is made from the prefab, as a Pull
## would make it. The new copy's id, or "".
func duplicate_linked(instance_id: String, offset: Vector3) -> String:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	if rec == null or not rec.linked or _instance_is_gone(rec):
		return ""
	var prefab = HFPrefabType.load_from_file(rec.source_path)
	if not prefab:
		return ""
	var frame := _instance_frame(
		rec, _instance_pieces(rec, prefab.get_variant_data(rec.variant_name))
	)
	frame.origin += offset
	var placed := place(prefab, rec.source_path, frame, rec.variant_name, true)
	var iid := str(placed.get("instance_id", ""))
	if iid == "":
		return ""
	var copy: PrefabInstanceRecord = _instances[iid]
	copy.kept = rec.kept.duplicate(true)
	_give_kept(copy, _read_kept(rec))
	return iid


## Rebuild a copy from its prefab, throwing away what it changed outside what it
## keeps. False when the prefab cannot be read.
func discard_changes(instance_id: String) -> bool:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	return rec != null and set_variant(instance_id, rec.variant_name)


## Each kept piece's values as they are now, by key: its kept properties, and
## with its wiring kept, its wires.
func _read_kept(rec: PrefabInstanceRecord) -> Dictionary:
	var out: Dictionary = {}
	for key in rec.kept:
		var node := node_of_piece(rec, key)
		if node == null:
			continue
		var entry: Dictionary = rec.kept[key]
		var data := _entity_data_of(node)
		var values: Dictionary = {}
		for prop_name in entry.get("properties", []):
			if data.has(prop_name):
				values[prop_name] = data[prop_name]
		var wires: Variant = null
		if bool(entry.get("wiring", false)):
			wires = (node.get_meta(HFBrushEntity.OUTPUTS_META, []) as Array).duplicate(true)
		out[key] = {"properties": values, "wiring": wires}
	return out


## Put kept values back on the pieces a rebuild made, by key.
func _give_kept(rec: PrefabInstanceRecord, values: Dictionary) -> void:
	for key in values:
		var node := node_of_piece(rec, key)
		if node == null:
			continue
		var entry: Dictionary = values[key]
		for prop_name in entry["properties"]:
			root.set_entity_property(node, prop_name, entry["properties"][prop_name])
		if entry["wiring"] is Array:
			for holder in root.entity_property_nodes(node):
				holder.set_meta(
					HFBrushEntity.OUTPUTS_META, (entry["wiring"] as Array).duplicate(true)
				)


## A point entity's properties, or a brush entity's.
static func _entity_data_of(node: Node) -> Dictionary:
	if node is DraftEntity:
		return (node as DraftEntity).entity_data
	var data: Variant = node.get_meta(HFBrushEntity.DATA_META, {})
	return data if data is Dictionary else {}


## Each node of the instance still there, with the record it was placed from, as
## `[info, node]`, brushes first. `info` is empty for a node no record pairs with.
##
## A record and the node placed from it share an index, as `brush_ids` and
## `entity_uids` are in placement order. A propagation reads the prefab as just
## pushed, which was captured from a copy in that same order. A node whose class
## is not its record's is not paired, in case the two have drifted apart.
##
## A rebuild keys what it keeps by the records, so the names come back as they
## were. It used to ask for the lowest free name instead, so with the second copy
## gone the third door's `gate_4` became `gate_3` (#1168) and its leaf `Box_6`
## became `Box_4` (#1178), and a wire aimed at either reached nothing.
func _instance_pieces(rec: PrefabInstanceRecord, placed_from: Dictionary) -> Array:
	var pieces: Array = []
	var brush_infos: Array = placed_from.get("brush_infos", [])
	for i in rec.brush_ids.size():
		var brush := _find_brush_by_id(str(rec.brush_ids[i]))
		if brush:
			var info: Dictionary = brush_infos[i] if i < brush_infos.size() else {}
			pieces.append([info if _brush_matches(brush, info) else {}, brush])
	var entity_infos: Array = placed_from.get("entity_infos", [])
	for i in rec.entity_uids.size():
		var entity := _find_entity_by_uid(str(rec.entity_uids[i]))
		if entity:
			var info: Dictionary = entity_infos[i] if i < entity_infos.size() else {}
			pieces.append([info if _entity_matches(entity, info) else {}, entity])
	return pieces


## What a node's own authored name is kept under when its record gives it none:
## the node name in the record. "" when the record has an authored name, which a
## rebuild keeps by that name, or when there is no record.
static func _unnamed_key(info: Dictionary) -> String:
	if info.is_empty() or str(info.get(HFBrushEntity.NAME_META, "")) != "":
		return ""
	return str(info.get(NODE_NAME, ""))


## Each of `records` the prefab leaves unnamed that takes back a name the copy gave
## it, as `[record, name]`: the one kept under its node name, or failing that the
## one a record of the same tie takes. Every brush of one entity answers to its
## name, and only the first is kept, as one name is one entity's; a variant can
## also add a brush to it.
static func _own_names(records: Array, own_names: Dictionary) -> Array:
	var out: Array = []
	var by_tie: Dictionary = {}
	var waiting: Array = []
	for record in records:
		var key := _unnamed_key(record)
		if key == "":
			continue
		var tie := str(record.get(HFBrushEntity.TIE_META, ""))
		if own_names.has(key):
			out.append([record, own_names[key]])
			if tie != "" and not by_tie.has(tie):
				by_tie[tie] = own_names[key]
		elif tie != "":
			waiting.append([record, tie])
	for entry in waiting:
		if by_tie.has(entry[1]):
			out.append([entry[0], by_tie[entry[1]]])
	return out


## `pieces` keyed by `field` of the record each was placed from, as
## `HFRebuildCarry.capture()` takes them. A node no record pairs with is under "".
static func _keyed(pieces: Array, field: String) -> Array:
	return pieces.map(func(piece): return [str(piece[0].get(field, "")), piece[1]])


static func _brush_matches(brush: Node, info: Dictionary) -> bool:
	return HFBrushEntity.entity_class(brush) == str(info.get("brush_entity_class", ""))


static func _entity_matches(entity: Node, info: Dictionary) -> bool:
	var info_class := str(info.get("entity_type", info.get("entity_class", "")))
	return str(entity.get("entity_class")) == info_class


## True when none of an instance's nodes are in the level any more.
##
## Delete leaves a copy's record in place, so undoing the delete brings back a
## copy that is still linked. Rebuilding a record like that placed the copy again
## at the origin, as there were no nodes left to say where it had been (#1181).
func _instance_is_gone(rec: PrefabInstanceRecord) -> bool:
	for bid in rec.brush_ids:
		if _find_brush_by_id(str(bid)):
			return false
	for uid in rec.entity_uids:
		if _find_entity_by_uid(str(uid)):
			return false
	return true


## Where the copy is and which way it is turned, as the transform that takes the
## prefab's records to the copy's nodes. Each node paired with its record says
## what that must be: the node's transform times the inverse of the record's.
## Nodes and records pair by index (`_instance_pieces()`). The transform most of
## them agree on is the answer, so a node moved or deleted does not move the rest
## (#1186, #1188), and a copy turned as a whole stays turned (#1192). A position
## alone used to be the answer, so a rebuild faced every copy the way the prefab
## faces.
##
## Where no two agree, as in a copy of two with one moved, nothing says which node
## stayed. Moving a node leaves the way it faces alone, so if they still agree on
## that, the copy keeps that turn and the first node to say it stays where it is,
## as the first node still there decides when part of the copy is gone. Only nodes
## that disagree on the turn as well rebuild the copy unturned around the centre
## of its nodes. Any disagreement used to, which un-turned a copy of two with a
## node moved, and turned every other copy to match one pushed from a turned copy
## (#1222).
func _instance_frame(rec: PrefabInstanceRecord, pieces: Array) -> Transform3D:
	var said: Array = []
	for piece in pieces:
		var recorded = piece[0].get("transform")
		if recorded is Transform3D:
			said.append(piece[1].global_transform * (recorded as Transform3D).affine_inverse())
	var missing := pieces.size() < rec.brush_ids.size() + rec.entity_uids.size()
	var centre := Transform3D(Basis.IDENTITY, _instance_centroid(rec))
	if said.is_empty():
		return centre
	var whole := HFRebuildCarry.most_agreed(said, _same_frame)
	if whole[1] > 1 or said.size() == 1 or missing:
		return whole[0]
	var turned := HFRebuildCarry.most_agreed(said, _same_turn)
	if turned[1] > 1:
		return turned[0]
	return centre


## Whether two frames are the same to a thousandth.
static func _same_frame(a: Transform3D, b: Transform3D) -> bool:
	return _frame_key(a) == _frame_key(b)


## Whether two frames face the same way to a thousandth, wherever they are.
static func _same_turn(a: Transform3D, b: Transform3D) -> bool:
	return _basis_key(a) == _basis_key(b)


## A transform to a thousandth, as a key two that are the same share.
static func _frame_key(frame: Transform3D) -> String:
	return _basis_key(frame) + str((frame.origin * 1000.0).round())


## The way a transform faces to a thousandth, wherever it is.
static func _basis_key(frame: Transform3D) -> String:
	var b := frame.basis
	return str([b.x, b.y, b.z].map(func(v): return (v * 1000.0).round()))


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
		if not rec.linked or _instance_is_gone(rec):
			continue
		_apply_variant(rec, prefab, rec.variant_name)
		count += 1
	return count


## Re-capture the current state of an instance back to the source prefab.
## This is the "edit one instance → push to source" workflow.
func push_instance_to_source(instance_id: String) -> bool:
	var rec: PrefabInstanceRecord = _instances.get(instance_id, null)
	# A copy with no nodes would save the prefab empty.
	if not rec or rec.source_path == "" or _instance_is_gone(rec):
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
	_leave_kept_out(rec, captured, prefab.get_variant_data(rec.variant_name))
	prefab.set_variant_data(rec.variant_name, captured.brush_infos, captured.entity_infos)

	var err := prefab.save_to_file(rec.source_path)
	return err == OK


## What a copy keeps is its own, so Push writes the prefab's value back in its
## place, and drops it where the prefab has none (#1734).
func _leave_kept_out(rec: PrefabInstanceRecord, captured, before: Dictionary) -> void:
	for key in rec.kept:
		var at := str(key).substr(1).to_int()
		var brush := str(key).begins_with("b")
		var infos: Array = captured.brush_infos if brush else captured.entity_infos
		var old_infos: Array = before.get("brush_infos" if brush else "entity_infos", [])
		if at >= infos.size():
			continue
		var info: Dictionary = infos[at]
		var old: Dictionary = old_infos[at] if at < old_infos.size() else {}
		var data_key := HFBrushEntity.DATA_META if brush else "properties"
		var wires_key := HFBrushEntity.OUTPUTS_META if brush else "io_outputs"
		var entry: Dictionary = rec.kept[key]
		var data: Dictionary = info.get(data_key, {})
		var old_data: Dictionary = old.get(data_key, {})
		for prop_name in entry.get("properties", []):
			if old_data.has(prop_name):
				data[prop_name] = old_data[prop_name]
			else:
				data.erase(prop_name)
		info[data_key] = data
		if bool(entry.get("wiring", false)):
			if old.has(wires_key):
				info[wires_key] = (old[wires_key] as Array).duplicate(true)
			else:
				info.erase(wires_key)


## Compute a diff between a prefab instance and its source.
## Returns an Array of {field, source_value, instance_value} dictionaries.
##
## Beside the counts, each piece's properties and wires against its record, with
## the names a copy's own entities answer to read as the prefab's, and what the
## copy keeps left out (#1734).
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

	var pieces := _instance_pieces(rec, data)
	var names: Dictionary = {}
	for piece in pieces:
		var theirs := str((piece[0] as Dictionary).get(HFBrushEntity.NAME_META, ""))
		var ours := str((piece[1] as Node).get_meta(HFBrushEntity.NAME_META, ""))
		if theirs != "" and ours != "":
			names[ours] = theirs
	for piece in pieces:
		var info: Dictionary = piece[0]
		var node: Node = piece[1]
		if info.is_empty():
			continue
		var entry: Dictionary = rec.kept.get(piece_key(rec, node), {})
		var brush := node is DraftBrush
		var source_data: Dictionary = info.get(
			HFBrushEntity.DATA_META if brush else "properties", {}
		)
		var own_data := _entity_data_of(node)
		var props: Array = source_data.keys()
		for prop_name in own_data:
			if not props.has(prop_name):
				props.append(prop_name)
		for prop_name in props:
			if (entry.get("properties", []) as Array).has(prop_name):
				continue
			var own: Variant = _as_prefab_names(own_data.get(prop_name), names)
			if var_to_str(own) != var_to_str(source_data.get(prop_name)):
				(
					diff
					. append(
						{
							"field": "%s %s" % [node.name, prop_name],
							"source_value": source_data.get(prop_name),
							"instance_value": own_data.get(prop_name),
						}
					)
				)
		if bool(entry.get("wiring", false)):
			continue
		var source_wires: Variant = info.get(
			HFBrushEntity.OUTPUTS_META if brush else "io_outputs", []
		)
		var own_wires: Variant = _as_prefab_names(
			node.get_meta(HFBrushEntity.OUTPUTS_META, []), names
		)
		if var_to_str(own_wires) != var_to_str(source_wires if source_wires is Array else []):
			(
				diff
				. append(
					{
						"field": "%s wiring" % node.name,
						"source_value": source_wires,
						"instance_value": node.get_meta(HFBrushEntity.OUTPUTS_META, []),
					}
				)
			)
	return diff


## `value` with the names a copy gave its own entities read as the prefab's, so a
## wire or a target to a piece of the copy is not a change.
static func _as_prefab_names(value: Variant, names: Dictionary) -> Variant:
	if value is String and names.has(value):
		return names[value]
	if value is Array:
		return (value as Array).map(func(item): return _as_prefab_names(item, names))
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value:
			out[key] = _as_prefab_names(value[key], names)
		return out
	return value


# ---------------------------------------------------------------------------
# Quick group-to-prefab
# ---------------------------------------------------------------------------


## Suggest a name for a new prefab based on the contents.
func suggest_prefab_name(brush_nodes: Array, entity_nodes: Array) -> String:
	if not brush_nodes.is_empty() and not entity_nodes.is_empty():
		return "group_%d_brushes_%d_entities" % [brush_nodes.size(), entity_nodes.size()]
	if not brush_nodes.is_empty():
		if brush_nodes.size() == 1:
			var shape = brush_nodes[0].get("shape")
			return _shape_name(shape if shape is int else 0)
		return "%d_brush_group" % brush_nodes.size()
	if not entity_nodes.is_empty():
		if entity_nodes.size() == 1:
			var raw = entity_nodes[0].get("entity_type")
			var etype: String = str(raw) if raw != null else ""
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


## A prefab name as a file name that stays inside the prefab directory.
##
## `to_snake_case()` normalises case and word breaks and does not touch a slash,
## a dot or a leading `..`, so the Save box was free text going straight into a
## path: "../escape" resolved to `res://escape.hfprefab`, beside `project.godot`
## and invisible to the panel that made it, and "level 2/pillar" failed silently
## (#667). The rest of the rules are every library file's, in `HFFileNames`.
static func prefab_file_name(prefab_name: String) -> String:
	# Trimmed before `to_snake_case()`, which turns a run of spaces into a run of
	# underscores: "   " came out as "___" rather than as no name at all.
	var snake := prefab_name.strip_edges().to_snake_case()
	return HFFileNames.safe_file_stem(snake, "untitled", "prefab") + ".hfprefab"


## Where a prefab of this name is saved.
static func prefab_path(prefab_name: String, dir_path: String = prefab_dir) -> String:
	return dir_path.path_join(prefab_file_name(prefab_name))


## This name, or the first of name_2, name_3 and so on that no file uses yet.
##
## Quick Save has no dialog to ask in, and the name it suggests depends only on
## what is selected, so a second box saved over the first one's file and every
## instance linked to it followed (#929). It takes the next free name instead.
## A numbered name is the free file's own stem, which `prefab_file_name()` gives
## back unchanged, so the file it is saved to is the one found free.
static func unused_prefab_name(prefab_name: String, dir_path: String = prefab_dir) -> String:
	var stem := prefab_file_name(prefab_name).get_basename()
	var free_stem := HFFileNames.unused_path(dir_path, stem, "hfprefab").get_file().get_basename()
	return prefab_name if free_stem == stem else free_stem


## The brushes and the entities among `nodes`, in selection order, as
## `{"brushes": [...], "entities": [...]}`. A node freed since it was selected,
## or one that is neither, is left out.
##
## Quick Save, the library panel's Save and Save Linked, and Add Variant each
## split the selection with a loop of their own, and only the panel's skipped a
## freed node (#1451).
static func split_selection(level_root: Node, nodes: Array) -> Dictionary:
	var brushes: Array = []
	var entities: Array = []
	for node in nodes:
		if not is_instance_valid(node) or not (node is Node):
			continue
		if level_root.is_brush_node(node):
			brushes.append(node)
		elif level_root.is_entity_node(node):
			entities.append(node)
	return {"brushes": brushes, "entities": entities}


## Say something to the mapper, the way the other subsystems do.
func _report(message: String, severity: int) -> void:
	HFLog.warn("HammerForge: %s" % message)
	if root and root.has_signal("user_message"):
		root.user_message.emit(message, severity)


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

	var dir_path := prefab_dir
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var path := prefab_path(prefab_name, dir_path)
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
	var err := prefab.save_to_file(clipboard_path)
	if err != OK:
		# The same rule the prefab save learned in #667: a write that failed has
		# to say so, or the next paste quietly puts back whatever was there
		# before and the mapper is looking at the wrong geometry.
		_report("Copy failed: the clipboard buffer could not be written (error %d)" % err, 2)
		return false
	return true


## What is on the clipboard, or null when it is empty or unreadable.
func clipboard_contents():
	if not FileAccess.file_exists(clipboard_path):
		return null
	return HFPrefabType.load_from_file(clipboard_path)


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
					"kept": rec.kept.duplicate(true),
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
	# What the restored records put on their pieces, by node, so the links left
	# on every other node can come off once they are all written.
	var written: Dictionary = {}
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
		var kept: Variant = entry.get("kept", {})
		rec.kept = (kept as Dictionary).duplicate(true) if kept is Dictionary else {}
		if rec.instance_id != "":
			_instances[rec.instance_id] = rec
			written.merge(_tag_nodes(rec), true)
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
	# A link the restored records do not give a node comes off it. A brush an undo
	# kept rather than rebuilt still carried the link of a copy that was gone, and
	# so still read as a linked copy after the link was taken back (#1276); one a
	# kept copy no longer listed kept that copy's link all the same (#1338).
	root.clear_stale_membership(LINK_META, written)
