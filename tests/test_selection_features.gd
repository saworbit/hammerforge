extends GutTest

const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")
const HFContextToolbar = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")
const HFSelectionFilter = preload("res://addons/hammerforge/ui/hf_selection_filter.gd")
const DockType = preload("res://addons/hammerforge/dock.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrushType = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntityType = preload("res://addons/hammerforge/draft_entity.gd")
const HFToastType = preload("res://addons/hammerforge/ui/hf_toast.gd")

# ===========================================================================
# Keymap tests for new bindings
# ===========================================================================

var keymap: HFKeymapType


func before_each():
	keymap = HFKeymapType.load_or_default("")


func after_each():
	keymap = null


func _make_key(
	keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false
) -> InputEventKey:
	var ev = InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


func test_apply_last_texture_binding():
	var ev = _make_key(KEY_T, false, true)
	assert_true(keymap.matches("apply_last_texture", ev), "Shift+T should match apply_last_texture")


func test_apply_last_texture_no_shift():
	var ev = _make_key(KEY_T)
	assert_false(
		keymap.matches("apply_last_texture", ev), "T alone should not match apply_last_texture"
	)


func test_select_similar_binding():
	var ev = _make_key(KEY_S, false, true)
	assert_true(keymap.matches("select_similar", ev), "Shift+S should match select_similar")


func test_selection_filter_binding():
	var ev = _make_key(KEY_F, false, true)
	assert_true(keymap.matches("selection_filter", ev), "Shift+F should match selection_filter")


func test_texture_picker_unchanged():
	var ev = _make_key(KEY_T)
	assert_true(keymap.matches("texture_picker", ev), "T should still match texture_picker")


func test_new_actions_have_labels():
	assert_ne(
		HFKeymapType.get_action_label("apply_last_texture"),
		"apply_last_texture",
		"apply_last_texture should have a human label",
	)
	assert_ne(
		HFKeymapType.get_action_label("select_similar"),
		"select_similar",
		"select_similar should have a human label",
	)
	assert_ne(
		HFKeymapType.get_action_label("selection_filter"),
		"selection_filter",
		"selection_filter should have a human label",
	)


func test_new_actions_have_categories():
	assert_eq(
		HFKeymapType.get_category("apply_last_texture"),
		"Tools",
		"apply_last_texture should be in Tools category",
	)
	assert_eq(
		HFKeymapType.get_category("select_similar"),
		"Selection",
		"select_similar should be in Selection category",
	)
	assert_eq(
		HFKeymapType.get_category("selection_filter"),
		"Selection",
		"selection_filter should be in Selection category",
	)


func test_new_bindings_in_actions_list():
	var actions = keymap.get_actions()
	assert_true("apply_last_texture" in actions, "actions should include apply_last_texture")
	assert_true("select_similar" in actions, "actions should include select_similar")
	assert_true("selection_filter" in actions, "actions should include selection_filter")


func test_display_strings():
	assert_eq(keymap.get_display_string("apply_last_texture"), "Shift+T")
	assert_eq(keymap.get_display_string("select_similar"), "Shift+S")
	assert_eq(keymap.get_display_string("selection_filter"), "Shift+F")


# ===========================================================================
# Context toolbar label tests
# ===========================================================================


func test_toolbar_brush_label_count():
	var tb = HFContextToolbar.new()
	add_child_autoqfree(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 3,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("3"), "Label should show brush count")
	assert_true(tb._label.text.contains("selected"), "Label should say 'selected'")


func test_toolbar_face_label_shows_brush_count():
	var tb = HFContextToolbar.new()
	add_child_autoqfree(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 2,
				"entity_count": 0,
				"face_count": 5,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("5"), "Label should show face count")
	assert_true(tb._label.text.contains("2"), "Label should show brush count in face context")


func test_toolbar_entity_selected_label():
	var tb = HFContextToolbar.new()
	add_child_autoqfree(tb)
	(
		tb
		. update_state(
			{
				"has_root": true,
				"brush_count": 0,
				"entity_count": 2,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(tb._label.text.contains("2"), "Label should show entity count")
	assert_true(tb._label.text.contains("selected"), "Label should say selected")


# ===========================================================================
# Selection filter helpers (does not need tree — pure logic)
# ===========================================================================


func test_size_similar_identical():
	var sf = HFSelectionFilter.new()
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(10, 20, 30), 0.2),
		"Identical sizes should be similar",
	)
	sf.free()


func test_size_similar_within_tolerance():
	var sf = HFSelectionFilter.new()
	# 10% difference on each axis — well within 20% tolerance
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(11, 22, 33), 0.2),
		"Sizes within 20% should be similar",
	)
	sf.free()


func test_size_similar_beyond_tolerance():
	var sf = HFSelectionFilter.new()
	assert_false(
		sf._size_similar(Vector3(10, 20, 30), Vector3(20, 40, 60), 0.2),
		"Sizes at 100% difference should not be similar",
	)
	sf.free()


func test_size_similar_ignores_orientation():
	var sf = HFSelectionFilter.new()
	# Same dimensions in different order
	assert_true(
		sf._size_similar(Vector3(10, 20, 30), Vector3(30, 10, 20), 0.2),
		"Orientation-swapped sizes should be similar",
	)
	sf.free()


# ===========================================================================
# Dock mixed-selection safety
# ===========================================================================


func _make_dock_selection_fixture() -> Dictionary:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	var dock := DockType.new()
	dock.level_root = root
	var brush := (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRootType.BrushShape.BOX,
					"size": Vector3(8, 8, 8),
					"center": Vector3.ZERO,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": "dock_mixed_guard_brush",
				}
			)
		)
		as DraftBrushType
	)
	var entity := DraftEntityType.new()
	entity.name = "DockGuardEntity"
	root.add_entity(entity)
	var native := Node3D.new()
	native.name = "OrdinaryGodotNode"
	root.add_child(native)
	return {"root": root, "dock": dock, "brush": brush, "entity": entity, "native": native}


func test_dock_selection_scope_uses_active_level_root_ownership() -> void:
	var fixture := _make_dock_selection_fixture()
	var dock: HammerForgeDock = fixture["dock"]
	var brush: DraftBrush = fixture["brush"]
	var entity: DraftEntity = fixture["entity"]
	var native: Node3D = fixture["native"]
	assert_eq(
		dock._classify_selection_scope([]),
		DockType.DockSelectionScope.EMPTY,
		"Empty selections should remain selection-independent",
	)
	assert_eq(
		dock._classify_selection_scope([brush, entity]),
		DockType.DockSelectionScope.MANAGED,
		"Brushes and entities owned by the active root are managed",
	)
	assert_eq(
		dock._classify_selection_scope([native]),
		DockType.DockSelectionScope.NATIVE,
		"Ordinary Godot nodes are native selection",
	)
	assert_eq(
		dock._classify_selection_scope([brush, native]),
		DockType.DockSelectionScope.MIXED,
		"Managed plus ordinary nodes must be classified as mixed",
	)
	var unattached_brush := DraftBrushType.new()
	assert_eq(
		dock._classify_selection_scope([unattached_brush]),
		DockType.DockSelectionScope.NATIVE,
		"A DraftBrush class outside the active LevelRoot is not managed by that root",
	)
	unattached_brush.free()
	dock.free()


func test_dock_mixed_guard_surfaces_a_clear_toast() -> void:
	var fixture := _make_dock_selection_fixture()
	var dock: HammerForgeDock = fixture["dock"]
	dock._selection_nodes = [fixture["brush"], fixture["native"]]
	var toast := HFToastType.new()
	add_child_autoqfree(toast)
	dock._toast_container = toast
	assert_false(dock._guard_selection_action("Group Selection"))
	assert_eq(toast.get_child_count(), 1, "Blocked action should surface exactly one toast")
	var label := toast.get_child(0).get_child(0) as Label
	assert_not_null(label)
	assert_true(label.text.contains("Group Selection"))
	assert_true(label.text.contains("mixed selection"))
	assert_true(label.text.contains("ordinary Godot nodes"))
	dock.free()


func test_group_and_visgroup_handlers_never_stamp_native_nodes_from_mixed_selection() -> void:
	var fixture := _make_dock_selection_fixture()
	var root: LevelRoot = fixture["root"]
	var dock: HammerForgeDock = fixture["dock"]
	var brush: DraftBrush = fixture["brush"]
	var native: Node3D = fixture["native"]
	dock._selection_nodes = [brush, native]
	dock._on_group_selection()
	assert_false(
		brush.has_meta("group_id"), "Mixed group action must leave managed brush unchanged"
	)
	assert_false(native.has_meta("group_id"), "Mixed group action must never tag native nodes")

	root.create_visgroup("guarded")
	var visgroup_list := ItemList.new()
	dock.add_child(visgroup_list)
	dock.visgroup_list = visgroup_list
	visgroup_list.add_item("[V] guarded")
	visgroup_list.select(0)
	dock._on_visgroup_add_selection()
	assert_false(brush.has_meta("visgroups"), "Mixed visgroup action must leave brush unchanged")
	assert_false(native.has_meta("visgroups"), "Mixed visgroup action must never tag native nodes")
	dock.free()


func test_mixed_selection_blocks_entity_property_and_cordon_mutation() -> void:
	var fixture := _make_dock_selection_fixture()
	var root: LevelRoot = fixture["root"]
	var dock: HammerForgeDock = fixture["dock"]
	var brush: DraftBrush = fixture["brush"]
	var entity: DraftEntity = fixture["entity"]
	var native: Node3D = fixture["native"]
	entity.entity_data["label"] = "before"
	dock._selection_nodes = [entity, native]
	dock._on_entity_prop_changed("after", entity, "label")
	assert_eq(entity.entity_data["label"], "before", "Stale entity controls must fail closed")

	var original_cordon := root.cordon_aabb
	dock._selection_nodes = [brush, native]
	dock._on_cordon_from_selection()
	assert_eq(
		root.cordon_aabb, original_cordon, "Mixed cordon action must not use a partial subset"
	)
	assert_eq(
		dock._get_selected_brush_ids(), [], "Brush-id helpers must fail closed for mixed input"
	)
	dock.free()


func test_entity_io_rejects_a_heterogeneous_hammerforge_selection() -> void:
	var fixture := _make_dock_selection_fixture()
	var root: LevelRoot = fixture["root"]
	var dock: HammerForgeDock = fixture["dock"]
	var entity: DraftEntity = fixture["entity"]
	dock._selection_nodes = [fixture["brush"], entity]
	for property_name in ["io_output_name", "io_target_name", "io_input_name"]:
		var input := LineEdit.new()
		dock.add_child(input)
		dock.set(property_name, input)
	dock.io_output_name.text = "OnTrigger"
	dock.io_target_name.text = "target"
	dock.io_input_name.text = "Enable"
	dock._on_io_add()
	assert_eq(
		root.get_entity_outputs(entity).size(),
		0,
		"Entity-only actions must not silently filter a brush out of the selection",
	)
	dock.free()


func test_mixed_selection_disables_managed_controls_but_not_independent_actions() -> void:
	var fixture := _make_dock_selection_fixture()
	var dock: HammerForgeDock = fixture["dock"]
	var controls := {
		"hollow_btn": Button.new(),
		"bake_selected_btn": Button.new(),
		"quick_play_area_btn": Button.new(),
		"heightmap_convert_btn": Button.new(),
		"visgroup_add_sel_btn": Button.new(),
		"group_sel_btn": Button.new(),
		"cordon_from_sel_btn": Button.new(),
		"io_add_btn": Button.new(),
		"scatter_preview_btn": Button.new(),
		"scatter_commit_btn": Button.new(),
		"floor_btn": Button.new(),
		"clear_btn": Button.new(),
		"_disp_sew_btn": Button.new(),
	}
	for property_name in controls:
		var control: Button = controls[property_name]
		dock.add_child(control)
		dock.set(property_name, control)
	dock.set_selection_nodes([fixture["brush"], fixture["native"]])
	for property_name in controls:
		var control: Button = controls[property_name]
		if property_name in ["floor_btn", "clear_btn", "_disp_sew_btn"]:
			assert_false(control.disabled, "%s is selection-independent" % property_name)
		else:
			assert_true(control.disabled, "%s must be disabled for mixed selection" % property_name)
	assert_false(
		dock._guard_selection_action(
			"Scatter Preview", DockType.DockSelectionRequirement.NATIVE_ALLOWED
		),
		"Native-capable actions must still reject mixed selections",
	)
	dock.set_selection_nodes([fixture["native"]])
	assert_true(
		dock._guard_selection_action(
			"Scatter Preview", DockType.DockSelectionRequirement.NATIVE_ALLOWED
		),
		"Scatter paths may continue to use an ordinary-node-only selection",
	)
	assert_false(dock.scatter_preview_btn.disabled)
	dock.free()


func test_brush_only_actions_reject_brush_plus_entity_without_partial_mutation() -> void:
	var fixture := _make_dock_selection_fixture()
	var dock: HammerForgeDock = fixture["dock"]
	var brush: DraftBrush = fixture["brush"]
	var entity: DraftEntity = fixture["entity"]
	brush.position = Vector3(0, 48, 0)
	var original_position := brush.position
	dock._selection_nodes = [brush, entity]
	assert_false(
		dock._guard_selection_action(
			"Move to Floor", DockType.DockSelectionRequirement.BRUSHES_ONLY
		),
		"Brush-only guards must reject a brush plus entity selection",
	)
	dock._on_move_to_floor()
	assert_eq(brush.position, original_position, "Rejected action must leave the brush unchanged")
	assert_eq(
		dock._get_selected_brush_ids(),
		[],
		"Brush extraction must not silently filter entities out of a managed selection",
	)
	assert_true(
		dock._guard_selection_action("Group Selection"),
		"Actions that intentionally consume both managed types should remain available",
	)
	dock.free()


func test_heterogeneous_managed_selection_disables_type_specific_controls() -> void:
	var fixture := _make_dock_selection_fixture()
	var dock: HammerForgeDock = fixture["dock"]
	for property_name in [
		"hollow_btn",
		"io_add_btn",
		"group_sel_btn",
		"visgroup_add_sel_btn",
		"floor_btn",
	]:
		var button := Button.new()
		dock.add_child(button)
		dock.set(property_name, button)
	dock.set_selection_nodes([fixture["brush"], fixture["entity"]])
	assert_true(dock.hollow_btn.disabled, "Brush-only controls should be unavailable")
	assert_true(dock.io_add_btn.disabled, "Entity-only controls should be unavailable")
	assert_false(dock.group_sel_btn.disabled, "Grouping consumes both managed node types")
	assert_false(dock.visgroup_add_sel_btn.disabled, "Visgroups consume both managed node types")
	assert_false(dock.floor_btn.disabled, "Selection-independent actions should remain available")
	dock.free()


func _dock_or_handler_function_source(
	dock_source: String, handler_sources: Array, function_name: String
) -> String:
	var block := _function_source(dock_source, function_name)
	if block.contains("_guard_selection_action("):
		return block
	var handler_name := function_name.trim_prefix("_")
	for handler_source in handler_sources:
		var handler_block := _function_source(str(handler_source), handler_name)
		if handler_block != "":
			return handler_block
	return block


func _function_source(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		return ""
	var next_function := source.find("\nstatic func ", start + 1)
	if next_function < 0:
		next_function = source.find("\nfunc ", start + 1)
	return (
		source.substr(start) if next_function < 0 else source.substr(start, next_function - start)
	)


func test_all_dock_selection_mutators_share_the_scope_guard() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var handler_sources := [
		FileAccess.get_file_as_string("res://addons/hammerforge/dock_paint_handler.gd"),
		FileAccess.get_file_as_string("res://addons/hammerforge/dock_brush_handler.gd"),
		FileAccess.get_file_as_string("res://addons/hammerforge/dock_entity_handler.gd"),
	]
	var guarded_functions := [
		"_on_prefab_save_requested",
		"_on_prefab_save_linked_requested",
		"_on_prefab_variant_add_requested",
		"_on_bake_selected",
		"_on_hollow",
		"_on_move_to_floor",
		"_on_move_to_ceiling",
		"_on_create_duplicate_array",
		"_on_remove_duplicate_array",
		"_on_tie_entity",
		"_on_untie_entity",
		"_on_justify",
		"_on_quick_play_selected_area",
		"_on_heightmap_convert",
		"_on_scatter_preview",
		"_on_scatter_commit",
		"_on_material_context_action",
		"_on_visgroup_add_selection",
		"_on_visgroup_remove_selection",
		"_on_group_selection",
		"_on_ungroup_selection",
		"_on_cordon_from_selection",
		"_on_clip",
		"_on_io_add",
		"_on_io_remove",
		"_apply_material_to_whole_brush",
	]
	for function_name in guarded_functions:
		var block := _dock_or_handler_function_source(source, handler_sources, function_name)
		assert_ne(block, "", "%s must exist" % function_name)
		assert_true(
			block.contains("_guard_selection_action("),
			"%s must fail closed through the shared scope guard" % function_name,
		)
	for function_name in [
		"_on_bake_selected",
		"_on_hollow",
		"_on_move_to_floor",
		"_on_move_to_ceiling",
		"_on_create_duplicate_array",
		"_on_remove_duplicate_array",
		"_on_tie_entity",
		"_on_untie_entity",
		"_on_quick_play_selected_area",
		"_on_heightmap_convert",
		"_on_cordon_from_selection",
		"_on_clip",
		"_apply_material_to_whole_brush",
	]:
		assert_true(
			_dock_or_handler_function_source(source, handler_sources, function_name).contains(
				"DockSelectionRequirement.BRUSHES_ONLY"
			),
			"%s must reject entities instead of filtering them out" % function_name,
		)
	for function_name in ["_on_io_add", "_on_io_remove"]:
		assert_true(
			_dock_or_handler_function_source(source, handler_sources, function_name).contains(
				"DockSelectionRequirement.ENTITIES_ONLY"
			),
			"%s must reject brushes instead of filtering them out" % function_name,
		)
	assert_true(
		_function_source(source, "_get_selected_brush_ids").contains("DockSelectionScope.MANAGED"),
		"Brush-id extraction must reject mixed/native selection before filtering",
	)
	assert_true(
		_function_source(source, "_get_selected_brush_ids").contains('["entities"]'),
		"Brush-id extraction must also reject heterogeneous managed selection",
	)
