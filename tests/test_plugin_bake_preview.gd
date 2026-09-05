extends GutTest
## Boundary coverage for the extracted bake-preview toggle state.

const HFPluginBakePreview = preload("res://addons/hammerforge/plugin_bake_preview.gd")


class FakeBakeSystem:
	extends RefCounted


class FakeRoot:
	extends Node3D

	var bake_system := FakeBakeSystem.new()
	var _last_bake_preview_mode := 0
	var bake_in_flight := false
	var bake_succeeds := true
	var bake_calls: Array = []

	func is_bake_in_flight() -> bool:
		return bake_in_flight

	func bake(_selection: bool, _dirty: bool, _layer: int, preview_mode: int) -> bool:
		bake_calls.append(preview_mode)
		if bake_succeeds:
			_last_bake_preview_mode = preview_mode
		return bake_succeeds


class FakeDock:
	extends RefCounted

	var _bake_disabled := false
	var button_states: Array = []

	func _set_bake_buttons_disabled(disabled: bool) -> void:
		button_states.append(disabled)


class FakePlugin:
	extends RefCounted

	var dock := FakeDock.new()
	var active_root: Node = null
	var _bake_preview_active := false
	var _bake_preview_in_flight := false
	var hud_updates := 0

	func _update_hud_context() -> void:
		hud_updates += 1

	func _get_level_root() -> Node:
		return active_root


var plugin: FakePlugin
var root: FakeRoot


func before_each():
	plugin = FakePlugin.new()
	root = FakeRoot.new()
	add_child_autoqfree(root)
	plugin.active_root = root


func after_each():
	plugin = null
	root = null


# ---------------------------------------------------------------------------
# Toggling
# ---------------------------------------------------------------------------


func test_turning_the_preview_on_bakes_wireframe():
	await HFPluginBakePreview.toggle(plugin, root, true)

	assert_eq(root.bake_calls, [HFPluginBakePreview.WIREFRAME_MODE])
	assert_true(plugin._bake_preview_active)
	assert_false(plugin._bake_preview_in_flight)
	assert_eq(plugin.dock.button_states, [true, false], "Bake buttons are released again")


func test_turning_the_preview_off_bakes_full_quality():
	plugin._bake_preview_active = true

	await HFPluginBakePreview.toggle(plugin, root, false)

	assert_eq(root.bake_calls, [0])
	assert_false(plugin._bake_preview_active)


func test_a_failed_preview_bake_walks_the_toggle_back():
	# The toggle is set speculatively before the await, so a failure has to undo it.
	root.bake_succeeds = false

	await HFPluginBakePreview.toggle(plugin, root, true)

	assert_false(plugin._bake_preview_active, "A bake that failed changed nothing on screen")
	assert_false(plugin._bake_preview_in_flight)
	assert_eq(plugin.dock.button_states, [true, false], "Buttons are released even on failure")


func test_a_failed_restore_bake_leaves_the_preview_on():
	plugin._bake_preview_active = true
	root.bake_succeeds = false

	await HFPluginBakePreview.toggle(plugin, root, false)

	assert_true(plugin._bake_preview_active, "The wireframe bake is still what is on screen")


func test_toggle_refuses_while_another_bake_is_running():
	root.bake_in_flight = true

	await HFPluginBakePreview.toggle(plugin, root, true)

	assert_eq(root.bake_calls.size(), 0, "Overlapping bakes must not be dispatched")
	assert_false(plugin._bake_preview_active)
	assert_eq(plugin.hud_updates, 1, "The toolbar is still refreshed so the button unsticks")


func test_toggle_refuses_while_the_dock_has_baking_disabled():
	plugin.dock._bake_disabled = true

	await HFPluginBakePreview.toggle(plugin, root, true)

	assert_eq(root.bake_calls.size(), 0)


# ---------------------------------------------------------------------------
# Reacting to bakes we did not start
# ---------------------------------------------------------------------------


func test_our_own_failed_bake_flips_the_speculative_flag_back():
	plugin._bake_preview_active = true
	plugin._bake_preview_in_flight = true

	HFPluginBakePreview.on_bake_state_changed(plugin, false, false)

	assert_false(plugin._bake_preview_active)
	assert_false(plugin._bake_preview_in_flight)


func test_our_own_successful_bake_keeps_the_speculative_flag():
	plugin._bake_preview_active = true
	plugin._bake_preview_in_flight = true

	HFPluginBakePreview.on_bake_state_changed(plugin, false, true)

	assert_true(plugin._bake_preview_active)
	assert_false(plugin._bake_preview_in_flight)


func test_someone_elses_bake_derives_the_toggle_from_what_was_baked():
	# The dock dropdown can request Wireframe for an ordinary bake.
	root._last_bake_preview_mode = HFPluginBakePreview.WIREFRAME_MODE

	HFPluginBakePreview.on_bake_state_changed(plugin, false, true)

	assert_true(plugin._bake_preview_active)


func test_someone_elses_proxy_bake_does_not_light_the_toggle():
	root._last_bake_preview_mode = 2  # Proxy

	HFPluginBakePreview.on_bake_state_changed(plugin, false, true)

	assert_false(plugin._bake_preview_active, "Only Wireframe maps to the toolbar toggle")


func test_someone_elses_failed_bake_leaves_the_toggle_alone():
	plugin._bake_preview_active = true

	HFPluginBakePreview.on_bake_state_changed(plugin, false, false)

	assert_true(plugin._bake_preview_active, "baked_container is untouched, so is the flag")


func test_a_bake_starting_only_refreshes_the_toolbar():
	plugin._bake_preview_active = true

	HFPluginBakePreview.on_bake_state_changed(plugin, true, false)

	assert_true(plugin._bake_preview_active)
	assert_eq(plugin.hud_updates, 1)


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------


func test_undo_restores_the_toggle_from_the_scene():
	plugin._bake_preview_active = true
	root._last_bake_preview_mode = 0

	HFPluginBakePreview.sync_after_undo(plugin, root)

	assert_false(plugin._bake_preview_active)
	assert_eq(plugin.hud_updates, 1)


func test_undo_during_our_own_bake_is_ignored():
	# version_changed also fires for our commit, which would otherwise clobber
	# the state the in-flight bake is about to produce.
	plugin._bake_preview_active = true
	plugin._bake_preview_in_flight = true
	root._last_bake_preview_mode = 0

	HFPluginBakePreview.sync_after_undo(plugin, root)

	assert_true(plugin._bake_preview_active)
	assert_eq(plugin.hud_updates, 0)


func test_undo_that_changes_nothing_does_not_refresh_the_toolbar():
	plugin._bake_preview_active = true
	root._last_bake_preview_mode = HFPluginBakePreview.WIREFRAME_MODE

	HFPluginBakePreview.sync_after_undo(plugin, root)

	assert_true(plugin._bake_preview_active)
	assert_eq(plugin.hud_updates, 0)
