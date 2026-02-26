@tool
extends RefCounted
class_name HFEntitySystem

const DraftEntity = preload("../draft_entity.gd")

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


func load_entity_definitions() -> void:
	root.entity_definitions.clear()
	if (
		root.entity_definitions_path == ""
		or not ResourceLoader.exists(root.entity_definitions_path)
	):
		return
	var file = FileAccess.open(root.entity_definitions_path, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	if data == null:
		return
	if data is Dictionary:
		var entries = data.get("entities", null)
		if entries is Array:
			for entry in entries:
				if entry is Dictionary:
					var key = str(entry.get("id", entry.get("class", "")))
					if key != "":
						root.entity_definitions[key] = entry
			return
		root.entity_definitions = data
		return
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				var key = str(entry.get("class", ""))
				if key != "":
					root.entity_definitions[key] = entry


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
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)
	return entity


func clear_entities() -> void:
	if not root.entities_node:
		return
	for child in root.entities_node.get_children():
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
			if child.name == entity_name:
				result.append(child)
	return result


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
