extends GutTest

## Clip, Hollow, Carve and Merge replace a brush with others, and when the brush
## is part of a brush entity the others have to be that entity: the same name or
## tie, the same properties and the same wires (#1194). Since #1148 brushes alike
## in class and in name or tie are one entity, so every piece carries all of it.
## The pieces copied the class alone, and the first of them the name and wires,
## so a door clipped to fit a frame came apart in the game.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, size: Vector3, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _leaf(root: LevelRoot, at: Vector3) -> Node:
	return _box(root, Vector3(1, 2, 0.2), at)


func _ids(nodes: Array) -> Array:
	return nodes.map(func(b): return str(b.get("brush_id")))


## Tie `brushes` as a door named `gate` with a speed of 7, wired to a lamp.
func _gate(root: LevelRoot, brushes: Array) -> void:
	root.tie_brushes_to_entity(_ids(brushes), "func_door", "gate")
	root.set_entity_property(brushes[0], "speed", 7.0)
	root.add_entity_output(brushes[0], "OnOpen", "lamp", "TurnOn")


func _doors(root: LevelRoot) -> Array:
	return root._iter_managed_brush_nodes().filter(
		func(node): return HFBrushEntity.entity_class(node) == "func_door"
	)


func _speed(brush: Node) -> Variant:
	return (brush.get_meta(HFBrushEntity.DATA_META, {}) as Dictionary).get("speed")


func _wires(brush: Node) -> Array:
	return brush.get_meta(HFBrushEntity.OUTPUTS_META, [])


## Every door brush is one door named `gate`, tied once, with its speed and its
## one wire.
func _assert_one_gate(root: LevelRoot, brushes: int, what: String) -> void:
	var doors := _doors(root)
	assert_eq(doors.size(), brushes, "%s: door brushes" % what)
	var identities := {}
	var ties := {}
	for door in doors:
		identities[HFBrushEntity.identity(door)] = true
		ties[HFBrushEntity.tie_key(door)] = true
		assert_eq(_speed(door), 7.0, "%s: every piece keeps the door's speed" % what)
		assert_eq(_wires(door).size(), 1, "%s: every piece holds the door's wire" % what)
	assert_eq(identities.keys(), ["@gate"], "%s: one door, by its name" % what)
	assert_eq(ties.size(), 1, "%s: in one tie, so Validate sees no second door" % what)
	assert_eq(root.find_entities_by_name("gate").size(), brushes, "%s: all answer to it" % what)


# ===========================================================================
# Clip, Hollow and Carve
# ===========================================================================


func test_clip_leaves_a_named_door_one_door():
	var root := _fresh_root()
	var leaf := _leaf(root, Vector3(0, 1, 0))
	_gate(root, [leaf])
	assert_true(root.clip_brush_by_id(_ids([leaf])[0], 1, 1.0).ok)
	_assert_one_gate(root, 2, "clip")


func test_hollow_leaves_a_named_door_one_door():
	var root := _fresh_root()
	var solid := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	_gate(root, [solid])
	assert_true(root.hollow_brush_by_id(_ids([solid])[0], 0.2).ok)
	_assert_one_gate(root, 6, "hollow")


func test_carve_leaves_a_named_door_one_door():
	var root := _fresh_root()
	var leaf := _leaf(root, Vector3(0, 1, 0))
	_gate(root, [leaf])
	var window := _box(root, Vector3(0.4, 0.6, 1.0), Vector3(0, 1, 0))
	assert_true(root.carve_with_brush(_ids([window])[0]).ok)
	assert_gt(_doors(root).size(), 1, "the window cut the leaf into pieces")
	_assert_one_gate(root, _doors(root).size(), "carve")


func test_clip_keeps_every_piece_of_an_unnamed_door_in_its_tie():
	# The halves had no tie, so one leaf clipped made a door of three.
	var root := _fresh_root()
	var leaves := [_leaf(root, Vector3(0, 1, 0)), _leaf(root, Vector3(1, 1, 0))]
	root.tie_brushes_to_entity(_ids(leaves), "func_door")
	var tie := str(leaves[0].get_meta(HFBrushEntity.TIE_META, ""))
	assert_true(root.clip_brush_by_id(_ids(leaves)[0], 1, 1.0).ok)
	var doors := _doors(root)
	assert_eq(doors.size(), 3)
	for door in doors:
		assert_eq(HFBrushEntity.identity(door), HFBrushEntity.TIE_PREFIX + tie)


func test_clip_keeps_a_door_of_one_untied_brush_one_door():
	# A brush with a class and neither a name nor a tie is an entity of its own,
	# as a level from before ties keeps it. Its halves are one, not two.
	var root := _fresh_root()
	var leaf := _leaf(root, Vector3(0, 1, 0))
	leaf.set_brush_entity_class("func_door")
	assert_true(root.clip_brush_by_id(_ids([leaf])[0], 1, 1.0).ok)
	var doors := _doors(root)
	assert_eq(doors.size(), 2)
	assert_ne(HFBrushEntity.identity(doors[0]), "", "the halves were given a tie")
	assert_eq(HFBrushEntity.identity(doors[0]), HFBrushEntity.identity(doors[1]))


func test_clip_of_plain_geometry_gives_no_piece_an_entity():
	var root := _fresh_root()
	var wall := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	assert_true(root.clip_brush_by_id(_ids([wall])[0], 1, 1.0).ok)
	for piece in root._iter_managed_brush_nodes():
		assert_eq(HFBrushEntity.fields(piece), {})


# ===========================================================================
# Merge
# ===========================================================================


func test_merging_the_leaves_of_one_door_gives_one_brush_of_that_door():
	var root := _fresh_root()
	var leaves := [_leaf(root, Vector3(0, 1, 0)), _leaf(root, Vector3(1, 1, 0))]
	_gate(root, leaves)
	assert_true(root.merge_brushes_by_ids(_ids(leaves)).ok)
	_assert_one_gate(root, 1, "merge")


func test_merge_keeps_a_wire_and_a_property_only_one_leaf_held():
	# A wire went on the selected leaf alone before #1129, and the export writes
	# what any brush of an entity holds.
	var root := _fresh_root()
	var leaves := [_leaf(root, Vector3(0, 1, 0)), _leaf(root, Vector3(1, 1, 0))]
	_gate(root, leaves)
	var wires: Array = _wires(leaves[1]).duplicate(true)
	wires.append({"output_name": "OnClose", "target_name": "lamp", "input_name": "TurnOff"})
	leaves[1].set_meta(HFBrushEntity.OUTPUTS_META, wires)
	leaves[1].set_meta(HFBrushEntity.DATA_META, {"speed": 7.0, "wait": 3.0})
	assert_true(root.merge_brushes_by_ids(_ids(leaves)).ok)
	var merged: Node = _doors(root)[0]
	assert_eq(_wires(merged).size(), 2, "the wire both held once, and the one leaf's own")
	assert_eq(merged.get_meta(HFBrushEntity.DATA_META, {}), {"speed": 7.0, "wait": 3.0})


func test_merge_refuses_a_door_leaf_and_plain_geometry():
	var root := _fresh_root()
	var leaf := _leaf(root, Vector3(0, 1, 0))
	_gate(root, [leaf])
	var wall := _leaf(root, Vector3(1, 1, 0))
	var ids := _ids([leaf, wall])
	assert_false(root.can_merge_brushes(ids).ok)
	assert_false(root.merge_brushes_by_ids(ids).ok, "refused on a redo as well")
	assert_eq(root._iter_managed_brush_nodes().size(), 2, "nothing was merged")
	_assert_one_gate(root, 1, "refused merge")


## A wire aimed at the door from elsewhere stays aimed at it. Merge, Clip, Hollow
## and Carve deleted the door's brushes before they made the new ones, so for a
## moment nothing answered to its name, and the delete took every wire aimed at
## it along (#1975).
func test_a_wire_aimed_at_the_door_outlasts_a_merge_a_clip_a_hollow_and_a_carve():
	for op in ["merge", "clip", "hollow", "carve"]:
		var root := _fresh_root()
		var leaves := [_leaf(root, Vector3(0, 1, 0))]
		if op == "merge":
			leaves.append(_leaf(root, Vector3(1, 1, 0)))
		elif op == "hollow":
			leaves = [_box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))]
		_gate(root, leaves)
		var button := _box(root, Vector3(0.2, 0.2, 0.2), Vector3(4, 1, 0))
		root.tie_brushes_to_entity(_ids([button]), "func_button", "press")
		root.add_entity_output(button, "OnPressed", "gate", "Open")
		var ids := _ids(leaves)
		var done: HFOpResult
		match op:
			"merge":
				done = root.merge_brushes_by_ids(ids)
			"clip":
				done = root.clip_brush_by_id(ids[0], 1, 1.0)
			"carve":
				var window := _box(root, Vector3(0.4, 0.6, 1.0), Vector3(0, 1, 0))
				done = root.carve_with_brush(_ids([window])[0])
			_:
				done = root.hollow_brush_by_id(ids[0], 0.2)
		assert_true(done.ok, "%s: fixture: done" % op)
		assert_eq(_wires(button).size(), 1, "%s: the button is still wired to the door" % op)


func test_merge_refuses_two_doors():
	var root := _fresh_root()
	var first := _leaf(root, Vector3(0, 1, 0))
	var second := _leaf(root, Vector3(1, 1, 0))
	root.tie_brushes_to_entity(_ids([first]), "func_door")
	root.tie_brushes_to_entity(_ids([second]), "func_door")
	assert_false(root.can_merge_brushes(_ids([first, second])).ok)


# ===========================================================================
# What the game gets
# ===========================================================================


func _baked_doors(root: LevelRoot) -> Array:
	var container := Node3D.new()
	root.add_child(container)
	root.bake_system._append_nonstructural_brushes(container)
	return container.get_node("Nonstructural").get_children().filter(
		func(node): return node.has_method("is_open")
	)


func test_a_clipped_door_bakes_as_one_door_whose_wire_goes_in_once():
	var root := _fresh_root()
	var leaf := _leaf(root, Vector3(0, 1, 0))
	_gate(root, [leaf])
	assert_true(root.clip_brush_by_id(_ids([leaf])[0], 1, 1.0).ok)
	var holders := _baked_doors(root)
	assert_eq(holders.size(), 2, "a holder for each half")
	var identities := {}
	for holder in holders:
		identities[HFBrushEntity.baked_identity(holder)] = true
	assert_eq(identities.keys(), ["@gate"], "one door")
	var dispatcher := HFIORuntime.new()
	holders[0].get_parent().add_child(dispatcher)
	dispatcher.wire()
	var opens := 0
	for id in dispatcher._connections:
		for connection in dispatcher._connections[id]:
			if str(connection.get("output_name", "")) == "OnOpen":
				opens += 1
	assert_eq(opens, 1, "the wire both halves hold is one wire")


# ===========================================================================
# Undo
# ===========================================================================


func _undone(root: LevelRoot, cut: Callable) -> void:
	var before: Dictionary = root.state_system.capture_state()
	assert_true(cut.call().ok)
	root.state_system.restore_state(before)


func test_undo_of_each_cut_puts_the_door_back():
	var root := _fresh_root()
	var solid := _box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	_gate(root, [solid])
	var brush_id: String = _ids([solid])[0]
	_undone(root, func(): return root.clip_brush_by_id(brush_id, 1, 1.0))
	_assert_one_gate(root, 1, "clip undone")
	_undone(root, func(): return root.hollow_brush_by_id(brush_id, 0.2))
	_assert_one_gate(root, 1, "hollow undone")
	var window := _box(root, Vector3(0.4, 0.6, 3.0), Vector3(0, 1, 0))
	var window_id: String = _ids([window])[0]
	_undone(root, func(): return root.carve_with_brush(window_id))
	_assert_one_gate(root, 1, "carve undone")


func test_undo_of_a_merge_puts_both_leaves_back():
	var root := _fresh_root()
	var leaves := [_leaf(root, Vector3(0, 1, 0)), _leaf(root, Vector3(1, 1, 0))]
	_gate(root, leaves)
	_undone(root, func(): return root.merge_brushes_by_ids(_ids(leaves)))
	_assert_one_gate(root, 2, "merge undone")
