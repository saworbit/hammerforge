extends GutTest

const HFPluginHud = preload("res://addons/hammerforge/plugin_hud.gd")
const HFContextToolbarScript = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func test_hud_update_is_noop_without_plugin():
	HFPluginHud.update_hud_context(null)
	HFPluginHud.update_context_toolbar_state(null, null, 0)
	assert_true(true, "Null plugin must not crash")


func _banner() -> String:
	return rig.plugin.dock._mode_label.text


func _toolbar_section(context: int) -> Node:
	return rig.plugin._context_toolbar._sections.get(context)


## The plugin's HUD update reaches the dock's mode banner and the context
## toolbar: the banner names the tool in hand, and the toolbar shows the actions
## for what is selected.
func test_plugin_wrappers_delegate_to_hud_module():
	assert_not_null(rig.plugin, rig.error())
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	assert_true(_banner().begins_with("Select"), "the banner names the Select tool")
	rig.select([box])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	assert_true(_banner().begins_with("Vertex"), "and vertex mode once it is on")
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	var toolbar = rig.plugin._context_toolbar
	assert_true(toolbar.visible, "the toolbar shows for a selected brush")
	assert_eq(toolbar._context, HFContextToolbarScript.Context.BRUSH_SELECTED, "with its actions")
	var palette = rig.plugin._hotkey_palette
	assert_false(palette._is_action_available("delete"), "the closed palette is not kept up")
	rig.plugin._on_toggle_hotkey_palette()
	assert_true(palette._is_action_available("delete"), "opening it brings it up to date")
	rig.plugin._on_toggle_hotkey_palette()
	await rig.frame()
	palette._search_field.release_focus()
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	assert_true(_banner().begins_with("Draw"), "the Draw tool, back where it began")
	await rig.leave_level(level)


func test_the_mode_banner_and_toolbar_counts_stay_in_the_hud_module():
	# A grep on purpose: it keeps plugin.gd's two HUD callbacks thin, a boundary
	# the behaviour above cannot see.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var hud_start := source.find("func _update_hud_context")
	var hud_end := source.find("func _update_context_toolbar_state", hud_start)
	var hud_block := source.substr(hud_start, hud_end - hud_start)
	assert_false(hud_block.contains("set_mode_indicator"), "Mode banner lives in plugin_hud.gd")
	var toolbar_start := source.find("func _update_context_toolbar_state")
	var toolbar_end := source.find("func should_suppress_empty_selection", toolbar_start)
	var toolbar_block := source.substr(toolbar_start, toolbar_end - toolbar_start)
	assert_false(
		toolbar_block.contains("pending_cut_count"), "Toolbar counts live in plugin_hud.gd"
	)


## A selection holding a Godot node as well as a brush hides the toolbar's
## HammerForge actions, which would act on only part of it.
func test_a_mixed_selection_hides_the_toolbar_actions():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.select([box])
	assert_true(rig.plugin._context_toolbar.visible, "a brush alone gets the toolbar")
	rig.select([box, rig.native_node()])
	assert_false(rig.plugin._context_toolbar.visible, "a mixed selection does not")
	await rig.leave_level(level)


## With the Draw tool idle, the toolbar counts the pending cuts and offers to
## apply them.
func test_the_toolbar_counts_pending_cuts():
	var level = await rig.make_level()
	(
		level
		. create_brush_from_info(
			{
				"size": Vector3(2, 2, 2),
				"center": Vector3.ZERO,
				"brush_id": "cut",
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"pending": true,
			}
		)
	)
	rig.plugin._update_hud_context()
	var section := _toolbar_section(HFContextToolbarScript.Context.DRAW_IDLE)
	assert_eq(section.get_node("CutsCountLabel").text, "1 pending", "the cut is counted")
	assert_true(section.get_node("ApplyCutsBtn").visible, "and can be applied")
	await rig.leave_level(level)


## A selected piece of a structure brings up the toolbar's Update and Detach, and
## a piece left behind by a Detach does not (#1302).
func test_the_toolbar_offers_update_and_detach_for_a_structure_piece():
	var level = await rig.make_level()
	var settings: Dictionary = HFGeneratorSystem.default_settings("stairs")
	settings["steps"] = 2
	level.create_generator("stairs", settings, Transform3D(Basis(), Vector3(10, 0, 0)))
	var generator_id := str(level.generator_system.generators.keys()[0])
	var piece = level.find_brush_by_id(str(level.generator_for_id(generator_id).brush_ids[0]))
	var box = rig.box(level, "a", Vector3.ZERO)
	var section := _toolbar_section(HFContextToolbarScript.Context.BRUSH_SELECTED)
	rig.select([piece])
	assert_true(section.get_node("StrDetBtn").visible, "a piece offers Detach")
	assert_true(section.get_node("StrUpdBtn").visible, "and Update")
	rig.select([box])
	assert_false(section.get_node("StrDetBtn").visible, "a plain box does not")
	assert_true(level.detach_generator(generator_id))
	rig.select([piece])
	rig.plugin._update_hud_context()
	assert_false(section.get_node("StrDetBtn").visible, "nor does a detached piece")
	await rig.leave_level(level)


## The entity toolbar's Highlight button follows the level's own highlight state.
func test_the_highlight_button_follows_the_level():
	var level = await rig.make_level()
	var entity = DraftEntityScript.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	rig.select([entity])
	var button: Button = _toolbar_section(HFContextToolbarScript.Context.ENTITY_SELECTED).get_node(
		"HighlightBtn"
	)
	level.set_highlight_connected(true)
	rig.plugin._update_hud_context()
	assert_true(button.button_pressed, "the button shows the highlight on")
	level.set_highlight_connected(false)
	rig.plugin._update_hud_context()
	assert_false(button.button_pressed, "and off")
	await rig.leave_level(level)


## The toolbar's badge names the copy a selected piece belongs to, read through
## the copy's record. A tag naming no record, as a saved scene can bring in, is
## no copy (#1340).
func test_the_toolbar_badge_names_the_copy_a_selected_piece_belongs_to():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var section := _toolbar_section(HFContextToolbarScript.Context.BRUSH_SELECTED)
	rig.select([box])
	assert_false(section.get_node("PfbVarBtn").visible, "a plain box is no copy")
	var iid: String = level.prefab_system.register_instance(
		"res://prefabs/crate.hfprefab", ["a"], [], false, "worn"
	)
	rig.plugin._update_hud_context()
	assert_true(section.get_node("PfbVarBtn").visible, "a piece of a copy offers its variants")
	assert_eq(rig.plugin._context_toolbar._label.text, "crate (worn)", "and the badge names it")
	level.prefab_system.unregister_instance(iid)
	box.set_meta("hf_prefab_instance", "pfx_9")
	rig.plugin._update_hud_context()
	assert_false(section.get_node("PfbVarBtn").visible, "a tag naming no copy is no copy")
	await rig.leave_level(level)
