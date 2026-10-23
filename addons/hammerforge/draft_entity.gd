@tool
extends Node3D
class_name DraftEntity

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFEntityPropUtils = preload("ui/hf_entity_prop_utils.gd")
@warning_ignore_restore("shadowed_global_identifier")

@export var entity_type: String = "":
	set = _set_entity_type
# Compatibility alias for older scenes and callers. It is deliberately not an
# exported second field: one visible Entity Type is enough.
var entity_class: String:
	get:
		return entity_type
	set(value):
		_set_entity_type(value)

## A note for the people working on the level (#1700). `HFNotes` reads them;
## the marker and the remembered author live here, where a note is drawn and
## made.
const NOTE_CLASS := "note"
const NOTE_DRAWN := ["title", "body", "kind", "done"]
const NOTE_KIND_COLORS := {"Note": "#ffd23f", "To Do": "#ff8a3d", "Playtest": "#4fc3f7"}

## The author the last note was signed with. A new note starts with it, so a
## name is typed once. The plugin keeps it between sessions.
static var last_note_author := ""

var entity_data: Dictionary = {}
var preview_node: Node3D = null
var _gizmo_update_queued := false
var _warned_scene_path := ""


func _set_entity_type(val: String) -> void:
	if entity_type == val:
		return
	entity_type = val
	_update_preview()
	_apply_entity_defaults()
	notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	var property_name := str(property.get("name", ""))
	if property_name == "entity_type":
		var type_hints := _get_entity_type_hints()
		if not type_hints.is_empty():
			property["hint"] = PROPERTY_HINT_ENUM
			property["hint_string"] = ",".join(type_hints)
	elif property_name == "entity_class":
		# Loadable through the declared compatibility alias, but neither visible
		# nor saved again. A resave therefore migrates old duplicate scene data.
		property["usage"] = PROPERTY_USAGE_NONE


func _ready() -> void:
	_update_preview()
	if entity_type != "" and entity_data.is_empty():
		_apply_entity_defaults()
		notify_property_list_changed()


## Back in the tree after an undo and its redo, or a scene tab switch, _ready()
## does not run again, and _exit_tree() took the preview with it.
func _enter_tree() -> void:
	if is_node_ready():
		refresh_preview()


func _exit_tree() -> void:
	_clear_preview()


func _update_preview() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	_queue_gizmo_update()
	_clear_preview()
	var definition = _get_entity_definition()
	if definition.is_empty():
		return
	# A class whose instances each name their own model shows that model, rather
	# than a proxy box standing in for something the mapper already chose. Falls
	# through to the definition's own preview when the path is empty or does not
	# resolve, so an unset or mistyped one still leaves something to select (#690).
	if _show_authored_scene(definition):
		return
	if not definition.has("preview"):
		return
	var preview = definition.get("preview", {})
	if not (preview is Dictionary):
		return
	var preview_type = str(preview.get("type", ""))
	var preview_path = str(preview.get("path", ""))
	if preview_type == "":
		return
	var preview_color = Color(preview.get("color", "#ffffff"))
	match preview_type:
		"billboard":
			if preview_path == "":
				return
			var sprite = Sprite3D.new()
			var tex = load(preview_path)
			if tex and tex is Texture2D:
				sprite.texture = tex
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.no_depth_test = true
			sprite.modulate = preview_color
			_assign_preview(sprite)
		"mesh":
			if preview_path == "":
				return
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
		"box":
			# A proxy that needs no asset. `door_basic` previewed with the only mesh
			# in the plugin, which is a light bulb, so a level with doors and lights
			# in it showed a bulb for both kinds of thing (#613).
			var box_inst = MeshInstance3D.new()
			var box = BoxMesh.new()
			var box_size = preview.get("size", [1.0, 2.0, 0.2])
			if box_size is Array and box_size.size() >= 3:
				box.size = Vector3(
					maxf(0.05, float(box_size[0])),
					maxf(0.05, float(box_size[1])),
					maxf(0.05, float(box_size[2]))
				)
			var box_alpha = float(preview.get("alpha", 0.6))
			var box_mat = StandardMaterial3D.new()
			box_mat.albedo_color = preview_color
			box_mat.albedo_color.a = clamp(box_alpha, 0.05, 1.0)
			box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			box_mat.shading_mode = (
				BaseMaterial3D.SHADING_MODE_UNSHADED
				if bool(preview.get("unshaded", true))
				else BaseMaterial3D.SHADING_MODE_PER_PIXEL
			)
			box_mat.no_depth_test = bool(preview.get("no_depth_test", false))
			box_inst.mesh = box
			box_inst.material_override = box_mat
			box_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_assign_preview(box_inst)
		"note":
			_assign_preview(_note_preview())
		"capsule":
			var mesh_inst = MeshInstance3D.new()
			var capsule = CapsuleMesh.new()
			var radius = float(preview.get("radius", 0.5))
			var height = float(preview.get("height", 2.0))
			var alpha = float(preview.get("alpha", 0.6))
			var unshaded = bool(preview.get("unshaded", true))
			var no_depth = bool(preview.get("no_depth_test", true))
			capsule.radius = max(0.05, radius)
			capsule.height = max(0.1, height)
			mesh_inst.mesh = capsule
			var mat = StandardMaterial3D.new()
			mat.albedo_color = preview_color
			mat.albedo_color.a = clamp(alpha, 0.05, 1.0)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = (
				BaseMaterial3D.SHADING_MODE_UNSHADED
				if unshaded
				else BaseMaterial3D.SHADING_MODE_PER_PIXEL
			)
			mat.no_depth_test = no_depth
			mesh_inst.material_override = mat
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_assign_preview(mesh_inst)


## A note's marker: a shape for its kind, its title over it, and its body under
## the title while the cursor is over it. A done note fades.
func _note_preview() -> Node3D:
	var kind := str(entity_data.get("kind", "Note"))
	var done: bool = entity_data.get("done") is bool and entity_data.get("done")
	var color := Color(str(NOTE_KIND_COLORS.get(kind, NOTE_KIND_COLORS["Note"])))
	var holder := Node3D.new()
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	match kind:
		"To Do":
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.3, 0.3)
			marker.mesh = box
			marker.rotation_degrees = Vector3(45, 0, 45)
		"Playtest":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.18
			cylinder.bottom_radius = 0.18
			cylinder.height = 0.4
			marker.mesh = cylinder
		_:
			var sphere := SphereMesh.new()
			sphere.radius = 0.2
			sphere.height = 0.4
			marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.3 if done else 0.9)
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(marker)
	var title := _note_label(
		str(entity_data.get("title", "Note")), 40, Color(color, 0.5 if done else 1.0)
	)
	title.name = "Title"
	title.position = Vector3(0, 0.45, 0)
	holder.add_child(title)
	var body := _note_label(
		str(entity_data.get("body", "")), 28, Color(1, 1, 1, 0.5 if done else 1.0)
	)
	body.name = "Body"
	body.position = Vector3(0, 0.25, 0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.width = 600.0
	body.visible = false
	holder.add_child(body)
	return holder


func _note_label(text: String, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.outline_size = 8
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	return label


## Show a note's body under its title, while the cursor is over the note.
func show_note_body(shown: bool) -> void:
	if preview_node == null or not is_instance_valid(preview_node):
		return
	var body := preview_node.get_node_or_null("Body") as Label3D
	if body:
		body.visible = shown and body.text != ""


## Whether a change to `prop_name` changes what the viewport draws.
func refreshes_preview_on(prop_name: String) -> bool:
	if prop_name == authored_scene_property():
		return true
	return entity_type == NOTE_CLASS and NOTE_DRAWN.has(prop_name)


## The property this entity's class uses to name its own model, or "".
func authored_scene_property() -> String:
	return str(_get_entity_definition().get("scene_property", "")).strip_edges()


## Rebuild the viewport preview. Called when a property the preview reads changes.
func refresh_preview() -> void:
	_update_preview()


## Build the preview from the scene this instance names, if it names one.
##
## Returns whether it did. `prop_static` is the class this exists for: it stores a
## scene path, it is the documented way to put a model in a level, and nothing
## loaded it, so the model was missing in the viewport, in the bake and in the
## export with nothing said anywhere.
func _show_authored_scene(definition: Dictionary) -> bool:
	var scene_property := str(definition.get("scene_property", "")).strip_edges()
	if scene_property == "":
		return false
	var path := str(entity_data.get(scene_property, "")).strip_edges()
	if path == "":
		return false
	if not ResourceLoader.exists(path):
		_warn_once_about_scene(path, "does not exist")
		return false
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		_warn_once_about_scene(path, "is not a PackedScene")
		return false
	var instance := packed.instantiate()
	if not (instance is Node3D):
		# A preview has to sit in the viewport. The export still builds it (#844).
		if instance != null:
			instance.free()
		_warn_once_about_scene(path, "has no Node3D root to show")
		return false
	_warned_scene_path = ""
	_assign_preview(instance as Node3D)
	return true


## Said once per path, because `_update_preview()` runs on every property change
## and a half-typed path is not worth a line of log per keystroke.
func _warn_once_about_scene(path: String, why: String) -> void:
	if _warned_scene_path == path:
		return
	_warned_scene_path = path
	HFLog.warn("HammerForge: %s names scene '%s', which %s." % [name, path, why])


func _assign_preview(node: Node3D) -> void:
	if not node:
		return
	node.name = "_EditorPreview"
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	node.owner = null
	preview_node = node
	_queue_gizmo_update()


func _clear_preview() -> void:
	var removed_preview := preview_node != null and is_instance_valid(preview_node)
	if preview_node and is_instance_valid(preview_node):
		# Detaching immediately prevents a same-frame class switch from keeping
		# the fixed name reserved or rendering both previews at once.
		if preview_node.get_parent() == self:
			remove_child(preview_node)
		if not preview_node.is_queued_for_deletion():
			preview_node.queue_free()
	preview_node = null
	if removed_preview:
		_queue_gizmo_update()


## Preview aliases can rebuild several internal nodes in one setter cascade.
## Defer one gizmo refresh so native collision and bounds see the final tree.
func _queue_gizmo_update() -> void:
	if _gizmo_update_queued or not is_inside_tree() or not Engine.is_editor_hint():
		return
	_gizmo_update_queued = true
	call_deferred("_flush_gizmo_update")


func _flush_gizmo_update() -> void:
	if not _gizmo_update_queued:
		return
	_gizmo_update_queued = false
	if is_inside_tree() and Engine.is_editor_hint():
		update_gizmos()


func _refresh_editor_gizmo_now() -> void:
	_gizmo_update_queued = false
	if is_inside_tree() and Engine.is_editor_hint():
		update_gizmos()


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
	var filled: Array = []
	for prop in props:
		var prop_name = str(prop.get("name", ""))
		if prop_name == "":
			continue
		if entity_data.has(prop_name):
			continue
		# The coercion the Entity panel and the MCP bridge use, so a property
		# starts at the same value on every path (#1453).
		entity_data[prop_name] = HFEntityPropUtils.coerce_default(
			str(prop.get("type", "")), prop.get("default", null)
		)
		filled.append(prop_name)
	# A new note is signed with the last author, so a name is typed once.
	if entity_type == NOTE_CLASS and filled.has("author") and last_note_author != "":
		entity_data["author"] = last_note_author


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var schema: Array = _get_entity_schema()
	if schema.is_empty():
		return properties
	properties.append({"name": "Entity Props", "type": TYPE_NIL, "usage": PROPERTY_USAGE_CATEGORY})
	for prop in schema:
		var p_name = str(prop.get("name", ""))
		if p_name == "":
			continue
		var prop_type = _type_from_schema(prop.get("type", ""))
		properties.append(
			{"name": "data/" + p_name, "type": prop_type, "usage": PROPERTY_USAGE_DEFAULT}
		)
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
			return HFEntityPropUtils.coerce_default(
				str(prop.get("type", "")), prop.get("default", null)
			)
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
