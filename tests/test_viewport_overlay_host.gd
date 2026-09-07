extends GutTest
## Viewport overlays belong over the 3D viewport, not in the toolbar row.
##
## CONTAINER_SPATIAL_EDITOR_MENU is a plain HBoxContainer and the 3D viewport
## gets whatever height is left under it, so every child reserves its full
## minimum size out of the viewport's space. Measured with the overlays parked
## there: the toolbar's minimum went from (800, 46) to (1136, 380) the moment the
## command palette opened. Only the shortcut HUD and the status strip are
## genuinely toolbar items; the rest float over the viewport and are parented to
## the Control Godot draws that viewport's overlays through.

const Overlays = preload("res://addons/hammerforge/plugin_overlays.gd")


class FakePlugin:
	extends RefCounted

	var _viewport_overlay_host: Control = null
	var _context_toolbar: Control = null
	var _hotkey_palette: Control = null
	var _quick_property: Control = null
	var _coach_marks: Control = null
	var _operation_replay: Control = null
	var _radial_menu: Control = null
	## Stands in for the 3D toolbar row, which is an HBoxContainer.
	var toolbar := HBoxContainer.new()
	var added_to_toolbar: Array = []
	var removed_from_toolbar: Array = []

	func add_control_to_container(_container: int, control: Control) -> void:
		added_to_toolbar.append(control)
		toolbar.add_child(control)

	func remove_control_from_container(_container: int, control: Control) -> void:
		removed_from_toolbar.append(control)
		if control.get_parent() == toolbar:
			toolbar.remove_child(control)


var plugin: FakePlugin
var host: Control


func before_each() -> void:
	plugin = FakePlugin.new()
	add_child_autoqfree(plugin.toolbar)
	host = Control.new()
	host.name = "ViewportOverlayHost"
	add_child_autoqfree(host)


func after_each() -> void:
	plugin = null
	host = null


func _overlay(name: String) -> Control:
	var c := PanelContainer.new()
	c.name = name
	c.custom_minimum_size = Vector2(320, 380)
	return c


# --- attach --------------------------------------------------------------


func test_overlay_goes_to_the_viewport_host_when_there_is_one() -> void:
	plugin._viewport_overlay_host = host
	var overlay := _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, overlay)
	assert_same(overlay.get_parent(), host)
	assert_eq(plugin.added_to_toolbar, [], "The toolbar never sees it")


func test_overlay_falls_back_to_the_toolbar_before_the_viewport_has_drawn() -> void:
	# Overlays are built in _enter_tree, before the 3D editor has handed us its
	# draw-over Control. They have to live somewhere until it does.
	var overlay := _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, overlay)
	assert_same(overlay.get_parent(), plugin.toolbar)
	assert_eq(plugin.added_to_toolbar, [overlay])


# --- adoption ------------------------------------------------------------


func test_adopting_the_host_moves_parked_overlays_off_the_toolbar() -> void:
	plugin._context_toolbar = _overlay("ContextToolbar")
	plugin._hotkey_palette = _overlay("Palette")
	plugin._quick_property = _overlay("QuickProperty")
	for c in [plugin._context_toolbar, plugin._hotkey_palette, plugin._quick_property]:
		Overlays.attach_viewport_overlay(plugin, c)
	assert_eq(plugin.toolbar.get_child_count(), 3, "Parked, as expected, before adoption")

	Overlays.adopt_viewport_overlay_host(plugin, host)

	assert_eq(plugin.toolbar.get_child_count(), 0, "The toolbar row reserves nothing for them")
	for c in [plugin._context_toolbar, plugin._hotkey_palette, plugin._quick_property]:
		assert_same(c.get_parent(), host)


func test_adoption_keeps_the_first_live_host() -> void:
	# Godot calls the draw-over hook once per viewport in a split layout, every
	# frame. Re-homing on each call would drag the overlays between viewports.
	plugin._hotkey_palette = _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, plugin._hotkey_palette)
	Overlays.adopt_viewport_overlay_host(plugin, host)

	var second := Control.new()
	add_child_autoqfree(second)
	Overlays.adopt_viewport_overlay_host(plugin, second)

	assert_same(plugin._viewport_overlay_host, host)
	assert_same(plugin._hotkey_palette.get_parent(), host)


func test_adoption_replaces_a_host_that_left_the_tree() -> void:
	plugin._hotkey_palette = _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, plugin._hotkey_palette)
	Overlays.adopt_viewport_overlay_host(plugin, host)
	remove_child(host)

	var second := Control.new()
	add_child_autoqfree(second)
	Overlays.adopt_viewport_overlay_host(plugin, second)

	assert_same(plugin._viewport_overlay_host, second)
	assert_same(plugin._hotkey_palette.get_parent(), second)
	host.free()


func test_adoption_is_safe_with_no_overlays_built_yet() -> void:
	Overlays.adopt_viewport_overlay_host(plugin, host)
	assert_same(plugin._viewport_overlay_host, host)


# --- detach --------------------------------------------------------------


func test_detach_takes_the_overlay_off_the_host() -> void:
	plugin._viewport_overlay_host = host
	var overlay := _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, overlay)
	Overlays.detach_viewport_overlay(plugin, overlay)
	assert_null(overlay.get_parent())
	assert_eq(plugin.removed_from_toolbar, [], "It was never in the toolbar")
	overlay.free()


func test_detach_takes_a_parked_overlay_off_the_toolbar() -> void:
	var overlay := _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, overlay)
	Overlays.detach_viewport_overlay(plugin, overlay)
	assert_null(overlay.get_parent())
	assert_eq(plugin.removed_from_toolbar, [overlay])
	overlay.free()


# --- the toolbar row keeps only what belongs in it ------------------------


func test_only_the_hud_and_the_status_strip_are_added_to_the_toolbar() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for overlay in Overlays.VIEWPORT_OVERLAY_PROPERTIES:
		assert_false(
			source.contains(
				"add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, %s)" % overlay
			),
			(
				"%s floats over the viewport; in the toolbar row it reserves its whole panel out of the viewport's height"
				% overlay
			)
		)
	assert_true(
		source.contains("add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, hud)"),
		"The shortcut HUD really is a toolbar item",
	)


func test_power_user_overlays_go_to_the_viewport_too() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_overlays.gd")
	for overlay in ["_coach_marks", "_operation_replay", "_radial_menu"]:
		assert_true(
			source.contains("attach_viewport_overlay(plugin, plugin.%s)" % overlay),
			"%s is an overlay, not a toolbar item" % overlay,
		)


# --- placement -----------------------------------------------------------


func test_overlays_are_anchored_rather_than_piled_in_the_corner() -> void:
	# Straight off the toolbar they all land at the host's origin, on top of each
	# other and on top of Godot's own viewport labels.
	host.size = Vector2(1000, 600)
	plugin._context_toolbar = _overlay("ContextToolbar")
	plugin._hotkey_palette = _overlay("Palette")
	plugin._coach_marks = _overlay("CoachMarks")
	plugin._operation_replay = _overlay("Replay")
	for c in [
		plugin._context_toolbar,
		plugin._hotkey_palette,
		plugin._coach_marks,
		plugin._operation_replay
	]:
		Overlays.attach_viewport_overlay(plugin, c)
	Overlays.adopt_viewport_overlay_host(plugin, host)

	var origins := {}
	for c in host.get_children():
		origins[c.name] = (c as Control).position
	for name in origins:
		assert_ne(origins[name], Vector2.ZERO, "%s was left at the corner" % name)
	assert_eq(origins.values().size(), 4)
	for name in origins:
		for other in origins:
			if name != other:
				assert_ne(origins[name], origins[other], "%s and %s share a spot" % [name, other])


func test_self_positioning_overlays_are_left_alone() -> void:
	# The quick property puts itself at the cursor and the radial menu draws
	# around one. A corner preset applied over the top is how an overlay ends up
	# in the wrong half of the screen.
	plugin._viewport_overlay_host = host
	for property in ["_quick_property", "_radial_menu"]:
		assert_false(
			Overlays.VIEWPORT_OVERLAY_ANCHORS.has(property),
			"%s places itself from event.position" % property
		)
	plugin._quick_property = _overlay("QuickProperty")
	Overlays.attach_viewport_overlay(plugin, plugin._quick_property)
	plugin._quick_property.position = Vector2(123, 456)
	Overlays.place_viewport_overlay(plugin, plugin._quick_property)
	assert_eq(plugin._quick_property.position, Vector2(123, 456))


# --- re-anchoring when the overlay's own size moves ----------------------


func test_a_grown_overlay_is_recentred_rather_than_left_hanging_off_the_edge() -> void:
	# `set_anchors_and_offsets_preset` bakes its offsets from the minimum size it
	# can see at the time. The contextual toolbar is 41px wide with nothing
	# selected and 940px with a brush selected, so the left edge it was centred
	# on while empty put most of it past the right side of the viewport. Caught
	# in the editor, not by the first round of these tests.
	host.size = Vector2(1486, 820)
	plugin._context_toolbar = _overlay("ContextToolbar")
	plugin._context_toolbar.custom_minimum_size = Vector2(41, 36)
	Overlays.attach_viewport_overlay(plugin, plugin._context_toolbar)
	Overlays.adopt_viewport_overlay_host(plugin, host)

	plugin._context_toolbar.custom_minimum_size = Vector2(940, 36)
	Overlays.refresh_viewport_overlay_placement(plugin)

	var rect: Rect2 = plugin._context_toolbar.get_rect()
	assert_almost_eq(rect.position.x + rect.size.x * 0.5, host.size.x * 0.5, 1.0, "Still centred")
	assert_gte(rect.position.x, 0.0, "Runs off the left of the viewport")
	assert_lte(rect.position.x + rect.size.x, host.size.x, "Runs off the right of the viewport")


func test_placement_is_not_rebaked_while_the_size_holds_still() -> void:
	# The draw hook runs this every frame, so it has to be a cheap no-op in the
	# common case rather than re-anchoring continuously.
	host.size = Vector2(1486, 820)
	plugin._hotkey_palette = _overlay("Palette")
	Overlays.attach_viewport_overlay(plugin, plugin._hotkey_palette)
	Overlays.adopt_viewport_overlay_host(plugin, host)
	var before: Rect2 = plugin._hotkey_palette.get_rect()
	plugin._hotkey_palette.position += Vector2(11, 13)
	Overlays.refresh_viewport_overlay_placement(plugin)
	assert_eq(
		plugin._hotkey_palette.position,
		before.position + Vector2(11, 13),
		"An unchanged minimum size must not trigger a re-anchor"
	)


func test_refresh_is_safe_before_a_host_exists() -> void:
	plugin._context_toolbar = _overlay("ContextToolbar")
	Overlays.attach_viewport_overlay(plugin, plugin._context_toolbar)
	Overlays.refresh_viewport_overlay_placement(plugin)
	assert_same(plugin._context_toolbar.get_parent(), plugin.toolbar)
