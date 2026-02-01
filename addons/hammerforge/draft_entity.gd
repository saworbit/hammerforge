@tool
extends Node3D
class_name DraftEntity

@export var entity_type: String = "": set = _set_entity_type
@export var entity_class: String = "": set = _set_entity_class

var entity_data: Dictionary = {}
var preview_node: Node3D = null
var entity_properties: Dictionary:
    get:
        return entity_data
    set(value):
        if value is Dictionary:
            entity_data = value

func _set_entity_type(val: String) -> void:
    if entity_type == val:
        return
    entity_type = val
    if entity_class != val:
        entity_class = val
    _update_preview()
    _apply_entity_defaults()
    notify_property_list_changed()

func _set_entity_class(val: String) -> void:
    if entity_class == val:
        return
    entity_class = val
    if entity_type != val:
        entity_type = val
    _update_preview()
    _apply_entity_defaults()
    notify_property_list_changed()

func _ready() -> void:
    _update_preview()
    if entity_type != "" and entity_data.is_empty():
        _apply_entity_defaults()
        notify_property_list_changed()

func _exit_tree() -> void:
    _clear_preview()

func _update_preview() -> void:
    if not is_inside_tree() or not Engine.is_editor_hint():
        return
    _clear_preview()
    var definition = _get_entity_definition()
    if definition.is_empty() or not definition.has("preview"):
        return
    var preview = definition.get("preview", {})
    if not (preview is Dictionary):
        return
    var preview_type = str(preview.get("type", ""))
    var preview_path = str(preview.get("path", ""))
    if preview_type == "" or preview_path == "":
        return
    var preview_color = Color(preview.get("color", "#ffffff"))
    match preview_type:
        "billboard":
            var sprite = Sprite3D.new()
            var tex = load(preview_path)
            if tex and tex is Texture2D:
                sprite.texture = tex
            sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            sprite.no_depth_test = true
            sprite.modulate = preview_color
            _assign_preview(sprite)
        "mesh":
            var mesh_inst = MeshInstance3D.new()
            var mesh_res = load(preview_path)
            if mesh_res and mesh_res is Mesh:
                mesh_inst.mesh = mesh_res
            var mat = StandardMaterial3D.new()
            mat.albedo_color = preview_color
            mat.albedo_color.a = 0.5
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mesh_inst.material_override = mat
            mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            _assign_preview(mesh_inst)

func _assign_preview(node: Node3D) -> void:
    if not node:
        return
    node.name = "_EditorPreview"
    add_child(node)
    node.owner = null
    preview_node = node

func _clear_preview() -> void:
    if preview_node and is_instance_valid(preview_node):
        preview_node.queue_free()
    preview_node = null

func _get_entity_definition() -> Dictionary:
    var key = entity_class if entity_class != "" else entity_type
    if key == "":
        return {}
    var level_root = _find_level_root()
    if not level_root:
        return {}
    return level_root.get_entity_definition(key)

func _apply_entity_defaults() -> void:
    if entity_type == "":
        return
    var level_root = _find_level_root()
    if not level_root:
        return
    var definition: Dictionary = level_root.get_entity_definition(entity_type)
    if definition.is_empty():
        return
    var props: Array = definition.get("properties", [])
    for prop in props:
        var name = str(prop.get("name", ""))
        if name == "":
            continue
        if entity_data.has(name):
            continue
        entity_data[name] = _parse_default_value(prop.get("type", ""), prop.get("default", null))

func _parse_default_value(type_name: String, value: Variant) -> Variant:
    match type_name:
        "float":
            return float(value)
        "int":
            return int(value)
        "bool":
            return bool(value)
        "color":
            if value is Color:
                return value
            if value is String:
                return Color(value)
            return Color.WHITE
        "vector3":
            if value is Vector3:
                return value
            if value is Array and value.size() == 3:
                return Vector3(value[0], value[1], value[2])
            return Vector3.ZERO
        "string":
            return str(value)
        _:
            return value

func _get_property_list() -> Array:
    var properties: Array = []
    var type_hints = _get_entity_type_hints()
    if not type_hints.is_empty():
        properties.append({
            "name": "entity_type",
            "type": TYPE_STRING,
            "hint": PROPERTY_HINT_ENUM,
            "hint_string": ",".join(type_hints),
            "usage": PROPERTY_USAGE_DEFAULT
        })
    var schema: Array = _get_entity_schema()
    if schema.is_empty():
        return properties
    properties.append({
        "name": "Entity Props",
        "type": TYPE_NIL,
        "usage": PROPERTY_USAGE_CATEGORY
    })
    for prop in schema:
        var p_name = str(prop.get("name", ""))
        if p_name == "":
            continue
        var prop_type = _type_from_schema(prop.get("type", ""))
        properties.append({
            "name": "data/" + p_name,
            "type": prop_type,
            "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_STORAGE
        })
        properties.append({
            "name": "entity_data/" + p_name,
            "type": prop_type,
            "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_STORAGE
        })
    return properties

func _get(property: StringName) -> Variant:
    var p_str = str(property)
    if p_str.begins_with("data/"):
        var key = p_str.replace("data/", "")
        if entity_data.has(key):
            return entity_data[key]
        var schema_default = _schema_default_value(key)
        if schema_default != null:
            return schema_default
    if p_str.begins_with("entity_data/"):
        var key = p_str.replace("entity_data/", "")
        if entity_data.has(key):
            return entity_data[key]
        var schema_default = _schema_default_value(key)
        if schema_default != null:
            return schema_default
    return null

func _set(property: StringName, value: Variant) -> bool:
    var p_str = str(property)
    if p_str.begins_with("data/"):
        var key = p_str.replace("data/", "")
        entity_data[key] = value
        return true
    if p_str.begins_with("entity_data/"):
        var key = p_str.replace("entity_data/", "")
        entity_data[key] = value
        return true
    return false

func _schema_default_value(key: String) -> Variant:
    var schema: Array = _get_entity_schema()
    for prop in schema:
        if str(prop.get("name", "")) == key:
            return _parse_default_value(prop.get("type", ""), prop.get("default", null))
    return null

func _get_entity_schema() -> Array:
    if entity_type == "":
        return []
    var level_root = _find_level_root()
    if not level_root:
        return []
    var definition: Dictionary = level_root.get_entity_definition(entity_type)
    if definition.is_empty():
        return []
    var props: Array = definition.get("properties", [])
    return props

func _type_from_schema(type_name: String) -> int:
    match type_name:
        "float":
            return TYPE_FLOAT
        "int":
            return TYPE_INT
        "bool":
            return TYPE_BOOL
        "color":
            return TYPE_COLOR
        "vector3":
            return TYPE_VECTOR3
        "string":
            return TYPE_STRING
        _:
            return TYPE_NIL

func _get_entity_type_hints() -> PackedStringArray:
    var level_root = _find_level_root()
    if not level_root:
        return PackedStringArray()
    var definitions: Dictionary = level_root.get_entity_definitions()
    var keys = definitions.keys()
    keys.sort()
    var list := PackedStringArray()
    for key in keys:
        list.append(str(key))
    return list

func _find_level_root() -> Node:
    var current: Node = self
    while current:
        if current is LevelRoot:
            return current
        current = current.get_parent()
    return null
