extends GutTest

## The dock's three Cast Shadows controls and the Lightmap Scale beside them
## (#1444, #1438): the level's default in Advanced Bake, the selected brushes' own
## in Selection Tools, and the highlighted visgroup's in Visgroups & Groups. Each
## writes the level through the command an undo step records, and shows what the
## level holds.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const EditorPluginStandIn = preload("res://tests/support/editor_plugin_stand_in.gd")
const HFBakeSplitScript = preload("res://addons/hammerforge/hf_bake_split.gd")
const HFUIFactoryScript = preload("res://addons/hammerforge/ui/hf_ui_factory.gd")
const SHADOWS_ON := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
const SHADOWS_OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
const SHADOWS_ONLY := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

var root: LevelRoot
var dock
var undo


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	undo = EditorPluginStandIn.FakeUndoRedoManager.new()
	dock.undo_redo = undo


func after_each() -> void:
	undo.free_histories()
	undo = null
	dock = null
	root = null


func _brush(brush_id: String, x: float) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(2, 2, 2), "center": Vector3(x, 0, 0), "brush_id": brush_id}
		)
		as DraftBrush
	)


## The index of the item standing for `value` on one of the dock's dropdowns.
func _item_for(opt: OptionButton, value: int) -> int:
	for i in opt.item_count:
		if HFUIFactoryScript.cast_shadow_at(opt, i) == value:
			return i
	return -1


func _pick(opt: OptionButton, value: int) -> void:
	var index := _item_for(opt, value)
	opt.select(index)
	opt.item_selected.emit(index)


func test_the_level_default_is_written_and_shown_by_advanced_bake():
	var opt: OptionButton = dock.bake_cast_shadows_opt
	assert_not_null(opt, "Advanced Bake has a Cast Shadows")
	assert_eq(opt.item_count, 4, "the four settings and no Level Default, as it is the level's")
	assert_eq(HFUIFactoryScript.cast_shadow_at(opt, opt.selected), SHADOWS_ON)
	root._full_reconcile_needed = false

	_pick(opt, SHADOWS_OFF)

	assert_eq(root.bake_cast_shadows, SHADOWS_OFF)
	assert_true(root._full_reconcile_needed, "a bake setting, so the bake is out of date")
	root.bake_cast_shadows = SHADOWS_ONLY
	dock._sync_grid_settings_from_root()
	assert_eq(HFUIFactoryScript.cast_shadow_at(opt, opt.selected), SHADOWS_ONLY, "and shows it")


func test_selection_tools_set_cast_shadows_on_every_selected_brush_in_one_step():
	var a := _brush("a", 0)
	var b := _brush("b", 4)
	root.set_brush_cast_shadow(["a"], SHADOWS_OFF)
	dock.set_selection_nodes([a, b])
	var opt: OptionButton = dock.brush_cast_shadow_opt
	assert_eq(opt.selected, -1, "two brushes that disagree show nothing")

	_pick(opt, SHADOWS_ONLY)

	assert_eq(HFBakeSplitScript.brush_cast_shadow(a), SHADOWS_ONLY)
	assert_eq(HFBakeSplitScript.brush_cast_shadow(b), SHADOWS_ONLY)
	assert_eq(undo.step_count(), 1, "one step for both")
	assert_eq(HFUIFactoryScript.cast_shadow_at(opt, opt.selected), SHADOWS_ONLY)
	_pick(opt, SHADOWS_ONLY)
	assert_eq(undo.step_count(), 1, "the same pick again changes nothing and is no step")

	assert_true(undo.press_undo())
	assert_eq(HFBakeSplitScript.brush_cast_shadow(root.find_brush_by_id("a")), SHADOWS_OFF)
	assert_eq(
		HFBakeSplitScript.brush_cast_shadow(root.find_brush_by_id("b")),
		HFBakeSplitScript.LEVEL_DEFAULT,
		"undo puts back what each had"
	)


func test_selection_tools_set_the_lightmap_scale_on_every_selected_brush():
	var a := _brush("a", 0)
	var b := _brush("b", 4)
	root.set_brush_lightmap_scale(["b"], 2.0)
	dock.set_selection_nodes([b, a])
	var spin: SpinBox = dock.brush_lightmap_scale_spin
	assert_eq(spin.value, 2.0, "the first brush's scale")
	assert_eq(spin.suffix, "(mixed)", "and the two disagree, which it says")
	assert_eq(HFBakeSplitScript.brush_lightmap_scale(a), 1.0, "showing it sets nothing")
	assert_eq(undo.step_count(), 0)

	spin.value = 4.0

	assert_eq(HFBakeSplitScript.brush_lightmap_scale(a), 4.0)
	assert_eq(HFBakeSplitScript.brush_lightmap_scale(b), 4.0)
	assert_eq(spin.suffix, "")
	assert_eq(undo.step_count(), 1)
	assert_true(root._dirty_brush_ids.has("a"), "a change for Bake Changed")
	assert_true(undo.press_undo())
	assert_eq(HFBakeSplitScript.brush_lightmap_scale(root.find_brush_by_id("a")), 1.0)
	assert_eq(HFBakeSplitScript.brush_lightmap_scale(root.find_brush_by_id("b")), 2.0)


func test_the_highlighted_visgroup_takes_the_cast_shadows_picked():
	var a := _brush("a", 0)
	root.create_visgroup("sky")
	root.add_selection_to_visgroup("sky", [a])
	dock.refresh_visgroup_ui()
	var opt: OptionButton = dock.visgroup_cast_shadow_opt
	assert_not_null(opt, "Visgroups & Groups has a Cast Shadows")
	assert_eq(opt.selected, -1, "nothing to show with no visgroup highlighted")
	dock.visgroup_list.select(0)
	root.consume_dirty_tags()

	_pick(opt, SHADOWS_OFF)

	assert_eq(root.visgroup_system.get_visgroup_cast_shadow("sky"), SHADOWS_OFF)
	assert_eq(undo.step_count(), 1)
	assert_true(root._dirty_brush_ids.has("a"), "its brushes are changes for Bake Changed")
	assert_eq(dock.visgroup_list.get_selected_items(), PackedInt32Array([0]), "still highlighted")
	assert_eq(HFUIFactoryScript.cast_shadow_at(opt, opt.selected), SHADOWS_OFF)
	assert_string_contains(dock.visgroup_list.get_item_tooltip(0), "Off")
	assert_true(undo.press_undo())
	assert_eq(root.visgroup_system.get_visgroup_cast_shadow("sky"), HFBakeSplitScript.LEVEL_DEFAULT)


func test_a_visgroup_pick_with_none_highlighted_says_so_and_changes_nothing():
	root.create_visgroup("sky")
	dock.refresh_visgroup_ui()

	_pick(dock.visgroup_cast_shadow_opt, SHADOWS_OFF)

	assert_eq(root.visgroup_system.get_visgroup_cast_shadow("sky"), HFBakeSplitScript.LEVEL_DEFAULT)
	assert_eq(undo.step_count(), 0)
	assert_eq(dock.visgroup_cast_shadow_opt.selected, -1, "the dropdown goes back to nothing")
