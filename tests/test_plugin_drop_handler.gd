extends GutTest

const DropHandler = preload("res://addons/hammerforge/plugin_drop_handler.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const BrushPresetScript = preload("res://addons/hammerforge/brush_preset.gd")
const HFPrefabScript = preload("res://addons/hammerforge/hf_prefab.gd")
const HFTextureFolderScript = preload("res://addons/hammerforge/hf_texture_folder.gd")
## Written by the brush preset and prefab drops below, and taken away again.
const PRESET_PATH := "user://hf_drop_test_preset.tres"
const PREFAB_PATH := "user://hf_drop_test.hfprefab"
## A scratch library for Place Selected Prefab, and taken away again.
const LIBRARY := "user://hf_drop_test_library"
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)
## A corner of the rig's viewport, where the camera sees nothing but sky.
const SKY := Vector2(5, 5)
## An image the project imports, as the FileSystem dock would drag one.
const IMAGE_PATH := "res://icon.svg"
const BRICK_ALBEDO_PATH := "res://tests/fixtures/texture_folder/brick_albedo.png"
const BRICK_NORMAL_PATH := "res://tests/fixtures/texture_folder/brick_normal.png"

var rig := PluginRig.new()
## A material saved to a file for the FileSystem drops, and taken away again.
## Named for the process, as `user://` is shared with every checkout of the
## project that runs tests at the same time.
var material_path := "user://hf_drop_test_material_%d.tres" % OS.get_process_id()


func before_all():
	await rig.bring_up(self, true)
	# The operation replay overlay is where the history shows without an undo
	# manager.
	rig.plugin._install_power_user_overlays()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.3, 0.1)
	assert_eq(ResourceSaver.save(material, material_path), OK)


func after_all():
	await rig.take_down()
	for path in [PRESET_PATH, PREFAB_PATH, LIBRARY.path_join("crate.hfprefab"), material_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(LIBRARY):
		DirAccess.remove_absolute(LIBRARY)


## The editor asks before a drop and only drops over the viewport, after the
## pointer has moved there, so the plugin has seen the camera.
func _drop(data: Dictionary) -> void:
	rig.forward(PluginRig.motion(AIM))
	assert_true(rig.plugin._can_drop_data(AIM, data), "the plugin takes %s" % data["type"])
	rig.plugin._drop_data(AIM, data)


## Enough of the plugin for `handle_material_drop()` to run. It reads the root,
## the camera and the undo manager off the plugin, and reports through the dock,
## which is left null so the toast path is skipped.
class FakePlugin:
	extends RefCounted

	var active_root: Node = null
	var last_3d_camera: Camera3D = null
	var last_3d_mouse_pos := Vector2.ZERO
	var dock = null

	func _get_level_root() -> Node:
		return active_root

	func _get_undo_redo():
		return null

	func _record_history(_action_name: String) -> void:
		pass


func test_drop_data_classification_accepts_only_supported_payloads() -> void:
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_entity"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_brush_preset"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_prefab"}))
	assert_true(DropHandler.can_drop_data({"type": "hammerforge_material"}))
	assert_false(DropHandler.can_drop_data({"type": "files"}))
	assert_false(DropHandler.can_drop_data({}))
	assert_false(DropHandler.can_drop_data(null))


func test_the_plugin_takes_what_the_drop_handler_takes() -> void:
	# Godot calls `_can_drop_data` and `_drop_data` on the plugin, and those two
	# are the whole of the viewport drop path it owns (#609).
	for kind in [
		"hammerforge_entity",
		"hammerforge_brush_preset",
		"hammerforge_prefab",
		"hammerforge_material",
	]:
		assert_true(rig.plugin._can_drop_data(AIM, {"type": kind}), "the plugin takes %s" % kind)
	assert_false(rig.plugin._can_drop_data(AIM, {"type": "files"}), "and nothing else")
	assert_false(rig.plugin._can_drop_data(AIM, {}))


func test_plugin_gd_does_not_classify_payloads_itself() -> void:
	# A grep on purpose. The drops above prove the plugin hands each payload on;
	# this keeps a second copy of the classification out of plugin.gd, which a
	# drop that works cannot show (#609).
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for payload in [
		"hammerforge_entity",
		"hammerforge_brush_preset",
		"hammerforge_prefab",
		"hammerforge_material",
	]:
		assert_false(
			source.contains(payload),
			"plugin.gd does not classify %s itself; the drop handler does" % payload
		)


## An entity dropped into a scene with no level makes the level, lands there,
## and is what is selected afterwards.
func test_an_entity_drop_makes_a_level_and_selects_what_it_placed() -> void:
	assert_eq(rig.level_roots(), 0, "the scene starts empty")
	_drop({"type": "hammerforge_entity", "entity_id": "light_point"})
	assert_eq(rig.level_roots(), 1, "the drop made a level")
	var level = rig.scene_root.get_node("LevelRoot")
	assert_eq(level.entities_node.get_child_count(), 1, "and placed the entity in it")
	var entity = level.entities_node.get_child(0)
	assert_eq(rig.plugin.stand_in_editor.selection.get_selected_nodes(), [entity], "selected")
	await rig.leave_level(level)


func test_a_brush_preset_drop_places_the_preset_on_the_ground() -> void:
	var preset := BrushPresetScript.new()
	preset.size = Vector3(8, 6, 4)
	assert_eq(ResourceSaver.save(preset, PRESET_PATH), OK)
	var level = await rig.make_level()
	_drop({"type": "hammerforge_brush_preset", "preset_path": PRESET_PATH})
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "a brush was placed")
	var brush = level.draft_brushes_node.get_child(0)
	assert_eq(brush.size, Vector3(8, 6, 4), "at the preset's size")
	assert_almost_eq(brush.global_position.y, 3.0, 0.01, "standing on the ground")
	await rig.leave_level(level)


func test_a_prefab_drop_places_the_prefab_and_records_the_instance() -> void:
	var level = await rig.make_level()
	var source = rig.box(level, "source", Vector3(20, 2, 0))
	var prefab = HFPrefabScript.capture_from_selection(
		level.brush_system, level.entity_system, [source], []
	)
	assert_eq(prefab.save_to_file(PREFAB_PATH), OK)
	level.delete_brush(source)
	_drop({"type": "hammerforge_prefab", "path": PREFAB_PATH})
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "the prefab's brush was placed")
	assert_eq(
		level.prefab_system.get_instances_for_source(PREFAB_PATH).size(),
		1,
		"and the placement is recorded as an instance of its file"
	)
	await rig.leave_level(level)


func test_a_material_drop_paints_the_face_under_the_pointer() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var hit: Dictionary = level.pick_face(rig.camera, AIM)
	assert_eq(hit.get("brush"), brush, "the camera looks at the brush")
	var recorded: int = rig.plugin._operation_replay._entries.size()
	_drop({"type": "hammerforge_material", "index": 1})
	assert_eq(brush.faces[int(hit["face_idx"])].material_idx, 1, "the face took the material")
	assert_has(rig.toasts(), "Applied material #1 to face")
	var entries: Array = rig.plugin._operation_replay._entries.slice(recorded)
	assert_eq(entries.size(), 1, "the drop went into the history")
	if entries.size() == 1:
		assert_eq(entries[0]["name"], "Drop Material on Face")
	await rig.leave_level(level)


## A prefab drop is one undo step named for the prefab, Ctrl+Z takes the piece
## away again, and Ctrl+Shift+Z puts it back.
func test_a_prefab_drop_opens_one_named_undo_step() -> void:
	var level = await rig.make_level()
	var source = rig.box(level, "source", Vector3(20, 2, 0))
	var prefab = HFPrefabScript.capture_from_selection(
		level.brush_system, level.entity_system, [source], []
	)
	assert_eq(prefab.save_to_file(PREFAB_PATH), OK)
	level.delete_brush(source)
	var undo = rig.undo()
	undo.clear()
	_drop({"type": "hammerforge_prefab", "path": PREFAB_PATH})
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "the piece was placed")
	assert_eq(undo.step_count(), 1, "in one undo step")
	assert_true(
		undo.scene_history.get_current_action_name().begins_with("Place Prefab:"),
		"named for what it placed"
	)
	undo.press_undo()
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 0, "Ctrl+Z takes it away")
	undo.press_redo()
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "and Ctrl+Shift+Z puts it back")
	await rig.leave_level(level)


## The library pointed at a scratch folder holding one prefab, a box, selected or
## not.
func _library_with_a_crate(level: Node, selected: bool) -> Object:
	var source = rig.box(level, "source", Vector3(20, 2, 0))
	var prefab = HFPrefabScript.capture_from_selection(
		level.brush_system, level.entity_system, [source], []
	)
	prefab.prefab_name = "crate"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LIBRARY))
	assert_eq(prefab.save_to_file(LIBRARY.path_join("crate.hfprefab")), OK)
	level.delete_brush(source)
	var library = rig.plugin.dock._prefab_library
	library._prefab_dir = LIBRARY
	library.refresh()
	library._file_list.deselect_all()
	if selected:
		library._file_list.select(0)
	return library


## Place Selected Prefab, from the viewport's Space menu: the prefab selected in
## the library goes where the cursor is, as a drop there puts it, in one undo step
## named as a drop's is (#1301).
func test_place_selected_prefab_puts_the_library_selection_under_the_cursor() -> void:
	var level = await rig.make_level()
	_library_with_a_crate(level, true)
	var undo = rig.undo()
	undo.clear()
	rig.forward(PluginRig.motion(AIM))
	rig.plugin._dispatch_viewport_action("place_prefab")
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "the crate was placed")
	assert_eq(
		level.prefab_system.get_instances_for_source(LIBRARY.path_join("crate.hfprefab")).size(),
		1,
		"as a copy of its file"
	)
	assert_eq(undo.step_count(), 1, "in one undo step")
	assert_eq(undo.scene_history.get_current_action_name(), "Place Prefab: crate")
	await rig.leave_level(level)


func test_place_selected_prefab_with_nothing_selected_says_so() -> void:
	var level = await rig.make_level()
	_library_with_a_crate(level, false)
	rig.clear_toasts()
	rig.forward(PluginRig.motion(AIM))
	rig.plugin._dispatch_viewport_action("place_prefab")
	assert_eq(level.draft_brushes_node.get_child_count(), 0, "nothing placed")
	assert_has(rig.toasts(), "Select a prefab in the Prefab Library first")
	await rig.leave_level(level)


## A material dropped on a brush that has never been captured into a level state.
##
## `brush_id` is minted lazily, so a brush placed and not yet recorded has none,
## and this path used to fall back to the instance id. Nothing resolves that:
## `assign_material_to_faces_by_id()` looks brushes up by id only, so the drop
## silently did nothing, and an instance id could not have survived an undo that
## rebuilt the brush anyway. The id is minted at the drop instead (#761).
func test_dropping_a_material_on_a_brush_with_no_id_still_paints_the_face() -> void:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"transform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
			}
		)
	)
	# The lazy id, taken back off the node so the drop meets the case it guards.
	brush.brush_id = ""
	if brush.has_meta("brush_id"):
		brush.remove_meta("brush_id")

	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	camera.global_position = Vector3(0, 0, 256)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var aim := camera.unproject_position(Vector3.ZERO)

	var plugin := FakePlugin.new()
	plugin.active_root = root
	plugin.last_3d_camera = camera

	var hit: Dictionary = root.pick_face(camera, aim)
	assert_false(hit.is_empty(), "the camera has to be looking at the brush")
	var face_idx: int = int(hit.get("face_idx", -1))

	DropHandler.handle_material_drop(plugin, aim, {"type": "hammerforge_material", "index": 1})
	assert_eq(
		brush.faces[face_idx].material_idx,
		1,
		"the face under the drop takes the material, so the key the drop built resolved"
	)
	assert_ne(brush.brush_id, "", "and the brush is left with an id an undo can replay")


# ---------------------------------------------------------------------------
# Files from the FileSystem dock (#1417)
# ---------------------------------------------------------------------------


func _files(paths: Array) -> Dictionary:
	return {"type": "files", "files": PackedStringArray(paths)}


func _face_idx(brush: Node, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.is_equal_approx(normal):
			return i
	return -1


## The brush with id `id`, looked up again, as an undo can rebuild it.
func _brush(level: Node, id: String) -> Node:
	return level._find_brush_by_key(id)


func test_a_material_file_dropped_on_a_face_paints_it_and_joins_the_palette() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var front := _face_idx(brush, Vector3.BACK)
	assert_eq(int(level.pick_face(rig.camera, AIM).get("face_idx", -1)), front, "aimed at")
	var was: int = brush.faces[front].material_idx
	var used: Array = []
	level.material_used.connect(func(material: Material): used.append(material))
	var undo = rig.undo()
	undo.clear()
	_drop(_files([material_path]))
	var palette: Array = level.get_materials()
	assert_eq(palette.size(), 3, "the material joined the palette once")
	assert_eq(palette[2].resource_path, material_path, "as the file")
	assert_eq(brush.faces[front].material_idx, 2, "and the face wears it")
	assert_eq(used, [palette[2]], "a drop is a use, so Recent fills")
	assert_has(rig.toasts(), "Applied material #2 to face")
	assert_eq(undo.step_count(), 1, "in one undo step")
	undo.press_undo()
	await rig.frame()
	assert_eq(level.get_materials().size(), 2, "one Ctrl+Z takes the slot back")
	assert_eq(_brush(level, "target").faces[front].material_idx, was, "and the paint with it")
	undo.press_redo()
	await rig.frame()
	assert_eq(level.get_materials().size(), 3, "Ctrl+Shift+Z puts both back")
	assert_eq(_brush(level, "target").faces[front].material_idx, 2)
	await rig.leave_level(level)


func test_a_material_file_the_palette_holds_reuses_its_slot() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), load(material_path), StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var front := _face_idx(brush, Vector3.BACK)
	_drop(_files([IMAGE_PATH, material_path]))
	assert_eq(level.get_materials().size(), 3, "nothing was added")
	assert_eq(brush.faces[front].material_idx, 1, "the slot holding the file was used")
	await rig.leave_level(level)


## A drop on a face that is in the face selection paints the whole selection, the
## file and the browser's drag alike. One on a face outside it paints that face.
func test_a_drop_on_a_selected_face_paints_every_selected_face() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var target = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var other = rig.box(level, "other", Vector3(20, 0, 0), Vector3(8, 8, 8))
	var front := _face_idx(target, Vector3.BACK)
	var top := _face_idx(target, Vector3.UP)
	var side := _face_idx(other, Vector3.BACK)
	level.face_selection = {"target": [front, top], "other": [side]}
	level.face_selection_changed.emit()
	var undo = rig.undo()
	undo.clear()
	_drop(_files([material_path]))
	for picked in [[target, front], [target, top], [other, side]]:
		assert_eq(picked[0].faces[picked[1]].material_idx, 2, "every selected face took it")
	assert_eq(target.faces[_face_idx(target, Vector3.DOWN)].material_idx, -1, "and no other")
	assert_has(rig.toasts(), "Applied material #2 to 3 faces")
	assert_eq(undo.step_count(), 1, "in one undo step")
	undo.press_undo()
	await rig.frame()
	assert_eq(_brush(level, "target").faces[front].material_idx, -1, "which takes all of it back")
	assert_eq(_brush(level, "target").faces[top].material_idx, -1)
	assert_eq(_brush(level, "other").faces[side].material_idx, -1)
	# The browser's drag follows the same rule.
	level.face_selection = {"target": [front, top], "other": [side]}
	level.face_selection_changed.emit()
	_drop({"type": "hammerforge_material", "index": 1})
	for picked in [["target", front], ["target", top], ["other", side]]:
		assert_eq(_brush(level, picked[0]).faces[picked[1]].material_idx, 1, "from the browser")
	# Outside the selection, only the face under the cursor.
	level.face_selection = {"target": [top], "other": [side]}
	level.face_selection_changed.emit()
	_drop({"type": "hammerforge_material", "index": 0})
	assert_eq(_brush(level, "target").faces[front].material_idx, 0, "the face dropped on")
	assert_eq(_brush(level, "target").faces[top].material_idx, 1, "and not the selection")
	assert_eq(_brush(level, "other").faces[side].material_idx, 1)
	await rig.leave_level(level)


## An image goes on as the material of its set (#1884): the one Add Texture
## Folder makes, its normal and roughness maps found by name beside it, written
## once, added to the palette and painted in one step. A second drop of any
## file of that set uses the same slot. A file that is no image and no material
## is refused, and changes nothing.
func test_a_dropped_image_paints_the_face_with_its_sets_material() -> void:
	_empty_texture_folder_output()
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var front := _face_idx(brush, Vector3.BACK)
	var undo = rig.undo()
	undo.clear()
	_drop(_files([BRICK_NORMAL_PATH]))
	assert_eq(level.get_materials().size(), 2, "the brick joins the palette")
	var brick = level.get_materials()[1] as StandardMaterial3D
	assert_eq(brick.resource_name, "brick")
	assert_not_null(brick.albedo_texture, "with its albedo")
	assert_true(brick.normal_enabled and brick.normal_texture != null, "its normal map")
	assert_not_null(brick.roughness_texture, "and its roughness map")
	assert_eq(_brush(level, "target").faces[front].material_idx, 1, "and the face wears it")
	assert_eq(undo.step_count(), 1, "one step")
	undo.press_undo()
	assert_eq(level.get_materials().size(), 1, "undo takes the slot back")
	assert_eq(_brush(level, "target").faces[front].material_idx, -1, "and the paint")
	undo.press_redo()
	_drop(_files([BRICK_ALBEDO_PATH]))
	assert_eq(level.get_materials().size(), 2, "another file of the set uses the same slot")
	assert_eq(_brush(level, "target").faces[front].material_idx, 1)
	await rig.leave_level(level)


func test_a_dropped_file_that_is_no_material_or_image_is_refused_with_a_toast() -> void:
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	var front := _face_idx(brush, Vector3.BACK)
	var undo = rig.undo()
	undo.clear()
	_drop(_files(["res://project.godot"]))
	assert_has(rig.toasts(), "project.godot is not a material a face can wear")
	assert_eq(level.get_materials().size(), 1, "the palette is as it was")
	assert_eq(brush.faces[front].material_idx, -1, "and so is the face")
	assert_eq(undo.step_count(), 0, "and nothing went into the history")
	await rig.leave_level(level)


func _empty_texture_folder_output() -> void:
	var dir: String = HFTextureFolderScript.write_dir
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))


## What Godot's own viewport drop places stays Godot's, and so does anything let go
## away from a brush face.
func test_files_off_a_face_or_that_godot_places_are_left_to_the_viewport() -> void:
	var level = await rig.make_level()
	rig.box(level, "target", Vector3.ZERO, Vector3(8, 8, 8))
	rig.forward(PluginRig.motion(AIM))
	assert_false(
		rig.plugin._can_drop_data(AIM, _files(["res://level_root.tscn"])), "a scene instances"
	)
	assert_false(rig.plugin._can_drop_data(SKY, _files([material_path])), "nothing under it")
	assert_false(rig.plugin._can_drop_data(SKY, _files([IMAGE_PATH])))
	assert_false(rig.plugin._can_drop_data(AIM, {"type": "files", "files": []}), "no files")
	assert_true(rig.plugin._can_drop_data(AIM, _files([material_path])), "a material on a face")
	await rig.leave_level(level)
