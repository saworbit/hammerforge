@tool
class_name HFPluginDropHandler
extends RefCounted
## Viewport drag-data classification and entity, brush, prefab, and material drop handling.

const BrushPresetType = preload("brush_preset.gd")
const DraftBrushType = preload("brush_instance.gd")
const HFPrefabType = preload("hf_prefab.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")


static func can_drop_data(data: Variant) -> bool:
	return (
		is_entity_drag_data(data)
		or is_brush_preset_drag_data(data)
		or is_prefab_drag_data(data)
		or is_material_drag_data(data)
	)


static func drop_data(plugin: Object, position: Vector2, data: Variant) -> void:
	if is_material_drag_data(data):
		handle_material_drop(plugin, position, data)
	elif is_brush_preset_drag_data(data):
		handle_brush_preset_drop(plugin, position, data)
	elif is_prefab_drag_data(data):
		handle_prefab_drop(plugin, position, data)
	else:
		handle_entity_drop(plugin, position, data)


static func is_entity_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_entity"


static func handle_entity_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	if not is_entity_drag_data(data):
		return
	var entity_id = str(data.get("entity_id", ""))
	if entity_id == "":
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		root = plugin._create_level_root()
	if not root:
		return
	var camera = plugin.last_3d_camera
	var mouse_pos = position if position != null else plugin.last_3d_mouse_pos
	if camera and root:
		var entity = root.place_entity_at_screen(camera, mouse_pos, entity_id)
		var preset: Variant = data.get("properties", {})
		if entity and preset is Dictionary and not (preset as Dictionary).is_empty():
			root.set_entity_properties(entity, preset)
		if entity:
			var selection = plugin.get_editor_interface().get_selection()
			if selection:
				selection.clear()
				selection.add_node(entity)
			plugin.hf_selection.clear()
			plugin.hf_selection.append(entity)


static func is_brush_preset_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_brush_preset"


static func handle_brush_preset_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	if not is_brush_preset_drag_data(data):
		return
	var preset_path = str(data.get("preset_path", ""))
	if preset_path == "":
		return
	var preset = load(preset_path)
	if not preset or not (preset is BrushPresetType):
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		root = plugin._create_level_root()
	if not root:
		return
	var camera = plugin.last_3d_camera
	var mouse_pos = position if position != null else plugin.last_3d_mouse_pos
	if not camera:
		return
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var point = root._snap_point(hit.get("position", Vector3.ZERO))
	var size = preset.size
	var center = point + Vector3(0, size.y * 0.5, 0)
	var operation = preset.operation
	var info = {
		"shape": preset.shape,
		"size": size,
		"center": center,
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		"brush_id": root._next_brush_id()
	}
	if root._shape_uses_sides(preset.shape):
		info["sides"] = preset.sides
	var mat = plugin.dock.get_active_material() if plugin.dock else null
	if mat:
		info["material"] = mat
	plugin._commit_brush_placement(root, info)


static func is_prefab_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_prefab"


static func handle_prefab_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	if not is_prefab_drag_data(data):
		return
	var prefab_path = str(data.get("path", ""))
	if prefab_path == "":
		return
	var prefab = HFPrefabType.load_from_file(prefab_path)
	if not prefab:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		root = plugin._create_level_root()
	if not root:
		return
	var mouse_pos = position if position != null else plugin.last_3d_mouse_pos
	var point = _point_under(plugin, root, mouse_pos)
	if point == null:
		return
	place_prefab(plugin, root, prefab, prefab_path, point)


## Place the prefab selected in the Prefab Library at the point under the cursor,
## as a drop of it there would. The viewport menu's Place Selected Prefab, and the
## arm of `place_prefab`, whose parameter form the agent bridge runs (#1301).
static func place_selected_prefab(plugin: Object, root: Node) -> void:
	var library = plugin.dock.get("_prefab_library") if plugin.dock else null
	var prefab_path: String = library.get_selected_path() if library else ""
	if prefab_path == "":
		_toast(plugin, "Select a prefab in the Prefab Library first")
		return
	var prefab = HFPrefabType.load_from_file(prefab_path)
	if prefab == null:
		_toast(plugin, "%s is not a prefab this build can read" % prefab_path.get_file())
		return
	var point = _point_under(plugin, root, plugin.last_3d_mouse_pos)
	if point == null:
		_toast(plugin, "Point at a surface in the viewport to place the prefab there")
		return
	place_prefab(plugin, root, prefab, prefab_path, point)


## Where a prefab dropped at `mouse_pos` lands: the surface under it, snapped. Null
## when there is no camera or nothing under the cursor.
static func _point_under(plugin: Object, root: Node, mouse_pos) -> Variant:
	var camera = plugin.last_3d_camera
	if not camera or mouse_pos == null:
		return null
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return null
	return root._snap_point(hit.get("position", Vector3.ZERO))


## Place a library prefab at `point`, unturned and unlinked, as one undo step.
static func place_prefab(
	plugin: Object, root: Node, prefab: HFPrefabType, prefab_path: String, point: Vector3
) -> void:
	if root.prefab_system == null:
		return
	var full_state = root.state_system.capture_state(true)
	var placed: Dictionary = root.prefab_system.place(
		prefab, prefab_path, Transform3D(Basis.IDENTITY, point)
	)
	if placed.is_empty():
		return
	var undo_redo = plugin.undo_redo_manager
	if undo_redo:
		undo_redo.create_action("Place Prefab: %s" % prefab.prefab_name)
		undo_redo.add_do_method(
			root.state_system, "restore_state", root.state_system.capture_state(true)
		)
		undo_redo.add_undo_method(root.state_system, "restore_state", full_state)
		undo_redo.commit_action(false)


static func _toast(plugin: Object, text: String) -> void:
	if plugin.dock:
		plugin.dock.show_toast(text, 1)


static func is_material_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_material"


static func handle_material_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	if not is_material_drag_data(data):
		return
	var mat_idx: int = int(data.get("index", -1))
	if mat_idx < 0:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	var camera = plugin.last_3d_camera
	var mouse_pos = position if position != null else plugin.last_3d_mouse_pos
	if not camera:
		return
	var hit: Dictionary = root.pick_face(camera, mouse_pos)
	if hit.is_empty():
		if plugin.dock:
			plugin.dock.show_toast("No face under drop position", 1)
		return
	var brush: DraftBrushType = hit.get("brush") as DraftBrushType
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0:
		return
	# The same mint the dock and the gizmo plugin ask for when a brush's id is
	# still empty. This site used to fall back to the node's instance id instead,
	# and nothing resolves one: assign_material_to_faces_by_id() looks brushes up
	# by id only, so the drop found no brush and returned. An instance id would
	# not have survived the undo record either, because a rebuilt brush gets a
	# new one and the redo would aim at a freed node.
	# An empty key would match the first brush that has no id, so it is refused.
	var brush_key: String = str(root.get_brush_info_from_node(brush).get("brush_id", ""))
	if brush_key == "":
		return
	# One brush, one face. assign_material_to_faces_by_id() writes face.material_idx
	# and rebuilds that brush's preview; the palette is read to check the slot is
	# usable and never written (#761).
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Drop Material on Face",
		"assign_material_to_faces_by_id",
		[brush_key, [face_idx], mat_idx],
		false,
		Callable(plugin, "_record_history"),
		"",
		false,
		[brush_key]
	)
	if plugin.dock:
		plugin.dock._selected_material_index = mat_idx
		if plugin.dock.material_browser:
			plugin.dock.material_browser.set_selected_index(mat_idx)
		plugin.dock.show_toast("Applied material #%d to face" % mat_idx, 0)
