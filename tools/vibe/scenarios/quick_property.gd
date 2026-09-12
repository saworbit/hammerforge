@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The double-tap quick property popup against the controls it writes into.
##
## G G, B B and R R open a small numeric popup over the viewport and the value
## typed there is pushed straight into a dock control. Three properties, six
## controls, and nobody has checked that the pairs agree about what a legal
## value is.

const QuickProperty = preload("res://addons/hammerforge/ui/hf_quick_property.gd")


func id() -> String:
	return "quick-property"


func summary() -> String:
	return "whether the quick popup and the dock control behind it agree on range and step"


func run() -> void:
	await _the_ranges_on_both_sides()
	await _what_a_committed_value_becomes()


func _popup() -> Control:
	var p = QuickProperty.new()
	_tree.get_root().add_child(p)
	return p


func _spin_ranges(popup: Control, type: int, values: Array) -> Array:
	popup.show_property(type, Vector2(10, 10), values)
	await frame()
	var out: Array = []
	for spin in popup._spinboxes:
		(
			out
			. append(
				{
					"min": spin.min_value,
					"max": spin.max_value,
					"step": spin.step,
					"value": spin.value,
				}
			)
		)
	return out


## A SpinBox built like the dock's, handed the popup's value.
func _through(min_v: float, max_v: float, step: float, value: float) -> float:
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	var out: float = spin.value
	spin.free()
	return out


func _the_ranges_on_both_sides() -> void:
	var popup = _popup()
	await frame()

	var grid: Array = await _spin_ranges(popup, QuickProperty.PropertyType.GRID_SNAP, [])
	note("quick GRID_SNAP spin", grid[0])
	note("dock GridSnap spin (dock.tscn)", {"min": 0.0, "max": 128.0, "step": 1.0})

	var size: Array = await _spin_ranges(popup, QuickProperty.PropertyType.BRUSH_SIZE, [])
	note("quick BRUSH_SIZE spin", size[0])
	if not is_equal_approx(float(size[0]["value"]), 4.0):
		known(
			447,
			"the brush size popup cannot express a whole number",
			(
				"min 0.1 with step 0.5 puts every legal value at .1 or .6, so a 4.0 brush opens "
				+ "the popup reading %s" % size[0]["value"]
			)
		)
	note("dock SizeX/Y/Z spin (dock.tscn)", {"min": 1.0, "max": 256.0, "step": 1.0})

	var radius: Array = await _spin_ranges(popup, QuickProperty.PropertyType.PAINT_RADIUS, [])
	note("quick PAINT_RADIUS spin", radius[0])
	note(
		"dock surface_paint_radius spin (paint_tab_builder)",
		{"min": 0.01, "max": 0.5, "step": 0.01}
	)
	note("dock paint_radius spin (paint_tab_builder)", {"min": 1.0, "max": 16.0, "step": 1.0})
	popup.queue_free()


func _what_a_committed_value_becomes() -> void:
	var popup = _popup()
	await frame()

	# PAINT_RADIUS. plugin_overlays.on_quick_property_committed() writes values[0]
	# into dock.surface_paint_radius, which is _make_spin(0.01, 0.5, 0.01, 0.1).
	var radius: Array = await _spin_ranges(popup, QuickProperty.PropertyType.PAINT_RADIUS, [])
	var offered: float = radius[0]["value"]
	var landed := _through(0.01, 0.5, 0.01, offered)
	note("popup offers a radius of", offered)
	note("surface_paint_radius takes it as", landed)
	if not is_equal_approx(offered, landed):
		known(
			447,
			"the quick radius popup's own default is ten times the control's maximum",
			(
				"show_property(PAINT_RADIUS) builds a spin of 0.1..512 defaulting to 5.0, and "
				+ "on_quick_property_committed() writes it into dock.surface_paint_radius, "
				+ "which is _make_spin(0.01, 0.5, 0.01, 0.1). Pressing Enter on the value the "
				+ (
					"popup itself put there turns %s into %s. The popup is documented as "
					% [offered, landed]
				)
				+ "'R R (paint radius)' and the floor paint radius is a different control "
				+ "again -- dock.paint_radius, 1..16 -- so whichever of the two was meant, "
				+ "the popup's range matches neither"
			)
		)

	# BRUSH_SIZE goes two places: unclamped into input_state.drag_size_default and
	# clamped into the dock spins.
	var root: Node3D = await fresh_root()
	await frame()
	var typed := Vector3(500.5, 500.5, 500.5)
	root.input_state.drag_size_default = typed
	var dock_shows := Vector3(
		_through(1.0, 256.0, 1.0, typed.x),
		_through(1.0, 256.0, 1.0, typed.y),
		_through(1.0, 256.0, 1.0, typed.z)
	)
	note("popup allows a brush size up to", 1024.0)
	note("typed size", typed)
	note("what the dock spins show", dock_shows)
	note("what input_state.drag_size_default holds", root.input_state.drag_size_default)
	if root.input_state.drag_size_default != dock_shows:
		known(
			448,
			"a brush size from the quick popup leaves the dock and the draw tool disagreeing",
			(
				"on_quick_property_committed() writes the raw values into "
				+ "input_state.drag_size_default and the same values into dock.size_x/y/z, "
				+ (
					"which are 1..256 step 1 and clamp them. A typed %s leaves the dock reading "
					% str(typed)
				)
				+ (
					"%s while the next brush drawn is %s. The popup's own spin is 0.1..1024 "
					% [str(dock_shows), str(root.input_state.drag_size_default)]
				)
				+ "step 0.5, so any value with a half unit in it or above 256 splits the two"
			)
		)

	var brush = root.create_brush_from_info(
		{"shape": 0, "size": root.input_state.drag_size_default}
	)
	await frame()
	note("a brush drawn at that size measures", HFVibe.local_extent(brush))
	popup.queue_free()
