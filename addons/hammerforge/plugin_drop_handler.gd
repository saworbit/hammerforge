@tool
class_name HFPluginDropHandler
extends RefCounted
## Viewport drag-data classification and entity, brush, prefab, and material drop handling.

const BrushPresetType = preload("brush_preset.gd")
const DraftBrushType = preload("brush_instance.gd")
const HFPrefabType = preload("hf_prefab.gd")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")
# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
const HFTextureFolder = preload("hf_texture_folder.gd")
@warning_ignore_restore("shadowed_global_identifier")


## Whether a drag is one of HammerForge's own: an entity, a brush preset, a prefab
## or a material from the browser. These are taken anywhere over the viewport.
static func can_drop_data(data: Variant) -> bool:
	return (
		is_entity_drag_data(data)
		or is_brush_preset_drag_data(data)
		or is_prefab_drag_data(data)
		or is_material_drag_data(data)
	)


## Whether the plugin takes this drag at `position`: one of its own anywhere, and
## files from the FileSystem dock over a brush face (#1417).
##
## Files are taken only over a face, and only when one of them is a material or
## none of them is something Godot's own viewport drop places. A scene, a mesh or
## a sound still goes where Godot puts it, and a material dropped on a plain mesh
## still goes in that mesh's override slot. An image or any other file over a
## face is taken too, so the drop can say why it paints nothing, rather than
## Godot laying it on the brush's preview mesh, which the next rebuild throws away.
static func can_drop(plugin: Object, position: Vector2, data: Variant) -> bool:
	if can_drop_data(data):
		return true
	if not is_files_drag_data(data):
		return false
	var files := files_of(data)
	if material_path_in(files) == "" and _godot_places_any(files):
		return false
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root or not plugin.last_3d_camera:
		return false
	return not root.pick_face(plugin.last_3d_camera, position).is_empty()


static func drop_data(plugin: Object, position: Vector2, data: Variant) -> void:
	if is_material_drag_data(data):
		handle_material_drop(plugin, position, data)
	elif is_files_drag_data(data):
		handle_files_drop(plugin, position, data)
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
	root.brush_system.give_active_material(info)
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
	# Through the helper, so the drop is in History and ends a run of nudges (#1677).
	var history := (
		Callable(plugin, "_record_history") if plugin.has_method("_record_history") else Callable()
	)
	HFUndoHelper.commit_completed(
		plugin.undo_redo_manager, root, "Place Prefab: %s" % prefab.prefab_name, full_state, history
	)


static func _toast(plugin: Object, text: String) -> void:
	if plugin.dock:
		plugin.dock.show_toast(text, 1)


static func is_material_drag_data(data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "hammerforge_material"


## A drag from Godot's FileSystem dock: `{"type": "files", "files": [paths]}`.
static func is_files_drag_data(data: Variant) -> bool:
	return (
		data is Dictionary
		and str(data.get("type", "")) == "files"
		and not files_of(data).is_empty()
	)


static func files_of(data: Variant) -> Array:
	if not (data is Dictionary):
		return []
	var files: Variant = (data as Dictionary).get("files", [])
	if files is PackedStringArray or files is Array:
		return Array(files)
	return []


## The first path that holds a material a face can wear, or "". These are the two
## kinds Godot's own drop puts on a mesh.
static func material_path_in(files: Array) -> String:
	for path in files:
		var kind := resource_kind(str(path))
		if (
			ClassDB.is_parent_class(kind, "BaseMaterial3D")
			or ClassDB.is_parent_class(kind, "ShaderMaterial")
		):
			return str(path)
	return ""


## The class of the resource saved at `path`, or "" when there is none.
##
## The editor's file system scan already knows it, so asking on every move of a
## drag is a lookup. Outside the editor, as in a test, the file is loaded instead,
## which the resource cache keeps cheap while anything holds it.
static func resource_kind(path: String) -> String:
	if Engine.is_editor_hint():
		var file_system := EditorInterface.get_resource_filesystem()
		if file_system:
			return file_system.get_file_type(path)
	if path == "" or not ResourceLoader.exists(path):
		return ""
	var resource := ResourceLoader.load(path)
	return resource.get_class() if resource else ""


static func _godot_places_any(files: Array) -> bool:
	for path in files:
		var kind := resource_kind(str(path))
		for placed in ["PackedScene", "Mesh", "AudioStream"]:
			if ClassDB.is_parent_class(kind, placed):
				return true
	return false


## A material file from the FileSystem dock, onto the face under the cursor or the
## face selection that face is in. The palette slot already holding the file is
## reused, and the material is added when there is none, in the same undo step as
## the paint (#1417).
##
## An image goes on as the material of its set, as Add Texture Folder makes it:
## its normal and roughness maps found by name beside it, written once and used
## again after (#1884).
static func handle_files_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	var files := files_of(data)
	var path := material_path_in(files)
	var material: Material = null
	if path == "":
		var image := image_path_in(files)
		if image == "":
			_toast(plugin, _refusal_text(files))
			return
		var built := HFTextureFolder.build_for_image(image)
		if (built["materials"] as Array).is_empty():
			_toast(plugin, "%s: %s" % [image.get_file(), HFTextureFolder.report(built)])
			return
		material = built["materials"][0]
		path = material.resource_path
		if Engine.is_editor_hint() and int(built["made"]) > 0:
			var file_system := EditorInterface.get_resource_filesystem()
			if file_system:
				file_system.scan()
	else:
		material = ResourceLoader.load(path) as Material
	if material == null:
		_toast(plugin, "%s could not be loaded as a material" % path.get_file())
		return
	var slot := -1
	if root.material_manager:
		slot = root.material_manager.slot_of_path(path)
	_paint_dropped(plugin, root, position, slot, material)


## The first image among `files`, or "".
static func image_path_in(files: Array) -> String:
	for path in files:
		var kind := resource_kind(str(path))
		if ClassDB.is_parent_class(kind, "Texture") or ClassDB.is_parent_class(kind, "Image"):
			return str(path)
	return ""


## Why a drop of `files` paints nothing.
static func _refusal_text(files: Array) -> String:
	var first := str(files[0]) if not files.is_empty() else ""
	return "%s is not a material a face can wear" % first.get_file()


static func handle_material_drop(plugin: Object, position: Vector2, data: Variant) -> void:
	if not is_material_drag_data(data):
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	if bool(data.get("hidden", false)):
		_hide_dropped(plugin, root, position)
		return
	var mat_idx: int = int(data.get("index", -1))
	if mat_idx < 0:
		return
	if mat_idx >= root.get_materials().size():
		_toast(plugin, "Material #%d is no longer in the palette" % mat_idx)
		return
	_paint_dropped(plugin, root, position, mat_idx, root.material_manager.get_material(mat_idx))


## Paint the face under `position` with the material in palette slot `slot`, or
## every selected face when that face is one of them, as one undo step. A `slot`
## of -1 adds `material` to the palette first, in the same step.
static func _paint_dropped(
	plugin: Object, root: Node, position: Vector2, slot: int, material: Material
) -> void:
	var camera = plugin.last_3d_camera
	if not camera:
		return
	var hit: Dictionary = root.pick_face(camera, position)
	if hit.is_empty():
		_toast(plugin, "No face under drop position")
		return
	var brush: DraftBrushType = hit.get("brush") as DraftBrushType
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0:
		return
	var targets := _drop_targets(root, brush, face_idx)
	if targets.is_empty():
		return
	var adds_slot := slot < 0
	# A brush scope claims that nothing but those brushes changes, so a drop that
	# adds a palette slot records the whole level instead, and one Ctrl+Z takes
	# the slot back with the paint.
	var before := HFUndoHelper.capture_scope_or_state(root, [] if adds_slot else targets.keys())
	if adds_slot:
		slot = root.add_material_to_palette(material)
	var count := 0
	for brush_id in targets:
		# Writes face.material_idx and rebuilds that brush's preview; the palette
		# is read to check the slot is usable and never written (#761).
		root.assign_material_to_faces_by_id(brush_id, targets[brush_id], slot)
		count += (targets[brush_id] as Array).size()
	HFUndoHelper.commit_completed_if_changed(
		plugin._get_undo_redo(),
		root,
		"Drop Material on Face" if count == 1 else "Drop Material on Faces",
		before["state"],
		Callable(plugin, "_record_history"),
		before["scope_ids"]
	)
	HFPluginMaterialCommands.note_material_used(root, root.material_manager.get_material(slot))
	if plugin.dock:
		plugin.dock._selected_material_index = slot
		if plugin.dock.material_browser:
			plugin.dock.material_browser.set_selected_index(slot)
		if count == 1:
			plugin.dock.show_toast("Applied material #%d to face" % slot, 0)
		else:
			plugin.dock.show_toast("Applied material #%d to %d faces" % [slot, count], 0)


## The Hidden swatch dropped on a face (#1719): that face, or every selected face
## when it is one of them, made Hidden as one undo step, as a material applies.
static func _hide_dropped(plugin: Object, root: Node, position: Vector2) -> void:
	var camera = plugin.last_3d_camera
	if not camera:
		return
	var hit: Dictionary = root.pick_face(camera, position)
	if hit.is_empty():
		_toast(plugin, "No face under drop position")
		return
	var brush: DraftBrushType = hit.get("brush") as DraftBrushType
	var face_idx: int = int(hit.get("face_idx", -1))
	if brush == null or face_idx < 0:
		return
	var targets := _drop_targets(root, brush, face_idx)
	if targets.is_empty():
		return
	var before := HFUndoHelper.capture_scope_or_state(root, targets.keys())
	var count: int = root.set_faces_hidden(targets, true)
	HFUndoHelper.commit_completed_if_changed(
		plugin._get_undo_redo(),
		root,
		"Make Face Hidden" if count == 1 else "Make Faces Hidden",
		before["state"],
		Callable(plugin, "_record_history"),
		before["scope_ids"]
	)
	if plugin.dock:
		plugin.dock.show_toast("%d face%s made Hidden" % [count, "" if count == 1 else "s"], 0)


## `{brush_id: [face indices]}` for a drop on face `face_idx` of `brush`: that
## face, or the whole face selection when the face is in it, as Assign does.
##
## Each brush is keyed by the id the dock and the gizmo plugin mint when it is
## still empty. This path used to fall back to the node's instance id, and
## nothing resolves one: assign_material_to_faces_by_id() looks brushes up by id
## only, so the drop found no brush and returned. An instance id would not have
## survived the undo record either, because a rebuilt brush gets a new one. An
## empty key would match the first brush that has no id, so it is left out.
static func _drop_targets(root: Node, brush: DraftBrushType, face_idx: int) -> Dictionary:
	var selection: Dictionary = root.face_selection
	# Read before an id is minted: the selection files a brush with no id under
	# its instance id.
	var picked: Array = selection.get(HFBrushSystemType.face_key(brush), [])
	var in_selection := false
	for index in picked:
		if int(index) == face_idx:
			in_selection = true
	var targets := {}
	if not in_selection:
		var brush_id := _minted_id(root, brush)
		if brush_id != "":
			targets[brush_id] = [face_idx]
		return targets
	for key in selection:
		var selected: DraftBrushType = root._find_brush_by_key(str(key))
		if selected == null:
			continue
		var brush_id := _minted_id(root, selected)
		if brush_id == "":
			continue
		var indices: Array = targets.get(brush_id, [])
		for index in selection[key]:
			var face := int(index)
			if face >= 0 and face < selected.faces.size() and not indices.has(face):
				indices.append(face)
		if not indices.is_empty():
			targets[brush_id] = indices
	return targets


static func _minted_id(root: Node, brush: DraftBrushType) -> String:
	return str(root.get_brush_info_from_node(brush).get("brush_id", ""))
