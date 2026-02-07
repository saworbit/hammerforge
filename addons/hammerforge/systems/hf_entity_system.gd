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
	entity.set_meta("is_entity", true)
	root.entities_node.add_child(entity)
	root._assign_owner(entity)
	return entity


func clear_entities() -> void:
	if not root.entities_node:
		return
	for child in root.entities_node.get_children():
		child.queue_free()
