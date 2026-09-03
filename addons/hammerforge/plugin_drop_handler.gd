@tool
class_name HFPluginDropHandler
extends RefCounted
## Viewport drag-data classification and entity, brush, prefab, and material drop handling.

const BrushPresetType = preload("brush_preset.gd")
const DraftBrushType = preload("brush_instance.gd")
const HFPrefabType = preload("hf_prefab.gd")
const HFUndoHelper = preload("undo_helper.gd")


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
	var camera = plugin.last_3d_camera
	var mouse_pos = position if position != null else plugin.last_3d_mouse_pos
	if not camera:
		return
	var hit = root._raycast(camera, mouse_pos)
	if hit.is_empty():
		return
	var point = root._snap_point(hit.get("position", Vector3.ZERO))
	var full_state = root.state_system.capture_state(true)
	var result = prefab.instantiate(root.brush_system, root.entity_system, root, point)
	var placed_anything: bool = (
		not result.get("brush_ids", []).is_empty() or result.get("entity_count", 0) > 0
	)
	if placed_anything:
		if root.prefab_system:
			root.prefab_system.register_instance(
				prefab_path, result.get("brush_ids", []), result.get("entity_nodes", []), false
			)
		var undo_redo = plugin.undo_redo_manager
		if undo_redo:
			undo_redo.create_action("Place Prefab: %s" % prefab.prefab_name)
			undo_redo.add_do_method(
				root.state_system, "restore_state", root.state_system.capture_state(true)
			)
			undo_redo.add_undo_method(root.state_system, "restore_state", full_state)
			undo_redo.commit_action(false)


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
	var brush_key: String = brush.brush_id if brush.brush_id != "" else str(brush.get_instance_id())
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Drop Material on Face",
		"assign_material_to_faces_by_id",
		[brush_key, [face_idx], mat_idx],
		false,
		Callable(plugin, "_record_history")
	)
	if plugin.dock:
		plugin.dock._selected_material_index = mat_idx
		if plugin.dock.material_browser:
			plugin.dock.material_browser.set_selected_index(mat_idx)
		plugin.dock.show_toast("Applied material #%d to face" % mat_idx, 0)
