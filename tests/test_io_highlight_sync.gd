extends GutTest

## Tests that the highlight-connected toggle stays in sync across the context
## toolbar button, the wiring-panel button, and the authoritative visualizer.

const HFIOVisualizer = preload("res://addons/hammerforge/systems/hf_io_visualizer.gd")
const HFIOPresets = preload("res://addons/hammerforge/systems/hf_io_presets.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFContextToolbar = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")
const HFIOWiringPanel = preload("res://addons/hammerforge/ui/hf_io_wiring_panel.gd")

var root: Node3D
var sys: HFEntitySystem
var viz: HFIOVisualizer
var presets: HFIOPresets
var toolbar: HFContextToolbar
var panel: HFIOWiringPanel


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.entity_definitions = {}
	root.entity_definitions_path = ""
	sys = HFEntitySystem.new(root)
	root.entity_system = sys
	viz = HFIOVisualizer.new(root)
	presets = HFIOPresets.new(root)
	presets.load_presets("user://test_highlight_sync_tmp.json")

	toolbar = HFContextToolbar.new()
	add_child_autoqfree(toolbar)

	panel = HFIOWiringPanel.new()
	add_child_autoqfree(panel)
	panel.setup(sys, presets, viz)


func after_each():
	viz.cleanup()
	if FileAccess.file_exists("user://test_highlight_sync_tmp.json"):
		DirAccess.remove_absolute("user://test_highlight_sync_tmp.json")
	root = null
	sys = null
	viz = null
	presets = null
	toolbar = null
	panel = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D
var draft_brushes_node: Node3D
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var entity_system = null

func _assign_owner(node: Node) -> void:
	pass

func get_selected_entities() -> Array:
	return []
"""
	s.reload()
	return s


func _make_entity(entity_name: String) -> Node3D:
	var e = Node3D.new()
	e.name = entity_name
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


func _get_toolbar_highlight_btn() -> Button:
	var section = toolbar._sections.get(HFContextToolbar.Context.ENTITY_SELECTED, null)
	if not section:
		return null
	return section.get_node_or_null("HighlightBtn") as Button


## Simulate a user click on a toggle button.
## In Godot 4, setting `button_pressed` on a toggle button emits `toggled`
## internally when the value actually changes. We rely on that built-in emission
## to exercise the same signal path a real click would trigger.
func _click_toggle(btn: Button, pressed: bool) -> void:
	btn.set_pressed_no_signal(not pressed)  # Ensure the value will actually change
	btn.button_pressed = pressed  # This triggers the engine's built-in toggled emission


# ===========================================================================
# Wiring panel syncs from visualizer
# ===========================================================================


func test_panel_button_defaults_off():
	assert_false(panel._highlight_btn.button_pressed, "Panel button should default to off")


func test_panel_syncs_when_visualizer_turned_on_externally():
	viz.set_highlight_connected(true)
	panel._sync_highlight_button()
	assert_true(panel._highlight_btn.button_pressed, "Panel should reflect visualizer=true")


func test_panel_syncs_when_visualizer_turned_off_externally():
	viz.set_highlight_connected(true)
	panel._sync_highlight_button()
	viz.set_highlight_connected(false)
	panel._sync_highlight_button()
	assert_false(panel._highlight_btn.button_pressed, "Panel should reflect visualizer=false")


func test_panel_syncs_on_set_source_entity():
	var e = _make_entity("ent_1")
	viz.set_highlight_connected(true)
	panel.set_source_entity(e)
	assert_true(panel._highlight_btn.button_pressed, "set_source_entity should sync button")


func test_panel_sync_uses_no_signal():
	# Verify _sync_highlight_button doesn't re-emit highlight_toggled
	var emitted := false
	panel.highlight_toggled.connect(func(_v): emitted = true)
	viz.set_highlight_connected(true)
	panel._sync_highlight_button()
	assert_false(emitted, "Sync should use set_pressed_no_signal, not trigger signal")


# ===========================================================================
# Context toolbar syncs from state dict
# ===========================================================================


func test_toolbar_button_defaults_off():
	# Force entity context so the button exists in a visible section
	var state = {"has_root": true, "entity_count": 1, "tool": 0, "input_mode": 0}
	toolbar.update_state(state)
	var btn = _get_toolbar_highlight_btn()
	assert_not_null(btn, "HighlightBtn should exist in entity section")
	assert_false(btn.button_pressed, "Toolbar button should default to off")


func test_toolbar_syncs_highlight_true_from_state():
	var state = {
		"has_root": true,
		"entity_count": 1,
		"tool": 0,
		"input_mode": 0,
		"highlight_connected": true,
	}
	toolbar.update_state(state)
	var btn = _get_toolbar_highlight_btn()
	assert_true(btn.button_pressed, "Toolbar should reflect state highlight_connected=true")


func test_toolbar_syncs_highlight_false_from_state():
	# First set to true
	var state_on = {
		"has_root": true,
		"entity_count": 1,
		"tool": 0,
		"input_mode": 0,
		"highlight_connected": true,
	}
	toolbar.update_state(state_on)
	# Then set to false
	var state_off = {
		"has_root": true,
		"entity_count": 1,
		"tool": 0,
		"input_mode": 0,
		"highlight_connected": false,
	}
	toolbar.update_state(state_off)
	var btn = _get_toolbar_highlight_btn()
	assert_false(btn.button_pressed, "Toolbar should reflect state highlight_connected=false")


func test_toolbar_sync_uses_no_signal():
	# Verify set_pressed_no_signal doesn't fire toggled → action_requested
	var action_fired := false
	toolbar.action_requested.connect(func(_a, _b): action_fired = true)
	var state = {
		"has_root": true,
		"entity_count": 1,
		"tool": 0,
		"input_mode": 0,
		"highlight_connected": true,
	}
	toolbar.update_state(state)
	assert_false(action_fired, "State sync should not re-emit action_requested")


# ===========================================================================
# Signal emission contracts
# ===========================================================================


func test_toolbar_button_emits_action_requested_on_toggle():
	# Verify the actual button wired in _build_entity_section fires the right signal
	# Use Array containers because GDScript closures don't reliably capture scalar reassignment
	var received: Array = []  # Will hold [action, args]
	toolbar.action_requested.connect(func(a, b): received.append([a, b]))
	# Force entity context so section is visible
	toolbar.update_state({"has_root": true, "entity_count": 1, "tool": 0, "input_mode": 0})
	var btn = _get_toolbar_highlight_btn()
	assert_not_null(btn)
	# Simulate user click
	_click_toggle(btn, true)
	assert_eq(received.size(), 1, "Should have received exactly one action_requested emission")
	assert_eq(
		received[0][0], "highlight_connected", "Button should emit highlight_connected action"
	)
	assert_eq(received[0][1], [true], "Action args should carry pressed state")


func test_panel_button_emits_highlight_toggled_on_toggle():
	var received: Array = []
	panel.highlight_toggled.connect(func(v): received.append(v))
	_click_toggle(panel._highlight_btn, true)
	assert_eq(received.size(), 1, "Should have one emission")
	assert_true(received[0], "Panel button should emit highlight_toggled(true)")
	_click_toggle(panel._highlight_btn, false)
	assert_eq(received.size(), 2, "Should have two emissions")
	assert_false(received[1], "Panel button should emit highlight_toggled(false)")


# ===========================================================================
# Signal-driven integration: wired coordinator replicating production paths
# ===========================================================================
#
# These tests wire up the same signal→callback→state chain that runs in
# production (plugin.gd + dock.gd), but using a lightweight coordinator
# RefCounted so we don't need EditorPlugin or the full dock.


func _make_coordinator() -> RefCounted:
	# Mimics the subset of plugin.gd + dock.gd that routes highlight signals:
	#   toolbar.action_requested → _on_toolbar_action → viz + panel sync
	#   panel.highlight_toggled  → _on_panel_toggle   → viz + toolbar state push
	var coord = RefCounted.new()
	coord.set_meta("viz", viz)
	coord.set_meta("toolbar", toolbar)
	coord.set_meta("panel", panel)

	# Path 1: toolbar button → viz + panel (mirrors plugin.gd action handler + dock.sync)
	toolbar.action_requested.connect(
		func(action: String, args: Array):
			if action != "highlight_connected":
				return
			var v = coord.get_meta("viz") as HFIOVisualizer
			var p = coord.get_meta("panel") as HFIOWiringPanel
			var tb = coord.get_meta("toolbar") as HFContextToolbar
			var pressed: bool = args[0] if not args.is_empty() else false
			v.set_highlight_connected(pressed)
			p._sync_highlight_button()
			# plugin.gd's next _update_hud_context pushes state into toolbar
			var state = _entity_state(v)
			tb.update_state(state)
	)

	# Path 2: panel button → viz + toolbar (mirrors dock._on_wiring_highlight_toggled
	# + plugin._update_hud_context on next cycle)
	panel.highlight_toggled.connect(
		func(enabled: bool):
			var v = coord.get_meta("viz") as HFIOVisualizer
			var tb = coord.get_meta("toolbar") as HFContextToolbar
			v.set_highlight_connected(enabled)
			var state = _entity_state(v)
			tb.update_state(state)
	)

	return coord


func _entity_state(v: HFIOVisualizer) -> Dictionary:
	return {
		"has_root": true,
		"entity_count": 1,
		"tool": 0,
		"input_mode": 0,
		"highlight_connected": v.highlight_connected,
	}


func test_integration_toolbar_click_propagates_to_panel():
	# Wire up the coordinator so signals flow through the production chain
	var _coord = _make_coordinator()
	# Ensure entity context
	toolbar.update_state(_entity_state(viz))
	var tb_btn = _get_toolbar_highlight_btn()

	# User clicks toolbar HL button
	_click_toggle(tb_btn, true)

	# Verify entire chain propagated
	assert_true(viz.highlight_connected, "Visualizer should be on")
	assert_true(panel._highlight_btn.button_pressed, "Panel should sync to on")
	assert_true(tb_btn.button_pressed, "Toolbar button should stay on")


func test_integration_panel_click_propagates_to_toolbar():
	var _coord = _make_coordinator()
	toolbar.update_state(_entity_state(viz))

	# User clicks panel HL button
	_click_toggle(panel._highlight_btn, true)

	var tb_btn = _get_toolbar_highlight_btn()
	assert_true(viz.highlight_connected, "Visualizer should be on")
	assert_true(tb_btn.button_pressed, "Toolbar should sync to on")
	assert_true(panel._highlight_btn.button_pressed, "Panel button should stay on")


func test_integration_toolbar_off_propagates_to_panel():
	var _coord = _make_coordinator()
	toolbar.update_state(_entity_state(viz))
	var tb_btn = _get_toolbar_highlight_btn()

	# Turn on then off
	_click_toggle(tb_btn, true)
	_click_toggle(tb_btn, false)

	assert_false(viz.highlight_connected, "Visualizer should be off")
	assert_false(panel._highlight_btn.button_pressed, "Panel should sync to off")
	assert_false(tb_btn.button_pressed, "Toolbar button should be off")


func test_integration_panel_off_propagates_to_toolbar():
	var _coord = _make_coordinator()
	toolbar.update_state(_entity_state(viz))

	_click_toggle(panel._highlight_btn, true)
	_click_toggle(panel._highlight_btn, false)

	var tb_btn = _get_toolbar_highlight_btn()
	assert_false(viz.highlight_connected, "Visualizer should be off")
	assert_false(tb_btn.button_pressed, "Toolbar should sync to off")
	assert_false(panel._highlight_btn.button_pressed, "Panel button should be off")


func test_integration_alternating_sources_stay_in_sync():
	var _coord = _make_coordinator()
	toolbar.update_state(_entity_state(viz))
	var tb_btn = _get_toolbar_highlight_btn()

	# Toolbar on
	_click_toggle(tb_btn, true)
	assert_true(panel._highlight_btn.button_pressed)
	# Panel off
	_click_toggle(panel._highlight_btn, false)
	assert_false(tb_btn.button_pressed, "Toolbar should follow panel off")
	# Panel on again
	_click_toggle(panel._highlight_btn, true)
	assert_true(tb_btn.button_pressed, "Toolbar should follow panel on")
	# Toolbar off
	_click_toggle(tb_btn, false)
	assert_false(panel._highlight_btn.button_pressed, "Panel should follow toolbar off")

	assert_false(viz.highlight_connected, "Visualizer should end off")
