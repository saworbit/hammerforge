extends GutTest

## The command surfaces the cutting tools are reachable from, and the contracts
## that keep them wired.
##
## Undo dispatches by method name on LevelRoot and silently does nothing when the
## lookup fails, so a rename would leave a cut working and its undo entry missing.

const HFKeymap = preload("res://addons/hammerforge/hf_keymap.gd")
const HFPluginCommands = preload("res://addons/hammerforge/plugin_commands.gd")
const HFConvexClipScript = preload("res://addons/hammerforge/hf_convex_clip.gd")


func test_level_root_exposes_the_methods_undo_dispatches_by_name():
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	for method_name in [
		"clip_brush_by_id",
		"clip_brush_by_plane",
		"clip_brush_to_face_plane",
		"can_clip_brush",
		"carve_with_brush",
	]:
		assert_true(root.has_method(method_name), "LevelRoot must expose %s" % method_name)


func test_clip_to_face_is_dispatched_and_requires_a_level():
	assert_true(
		HFPluginCommands.requires_existing_root("clip_to_face"),
		"a cut changes scene content, so it must not create a level as a side effect"
	)
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_commands.gd")
	assert_true(source.contains('"clip_to_face":'))
	assert_true(source.contains("plugin._clip_to_face_plane_selected(root)"))


func test_the_plugin_callback_is_a_thin_delegate():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.contains("HFPluginEditActions.clip_to_face_plane_selected"))


func test_clip_to_face_has_a_binding_a_label_and_no_collision():
	var keymap := HFKeymap.new()
	keymap._bindings = HFKeymap._default_bindings()
	var bindings: Dictionary = keymap.get_all_bindings()
	assert_true(bindings.has("clip_to_face"), "the command needs a shortcut")
	assert_ne(keymap.get_display_string("clip_to_face"), "?")
	assert_eq(HFKeymap.get_action_label("clip_to_face"), "Clip to Face Plane")
	var binding: Dictionary = bindings["clip_to_face"]
	for other in bindings:
		if other == "clip_to_face":
			continue
		var same := true
		for key in ["keycode", "ctrl", "shift", "alt", "meta"]:
			var fallback: Variant = 0 if key == "keycode" else false
			if binding.get(key, fallback) != bindings[other].get(key, fallback):
				same = false
				break
		assert_false(same, "clip_to_face collides with %s" % other)


func test_clip_to_face_is_offered_by_the_menus():
	var menu := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	assert_true(menu.contains('add_item("Clip to Face Plane"'))
	assert_true(menu.contains('action = "clip_to_face"'))
	var toolbar := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_context_toolbar.gd"
	)
	assert_true(toolbar.contains('"clip_to_face"'))


func test_context_menu_ids_are_unique():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/hf_viewport_context_menu.gd"
	)
	var seen := {}
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("const _ID_"):
			continue
		var value := trimmed.get_slice(":=", 1).strip_edges()
		assert_false(seen.has(value), "menu id %s is used twice" % value)
		seen[value] = true


func test_clip_to_face_asks_for_a_face_before_cutting_anything():
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_edit_actions.gd")
	var start := source.find("static func clip_to_face_plane_selected")
	assert_gt(start, -1)
	var body := source.substr(start, 2000)
	assert_true(body.contains("root.face_selection"), "the plane comes from the face selection")
	assert_lt(
		body.find("face_selection.is_empty()"),
		body.find("clip_brush_to_face_plane"),
		"the missing-face check must run before anything is cut"
	)
	assert_true(body.contains("user_message.emit"), "a refusal must reach the user")


func test_the_previews_run_the_same_split_the_tools_run():
	# A preview that computed the cut its own way could promise geometry the tool
	# would not produce, which is exactly what the box-only previews used to do.
	var clip_preview := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_clip_preview.gd"
	)
	assert_true(clip_preview.contains("HFConvexClip.split"), "the clip preview must split for real")
	var carve_preview := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_carve_preview.gd"
	)
	assert_true(
		carve_preview.contains("_carve_pieces"), "the carve preview must use the carve algorithm"
	)


func test_the_ring_sorter_has_one_home():
	# Ordering a ring of coplanar vertices the wrong way round is invisible until
	# bake, so there is exactly one implementation and its name states the
	# convention. A second copy is how Clip to Convex ended up inside out.
	var vertex_system := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_vertex_system.gd"
	)
	assert_false(
		vertex_system.contains("func _sort_coplanar_verts"),
		"the duplicate ring sorter must stay deleted"
	)
	assert_true(vertex_system.contains("HFConvexClip.sort_coplanar_cw"))


func test_the_axis_aligned_guard_is_gone_entirely():
	# Clip, carve and hollow all work on real geometry now, so the guard that
	# required an unrotated box has no callers left and has been deleted.
	for path in [
		"res://addons/hammerforge/systems/hf_brush_system.gd",
		"res://addons/hammerforge/systems/hf_carve_system.gd",
		"res://addons/hammerforge/systems/hf_carve_preview.gd",
		"res://addons/hammerforge/systems/hf_clip_preview.gd",
		"res://addons/hammerforge/systems/hf_hollow_preview.gd",
	]:
		assert_false(
			FileAccess.get_file_as_string(path).contains("_check_axis_aligned_box"),
			"%s should not need an unrotated box" % path
		)


func test_the_two_boolean_operations_share_one_loop():
	# Carve subtracts another brush; hollow subtracts the brush from itself. Same
	# progressive remainder, different planes — and one implementation.
	var carve_system := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_carve_system.gd"
	)
	assert_true(carve_system.contains("HFConvexClip.progressive_remainder"))
	var brush_system := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_brush_system.gd"
	)
	assert_true(brush_system.contains("HFConvexClip.progressive_remainder"))


func test_the_split_names_its_halves_after_the_plane():
	# Callers rely on "front" meaning the side the normal points to.
	var faces: Array = []
	var box := Vector3(2, 2, 2)
	var brush := DraftBrush.new()
	brush.size = box
	add_child_autoqfree(brush)
	brush.rebuild_preview()
	faces = brush.get_faces()
	var result: Dictionary = HFConvexClipScript.split(faces, Plane(Vector3.UP, 0.0))
	var front_top := -1000.0
	for face in result["front"]:
		for v in face.local_verts:
			front_top = maxf(front_top, v.y)
	assert_gt(front_top, 0.0, "the front half must be the one the normal points at")
