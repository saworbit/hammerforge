@tool
class_name HFDecalTool
extends "hf_editor_tool.gd"

## Place decals on surfaces via raycast.
##
## Click a surface to spawn a Godot Decal node oriented to the hit normal.
## Configure texture, size, and fade distance through the tool settings panel.

var _preview_decal: Decal = null


func tool_name() -> String:
	return "Decal"


func tool_id() -> int:
	return 101


func tool_shortcut_key() -> int:
	return KEY_N


func can_activate(p_root: Node3D) -> bool:
	return p_root != null


func activate(p_root: Node3D, p_camera: Camera3D) -> void:
	super.activate(p_root, p_camera)


func deactivate() -> void:
	_remove_preview()
	super.deactivate()


func get_settings_schema() -> Array:
	return [
		{
			"name": "texture",
			"type": "string",
			"label": "Texture Path",
			"default": "",
		},
		{
			"name": "size",
			"type": "float",
			"label": "Decal Size",
			"default": 2.0,
			"min": 0.1,
			"max": 50.0,
		},
		{
			"name": "fade",
			"type": "float",
			"label": "Fade Distance",
			"default": 4.0,
			"min": 0.1,
			"max": 100.0,
		},
	]


func handle_input(event: InputEvent, camera: Camera3D, mouse_pos: Vector2) -> int:
	if not root or not camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Escape cancels / exits
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_remove_preview()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Left click places a decal
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit = _raycast_surface(camera, mouse_pos)
		if hit.is_empty():
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_place_decal(hit.position, hit.normal)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Mouse motion updates a preview decal
	if event is InputEventMouseMotion:
		var hit = _raycast_surface(camera, mouse_pos)
		if hit.is_empty():
			_remove_preview()
		else:
			_update_preview(hit.position, hit.normal)
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func handle_keyboard(event: InputEventKey) -> int:
	if event.pressed and event.keycode == KEY_ESCAPE:
		_remove_preview()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func get_shortcut_hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("-- Decal Tool --")
	lines.append("Click: Place decal")
	lines.append("Esc: Exit / N: Exit")
	return lines


# ---------------------------------------------------------------------------
# Raycasting
# ---------------------------------------------------------------------------


## Raycast into the scene and return the hit dictionary (position + normal).
## Returns an empty Dictionary on miss.
func _raycast_surface(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	if not root:
		return {}
	var space_state = root.get_world_3d().direct_space_state if root.get_world_3d() else null
	if not space_state:
		return {}
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_origin + ray_dir * 10000.0
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	return result


# ---------------------------------------------------------------------------
# Decal placement
# ---------------------------------------------------------------------------


func _place_decal(position: Vector3, normal: Vector3) -> void:
	if not root:
		return
	var decal_size: float = get_setting("size")
	var fade: float = get_setting("fade")
	var tex_path: String = get_setting("texture")

	var decal := Decal.new()
	decal.name = "HFDecal"
	decal.set_meta("hf_decal", true)

	# Decal projects along its local -Y axis. We need to orient -Y toward the
	# surface (i.e., local +Y away from the surface, aligned with the normal).
	decal.size = Vector3(decal_size, fade, decal_size)

	# Load texture if a valid path is provided
	if tex_path != "":
		var tex = load(tex_path)
		if tex is Texture2D:
			decal.texture_albedo = tex

	root.add_child(decal)
	decal.owner = root.owner if root.owner else root

	# Position and orient
	decal.global_position = position + normal * 0.01  # slight offset to avoid z-fight
	_orient_decal(decal, normal)


func _orient_decal(decal: Decal, normal: Vector3) -> void:
	# Decal projects along local -Y. We want local +Y = surface normal.
	# Build a basis where Y = normal.
	var up = normal.normalized()
	# Pick an arbitrary right vector that isn't parallel to up
	var right: Vector3
	if abs(up.dot(Vector3.UP)) < 0.99:
		right = up.cross(Vector3.UP).normalized()
	else:
		right = up.cross(Vector3.FORWARD).normalized()
	var forward = right.cross(up).normalized()
	decal.global_basis = Basis(right, up, forward)


# ---------------------------------------------------------------------------
# Preview decal (transient, not saved)
# ---------------------------------------------------------------------------


func _update_preview(position: Vector3, normal: Vector3) -> void:
	if not root:
		return
	if not _preview_decal or not is_instance_valid(_preview_decal):
		_preview_decal = Decal.new()
		_preview_decal.name = "_HFDecalPreview"
		_preview_decal.set_meta("hf_decal_preview", true)
		# Make preview semi-transparent
		_preview_decal.modulate = Color(1.0, 1.0, 1.0, 0.5)
		root.add_child(_preview_decal)

	var decal_size: float = get_setting("size")
	var fade: float = get_setting("fade")
	var tex_path: String = get_setting("texture")

	_preview_decal.size = Vector3(decal_size, fade, decal_size)
	if tex_path != "":
		var tex = load(tex_path)
		if tex is Texture2D:
			_preview_decal.texture_albedo = tex
		else:
			_preview_decal.texture_albedo = null
	else:
		_preview_decal.texture_albedo = null

	_preview_decal.global_position = position + normal * 0.01
	_orient_decal(_preview_decal, normal)


func _remove_preview() -> void:
	if _preview_decal and is_instance_valid(_preview_decal):
		_preview_decal.get_parent().remove_child(_preview_decal)
		_preview_decal.queue_free()
		_preview_decal = null
