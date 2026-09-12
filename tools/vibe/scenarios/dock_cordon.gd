@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The cordon controls against the cordon the level actually bakes with.
##
## Set from Selection writes the bounds onto the level and then copies the six
## numbers into the six spins. Those spins have a range, and writing a value
## into a SpinBox that is outside it is not an error -- it is a different value,
## and one that fires `value_changed` on the way past.

const DockScene = preload("res://addons/hammerforge/dock.tscn")


func id() -> String:
	return "dock-cordon"


func summary() -> String:
	return "whether the cordon spins can hold the cordon the level was given"


func run() -> void:
	await _a_selection_outside_the_spin_range()


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	return dock


func _a_selection_outside_the_spin_range() -> void:
	var root: Node3D = await fresh_root("CordonLevel")
	var dock = await _dock(root)
	await frame()
	note("cordon spin range", [dock.cordon_min_x.min_value, dock.cordon_min_x.max_value])

	# A room out at the edge of a large map. Quake-scale maps run past +-4096 per
	# axis, and the structure builders take a width or radius up to 4096 for one
	# piece of geometry, so this is a level rather than a stress test.
	var far = box(root, Vector3(256, 256, 256), Vector3(12000, 0, 0))
	await frame()
	dock.set_selection_nodes([far])
	dock._on_cordon_from_selection()
	await frame()

	var bounds: AABB = root.get("cordon_aabb")
	note("cordon the level holds after Set from Selection", bounds)
	note(
		"the six spins now read",
		[
			dock.cordon_min_x.value,
			dock.cordon_min_y.value,
			dock.cordon_min_z.value,
			dock.cordon_max_x.value,
			dock.cordon_max_y.value,
			dock.cordon_max_z.value,
		]
	)
	var brush_position: Vector3 = far.global_position
	note("the brush the cordon was set from is at", brush_position)
	note("does the cordon contain it", bounds.has_point(brush_position))
	if not bounds.has_point(brush_position):
		known(
			467,
			"Set Cordon from Selection leaves a cordon that excludes the selection",
			(
				(
					"set_cordon_from_selection() puts the right AABB on the level, and then the"
					+ " handler copies the six numbers into the cordon spins, which are built with"
					+ " a -9999..9999 range. Each assignment clamps and fires value_changed, and"
					+ " on_cordon_value_changed() reads the six clamped spins straight back onto"
					+ " level_root.cordon_aabb. The selection sits at %s, the cordon ends up %s,"
					+ " the cordon is now switched on, and the next bake drops the very geometry"
					+ " the button was pressed for."
				)
				% [brush_position, bounds]
			)
		)

	var enabled = root.get("cordon_enabled")
	note("cordon enabled after the button", enabled)
	dock.queue_free()
	await frame()
