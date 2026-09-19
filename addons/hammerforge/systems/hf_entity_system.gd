@tool
extends RefCounted
class_name HFEntitySystem

const DraftEntity = preload("../draft_entity.gd")
const HFEntityDef = preload("../hf_entity_def.gd")

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


func load_entity_definitions() -> void:
	root.entity_definitions.clear()
	var defs = HFEntityDef.load_merged_definitions(
		str(root.entity_definitions_path), HFEntityDef.PROJECT_DEFINITIONS_PATH
	)
	for def in defs:
		if def and def.classname != "":
			root.entity_definitions[def.classname] = def.to_dict()


func get_entity_definition(entity_type: String) -> Dictionary:
	if entity_type == "":
		return {}
	return root.entity_definitions.get(entity_type, {})


func get_entity_definitions() -> Dictionary:
	return root.entity_definitions


func find_entity_by_prefab_uid(uid: String) -> Node3D:
	if uid == "":
		return null
	if root.entities_node:
		for child in root.entities_node.get_children():
			if str(child.get_meta("hf_prefab_entity_id", "")) == uid:
				return child as Node3D
	if root.has_method("_iter_managed_brush_nodes"):
		for child in root._iter_managed_brush_nodes():
			if str(child.get_meta("hf_prefab_entity_id", "")) == uid:
				return child as Node3D
	return null


## Entity lifecycle signals live on LevelRoot. Route through the batcher so a
## multi-entity operation flushes them together with everything else it queued.
func _emit_entity_signal(signal_name: String, entity: Node) -> void:
	if not root:
		return
	if root.has_method("_emit_or_batch"):
		root._emit_or_batch(signal_name, [entity])
	elif root.has_signal(signal_name):
		root.emit_signal(signal_name, entity)


func add_entity(entity: Node3D) -> void:
	if not entity:
		return
	if not root.entities_node:
		return
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)
	_emit_entity_signal("entity_added", entity)


func place_entity_at_screen(
	camera: Camera3D, mouse_pos: Vector2, entity_type: String
) -> DraftEntity:
	if not camera:
		return null
	var hit = root._raycast(camera, mouse_pos)
	if not hit:
		return null
	var snapped = root._snap_point(hit.position)
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	if entity_type != "":
		entity.entity_type = entity_type
		entity.entity_class = entity_type
	add_entity(entity)
	entity.global_position = snapped
	return entity


func create_entity_from_map(info: Dictionary) -> DraftEntity:
	if info.is_empty():
		return null
	var entity_class = str(info.get("classname", ""))
	if entity_class == "":
		return null
	var entity = DraftEntity.new()
	entity.name = "DraftEntity"
	entity.entity_type = entity_class
	entity.entity_class = entity_class
	var props = info.get("properties", {})
	if props is Dictionary:
		var data = props.duplicate(true)
		for reserved in MapIO.RESERVED_ENTITY_KEYS:
			data.erase(reserved)
		# The output lines are wiring, not settings, and go back into metadata.
		for connection in info.get("entity_io_outputs", []):
			if connection is Dictionary:
				data.erase(str(connection.get("output_name", "")))
		entity.entity_data = data
	var authored := str(info.get("entity_name", ""))
	if authored != "":
		entity.set_meta("entity_name", authored)
	var outputs = info.get("entity_io_outputs", [])
	if outputs is Array and not outputs.is_empty():
		entity.set_meta("entity_io_outputs", outputs.duplicate(true))
	add_entity(entity)
	var origin = info.get("origin", Vector3.ZERO)
	if origin is Vector3:
		entity.global_position = origin
	return entity


func is_entity_node(node: Node) -> bool:
	if not node or not (node is Node3D):
		return false
	if bool(node.get_meta("is_entity", false)):
		return true
	if not root.entities_node:
		return false
	var current: Node = node
	while current:
		if current == root.entities_node:
			return true
		current = current.get_parent()
	return false


func capture_entity_info(entity: DraftEntity) -> Dictionary:
	if not entity:
		return {}
	var info: Dictionary = {}
	info["entity_type"] = entity.entity_type
	info["entity_class"] = entity.entity_class
	info["transform"] = entity.global_transform
	info["properties"] = entity.entity_data.duplicate(true)
	info["name"] = entity.name
	var outputs = entity.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		info["io_outputs"] = outputs.duplicate(true)
	var visgroups: PackedStringArray = entity.get_meta("visgroups", PackedStringArray())
	if not visgroups.is_empty():
		info["visgroups"] = Array(visgroups)
	var group_id := str(entity.get_meta("group_id", ""))
	if group_id != "":
		info["group_id"] = group_id
	# The authored name, which is not the node name. It is what an I/O output
	# targets and what `find_entities_by_name()` looks up, so an entity that comes
	# back without it is wired to nothing. Brush entities have carried it through
	# their own infos since #149; point entities were left out.
	var authored := str(entity.get_meta("entity_name", ""))
	if authored != "":
		info["entity_name"] = authored
	return info


func restore_entity_from_info(info: Dictionary) -> DraftEntity:
	if info.is_empty():
		return null
	if not root.entities_node:
		return null
	var entity = DraftEntity.new()
	entity.name = str(info.get("name", "Entity"))
	var type_value = str(info.get("entity_type", info.get("entity_class", "")))
	entity.entity_type = type_value
	entity.entity_class = type_value
	var props = info.get("properties", {})
	if props is Dictionary:
		entity.entity_data = props.duplicate(true)
	var io_outputs = info.get("io_outputs", [])
	if not io_outputs.is_empty():
		entity.set_meta("entity_io_outputs", io_outputs.duplicate(true))
	if info.has("visgroups"):
		var visgroups := PackedStringArray()
		for visgroup in info.get("visgroups", []):
			visgroups.append(str(visgroup))
		entity.set_meta("visgroups", visgroups)
	var group_id := str(info.get("group_id", ""))
	if group_id != "":
		entity.set_meta("group_id", group_id)
	var authored := str(info.get("entity_name", ""))
	if authored != "":
		entity.set_meta("entity_name", authored)
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)
	if info.has("transform"):
		entity.global_transform = info["transform"]
	_emit_entity_signal("entity_added", entity)
	return entity


## The entities an undo step records instead of the whole level.
##
## The brush half of this is `HFStateSystem.capture_brush_scope()`, and #761
## parked the entity half on identity: a restore that rebuilds an entity changes
## its node path, and the commands name entities by path. That is true of
## `restore_state()`, which clears every entity and builds new ones. It is not
## true of a scope. Nudge, rotate and flip write `global_transform` and
## `entity_data["angle"]` onto entities that are already there, so a scoped undo
## frees nothing, rebuilds nothing and moves no path, and the record can be
## written straight back onto the node it came from.
##
## Keyed by node path, which is both how the commands name an entity and what
## the restore looks it up by. It used to be the only thing keeping a scope from
## being read as a level, because a level state's `entities` is a list and this
## is a set, so `HFValidation.level_state_problem()` refused the swap. That was a
## side effect of a record shape rather than a decision, and a brush-only scope
## had no equivalent, so a scope now carries a key that says what it is and the
## refusal rests on that instead (#768).
##
## An empty dictionary back means these paths cannot be a scope and the caller
## should take the whole snapshot: a path that does not resolve to a managed
## entity is the one case, and it is the same refusal `capture_brush_scope()`
## makes for an id that does not resolve.
func capture_entity_scope(entity_paths: Array) -> Dictionary:
	var records: Dictionary = {}
	for raw_path in entity_paths:
		var entity_path := str(raw_path)
		if entity_path == "" or records.has(entity_path):
			continue
		var entity := _entity_at_path(entity_path)
		if entity == null:
			return {}
		var info: Dictionary = capture_entity_info(entity)
		if info.is_empty():
			return {}
		records[entity_path] = info
	return records


## The mirror of `capture_entity_scope()`. Returns how many records it could not
## use, which the caller adds to its own count for one warning per step.
##
## One unreadable record costs that record and not the step, the same way one
## unreadable brush entry does.
func restore_entity_scope(records: Dictionary) -> int:
	var skipped := 0
	for entity_path in records:
		var info = records[entity_path]
		if not (info is Dictionary):
			skipped += 1
			continue
		var entity := _entity_at_path(str(entity_path))
		if entity == null:
			skipped += 1
			continue
		apply_entity_record(entity, info as Dictionary)
	return skipped


## Write a captured record back onto the entity it was captured from.
##
## `restore_entity_from_info()` is the other mirror of `capture_entity_info()`:
## it builds a new node, because a whole-level restore cleared them all first.
## This one is for an entity that is still there, and every field the record
## carries -- type, properties, transform, name, io outputs, visgroups, group id
## and the authored name -- is writable onto a live node.
##
## The record is authoritative, so a field it does not carry is cleared rather
## than left as it is. Setting the type first and the properties after is the
## order that matters: the type setter fills `entity_data` in from the class
## schema, so the other way round would put back the record's properties and then
## grow keys onto them.
func apply_entity_record(entity: DraftEntity, info: Dictionary) -> void:
	if entity == null or info.is_empty():
		return
	var scene_before := _authored_scene_value(entity)
	entity.entity_type = str(info.get("entity_type", info.get("entity_class", "")))
	var props = info.get("properties", {})
	entity.entity_data = (props as Dictionary).duplicate(true) if props is Dictionary else {}
	var outputs = info.get("io_outputs", null)
	_apply_entity_meta(
		entity, "entity_io_outputs", outputs.duplicate(true) if outputs is Array else null
	)
	var visgroups = info.get("visgroups", null)
	if visgroups is Array:
		var packed := PackedStringArray()
		for visgroup in visgroups:
			packed.append(str(visgroup))
		_apply_entity_meta(entity, "visgroups", packed)
	else:
		_apply_entity_meta(entity, "visgroups", null)
	_apply_entity_meta(entity, "group_id", _record_string(info, "group_id"))
	_apply_entity_meta(entity, "entity_name", _record_string(info, "entity_name"))
	if info.has("transform"):
		entity.global_transform = info["transform"]
	_rename_entity_in_place(entity, str(info.get("name", "")))
	# The preview is built from the class and from the scene path the class names,
	# and from nothing else. The type setter already rebuilt it if the type moved,
	# so this is the other input.
	if _authored_scene_value(entity) != scene_before:
		entity.refresh_preview()


## A record's string field, or null when it does not carry one. `null` rather
## than `""` because the metadata it becomes is either there or it is not, and
## `capture_entity_info()` writes these only when they are non-empty.
func _record_string(info: Dictionary, key: String):
	var value := str(info.get(key, ""))
	return value if value != "" else null


func _apply_entity_meta(entity: DraftEntity, meta_name: StringName, value) -> void:
	if value == null:
		if entity.has_meta(meta_name):
			entity.remove_meta(meta_name)
		return
	entity.set_meta(meta_name, value)


## Put the node name back, and only when it is free.
##
## Godot documents `Node.name` as unique among siblings and renames the node
## itself when it is set to a name one of them holds. A scoped undo finds its
## entities by node path, so a silent uniquify here would leave every later
## lookup in the step pointing at nothing. None of the commands that scope
## renames an entity, so this is a no-op in practice and a refusal in the one
## case that would break the record.
func _rename_entity_in_place(entity: DraftEntity, wanted: String) -> void:
	if wanted == "" or str(entity.name) == wanted:
		return
	var parent := entity.get_parent()
	if parent != null and parent.has_node(NodePath(wanted)):
		HFLog.warn(
			(
				"HFEntitySystem: '%s' kept its name because a sibling already holds '%s'"
				% [str(entity.name), wanted]
			)
		)
		return
	entity.name = wanted


## The scene path this entity's class names, when it names one. Two of these
## either side of a record write say whether the viewport preview is stale.
func _authored_scene_value(entity: DraftEntity) -> String:
	var scene_property := entity.authored_scene_property()
	if scene_property == "":
		return ""
	return str(entity.entity_data.get(scene_property, ""))


func build_duplicate_info(entity: DraftEntity, offset: Vector3) -> Dictionary:
	var info := capture_entity_info(entity)
	if info.is_empty():
		return {}
	var transform: Transform3D = info.get("transform", Transform3D.IDENTITY)
	transform.origin += offset
	info["transform"] = transform
	info["name"] = _unique_entity_copy_name(str(entity.name))
	# The authored name is the address I/O is wired by, so a copy that keeps it
	# answers to everything aimed at the original and there is no way to aim at
	# one of them. The copy's own outputs are left as they are on purpose: a copy
	# of a button should go on firing at the door it fired at.
	if info.has("entity_name"):
		info["entity_name"] = unique_authored_name(str(info["entity_name"]))
	return info


## An authored name nothing in the level already answers to.
##
## A trailing number is counted on, because that is how a mapper names a run of
## them — `door_1` becomes `door_2` — and a name without one gets `_2` added.
## Both node names and authored names are checked, since an output resolves
## against either.
func unique_authored_name(source_name: String) -> String:
	if source_name.strip_edges() == "":
		return source_name
	var taken := build_name_index()
	if not taken.has(source_name):
		return source_name
	var stem := source_name
	var counter := 2
	var underscore := source_name.rfind("_")
	if underscore > 0 and source_name.substr(underscore + 1).is_valid_int():
		stem = source_name.substr(0, underscore)
		counter = int(source_name.substr(underscore + 1)) + 1
	while taken.has("%s_%d" % [stem, counter]):
		counter += 1
	return "%s_%d" % [stem, counter]


func create_entities_from_infos(infos: Array) -> void:
	for info in infos:
		if info is Dictionary:
			restore_entity_from_info(info)


func delete_entities_by_paths(entity_paths: Array) -> void:
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if not entity:
			continue
		var entity_name := str(entity.name)
		var group_id := str(entity.get_meta("group_id", ""))
		entity.set_meta("group_id", "")
		entity.set_meta("visgroups", PackedStringArray())
		if group_id != "" and root.get("visgroup_system"):
			root.visgroup_system._cleanup_empty_group(group_id)
		var removed_count := cleanup_connections_for_deleted(entity)
		if removed_count > 0 and root.has_signal("user_message"):
			root.user_message.emit(
				(
					"Removed %d I/O connection(s) targeting deleted entity '%s'"
					% [removed_count, entity_name]
				),
				1
			)
		_emit_entity_signal("entity_removed", entity)
		var parent := entity.get_parent()
		if parent:
			parent.remove_child(entity)
		entity.queue_free()


func nudge_entities_by_paths(entity_paths: Array, offset: Vector3) -> void:
	# The same guard the brush nudge has. Entities travel with the selection, so
	# an offset that cannot be added would take them to the same nowhere.
	if not offset.is_finite():
		HFLog.warn("HFEntitySystem: nudge offset %s is not an offset" % str(offset))
		return
	for entity_path in entity_paths:
		var entity := _entity_at_path(entity_path)
		if entity:
			entity.global_position += offset


func _entity_at_path(entity_path: Variant) -> DraftEntity:
	if not root or not root.entities_node:
		return null
	var node := root.get_node_or_null(NodePath(str(entity_path)))
	return node as DraftEntity if node is DraftEntity and is_entity_node(node) else null


func _unique_entity_copy_name(source_name: String) -> String:
	var base := "%s Copy" % (source_name if source_name != "" else "Entity")
	var used := {}
	if root.entities_node:
		for child in root.entities_node.get_children():
			used[str(child.name)] = true
	if not used.has(base):
		return base
	var suffix := 2
	while used.has("%s %d" % [base, suffix]):
		suffix += 1
	return "%s %d" % [base, suffix]


func clear_entities() -> void:
	if not root.entities_node:
		return
	for child in root.entities_node.get_children():
		_emit_entity_signal("entity_removed", child)
		root.entities_node.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Entity I/O (inputs / outputs / connections)
# ---------------------------------------------------------------------------


## Add an output connection to a source entity.
## Each connection: {output_name, target_name, input_name, parameter, delay, fire_once}
func add_entity_output(
	entity: Node,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String = "",
	delay: float = 0.0,
	fire_once: bool = false
) -> void:
	if not entity:
		return
	# Every one of these reaches the exported `.map` as a line that reads like
	# wiring and does nothing, and this project's own importer drops it again on
	# the way back in — so the dock shows a connection that the round trip has
	# already lost.
	if output_name.strip_edges() == "":
		HFLog.warn("HFEntitySystem: an output needs a name")
		return
	if target_name.strip_edges() == "":
		HFLog.warn("HFEntitySystem: an output needs something to fire at")
		return
	if input_name.strip_edges() == "":
		HFLog.warn("HFEntitySystem: an output needs an input to fire")
		return
	if not is_finite(delay) or delay < 0.0:
		HFLog.warn("HFEntitySystem: an output delay must be zero or more seconds")
		return
	var outputs: Array = entity.get_meta("entity_io_outputs", [])
	(
		outputs
		. append(
			{
				"output_name": output_name,
				"target_name": target_name,
				"input_name": input_name,
				"parameter": parameter,
				"delay": delay,
				"fire_once": fire_once,
			}
		)
	)
	entity.set_meta("entity_io_outputs", outputs)


## Remove an output connection by index.
func remove_entity_output(entity: Node, index: int) -> void:
	if not entity:
		return
	var outputs: Array = entity.get_meta("entity_io_outputs", [])
	if index < 0 or index >= outputs.size():
		return
	outputs.remove_at(index)
	entity.set_meta("entity_io_outputs", outputs)


## Get all output connections for an entity.
func get_entity_outputs(entity: Node) -> Array:
	if not entity:
		return []
	return entity.get_meta("entity_io_outputs", [])


## Remove all I/O connections that target a deleted node by name.
## Returns the number of connections removed.
## Drop the connections aimed at an entity that is going away.
##
## An entity has two addresses: its node name and its authored `entity_name`.
## An output can be aimed at either, so cleaning up only the node name leaves the
## connections that used the alias — silently, and ready to start addressing an
## unrelated entity the moment somebody reuses the name.
##
## A name that some other live node still answers to is not dangling and is left
## alone. Two entities can share an authored name; duplication and prefab
## placement both produce that, and cutting the survivor's connections would be a
## worse bug than the one this fixes.
##
## Called while the node is still in the tree, so it is excluded by identity
## rather than by having already gone.
func cleanup_connections_for_deleted(entity: Node) -> int:
	if entity == null:
		return 0
	var removed := 0
	var seen := {}
	for address in [str(entity.name), str(entity.get_meta("entity_name", ""))]:
		var target := str(address)
		if target == "" or seen.has(target):
			continue
		seen[target] = true
		if _another_node_answers_to(target, entity):
			continue
		removed += cleanup_dangling_connections(target)
	return removed


## True when some node other than `excluding` still answers to this address.
##
## The same set of addresses `find_entities_by_name()` resolves: a node name and
## an authored name, for point entities and brush entities alike.
func _another_node_answers_to(address: String, excluding: Node) -> bool:
	if address == "":
		return false
	if root.entities_node:
		for child in root.entities_node.get_children():
			if child != excluding and _node_answers_to(child, address):
				return true
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if child == excluding or not is_brush_io_target(child):
				continue
			if _node_answers_to(child, address):
				return true
	return false


static func _node_answers_to(node: Node, address: String) -> bool:
	return str(node.name) == address or str(node.get_meta("entity_name", "")) == address


func cleanup_dangling_connections(deleted_name: String) -> int:
	var removed := 0
	if deleted_name == "":
		return removed
	for child in _iter_io_sources():
		var outputs: Array = child.get_meta("entity_io_outputs", [])
		if outputs.is_empty():
			continue
		var cleaned: Array = []
		for conn in outputs:
			if conn is Dictionary and str(conn.get("target_name", "")) == deleted_name:
				removed += 1
			else:
				cleaned.append(conn)
		if cleaned.size() != outputs.size():
			child.set_meta("entity_io_outputs", cleaned)
	return removed


## Remap I/O connection target names using a name_map (old_name -> new_name).
## Used when instancing prefabs to update entity references.
func remap_io_connections(entity: Node, name_map: Dictionary) -> void:
	var outputs: Array = entity.get_meta("entity_io_outputs", [])
	if outputs.is_empty():
		return
	var changed := false
	for conn in outputs:
		if conn is Dictionary:
			var target: String = str(conn.get("target_name", ""))
			if name_map.has(target):
				conn["target_name"] = name_map[target]
				changed = true
	if changed:
		entity.set_meta("entity_io_outputs", outputs)


## Native Scene-tree rename bypasses HammerForge's managed actions. Preserve
## literal I/O targets by following the same object instance from its old name
## to its new one; Undo naturally supplies the reverse map on the next pass.
func reconcile_external_names(previous_names: Dictionary, current_names: Dictionary) -> int:
	var name_map: Dictionary = {}
	# A literal target may resolve through either a node's old Scene-tree name or
	# a point entity's current compatibility alias. Track the owning instances,
	# not raw occurrences: a node can legitimately own the same spelling through
	# both fields, while a second owner makes an automatic rewrite unsafe.
	var previous_name_owners: Dictionary = {}
	for instance_id in previous_names:
		_add_name_owner(previous_name_owners, str(previous_names[instance_id]), instance_id)
	if root.entities_node:
		for entity in root.entities_node.get_children():
			_add_name_owner(
				previous_name_owners,
				str(entity.get_meta("entity_name", "")),
				entity.get_instance_id(),
			)
	for instance_id in current_names:
		if not previous_names.has(instance_id):
			continue
		var old_name := str(previous_names[instance_id])
		var new_name := str(current_names[instance_id])
		var owners: Dictionary = previous_name_owners.get(old_name, {})
		if (
			not old_name.is_empty()
			and old_name != new_name
			and owners.size() == 1
			and owners.has(instance_id)
		):
			name_map[old_name] = new_name
	if name_map.is_empty():
		return 0
	var remapped := 0
	for source in _iter_io_sources():
		var outputs: Array = source.get_meta("entity_io_outputs", [])
		for connection in outputs:
			if connection is Dictionary and name_map.has(str(connection.get("target_name", ""))):
				remapped += 1
		remap_io_connections(source, name_map)
	return remapped


static func _add_name_owner(owners_by_name: Dictionary, name: String, instance_id: Variant) -> void:
	if name.is_empty():
		return
	var owners: Dictionary = owners_by_name.get(name, {})
	owners[instance_id] = true
	owners_by_name[name] = owners


## Find all entities by name (used for resolving target_name references).
func find_entities_by_name(entity_name: String) -> Array:
	var result: Array = []
	if not root.entities_node or entity_name == "":
		return result
	for child in root.entities_node.get_children():
		if child.name == entity_name or str(child.get_meta("entity_name", "")) == entity_name:
			result.append(child)
	# Also check brush entities. A brush's node name is engine generated
	# (`DraftBrush_1`), so the authored name in metadata is the one a connection
	# is written against, and matching only the node name meant an output pointed
	# at a door or a button never resolved.
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if is_brush_io_target(child) and _node_answers_to(child, entity_name):
				result.append(child)
	return result


## Every address in the level mapped to the nodes that answer to it.
##
## One pass over the entities and brush entities, so a caller resolving many
## connections at once does not rescan the level per connection. The addresses
## and the order within an address match `find_entities_by_name()` exactly, and
## they are built here rather than at the call site so the two cannot drift.
##
## A snapshot. Anything that adds, removes, renames or re-aliases a node makes it
## wrong, so build it inside the pass that reads it.
func build_name_index() -> Dictionary:
	var index: Dictionary = {}
	if root.entities_node:
		for child in root.entities_node.get_children():
			_index_address(index, str(child.name), child)
			_index_address(index, str(child.get_meta("entity_name", "")), child)
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if is_brush_io_target(child):
				_index_address(index, str(child.name), child)
				_index_address(index, str(child.get_meta("entity_name", "")), child)
	return index


## A node answering to both its node name and the same authored name is still one
## target, the way `find_entities_by_name()` appends it once.
static func _index_address(index: Dictionary, address: String, node: Node) -> void:
	if address == "":
		return
	if not index.has(address):
		index[address] = [node]
		return
	var nodes: Array = index[address]
	if not nodes.has(node):
		nodes.append(node)


static func is_brush_io_target(node: Node) -> bool:
	return (
		node != null
		and is_instance_valid(node)
		and not str(node.get_meta("brush_entity_class", "")).is_empty()
	)


func _iter_io_sources() -> Array:
	var nodes: Array = []
	if root.entities_node:
		nodes.append_array(root.entities_node.get_children())
	if root.draft_brushes_node:
		nodes.append_array(root.draft_brushes_node.get_children())
	return nodes


## The name an entity is addressed by: its authored `entity_name` when it has
## one, its node name otherwise.
##
## The two halves of a connection record used to be in different namespaces. The
## target side is whatever the output was aimed at, which is the authored name,
## while the source side was the scene tree name. For a brush entity that is
## whatever Godot generated, so a source never matched an authored name and
## get_connection_summary() reported every wired entity as wired to nothing.
static func authored_address(entity: Node) -> String:
	if entity == null:
		return ""
	var authored := str(entity.get_meta("entity_name", ""))
	return authored if authored != "" else str(entity.name)


## Get all I/O connections in the scene (for visualization).
func get_all_connections() -> Array:
	var connections: Array = []
	for child in _iter_io_sources():
		var outputs = get_entity_outputs(child)
		for conn in outputs:
			if not (conn is Dictionary):
				continue
			(
				connections
				. append(
					{
						"source": child,
						"source_name": authored_address(child),
						"source_node_name": str(child.name),
						"output_name": str(conn.get("output_name", "")),
						"target_name": str(conn.get("target_name", "")),
						"input_name": str(conn.get("input_name", "")),
						"parameter": str(conn.get("parameter", "")),
						"delay": float(conn.get("delay", 0.0)),
						"fire_once": bool(conn.get("fire_once", false)),
					}
				)
			)
	return connections


## Fire an output on an entity at runtime.  Delegates to the scene's
## HFIORuntime dispatcher if one exists; otherwise resolves targets and calls
## input methods directly (single-shot, no delay/fire_once support).
func fire_output(entity: Node, output_name: String, parameter: String = "") -> void:
	if not is_instance_valid(entity):
		return
	# Prefer the runtime dispatcher if present in the tree
	if entity.is_inside_tree():
		var dispatcher: Node = null
		var scene_root: Node = entity.get_tree().current_scene if entity.get_tree() else null
		if scene_root:
			dispatcher = scene_root.find_child("HFIODispatcher", true, false)
		if dispatcher and dispatcher.has_method("fire_from"):
			dispatcher.fire_from(entity, output_name, parameter)
			return
	# Fallback: resolve targets manually from our connection data
	var outputs: Array = get_entity_outputs(entity)
	for conn in outputs:
		if not (conn is Dictionary):
			continue
		if str(conn.get("output_name", "")) != output_name:
			continue
		var target_name: String = str(conn.get("target_name", ""))
		var input_name: String = str(conn.get("input_name", ""))
		var param: String = parameter if parameter != "" else str(conn.get("parameter", ""))
		var targets: Array = find_entities_by_name(target_name)
		for target in targets:
			if not is_instance_valid(target):
				continue
			if target.has_method(input_name):
				if param != "":
					target.call(input_name, param)
				else:
					target.call(input_name)
			elif target.has_method("_on_io_input"):
				target.call("_on_io_input", input_name, param)
