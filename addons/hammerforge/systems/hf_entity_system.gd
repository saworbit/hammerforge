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


func add_entity(entity: Node3D) -> void:
	if not entity:
		return
	if not root.entities_node:
		return
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)


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
		data.erase("classname")
		data.erase("origin")
		entity.entity_data = data
	var origin = info.get("origin", Vector3.ZERO)
	if origin is Vector3:
		entity.global_position = origin
	add_entity(entity)
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
	if info.has("transform"):
		entity.global_transform = info["transform"]
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
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)
	return entity


func build_duplicate_info(entity: DraftEntity, offset: Vector3) -> Dictionary:
	var info := capture_entity_info(entity)
	if info.is_empty():
		return {}
	var transform: Transform3D = info.get("transform", Transform3D.IDENTITY)
	transform.origin += offset
	info["transform"] = transform
	info["name"] = _unique_entity_copy_name(str(entity.name))
	return info


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
		var removed_count := cleanup_dangling_connections(entity_name)
		if removed_count > 0 and root.has_signal("user_message"):
			root.user_message.emit(
				(
					"Removed %d I/O connection(s) targeting deleted entity '%s'"
					% [removed_count, entity_name]
				),
				1
			)
		var parent := entity.get_parent()
		if parent:
			parent.remove_child(entity)
		entity.queue_free()


func nudge_entities_by_paths(entity_paths: Array, offset: Vector3) -> void:
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
func cleanup_dangling_connections(deleted_name: String) -> int:
	var removed := 0
	if deleted_name == "" or not root.entities_node:
		return removed
	for child in root.entities_node.get_children():
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
	if name_map.is_empty() or not root.entities_node:
		return 0
	var remapped := 0
	for source in root.entities_node.get_children():
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
	# Also check brush entities
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if is_brush_io_target(child) and child.name == entity_name:
				result.append(child)
	return result


static func is_brush_io_target(node: Node) -> bool:
	return (
		node != null
		and is_instance_valid(node)
		and not str(node.get_meta("brush_entity_class", "")).is_empty()
	)


## Get all I/O connections in the scene (for visualization).
func get_all_connections() -> Array:
	var connections: Array = []
	if not root.entities_node:
		return connections
	for child in root.entities_node.get_children():
		var outputs = get_entity_outputs(child)
		for conn in outputs:
			if not (conn is Dictionary):
				continue
			(
				connections
				. append(
					{
						"source": child,
						"source_name": child.name,
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
