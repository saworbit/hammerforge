extends GutTest

## `capture_state()` has to be a fixed point (#660).
##
## Undo is a whole-level snapshot restore. A brush whose record still matches is
## kept where it is (#600); one that has to be rebuilt is `add_child`ed and lands
## at the end. The brushes a restore rebuilds are exactly the ones the undone
## action changed, so every undo moved the brushes the mapper had just touched to
## the back of the level, and `capture_state()` records the container in order.
##
## Capture, restore, capture then gives a different dictionary from capture. That
## is the property the whole undo design rests on, and nothing asserted it.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _order(root: LevelRoot) -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			out.append(str(child.get("brush_id")))
	return out


func _ids_in(state: Dictionary) -> Array:
	var out: Array = []
	for entry in state.get("brushes", []):
		out.append(str((entry as Dictionary).get("brush_id", "")))
	return out


# ===========================================================================


func test_taking_back_a_nudge_leaves_the_brushes_where_they_were():
	var root := _fresh_root()
	var a := _box(root, Vector3.ZERO)
	_box(root, Vector3(4, 0, 0))
	var drawn := _order(root)
	assert_eq(drawn.size(), 2, "two brushes to get out of order")

	var before: Dictionary = root.state_system.capture_state()
	a.global_position = Vector3(0, 2, 0)
	root.state_system.restore_state(before)

	assert_eq(_order(root), drawn, "the level comes back in the order it was drawn in")


func test_capture_restore_capture_is_the_same_capture():
	var root := _fresh_root()
	for i in 6:
		_box(root, Vector3(i * 4, 0, 0))
	var first: Dictionary = root.state_system.capture_state()

	# Change something in the middle, then take it back.
	var middle = root.draft_brushes_node.get_child(2)
	middle.global_position = Vector3(0, 8, 0)
	root.state_system.restore_state(first)
	var second: Dictionary = root.state_system.capture_state()

	assert_eq(
		_ids_in(second), _ids_in(first), "the same brushes, in the same order, after a round trip"
	)
	assert_eq(
		int(second["id_counter"]),
		int(first["id_counter"]),
		"and the id counter does not climb on a restore that minted nothing"
	)


func test_a_rebuilt_brush_does_not_jump_to_the_end():
	# The rebuilt brush is the one the undone action changed, so this is the
	# ordinary case rather than an edge of it.
	var root := _fresh_root()
	var first_id := str(_box(root, Vector3.ZERO).get("brush_id"))
	_box(root, Vector3(4, 0, 0))
	_box(root, Vector3(8, 0, 0))
	var state: Dictionary = root.state_system.capture_state()

	root.draft_brushes_node.get_child(0).global_position = Vector3(0, 5, 0)
	root.state_system.restore_state(state)

	assert_eq(_order(root)[0], first_id, "the brush that was rebuilt is still the first one")


func test_a_brush_nobody_named_still_round_trips():
	# Godot auto-names an unnamed brush `@Node3D@14`. That cannot round trip --
	# `@` is not a character a node name may hold -- and the engine reuses the
	# number once a node is freed, so two live brushes can record the same name
	# and the second rebuilt collides with the first. Either way the record could
	# not match the node, whatever the order was.
	var root := _fresh_root()
	var brush := _box(root, Vector3.ZERO)
	var first: Dictionary = root.state_system.capture_state()
	brush.global_position = Vector3(0, 3, 0)
	root.state_system.restore_state(first)
	var second: Dictionary = root.state_system.capture_state()

	var before: Dictionary = first["brushes"][0]
	var after: Dictionary = second["brushes"][0]
	assert_false(before.has("name"), "a generated name is not identity and is not recorded")
	assert_eq(
		str(after.get("name", "")), str(before.get("name", "")), "so the record is a fixed point"
	)


func test_a_brush_someone_named_keeps_its_name():
	var root := _fresh_root()
	var brush := _box(root, Vector3.ZERO)
	brush.name = "GateLeaf"
	var first: Dictionary = root.state_system.capture_state()
	brush.global_position = Vector3(0, 3, 0)
	root.state_system.restore_state(first)

	assert_eq(
		str((root.state_system.capture_state()["brushes"][0] as Dictionary).get("name", "")),
		"GateLeaf",
		"an authored name is what I/O and the baked geometry are named after, and it survives"
	)


func test_the_order_survives_several_undone_edits():
	var root := _fresh_root()
	for i in 5:
		_box(root, Vector3(i * 4, 0, 0))
	var drawn := _order(root)

	for step in 5:
		var snapshot: Dictionary = root.state_system.capture_state()
		root.draft_brushes_node.get_child(step).global_position = Vector3(0, step + 1, 0)
		root.state_system.restore_state(snapshot)
		assert_eq(_order(root), drawn, "order held at step %d" % step)
