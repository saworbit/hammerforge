extends GutTest

## #447, #448. The double-tap popup (G G, B B, R R) builds its own spinboxes and
## pushes the value into a dock control. It used to restate the ranges rather
## than take them, so none of the three pairs agreed about what a legal value
## was, and the committed brush size went into two places of which only one
## clamped.

const HFQuickProperty = preload("res://addons/hammerforge/ui/hf_quick_property.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const DockScene = preload("res://addons/hammerforge/dock.tscn")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


class PluginStub:
	extends RefCounted

	var active_root: Node3D = null
	var dock: Node = null

	func _get_level_root() -> Node3D:
		return active_root


var popup


func before_each():
	popup = HFQuickProperty.new()
	add_child_autoqfree(popup)


func after_each():
	popup = null


func _spin_of(type: int, values: Array, ranges: Array = []) -> SpinBox:
	popup.show_property(type, Vector2(10, 10), values, ranges)
	return popup._spinboxes[0] if not popup._spinboxes.is_empty() else null


# ===========================================================================
# The popup takes its range from the control it writes into (#447)
# ===========================================================================


func test_a_given_range_is_used_for_the_spin():
	var spin := _spin_of(
		HFQuickProperty.PropertyType.PAINT_RADIUS, [0.25], [{"min": 0.01, "max": 0.5, "step": 0.01}]
	)
	assert_not_null(spin)
	assert_eq(spin.min_value, 0.01)
	assert_eq(spin.max_value, 0.5)
	assert_eq(spin.step, 0.01)
	assert_almost_eq(spin.value, 0.25, 0.001, "And the current value survives")


func test_one_given_range_covers_all_three_size_fields():
	popup.show_property(
		HFQuickProperty.PropertyType.BRUSH_SIZE,
		Vector2.ZERO,
		[8.0, 8.0, 8.0],
		[{"min": 2.0, "max": 64.0, "step": 2.0}]
	)
	assert_eq(popup._spinboxes.size(), 3)
	for spin in popup._spinboxes:
		assert_eq(spin.max_value, 64.0)
		assert_eq(spin.value, 8.0)


func test_the_brush_size_spin_can_hold_a_whole_number():
	var spin := _spin_of(HFQuickProperty.PropertyType.BRUSH_SIZE, [4.0, 4.0, 4.0])
	assert_eq(spin.value, 4.0, "Opening the popup on a 4 unit brush must not change it to 4.1")


func test_the_fallback_ranges_match_the_dock_controls():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	assert_eq(dock.grid_snap.min_value, HFQuickProperty.DEFAULT_GRID_SNAP_RANGE["min"])
	assert_eq(dock.grid_snap.max_value, HFQuickProperty.DEFAULT_GRID_SNAP_RANGE["max"])
	assert_eq(dock.grid_snap.step, HFQuickProperty.DEFAULT_GRID_SNAP_RANGE["step"])
	assert_eq(dock.size_x.min_value, HFQuickProperty.DEFAULT_BRUSH_SIZE_RANGE["min"])
	assert_eq(dock.size_x.max_value, HFQuickProperty.DEFAULT_BRUSH_SIZE_RANGE["max"])
	assert_eq(dock.size_x.step, HFQuickProperty.DEFAULT_BRUSH_SIZE_RANGE["step"])
	if dock.surface_paint_radius:
		assert_eq(
			dock.surface_paint_radius.max_value, HFQuickProperty.DEFAULT_PAINT_RADIUS_RANGE["max"]
		)


func test_ranges_of_reads_the_dock_controls():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	var plugin := PluginStub.new()
	plugin.dock = dock
	var ranges: Array = HFPluginOverlays._ranges_of(plugin, ["size_x", "size_y", "size_z"])
	assert_eq(ranges.size(), 3)
	assert_eq(ranges[0]["min"], dock.size_x.min_value)
	assert_eq(ranges[0]["max"], dock.size_x.max_value)


func test_ranges_of_is_empty_without_a_dock():
	var plugin := PluginStub.new()
	assert_eq(HFPluginOverlays._ranges_of(plugin, ["size_x"]), [])


# ===========================================================================
# One answer for the committed brush size (#448)
# ===========================================================================


func test_a_committed_size_leaves_both_ends_agreeing():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	var plugin := PluginStub.new()
	plugin.active_root = root
	plugin.dock = dock

	HFPluginOverlays.on_quick_property_committed(
		plugin, HFQuickProperty.PropertyType.BRUSH_SIZE, [500.5, 500.5, 500.5]
	)
	var shown := Vector3(dock.size_x.value, dock.size_y.value, dock.size_z.value)
	assert_eq(shown, Vector3(256, 256, 256), "The dock spins clamp, as they always did")
	assert_eq(
		root.input_state.drag_size_default,
		shown,
		"And the next brush is drawn at the size the dock shows"
	)


func test_a_size_inside_the_range_is_committed_as_typed():
	var dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	var plugin := PluginStub.new()
	plugin.active_root = root
	plugin.dock = dock

	HFPluginOverlays.on_quick_property_committed(
		plugin, HFQuickProperty.PropertyType.BRUSH_SIZE, [32.0, 16.0, 8.0]
	)
	assert_eq(root.input_state.drag_size_default, Vector3(32, 16, 8))
	assert_eq(Vector3(dock.size_x.value, dock.size_y.value, dock.size_z.value), Vector3(32, 16, 8))
